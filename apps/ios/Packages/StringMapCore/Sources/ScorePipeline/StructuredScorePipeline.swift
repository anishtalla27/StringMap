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
        let importedScore = try importer.importScore(from: data)
        let score = try importedScore.transposed(by: options.transposeSemitones)
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
        let fingering = try FingeringEngine.optimize(fingeringNotes, options: options)
        let alphaTex = try AlphaTexGenerator.generate(score: score, fingering: fingering)
        return PipelineResult(score: score, candidates: candidates, fingering: fingering, alphaTex: alphaTex)
    }
}
