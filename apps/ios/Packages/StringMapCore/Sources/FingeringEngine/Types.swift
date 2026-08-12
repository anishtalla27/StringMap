import Foundation

/// The six open-string pitches, ordered from string 1 (highest) to string 6 (lowest).
public struct GuitarTuning: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let openMIDIPitches: [Int]

    public init(name: String = "Custom", openMIDIPitches: [Int]) throws {
        guard openMIDIPitches.count == 6,
              openMIDIPitches.allSatisfy({ (0...127).contains($0) }) else {
            throw FingeringError.invalidTuning
        }
        self.name = name
        self.openMIDIPitches = openMIDIPitches
    }

    private init(uncheckedName name: String, pitches: [Int]) {
        self.name = name
        openMIDIPitches = pitches
    }

    public static let standard = GuitarTuning(uncheckedName: "Standard", pitches: [64, 59, 55, 50, 45, 40])
    public static let dropD = GuitarTuning(uncheckedName: "Drop D", pitches: [64, 59, 55, 50, 45, 38])
    public static let halfStepDown = GuitarTuning(uncheckedName: "Half Step Down", pitches: [63, 58, 54, 49, 44, 39])
    public static let dStandard = GuitarTuning(uncheckedName: "D Standard", pitches: [62, 57, 53, 48, 43, 38])
    public static let dadgad = GuitarTuning(uncheckedName: "DADGAD", pitches: [62, 57, 55, 50, 45, 38])

    public var pitchNames: [String] { openMIDIPitches.map(Self.pitchName) }

    private static func pitchName(_ midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[midi % 12])\(midi / 12 - 1)"
    }
}

public enum GuitarTuningPreset: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case standard
    case dropD
    case halfStepDown
    case dStandard
    case dadgad
    case custom

    public var displayName: String {
        switch self {
        case .standard: "Standard"
        case .dropD: "Drop D"
        case .halfStepDown: "Half Step Down"
        case .dStandard: "D Standard"
        case .dadgad: "DADGAD"
        case .custom: "Custom"
        }
    }

    public var tuning: GuitarTuning? {
        switch self {
        case .standard: .standard
        case .dropD: .dropD
        case .halfStepDown: .halfStepDown
        case .dStandard: .dStandard
        case .dadgad: .dadgad
        case .custom: nil
        }
    }
}

public struct FingeringNote: Equatable, Sendable {
    public let id: String
    public let midi: Int
    public let tieStop: Bool
    public let durationQuarters: Double

    public init(id: String, midi: Int, tieStop: Bool = false, durationQuarters: Double = 1) {
        self.id = id
        self.midi = midi
        self.tieStop = tieStop
        self.durationQuarters = durationQuarters
    }
}

public struct GuitarPosition: Codable, Equatable, Hashable, Sendable {
    /// Conventional guitar string number: 1 is the highest-pitched string.
    public let string: Int
    /// Tab fret, relative to the capo. Zero means the capoed open string.
    public let fret: Int
    /// Physical fret counted from the nut.
    public let physicalFret: Int
    public let midi: Int

    public init(string: Int, fret: Int, midi: Int, physicalFret: Int? = nil) {
        self.string = string
        self.fret = fret
        self.physicalFret = physicalFret ?? fret
        self.midi = midi
    }
}

/// Every term in the cost model is independently weighted and exposed in the trace.
public struct CostWeights: Equatable, Sendable {
    public let fretMovement: Double
    public let positionShift: Double
    public let stringChange: Double
    public let stringSkipping: Double
    public let largeStretch: Double
    public let fretHeight: Double
    public let openStringPreference: Double
    public let repeatedNoteConsistency: Double
    public let initialHandPosition: Double
    public let awkwardTransition: Double
    public let comfortableStretch: Double

    public init(
        fretMovement: Double,
        positionShift: Double,
        stringChange: Double,
        largeStretch: Double,
        fretHeight: Double,
        openStringPreference: Double,
        comfortableStretch: Double,
        stringSkipping: Double = 0,
        repeatedNoteConsistency: Double = 0,
        initialHandPosition: Double = 0,
        awkwardTransition: Double = 0
    ) {
        self.fretMovement = fretMovement
        self.positionShift = positionShift
        self.stringChange = stringChange
        self.stringSkipping = stringSkipping
        self.largeStretch = largeStretch
        self.fretHeight = fretHeight
        self.openStringPreference = openStringPreference
        self.repeatedNoteConsistency = repeatedNoteConsistency
        self.initialHandPosition = initialHandPosition
        self.awkwardTransition = awkwardTransition
        self.comfortableStretch = comfortableStretch
    }
}

