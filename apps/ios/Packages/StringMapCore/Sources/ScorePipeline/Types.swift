import Foundation
import FingeringEngine

public enum ScoreSource: String, Equatable, Sendable {
    case musicXML
}

public struct TimeSignature: Equatable, Sendable {
    public let beats: Int
    public let beatType: Int

    public init(beats: Int, beatType: Int) {
        self.beats = beats
        self.beatType = beatType
    }
}

public struct NormalizedNote: Equatable, Sendable {
    public let id: String
    public let measureIndex: Int
    public let onsetQuarters: Double
    public let durationQuarters: Double
    public let midi: Int
    public let pitch: String
    public let tieStart: Bool
    public let tieStop: Bool
}

public struct NormalizedRest: Equatable, Sendable {
    public let id: String
    public let measureIndex: Int
    public let onsetQuarters: Double
    public let durationQuarters: Double
}

public enum NormalizedEvent: Equatable, Sendable {
    case note(NormalizedNote)
    case rest(NormalizedRest)

    public var id: String {
        switch self {
        case let .note(note): note.id
        case let .rest(rest): rest.id
        }
    }

    public var durationQuarters: Double {
        switch self {
        case let .note(note): note.durationQuarters
        case let .rest(rest): rest.durationQuarters
        }
    }
}

public struct NormalizedMeasure: Equatable, Sendable {
    public let id: String
    public let index: Int
    public let number: String
    public let timeSignature: TimeSignature
    public let keyFifths: Int
    public let events: [NormalizedEvent]
}

public struct NormalizedScore: Equatable, Sendable {
    public let source: ScoreSource
    public let title: String
    public let composer: String?
    public let partName: String
    public let tempo: Double
    public let measures: [NormalizedMeasure]
    public let warnings: [String]

    public var notes: [NormalizedNote] {
        measures.flatMap(\.events).compactMap { event in
            guard case let .note(note) = event else { return nil }
            return note
        }
    }

    public func transposed(by semitones: Int) throws -> NormalizedScore {
        guard semitones != 0 else { return self }
        let shiftedMeasures = try measures.map { measure in
            let shiftedEvents = try measure.events.map { event in
                switch event {
                case .rest:
                    return event
                case let .note(note):
                    let shiftedMIDI = note.midi + semitones
                    guard (0...127).contains(shiftedMIDI) else {
                        throw MusicXMLImportError.pitchOutsideMIDIRange("MIDI \(shiftedMIDI)")
                    }
                    return .note(NormalizedNote(
                        id: note.id,
                        measureIndex: note.measureIndex,
                        onsetQuarters: note.onsetQuarters,
                        durationQuarters: note.durationQuarters,
                        midi: shiftedMIDI,
                        pitch: Self.pitchName(shiftedMIDI),
                        tieStart: note.tieStart,
                        tieStop: note.tieStop
                    ))
                }
            }
            return NormalizedMeasure(
                id: measure.id,
                index: measure.index,
                number: measure.number,
                timeSignature: measure.timeSignature,
                keyFifths: measure.keyFifths,
                events: shiftedEvents
            )
        }
        return NormalizedScore(
            source: source,
            title: title,
            composer: composer,
            partName: partName,
            tempo: tempo,
            measures: shiftedMeasures,
            warnings: warnings
        )
    }

    private static func pitchName(_ midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[midi % 12])\(midi / 12 - 1)"
    }
}

/// Future OMR and MIDI adapters implement this boundary and return the same stable model.
public protocol ScoreImporter: Sendable {
    func importScore(from data: Data) throws -> NormalizedScore
}

public struct PipelineResult: Equatable, Sendable {
    public let score: NormalizedScore
    public let candidates: [String: [GuitarPosition]]
    public let fingering: FingeringResult
    public let alphaTex: String
}

public enum MusicXMLImportError: Error, Equatable, LocalizedError, Sendable {
    case emptyInput
    case malformed(String)
    case unsupportedRoot(String)
    case missingPart
    case unsupportedMultipleVoices(measure: Int)
    case unsupportedChord(measure: Int)
    case unsupportedGraceNote(measure: Int)
    case unsupportedTuplet(measure: Int)
    case unpitchedNote(measure: Int)
    case missingElement(String)
    case invalidValue(element: String, value: String)
    case pitchOutsideMIDIRange(String)
    case unsupportedDuration(Double)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            "MusicXML input is empty."
        case let .malformed(message):
            "Invalid MusicXML: \(message)"
        case let .unsupportedRoot(root):
            "Only score-partwise MusicXML is supported; found \(root)."
        case .missingPart:
            "MusicXML does not contain a part."
        case let .unsupportedMultipleVoices(measure):
            "Measure \(measure) contains multiple voices; only monophonic MusicXML is supported."
        case let .unsupportedChord(measure):
            "Measure \(measure) contains a chord; only monophonic MusicXML is supported."
        case let .unsupportedGraceNote(measure):
            "Measure \(measure) contains a grace note, which is not supported yet."
        case let .unsupportedTuplet(measure):
            "Measure \(measure) contains a tuplet, which is not supported yet."
        case let .unpitchedNote(measure):
            "Measure \(measure) contains an unpitched note."
        case let .missingElement(element):
            "MusicXML element <\(element)> is missing or empty."
        case let .invalidValue(element, value):
            "Invalid MusicXML \(element): \(value)"
        case let .pitchOutsideMIDIRange(pitch):
            "MusicXML pitch \(pitch) is outside MIDI range."
        case let .unsupportedDuration(duration):
            "Duration \(duration) quarter notes cannot yet be represented by the alphaTex generator."
        }
    }
}
