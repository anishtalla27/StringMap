import XCTest
import FingeringEngine
import ScorePipeline
import WebKit
@testable import StringMap

final class AlphaTabBridgeTests: XCTestCase {
    @MainActor
    func testRestoredSeekSurvivesOldScoreStopBeforeReadiness() {
        let player = AlphaTabController()
        player.prepareForNewScore()
        player.seek(milliseconds: 17000)
        player.receive(.position(milliseconds: 0, endMilliseconds: 30000))
        XCTAssertEqual(player.cursorMilliseconds, 17000)
        player.receive(.playerReady)
        player.receive(.position(milliseconds: 17000, endMilliseconds: 30000))
        XCTAssertEqual(player.cursorMilliseconds, 17000)
        player.receive(.position(milliseconds: 18000, endMilliseconds: 30000))
        XCTAssertEqual(player.cursorMilliseconds, 18000)
    }

    @MainActor
    func testRestartClearsLaterLoopAndReturnsToBeginning() {
        let model = AppModel()
        model.setLoop(startMeasure: 2, endMeasure: 3)
        model.player.seek(milliseconds: 8000)
        model.restartPiece()
        XCTAssertNil(model.loopStartMeasure)
        XCTAssertNil(model.loopEndMeasure)
        XCTAssertFalse(model.player.isLooping)
        XCTAssertEqual(model.player.cursorMilliseconds, 0)
    }

    @MainActor
    func testExplicitSilentMeasureEndRetainsSeekingAndFretboardTiming() throws {
        let xml = "<score-partwise><part id='P1'><measure number='1'><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes><direction><sound tempo='60'/></direction><note id='a'><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration></note><forward><duration>3</duration></forward></measure><measure number='2'><note id='b'><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration></note></measure></part></score-partwise>"
        let model = AppModel(loadSample: false)
        model.pipelineResult = try StructuredScorePipeline().run(musicXML: Data(xml.utf8))
        model.player.seek(milliseconds: 2500)
        XCTAssertEqual(model.currentMeasureIndex, 0)
        XCTAssertTrue(model.activeSteps.isEmpty)
        XCTAssertEqual(model.upcomingStep?.note.id, "b")
        model.nextMeasure()
        XCTAssertEqual(model.player.cursorMilliseconds, 4000)
        XCTAssertEqual(model.activeSteps.map(\.note.id), ["b"])
        model.loopCurrentMeasure()
        XCTAssertEqual(model.loopStartMeasure, 1)
        XCTAssertTrue(model.player.isLooping)
        model.previousMeasure()
        XCTAssertEqual(model.player.cursorMilliseconds, 0)
    }

    @MainActor
    func testFretboardChordSustainRestAndNextOnset() throws {
        let xml = """
        <score-partwise><part id='P1'><measure number='1'><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes><direction><sound tempo='60'/></direction>
        <note id='bass'><pitch><step>E</step><octave>2</octave></pitch><duration>2</duration><voice>2</voice></note>
        <backup><duration>2</duration></backup>
        <note id='a'><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
        <note id='b'><chord/><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
        <note id='c'><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
        <note><rest/><duration>1</duration><voice>1</voice></note>
        <note id='d'><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
        </measure></part></score-partwise>
        """
        let model = AppModel(loadSample: false)
        model.pipelineResult = try StructuredScorePipeline().run(musicXML: Data(xml.utf8))
        XCTAssertEqual(Set(model.activeSteps.map(\.note.id)), ["bass", "a", "b"])
        XCTAssertEqual(model.upcomingStep?.note.id, "c")
        model.player.seek(milliseconds: 1500)
        XCTAssertEqual(Set(model.activeSteps.map(\.note.id)), ["bass", "c"])
        XCTAssertEqual(model.upcomingStep?.note.id, "d")
        model.player.seek(milliseconds: 2500)
        XCTAssertTrue(model.activeSteps.isEmpty)
        XCTAssertNil(model.activeStep)
        XCTAssertEqual(model.upcomingStep?.note.id, "d")
        model.player.seek(milliseconds: 3500)
        XCTAssertEqual(model.activeSteps.map(\.note.id), ["d"])
        XCTAssertNil(model.upcomingStep)
    }

    @MainActor
    func testNotationWithoutTabRetainsMeasureNavigationAndLooping() throws {
        let xml = "<score-partwise><part-list><score-part id='P1'><part-name>Guitar</part-name></score-part></part-list><part id='P1'><measure number='1'><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes><direction><sound tempo='60'/></direction><note><pitch><step>C</step><octave>1</octave></pitch><duration>4</duration></note></measure><measure number='2'><note><pitch><step>C</step><octave>1</octave></pitch><duration>4</duration></note></measure></part></score-partwise>"
        let model = AppModel(loadSample: false)
        model.notationScore = try MusicXMLImporter().importScore(from: Data(xml.utf8))
        XCTAssertNil(model.pipelineResult)
        model.nextMeasure()
        XCTAssertEqual(model.player.cursorMilliseconds, 4000)
        model.loopCurrentMeasure()
        XCTAssertTrue(model.player.isLooping)
        XCTAssertEqual(model.loopStartMeasure, 1)
        model.previousMeasure()
        XCTAssertEqual(model.player.cursorMilliseconds, 0)
    }

