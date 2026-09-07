import Foundation
import ScorePipeline
import FingeringEngine

// Machine-readable release verification using the shipping Swift pipeline.
let path = CommandLine.arguments.dropFirst().first ?? ""
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let forReview = CommandLine.arguments.contains("--for-review")
    let importOnly = CommandLine.arguments.contains("--import-only")
    let imported = try MusicXMLImporter().importScore(from: data, forReview: forReview,
        pitchConvention: CommandLine.arguments.contains("--guitar-photo") ? .guitarWritten : .asEncoded)
    let score = try (forReview || importOnly) ? imported : imported.expandingRepeats()
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let normalized = try JSONSerialization.jsonObject(with: encoder.encode(score))
    var output: [String: Any] = ["parsed": true, "score": normalized, "renderedVoiceIndices": score.renderedVoiceIndices]
    if !importOnly {
        do {
            let tuning: GuitarTuning = CommandLine.arguments.contains("--drop-d") ? GuitarTuningPreset.dropD.tuning! : .standard
            let result = try StructuredScorePipeline().run(score: score, options: .init(tuning: tuning))
            output["score"] = try JSONSerialization.jsonObject(with: encoder.encode(result.score))
            output["renderedVoiceIndices"] = result.score.renderedVoiceIndices
            output["tuning"] = result.fingering.tuning.openMIDIPitches
            output["alphaTex"] = result.alphaTex
            output["positions"] = result.fingering.steps.map { ["id": $0.note.id, "midi": $0.note.midi,
                "string": $0.position.string, "fret": $0.position.fret, "physicalFret": $0.position.physicalFret] as [String: Any] }
            output["tabPlayable"] = true
        } catch { output["tabPlayable"] = false; output["tabError"] = error.localizedDescription }
        do { output["notationAlphaTex"] = try AlphaTexGenerator.notation(score: score) }
        catch { output["notationError"] = error.localizedDescription }
    }
    let result = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    print(String(decoding: result, as: UTF8.self))
} catch {
    let data = try JSONSerialization.data(withJSONObject: ["parsed": false, "error": error.localizedDescription])
    print(String(decoding: data, as: UTF8.self))
}
