import XCTest

final class SongbookUITests: XCTestCase {
    @MainActor
    func testSongbookArrangementSwitchingAndPlayback() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["homeSongbook"].waitForExistence(timeout: 25))
        app.buttons["homeSongbook"].tap()
        let melody = app.buttons["songbook-amazing-grace-melody"]
        XCTAssertTrue(melody.waitForExistence(timeout: 10)); melody.tap()
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 45))
        let cursor = app.sliders["Playback position"]
        cursor.adjust(toNormalizedSliderPosition: 0)
        app.buttons["stopPlayback"].tap()
        let board = app.otherElements["guitarFretboard"]
        let first = board.value as? String
        app.buttons["playPause"].tap()
        expectation(for: NSPredicate(format: "label != '0:00'"), evaluatedWith: app.staticTexts["playbackTime"])
        waitForExpectations(timeout: 15)
        expectation(for: NSPredicate { _, _ in board.value as? String != first }, evaluatedWith: board)
        waitForExpectations(timeout: 15)
        app.buttons["playPause"].tap()
        XCTAssertTrue(app.staticTexts["Playback paused"].waitForExistence(timeout: 8))
        capture("songbook-melody-paused", app)
        cursor.adjust(toNormalizedSliderPosition: 0.5)
        let saved = app.staticTexts["playbackTime"].label
        app.buttons["switch-chords"].tap()
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.staticTexts["activeChord"].exists)
        app.buttons["stopPlayback"].tap()
        app.buttons["playPause"].tap()
        expectation(for: NSPredicate { _, _ in (board.value as? String)?.contains("Sounding chord:") == true }, evaluatedWith: board)
        waitForExpectations(timeout: 12)
        app.buttons["playPause"].tap()
        capture("songbook-chords-paused", app)
        app.buttons["switch-melody"].tap()
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 40))
        expectation(for: NSPredicate { _, _ in app.staticTexts["playbackTime"].label == saved }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        capture("songbook-melody-restored", app)
    }

    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        // Capture the display: app-scoped crops can retain portrait coordinates after iPad rotation.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}

extension SongbookUITests {
    @MainActor
    func testEverySongbookArrangementClockSeekingAndFretboard() throws {
        continueAfterFailure = false
        struct Catalog: Decodable { let songs: [Song] }
        struct Song: Decodable { let id: String; let arrangements: [Arrangement] }
        struct Arrangement: Decodable {
            let id: String; let kind: String; let chords: [Chord]
            let durationQuarters: Double; let events: [Event]; let positions: [String: Position]
        }
        struct Event: Decodable { let id: String; let onsetQuarters: Double; let durationQuarters: Double; let midi: Int? }
        struct Position: Decodable { let string: Int; let fret: Int }
        struct Chord: Decodable { let onset: Double; let duration: Double; let root: Int; let quality: String }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "catalog", withExtension: "json"))
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        XCTAssertEqual(catalog.songs.count, 20)
        let app = XCUIApplication()
        for song in catalog.songs {
            for arrangement in song.arrangements {
                app.launchEnvironment["STRINGMAP_SONGBOOK_ID"] = arrangement.id
                app.launch()
                XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 45), arrangement.id)
                app.buttons["stopPlayback"].tap()
                let cursor = app.sliders["Playback position"]
                let board = app.otherElements["guitarFretboard"]
                XCTAssertTrue(board.exists, arrangement.id)
                app.buttons["playPause"].tap()
                expectation(for: NSPredicate(format: "label != '0:00'"), evaluatedWith: app.staticTexts["playbackTime"])
                waitForExpectations(timeout: 15)
                if arrangement.kind == "chords" {
                    XCTAssertTrue((board.value as? String)?.contains("Sounding chord:") == true, arrangement.id)
                }
                app.buttons["playPause"].tap()
                XCTAssertTrue(app.staticTexts["Playback paused"].waitForExistence(timeout: 8))
                capture(arrangement.id + "-beginning", app)
                for fraction in [0.5, 0.85] {
                    cursor.adjust(toNormalizedSliderPosition: fraction)
                    XCTAssertTrue(board.exists)
                    capture(arrangement.id + (fraction == 0.5 ? "-middle" : "-ending"), app)
                }
                if arrangement.kind == "chords" {
                    app.buttons["stopPlayback"].tap()
                    var previous = ""
                    for (index, chord) in arrangement.chords.enumerated() {
                        if index > 0 { app.buttons["songbookNextMeasure"].tap() }
                        let shape = "\(chord.root)\(chord.quality)"
                        guard shape != previous else { continue }
                        previous = shape
                        let quarter = chord.onset + chord.duration * 0.5
                        let expected = arrangement.events.filter {
                            $0.midi != nil && quarter >= $0.onsetQuarters && quarter < $0.onsetQuarters + $0.durationQuarters
                        }.compactMap { arrangement.positions[$0.id] }.map { "string \($0.string), fret \($0.fret)" }
                        let diagnostic = XCTAttachment(string: "\(arrangement.id) change \(index + 1), quarter \(quarter), slider \(cursor.value ?? "nil"), time \(app.staticTexts["playbackTime"].label), board \(board.value ?? "nil"), expected \(expected)")
                        diagnostic.lifetime = .keepAlways; add(diagnostic)
                        expectation(for: NSPredicate { _, _ in
                            let value = board.value as? String ?? ""
                            let tones = value.components(separatedBy: "Sounding chord: ").last ?? ""
                            return Set(tones.components(separatedBy: "; ")) == Set(expected)
                        }, evaluatedWith: board)
                        waitForExpectations(timeout: 8)
                        capture(arrangement.id + "-change-\(index + 1)", app)
                    }
                }
                app.buttons["stopPlayback"].tap()
                XCTAssertEqual(app.staticTexts["playbackTime"].label, "0:00")
                app.terminate()
            }
        }
    }
}