public enum FingeringProfile: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case beginner
    case balanced
    case stayInPosition
    case minimumMovement
    case performance

    public var displayName: String {
        switch self {
        case .beginner: "Beginner"
        case .balanced: "Balanced"
        case .stayInPosition: "Stay in Position"
        case .minimumMovement: "Minimum Movement"
        case .performance: "Performance"
        }
    }
}

public enum AppliedFingeringProfile: Equatable, Sendable {
    case preset(FingeringProfile)
    case custom
}

public struct UnaryCostBreakdown: Equatable, Sendable {
    public let fretHeight: Double
    public let openStringPreference: Double
    public let initialHandPosition: Double

    public var total: Double { fretHeight + openStringPreference + initialHandPosition }
}

public struct TransitionCostBreakdown: Equatable, Sendable {
    public let fretMovement: Double
    public let positionShift: Double
    public let stringChange: Double
    public let stringSkipping: Double
    public let largeStretch: Double
    public let repeatedNoteConsistency: Double
    public let awkwardTransition: Double

    public var total: Double {
        fretMovement + positionShift + stringChange + stringSkipping + largeStretch
            + repeatedNoteConsistency + awkwardTransition
    }
}

public struct FingeringStep: Equatable, Sendable {
    public let note: FingeringNote
    public let position: GuitarPosition
    public let candidateCount: Int
    public let unary: UnaryCostBreakdown
    public let transition: TransitionCostBreakdown?
    public let incrementalCost: Double
    public let cumulativeCost: Double
    public let isLocked: Bool
}

public struct FingeringMetrics: Equatable, Sendable {
    public let positionShifts: Int
    public let stringChanges: Int
    public let stringSkips: Int
    public let openStrings: Int
    public let averagePhysicalFret: Double
    public let largestStretch: Int
    public let estimatedDifficulty: Double
}

public struct FingeringResult: Equatable, Sendable {
    public let profile: AppliedFingeringProfile
    public let weights: CostWeights
    public let tuning: GuitarTuning
    public let capo: Int
    public let maxFret: Int
    public let totalCost: Double
    public let steps: [FingeringStep]
    public let metrics: FingeringMetrics
}

public struct OptimizationOptions: Equatable, Sendable {
    public var tuning: GuitarTuning
    /// Last physical fret available on the instrument, counted from the nut.
    public var maxFret: Int
    public var capo: Int
    public var profile: FingeringProfile
    public var customWeights: CostWeights?
    public var preferredHandPosition: Int?
    public var lockedPositions: [String: GuitarPosition]
    /// Used by the score pipeline before candidate generation. The engine itself expects already-transposed notes.
    public var transposeSemitones: Int

    public init(
        tuning: GuitarTuning = .standard,
        maxFret: Int = 20,
        capo: Int = 0,
        profile: FingeringProfile = .balanced,
        customWeights: CostWeights? = nil,
        preferredHandPosition: Int? = nil,
        lockedPositions: [String: GuitarPosition] = [:],
        transposeSemitones: Int = 0
    ) {
        self.tuning = tuning
        self.maxFret = maxFret
        self.capo = capo
        self.profile = profile
        self.customWeights = customWeights
        self.preferredHandPosition = preferredHandPosition
        self.lockedPositions = lockedPositions
        self.transposeSemitones = transposeSemitones
    }
}

public struct CapoSuggestion: Equatable, Sendable {
    public let capo: Int
    public let result: FingeringResult
    public let improvement: Double
}

public enum FingeringError: Error, Equatable, LocalizedError, Sendable {
    case invalidMIDI(Int)
    case invalidMaxFret(Int)
    case invalidCapo(Int)
    case invalidTuning
    case unplayableNote(id: String, midi: Int)
    case invalidLockedPosition(id: String)
    case noValidPath

    public var errorDescription: String? {
        switch self {
        case let .invalidMIDI(midi):
            "MIDI pitch must be from 0 to 127; received \(midi)."
        case let .invalidMaxFret(maxFret):
            "maxFret must be non-negative; received \(maxFret)."
        case let .invalidCapo(capo):
            "Capo must be between zero and the instrument's last fret; received \(capo)."
        case .invalidTuning:
            "A guitar tuning must contain six valid MIDI pitches."
        case let .unplayableNote(id, midi):
            "Note \(id) (MIDI \(midi)) is outside this guitar's playable range."
        case let .invalidLockedPosition(id):
            "The locked fingering for note \(id) is not playable with the current tuning, capo, or fret count."
        case .noValidPath:
            "No valid fingering path exists; a tie or locked fingering may be incompatible."
        }
    }
}
