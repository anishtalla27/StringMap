import Foundation
import FingeringEngine

public enum ScoreSource: String, Codable, Equatable, Sendable {
    case musicXML
}

public struct TimeSignature: Codable, Equatable, Sendable {
    public var beats: Int
    public var beatType: Int

    public init(beats: Int, beatType: Int) {
        self.beats = beats
        self.beatType = beatType
    }
}

public enum GuitarSlurKind: String, Codable, Sendable { case hammerOn, pullOff }

public struct NormalizedNote: Codable, Equatable, Sendable {
    public var id: String
    public var measureIndex: Int
    public var onsetQuarters: Double
    public var durationQuarters: Double
    public var midi: Int
    public var pitch: String
    public var tieStart: Bool
    public var tieStop: Bool
    public var voice: String = "1"
    public var staff: Int = 1
    public var slurFromID: String? = nil
    public var slurKind: GuitarSlurKind? = nil
    public var tieFromID: String? = nil

    public init(id: String, measureIndex: Int, onsetQuarters: Double, durationQuarters: Double,
                midi: Int, pitch: String, tieStart: Bool = false, tieStop: Bool = false,
                voice: String = "1", staff: Int = 1, tieFromID: String? = nil, slurFromID: String? = nil, slurKind: GuitarSlurKind? = nil) {
        self.id = id; self.measureIndex = measureIndex; self.onsetQuarters = onsetQuarters
        self.durationQuarters = durationQuarters; self.midi = midi; self.pitch = pitch
        self.tieStart = tieStart; self.tieStop = tieStop; self.voice = voice; self.staff = staff
        self.tieFromID = tieFromID; self.slurFromID = slurFromID; self.slurKind = slurKind
    }
}

public struct NormalizedRest: Codable, Equatable, Sendable {
    public var id: String
    public var measureIndex: Int
    public var onsetQuarters: Double
    public var durationQuarters: Double
    public var voice: String = "1"
    public var staff: Int = 1

    public init(id: String, measureIndex: Int, onsetQuarters: Double, durationQuarters: Double,
                voice: String = "1", staff: Int = 1) {
        self.id = id; self.measureIndex = measureIndex; self.onsetQuarters = onsetQuarters
        self.durationQuarters = durationQuarters; self.voice = voice; self.staff = staff
    }
}

public enum NormalizedEvent: Codable, Equatable, Sendable {
    case note(NormalizedNote)
    case rest(NormalizedRest)

    public var id: String {
        switch self {
        case let .note(note): note.id
        case let .rest(rest): rest.id
        }
    }

    public var onsetQuarters: Double {
        switch self { case let .note(n): n.onsetQuarters; case let .rest(r): r.onsetQuarters }
    }
    public var voice: String {
        switch self { case let .note(n): n.voice; case let .rest(r): r.voice }
    }
    public var staff: Int {
        switch self { case let .note(n): n.staff; case let .rest(r): r.staff }
    }
    public var durationQuarters: Double {
        switch self {
        case let .note(note): note.durationQuarters
        case let .rest(rest): rest.durationQuarters
        }
    }
}

public struct NormalizedMeasure: Codable, Equatable, Sendable {
    public var id: String
    public var index: Int
    public var number: String
    public var timeSignature: TimeSignature
    public var keyFifths: Int
    public var events: [NormalizedEvent]
    public var repeatStart: Bool = false
    public var repeatCount: Int = 0
    /// Explicit MusicXML forward timing beyond the last event. Optional so
    /// existing saved scores retain their original measure lengths.
    public var minimumDurationQuarters: Double?

    public init(id: String, index: Int, number: String, timeSignature: TimeSignature,
                keyFifths: Int, events: [NormalizedEvent], repeatStart: Bool = false, repeatCount: Int = 0,
                minimumDurationQuarters: Double? = nil) {
        self.id = id; self.index = index; self.number = number; self.timeSignature = timeSignature
        self.keyFifths = keyFifths; self.events = events; self.repeatStart = repeatStart; self.repeatCount = repeatCount
        self.minimumDurationQuarters = minimumDurationQuarters
    }

    public var durationQuarters: Double {
        let extent = max(events.map { $0.onsetQuarters + $0.durationQuarters }.max() ?? 0,
                         minimumDurationQuarters ?? 0)
        return extent > 0 ? extent : Double(timeSignature.beats) * 4 / Double(timeSignature.beatType)
    }
}

/// An unsupported recognized mark awaiting comparison with the source page.
/// Retained separately so editing notes never silently removes the release gate.
public struct ScoreReviewIssue: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var measureIndex: Int
    public var measureNumber: String
    public var eventID: String
    public var mark: String
}

public struct NormalizedScore: Codable, Equatable, Sendable {
    public var source: ScoreSource
    public var title: String
    public var composer: String?
    public var partName: String
    public var tempo: Double
    public var measures: [NormalizedMeasure]
    public var warnings: [String]
    public var reviewIssues: [ScoreReviewIssue]? = nil

    public var notes: [NormalizedNote] {
        measures.flatMap(\.events).compactMap { event in
            guard case let .note(note) = event else { return nil }
            return note
        }
    }

    /// alphaTab ties continue inside a rendered voice. Keep the source voice
    /// unchanged while placing a tied continuation in its anchor's render voice.
    public var renderedVoices: [String: String] {
        var result: [String: String] = [:]
        for measure in measures {
            for event in measure.events.sorted(by: { $0.onsetQuarters == $1.onsetQuarters ? $0.id < $1.id : $0.onsetQuarters < $1.onsetQuarters }) {
                if case let .note(note) = event, let anchor = note.tieFromID, let voice = result[anchor] {
                    result[note.id] = voice
                } else { result[event.id] = event.voice }
            }
        }
        return result
    }

    public var renderedVoiceIndices: [String: Int] {
        let mapping = renderedVoices
        let names = Array(Set(mapping.values)).sorted()
        let indices = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, $0.offset) })
        return mapping.mapValues { indices[$0]! }
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
                        tieStop: note.tieStop, voice: note.voice, staff: note.staff, tieFromID: note.tieFromID, slurFromID: note.slurFromID, slurKind: note.slurKind
                    ))
                }
            }
            return NormalizedMeasure(
                id: measure.id,
                index: measure.index,
                number: measure.number,
                timeSignature: measure.timeSignature,
                keyFifths: measure.keyFifths,
                events: shiftedEvents, repeatStart: measure.repeatStart, repeatCount: measure.repeatCount,
                minimumDurationQuarters: measure.minimumDurationQuarters
            )
        }
        return NormalizedScore(
            source: source,
            title: title,
            composer: composer,
            partName: partName,
            tempo: tempo,
            measures: shiftedMeasures,
            warnings: warnings, reviewIssues: reviewIssues
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