extension SongbookUITests {
    @MainActor
    func testEveryArrangementPracticeSettingsAndRelaunch() throws {
        continueAfterFailure = false
        struct Catalog: Decodable { let songs: [Song] }
        struct Song: Decodable { let arrangements: [Arrangement] }
        struct Arrangement: Decodable { let id: String; let kind: String }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "catalog", withExtension: "json"))
        let book = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        let app = XCUIApplication()
        for arrangement in book.songs.flatMap(\.arrangements) {
            app.launchEnvironment["STRINGMAP_SONGBOOK_ID"] = arrangement.id
            app.launch()
            XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 45))
            app.sliders["Playback position"].adjust(toNormalizedSliderPosition: 0.85)
            capture(arrangement.id + "-final-ending", app)
            app.buttons["stopPlayback"].tap()
            XCTAssertEqual(app.staticTexts["playbackTime"].label, "0:00")
            capture(arrangement.id + "-final-restart", app)
            app.buttons["Practice"].tap()
            app.buttons["75%"].tap()
            app.buttons["practiceNextMeasure"].tap()
            app.buttons["practiceLoopCurrentMeasure"].tap()
            for name in ["Count-in", "Metronome"] {
                let toggle = app.switches[name]
                for _ in 0..<8 where !toggle.isHittable { app.swipeUp() }
                XCTAssertTrue(toggle.isHittable, name)
                if toggle.value as? String == "0" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
                XCTAssertEqual(toggle.value as? String, "1", name)
            }
            app.buttons["Done"].tap()
            XCTAssertEqual(app.buttons["Loop current measure"].value as? String, "Loop on")
            let before = app.staticTexts["playbackTime"].label
            app.buttons["playPause"].tap()
            expectation(for: NSPredicate { _, _ in app.staticTexts["playbackTime"].label != before }, evaluatedWith: app)
            waitForExpectations(timeout: 20)
            app.buttons["playPause"].tap()
            XCTAssertTrue(app.staticTexts["Playback paused"].waitForExistence(timeout: 8))
            let paused = app.staticTexts["playbackTime"].label
            app.switches["songbookShowTab"].tap()
            XCTAssertEqual(app.staticTexts["playbackTime"].label, paused)
            app.switches["songbookShowTab"].tap()
            app.buttons["Practice"].tap()
            app.buttons["Reset to score tempo"].tap()
            let clearLoop = app.buttons["Clear loop"]
            for _ in 0..<8 where !clearLoop.isHittable { app.swipeUp() }
            clearLoop.tap()
            for name in ["Count-in", "Metronome"] {
                let toggle = app.switches[name]
                for _ in 0..<8 where !toggle.isHittable { app.swipeUp() }
                XCTAssertTrue(toggle.isHittable, name)
                if toggle.value as? String == "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
                XCTAssertEqual(toggle.value as? String, "0", name)
            }
            app.buttons["Done"].tap()
            XCTAssertEqual(app.buttons["Loop current measure"].value as? String, "Loop off")
            app.sliders["Playback position"].adjust(toNormalizedSliderPosition: 0.5)
            let saved = app.staticTexts["playbackTime"].label
            let other = arrangement.kind == "melody" ? "chords" : "melody"
            app.buttons["switch-" + other].tap()
            XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 45))
            app.buttons["switch-" + arrangement.kind].tap()
            XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 45))
            expectation(for: NSPredicate { _, _ in app.staticTexts["playbackTime"].label == saved }, evaluatedWith: app)
            waitForExpectations(timeout: 8)
            app.terminate(); app.launch()
            XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 45))
            expectation(for: NSPredicate { _, _ in app.staticTexts["playbackTime"].label == saved }, evaluatedWith: app)
            waitForExpectations(timeout: 8)
            app.buttons["stopPlayback"].tap()
            app.terminate()
        }
    }
}

