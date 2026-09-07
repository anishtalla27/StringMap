import Foundation
import SwiftData
import ScorePipeline
import FingeringEngine

struct Songbook: Decodable {
    let version: Int
    let songs: [ClassicSong]

    private static let bundled = Result { try readBundle() }
    static func load() throws -> Songbook { try bundled.get() }

    private static func readBundle() throws -> Songbook {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "Songbook") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

struct ClassicSong: Decodable, Identifiable {
    let id: String
    let title: String
    let composer: String
    let difficulty: String
    let sourceURL: String
    let sourceEdition: String
    let arrangements: [ClassicArrangement]
}

struct ClassicArrangement: Decodable, Identifiable {
    let id: String
    let kind: String
    let resource: String
    let positions: [String: GuitarPosition]
    let fingers: [String: Int]
    let chords: [ClassicChord]
    let durationQuarters: Double
    let events: [ClassicEvent]
    var label: String { kind == "melody" ? "Melody" : "Chords" }

    func data() throws -> Data {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "musicxml", subdirectory: "Songbook") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    @MainActor
    func document(song: ClassicSong, context: ModelContext) throws -> SongDocument {
        let xml = try data()
        let identity = id
        var query = FetchDescriptor<SongDocument>(predicate: #Predicate { $0.bundledArrangementID == identity })
        query.fetchLimit = 1
        if let existing = try context.fetch(query).first {
            if existing.musicXML != xml {
                let previous = (existing.musicXML, existing.lockedPositionsData, existing.title, existing.composer)
                existing.musicXML = xml
                existing.title = "\(song.title) · \(label)"
                existing.composer = song.composer
                // A corrected bundled score keeps practice settings and its record ID.
                // Rebuild the prescribed positions only in the authored configuration;
                // other tunings/transpositions are optimized when the document opens.
                let authored = existing.tuningPreset == .standard && existing.capo == 0 && existing.transposition == 0
                var revisedLocks = authored ? positions : [:]
                let tuning = existing.tuningPreset.tuning?.openMIDIPitches ?? existing.customTuningMIDIs
                for (noteID, lock) in existing.lockedPositions {
                    guard tuning.count == 6, let source = positions[noteID], source.midi + existing.transposition == lock.midi,
                          (1...6).contains(lock.string), lock.fret >= 0, lock.physicalFret <= existing.maxFret,
                          tuning[lock.string - 1] + lock.physicalFret == lock.midi,
                          lock.physicalFret == lock.fret + existing.capo else { continue }
                    revisedLocks[noteID] = lock
                }
                existing.lockedPositionsData = try JSONEncoder().encode(revisedLocks)
                do { try context.save() }
                catch {
                    existing.musicXML = previous.0; existing.lockedPositionsData = previous.1
                    existing.title = previous.2; existing.composer = previous.3
                    throw error
                }
            }
            return existing
        }
        let document = SongDocument(title: "\(song.title) · \(label)", composer: song.composer,
                                    sourceName: resource, musicXML: xml)
        document.bundledArrangementID = id
        document.sourceType = "Songbook"
        document.tuningPresetRaw = GuitarTuningPreset.standard.rawValue
        document.maxFret = 20
        document.profileRaw = FingeringProfile.balanced.rawValue
        document.capo = 0
        document.transposition = 0
        document.lockedPositionsData = try JSONEncoder().encode(positions)
        context.insert(document)
        do { try context.save() } catch { context.delete(document); throw error }
        return document
    }
}

struct ClassicEvent: Decodable {
    let id: String
    let measureIndex: Int
    let onsetQuarters: Double
    let durationQuarters: Double
    let midi: Int?
}

struct ClassicChord: Decodable {
    let onset: Double
    let duration: Double
    let root: Int
    let quality: String
    func name(transposition: Int) -> String {
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        return names[((root + transposition) % 12 + 12) % 12] + quality
    }
}

extension AppModel {
    var classicSelection: (ClassicSong, ClassicArrangement)? {
        guard let catalog = try? Songbook.load() else { return nil }
        for song in catalog.songs {
            if let arrangement = song.arrangements.first(where: { $0.resource == sourceName }) {
                return (song, arrangement)
            }
        }
        return nil
    }

    var classicChordLabel: String? {
        guard let (_, arrangement) = classicSelection, pipelineResult != nil else { return nil }
        let quarter = scoreQuarterPosition
        return arrangement.chords.first { quarter >= $0.onset && quarter < $0.onset + $0.duration }?.name(transposition: transposition)
    }

    var classicFingerGuidanceCompact: String? {
        guard classicFingerGuidance != nil, let (_, arrangement) = classicSelection,
              activeSteps.allSatisfy({ arrangement.positions[$0.note.id] == $0.position }) else { return nil }
        let steps = activeSteps.sorted { $0.position.string > $1.position.string }
        let strings = steps.map { String($0.position.string) }.joined(separator: "–")
        let fingers = steps.compactMap { arrangement.fingers[$0.note.id].map(String.init) }.joined(separator: "–")
        return "Strings \(strings) · Fingers \(fingers) · 0 = open"
    }

    var classicFingerGuidance: String? {
        guard let (_, arrangement) = classicSelection,
              tuning == .standard, capo == 0, transposition == 0 else { return nil }
        let labels = activeSteps.compactMap { step -> String? in
            guard arrangement.positions[step.note.id] == step.position,
                  let finger = arrangement.fingers[step.note.id] else { return nil }
            return "String \(step.position.string): \(finger == 0 ? "open" : "finger \(finger)")"
        }
        return labels.isEmpty ? nil : labels.joined(separator: " · ")
    }
}
