import XCTest
import FingeringEngine
import ScorePipeline
@testable import StringMap

final class AlphaTabBridgeTests: XCTestCase {
    func testParsesBridgeMessagesIntoTypedEvents() {
        XCTAssertEqual(AlphaTabEvent.parse(["type": "bridgeReady"]), .bridgeReady)
        XCTAssertEqual(AlphaTabEvent.parse(["type": "rendered"]), .rendered)
        XCTAssertEqual(
            AlphaTabEvent.parse(["type": "soundFontLoad", "loaded": 50.0, "total": 100.0]),
            .soundFontLoad(loaded: 50, total: 100)
        )
        XCTAssertEqual(AlphaTabEvent.parse(["type": "playerReady"]), .playerReady)
        XCTAssertEqual(
            AlphaTabEvent.parse(["type": "playerState", "state": 1, "stopped": false]),
            .playerState(state: 1, stopped: false)
        )
        XCTAssertEqual(
            AlphaTabEvent.parse(["type": "position", "currentTime": 1250.0]),
            .position(milliseconds: 1250, endMilliseconds: 0)
        )
        XCTAssertEqual(
            AlphaTabEvent.parse(["type": "error", "message": "broken"]),
            .error("broken")
        )
        XCTAssertNil(AlphaTabEvent.parse(["type": "unknown"]))
    }

    @MainActor
    func testControllerStateFollowsPlayerEvents() {
        let controller = AlphaTabController()
        controller.receive(.playerReady)
        XCTAssertTrue(controller.isPlayerReady)
        XCTAssertEqual(controller.playbackStatus, "Playback ready")

        controller.receive(.playerState(state: 1, stopped: false))
        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(controller.playbackStatus, "Playing synchronized score")

        controller.receive(.position(milliseconds: 2_500, endMilliseconds: 8_000))
        XCTAssertEqual(controller.cursorMilliseconds, 2_500)
        XCTAssertEqual(controller.endMilliseconds, 8_000)

        controller.receive(.playerState(state: 0, stopped: true))
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.playbackStatus, "Playback ready")
    }

    func testRequiredAlphaTabResourcesAreBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "AlphaTab"))
        XCTAssertNotNil(Bundle.main.url(forResource: "bridge", withExtension: "js", subdirectory: "AlphaTab"))
        XCTAssertNotNil(Bundle.main.url(forResource: "alphaTab.min", withExtension: "js", subdirectory: "AlphaTab"))
        XCTAssertNotNil(Bundle.main.url(forResource: "sonivox", withExtension: "sf2", subdirectory: "AlphaTab/soundfont"))
        XCTAssertNotNil(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    }

    func testBridgeImplementsRealPracticeCommands() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "bridge", withExtension: "js", subdirectory: "AlphaTab"))
        let bridge = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(bridge.contains("api.playbackSpeed"))
        XCTAssertTrue(bridge.contains("api.playbackRange"))
        XCTAssertTrue(bridge.contains("api.isLooping"))
        XCTAssertTrue(bridge.contains("api.metronomeVolume"))
        XCTAssertTrue(bridge.contains("api.countInVolume"))
    }

    func testNotationPageKeepsReadablePaperContrastInDarkMode() throws {
        let url = try XCTUnwrap(Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "AlphaTab"
        ))
        let page = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(page.contains("color-scheme: light"))
        XCTAssertTrue(page.contains("background: #fff"))
    }

    func testBundledDemoScoresCompleteTheStructuredPipelineWithCorrectPitchMath() throws {
        let demos: [(String, GuitarTuning)] = [
            ("known-melody", .standard),
            ("beginner-scale", .standard),
            ("profile-contrast", .standard),
            ("drop-d-study", .dropD),
            ("chromatic-position-study", .standard),
        ]
        for (resource, tuning) in demos {
            let url = try XCTUnwrap(Bundle.main.url(
                forResource: resource,
                withExtension: "musicxml",
                subdirectory: "Samples"
            ))
            let data = try Data(contentsOf: url)
            let result = try StructuredScorePipeline().run(
                musicXML: data,
                options: .init(tuning: tuning, maxFret: 24)
            )
            XCTAssertFalse(result.fingering.steps.isEmpty, resource)
            XCTAssertTrue(result.alphaTex.contains("\\staff{score tabs}"), resource)
            for step in result.fingering.steps {
                let soundingPitch = tuning.openMIDIPitches[step.position.string - 1]
                    + result.fingering.capo + step.position.fret
                XCTAssertEqual(soundingPitch, step.note.midi, resource)
            }
        }
    }

    @MainActor
    func testPracticeSettingsRemainInspectableWithoutAWebView() {
        let controller = AlphaTabController()
        controller.setPlaybackSpeed(0.75)
        controller.setMetronome(enabled: true)
        controller.setCountIn(enabled: true)
        controller.setLoop(startTick: 960, endTick: 3_840)
        XCTAssertEqual(controller.playbackSpeed, 0.75)
        XCTAssertTrue(controller.isMetronomeEnabled)
        XCTAssertTrue(controller.isCountInEnabled)
        XCTAssertTrue(controller.isLooping)
        controller.clearLoop()
        XCTAssertFalse(controller.isLooping)
    }
}
