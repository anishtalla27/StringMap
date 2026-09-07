import Foundation
import FingeringEngine

public struct StructuredScorePipeline: Sendable {
    private let importer: any ScoreImporter

    public init(importer: any ScoreImporter = MusicXMLImporter()) {
        self.importer = importer
    }

    public func run(
        musicXML data: Data,
        options: OptimizationOptions = .init()
    ) throws -> PipelineResult {
        try run(score: importer.importScore(from: data), options: options)
    }

    public func run(score input: NormalizedScore, options: OptimizationOptions = .init()) throws -> PipelineResult {
        let score = try ScoreValidator.validate(input).expandingRepeats().transposed(by: options.transposeSemitones)
        let fingeringNotes = score.notes.map {
            FingeringNote(
                id: $0.id,
                midi: $0.midi,
                tieStop: $0.tieStop,
                durationQuarters: $0.durationQuarters
            )
        }
        var candidates: [String: [GuitarPosition]] = [:]
        for note in fingeringNotes {
            candidates[note.id] = try FingeringEngine.positions(
                for: note.midi,
                tuning: options.tuning,
                capo: options.capo,
                maxFret: options.maxFret
            )
        }
        let fingering: FingeringResult
        if score.needsPolyphonicFingering {
            var offset = 0.0
            var timed: [TimedFingeringNote] = []
            for measure in score.measures {
                for event in measure.events {
                    if case let .note(n) = event {
                        timed.append(TimedFingeringNote(note: FingeringNote(id: n.id, midi: n.midi,
                            tieStop: n.tieStop, durationQuarters: n.durationQuarters),
                            onset: offset + n.onsetQuarters, voice: n.voice, tieFromID: n.tieFromID))
                    }
                }
                offset += measure.durationQuarters
            }
            fingering = try FingeringEngine.optimizePolyphonic(timed, options: options)
        } else { fingering = try FingeringEngine.optimize(fingeringNotes, options: options) }
        let positions = Dictionary(uniqueKeysWithValues: fingering.steps.map { ($0.note.id, $0.position) })
        var starts: [String: Double] = [:]; var offset = 0.0
        for measure in score.measures {
            for event in measure.events { starts[event.id] = offset + event.onsetQuarters }
            offset += measure.durationQuarters
        }
        for note in score.notes where note.slurFromID != nil {
            guard let origin = score.notes.first(where: { $0.id == note.slurFromID }),
                  let from = positions[origin.id], let to = positions[note.id],
                  from.string == to.string, origin.voice == note.voice,
                  !note.tieStop, !origin.tieStart,
                  abs((starts[origin.id]! + origin.durationQuarters) - starts[note.id]!) < 1e-8,
                  (note.slurKind == .hammerOn && note.midi > origin.midi) || (note.slurKind == .pullOff && note.midi < origin.midi) else {
                throw MusicXMLImportError.malformed("Guitar slurs require adjacent notes on one string with the correct pitch direction.")
            }
        }
        let alphaTex = try AlphaTexGenerator.generate(score: score, fingering: fingering)
        return PipelineResult(score: score, candidates: candidates, fingering: fingering, alphaTex: alphaTex)
    }
}

public extension NormalizedScore {
    var needsPolyphonicFingering: Bool {
        if Set(notes.map(\.voice)).count > 1 { return true }
        for measure in measures {
            let notes = measure.events.compactMap { if case let .note(n) = $0 { return n }; return nil }
            var end = 0.0
            for n in notes.sorted(by: { $0.onsetQuarters < $1.onsetQuarters }) {
                if n.onsetQuarters < end - 1e-8 { return true }
                end = max(end, n.onsetQuarters + n.durationQuarters)
            }
        }
        return false
    }
}