    @MainActor
    func testLoadFailureIsNotHiddenByLaterSynthesizerEvents() {
        let controller = AlphaTabController()
        controller.receive(.error("Missing source mapping script"))
        controller.receive(.playerReady)
        controller.receive(.playerState(state: 0, stopped: true))
        controller.receive(.soundFontLoad(loaded: 100, total: 100))
        XCTAssertFalse(controller.isPlayerReady)
        XCTAssertEqual(controller.playbackStatus, "alphaTab: Missing source mapping script")
    }

    func testPageScriptsAreActuallyServedAndOtherPathsAreDenied() async throws {
        let root = try XCTUnwrap(Bundle.main.resourceURL?.appending(path: "AlphaTab"))
        let server = LoopbackResourceServer(root: root)
        defer { server.stop() }
        let url: URL = try await withCheckedThrowingContinuation { continuation in
            server.start { continuation.resume(with: $0) }
        }
        let (html, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let page = String(decoding: html, as: UTF8.self)
        let regex = try NSRegularExpression(pattern: #"<script src="([^"]+)""#)
        let matches = regex.matches(in: page, range: NSRange(page.startIndex..., in: page))
        XCTAssertGreaterThan(matches.count, 0)
        for match in matches {
            let range = try XCTUnwrap(Range(match.range(at: 1), in: page))
            let path = String(page[range])
            let (body, response) = try await URLSession.shared.data(from: url.deletingLastPathComponent().appending(path: path))
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, path)
            XCTAssertEqual(body, try Data(contentsOf: root.appending(path: path)), path)
        }
        let (_, denied) = try await URLSession.shared.data(from: url.deletingLastPathComponent().appending(path: "Info.plist"))
        XCTAssertEqual((denied as? HTTPURLResponse)?.statusCode, 404)
    }

    @MainActor
    func testRecreatedPlayerInvalidatesOldReadinessAndIgnoresLateDetach() {
        let controller = AlphaTabController()
        let oldView = WKWebView()
        let replacement = WKWebView()
        controller.attach(oldView)
        controller.receive(.playerReady)
        controller.receive(.playerState(state: 1, stopped: false))
        controller.attach(replacement)
        XCTAssertFalse(controller.isBridgeReady)
        XCTAssertFalse(controller.isPlayerReady)
        XCTAssertFalse(controller.isPlaying)
        controller.detach(oldView)
        XCTAssertTrue(controller.webView === replacement)
        controller.detach(replacement)
        XCTAssertNil(controller.webView)
    }

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
        XCTAssertNotNil(Bundle.main.url(forResource: "source-note-map", withExtension: "js", subdirectory: "AlphaTab"))
        XCTAssertNotNil(Bundle.main.url(forResource: "alphaTab.min", withExtension: "js", subdirectory: "AlphaTab"))
        XCTAssertNotNil(Bundle.main.url(forResource: "stringmap-guitar", withExtension: "sf2", subdirectory: "AlphaTab/soundfont"))
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

    func testNotationPageIsThemeableRatherThanFixedWhitePaper() throws {
        let url = try XCTUnwrap(Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "AlphaTab"
        ))
        let page = try String(contentsOf: url, encoding: .utf8)
        // The score follows the app's appearance instead of always being white
        // paper, so the page must drive its colours from custom properties.
        XCTAssertTrue(page.contains("--paper"))
        XCTAssertTrue(page.contains("background: var(--paper)"))
        XCTAssertTrue(page.contains("var(--cursor-bar)"))

        let bridgeURL = try XCTUnwrap(Bundle.main.url(
            forResource: "bridge",
            withExtension: "js",
            subdirectory: "AlphaTab"
        ))
        let bridge = try String(contentsOf: bridgeURL, encoding: .utf8)
        XCTAssertTrue(bridge.contains("setTheme"))
        for key in ["staffLineColor", "mainGlyphColor", "secondaryGlyphColor", "barNumberColor"] {
            XCTAssertTrue(bridge.contains(key), "bridge must set \(key)")
        }
    }

    func testBothScoreThemesKeepReadablePaperContrast() throws {
        for theme in [ScoreTheme(dark: false), ScoreTheme(dark: true)] {
            let payload = theme.payload
            let paper = try XCTUnwrap(payload["paper"] as? String)
            let ink = try XCTUnwrap(payload["mainGlyph"] as? String)
            let paperLuminance = try XCTUnwrap(Self.luminance(paper))
            let inkLuminance = try XCTUnwrap(Self.luminance(ink))

            // Engraved notation is fine detail; it needs a wide separation from
            // the paper it sits on in either appearance.
            XCTAssertGreaterThan(
                abs(paperLuminance - inkLuminance),
                0.5,
                "dark: \(theme.dark) paper \(paper) against ink \(ink)"
            )
            XCTAssertEqual(paperLuminance > 0.5, !theme.dark)
        }
    }

    /// Relative luminance, so the assertion is about perceived contrast rather
    /// than raw channel values.
    private static func luminance(_ hex: String) -> Double? {
        guard let value = UInt32(hex.replacingOccurrences(of: "#", with: ""), radix: 16) else { return nil }
        let channels = [
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255,
        ].map { channel in
            channel <= 0.039_28 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
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

    /// The release default for the recognition preview is a shipping decision,
    /// not a preference: assert it rather than trusting the directive.
    func testRecognitionPreviewDefaultsOffOutsideDebugBuilds() {
        #if DEBUG
        XCTAssertFalse(FeatureFlags.scanEnabledByDefault)
        #else
        XCTAssertFalse(FeatureFlags.scanEnabledByDefault)
        #endif
    }
}
