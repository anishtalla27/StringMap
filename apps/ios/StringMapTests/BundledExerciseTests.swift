import XCTest
import FingeringEngine
import ScorePipeline
@testable import StringMap

final class BundledExerciseTests: XCTestCase {
    struct Entry: Decodable {
        let resource: String
        let title: String
        let tempo: Double
        let beats: Int
        let beatType: Int
        let events: [Event]
    }
    struct Event: Decodable {
        let id: String
        let measureIndex: Int
        let onsetQuarters: Double
        let durationQuarters: Double
        let midi: Int?
    }

    @MainActor
    func testEveryAuthoredEventAndFretboardAtAllPracticeSpeeds() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "Exercises"))
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
        XCTAssertEqual(entries.count, 18)
        XCTAssertEqual(DemoScore.all.map(\.resource), entries.map(\.resource))
        for entry in entries {
            let xml = try XCTUnwrap(Bundle.main.url(forResource: entry.resource, withExtension: "musicxml", subdirectory: "Exercises"))
            let data = try Data(contentsOf: xml)
            let result = try StructuredScorePipeline().run(musicXML: data)
            XCTAssertEqual(result.score.title, entry.title)
            XCTAssertEqual(result.score.tempo, entry.tempo)
            XCTAssertFalse(result.score.needsPolyphonicFingering)
            XCTAssertTrue(result.score.warnings.isEmpty, "\(entry.title): \(result.score.warnings)")
            XCTAssertEqual(result.score.measures.count, 8)
            let actual = result.score.measures.flatMap(\.events)
            XCTAssertEqual(actual.count, entry.events.count)
            let model = AppModel(loadSample: false)
            model.pipelineResult = result
            for (expected, event) in zip(entry.events, actual) {
                XCTAssertEqual(event.id, expected.id)
                XCTAssertEqual(event.onsetQuarters, expected.onsetQuarters)
                XCTAssertEqual(event.durationQuarters, expected.durationQuarters)
                if case let .note(note) = event { XCTAssertEqual(note.midi, expected.midi) }
                else { XCTAssertNil(expected.midi) }
                let start = Double(expected.measureIndex * entry.beats) * 4 / Double(entry.beatType) + expected.onsetQuarters
                for speed in [0.25, 0.5, 0.75, 1.0, 1.5, 2.0] {
                    model.setPlaybackSpeed(speed)
                    // Bridge normalizes speed-adjusted time to this score clock.
                    model.player.seek(milliseconds: (start + expected.durationQuarters / 2) * 60_000 / entry.tempo)
                    XCTAssertEqual(model.activeSteps.map(\.note.id), expected.midi == nil ? [] : [expected.id], entry.title)
                    if let step = model.activeStep {
                        XCTAssertEqual(result.fingering.tuning.openMIDIPitches[step.position.string - 1] + step.position.physicalFret, expected.midi)
                    }
                }
            }
            for profile in FingeringProfile.allCases {
                let variant = try StructuredScorePipeline().run(musicXML: data, options: .init(profile: profile))
                XCTAssertEqual(variant.score.notes, result.score.notes)
                XCTAssertEqual(variant.fingering.steps.count, result.score.notes.count)
            }
        }
    }
}
