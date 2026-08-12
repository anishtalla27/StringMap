import Foundation
import SwiftData
import FingeringEngine
import ScorePipeline

@Model
final class SongDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var composer: String?
    var sourceName: String
    var sourceType: String
    var importedAt: Date
    var updatedAt: Date
    var musicXML: Data
    var tuningPresetRaw: String
    var customTuningData: Data
    var capo: Int
    var maxFret: Int
    var profileRaw: String
    var transposition: Int
    var lastPracticedPosition: Double
    var lockedPositionsData: Data
    var generatedArrangementState: String

    init(
        id: UUID = UUID(),
        title: String,
        composer: String?,
        sourceName: String,
        musicXML: Data
    ) {
        self.id = id
        self.title = title
        self.composer = composer
        self.sourceName = sourceName
        sourceType = "MusicXML"
        importedAt = .now
        updatedAt = .now
        self.musicXML = musicXML
        let defaults = UserDefaults.standard
        tuningPresetRaw = defaults.string(forKey: "defaultTuning") ?? GuitarTuningPreset.standard.rawValue
        customTuningData = Self.encode(GuitarTuning.standard.openMIDIPitches)
        capo = defaults.object(forKey: "defaultCapo") as? Int ?? 0
        maxFret = defaults.object(forKey: "defaultFrets") as? Int ?? 20
        profileRaw = defaults.string(forKey: "defaultProfile") ?? FingeringProfile.balanced.rawValue
        transposition = 0
        lastPracticedPosition = 0
        lockedPositionsData = Self.encode([String: GuitarPosition]())
        generatedArrangementState = "Ready"
    }

    var tuningPreset: GuitarTuningPreset {
        GuitarTuningPreset(rawValue: tuningPresetRaw) ?? .standard
    }

    var customTuningMIDIs: [Int] {
        Self.decode([Int].self, from: customTuningData) ?? GuitarTuning.standard.openMIDIPitches
    }

    var profile: FingeringProfile {
        FingeringProfile(rawValue: profileRaw) ?? .balanced
    }

    var lockedPositions: [String: GuitarPosition] {
        Self.decode([String: GuitarPosition].self, from: lockedPositionsData) ?? [:]
    }

    @MainActor
    func open(in model: AppModel) {
        model.load(
            data: musicXML,
            sourceName: sourceName,
            songID: id,
            profile: profile,
            tuningPreset: tuningPreset,
            customTuningMIDIs: customTuningMIDIs,
            capo: capo,
            maxFret: maxFret,
            transposition: transposition,
            lastPositionMilliseconds: lastPracticedPosition,
            lockedPositions: lockedPositions
        )
    }

    @MainActor
    func update(from model: AppModel) {
        guard model.currentSongID == id else { return }
        if let result = model.pipelineResult {
            title = result.score.title
            composer = result.score.composer
            generatedArrangementState = "\(result.fingering.steps.count) notes · \(model.profile.displayName)"
        }
        sourceName = model.sourceName
        musicXML = model.sourceData ?? musicXML
        tuningPresetRaw = model.tuningPreset.rawValue
        customTuningData = Self.encode(model.customTuningMIDIs)
        capo = model.capo
        maxFret = model.maxFret
        profileRaw = model.profile.rawValue
        transposition = model.transposition
        lastPracticedPosition = model.player.cursorMilliseconds
        lockedPositionsData = Self.encode(model.lockedPositionsForPersistence)
        updatedAt = .now
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}