extension SongbookUITests {
    @MainActor
    func testSongbookLargeTextOrientationAndRecovery() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["STRINGMAP_SONGBOOK_ID"] = "amazing-grace-chords"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL", "-leftHanded", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 45))
        app.buttons["stopPlayback"].tap()
        let board = app.otherElements["guitarFretboard"]
        XCTAssertTrue((board.value as? String)?.contains("Sounding chord:") == true)
        capture("songbook-large-text-left-handed", app)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        // Geometry changes before the rotation compositor finishes. Capture a
        // settled frame, then scroll the accessibility layout to its notation.
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertTrue(app.buttons["playPause"].isHittable)
        capture("songbook-large-text-landscape", app)
        app.swipeUp()
        capture("songbook-large-text-landscape-score", app)
        XCUIDevice.shared.orientation = .portrait
        expectation(for: NSPredicate { _, _ in app.frame.height > app.frame.width }, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        app.buttons["Tuning, capo, and transposition"].tap()
        let capo = app.steppers["instrumentCapo"]
        for _ in 0..<4 { capo.buttons.element(boundBy: 1).tap() }
        app.buttons["Apply"].tap()
        let restore = app.buttons["Restore original guitar settings"]
        XCTAssertTrue(restore.waitForExistence(timeout: 30))
        capture("songbook-unplayable-recovery", app)
        restore.tap()
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 45))
        XCTAssertTrue((board.value as? String)?.contains("Sounding chord:") == true)
        app.buttons["playPause"].tap()
        expectation(for: NSPredicate(format: "label != '0:00'"), evaluatedWith: app.staticTexts["playbackTime"])
        waitForExpectations(timeout: 15)
        app.buttons["playPause"].tap()
        capture("songbook-restored-large-text", app)
        app.terminate()
    }

    @MainActor
    func testSongbookPublicStoreScreenshots() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-leftHanded", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["homeSongbook"].waitForExistence(timeout: 30))
        capture("store-07-songbook-home", app)
        app.buttons["homeSongbook"].tap()
        XCTAssertTrue(app.buttons["songbook-amazing-grace-melody"].waitForExistence(timeout: 10))
        capture("store-08-songbook-library", app)
        app.buttons["songbook-amazing-grace-melody"].tap()
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 45))
        app.buttons["stopPlayback"].tap()
        // WKWebView seek and cursor scrolling finish asynchronously after the native label.
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        capture("store-09-songbook-melody", app)
        app.buttons["switch-chords"].tap()
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 45))
        app.buttons["stopPlayback"].tap()
        app.buttons["songbookNextMeasure"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        capture("store-10-songbook-chords", app)
    }
}
