import XCTest

final class StringMapUITests: XCTestCase {
    @MainActor
    func testExternalCompressedScoreThroughFilesAndLibrary() throws {
        guard ProcessInfo.processInfo.environment["STRINGMAP_RUN_EXTERNAL_FILES"] == "1" else {
            throw XCTSkip("Requires supplied Fantasy Compressed QA.mxl in Simulator Files/StringMap QA")
        }
        let app = XCUIApplication()
        app.launch()
        openExternalFile("Fantasy Compressed QA", in: app)
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Fantasy"].firstMatch.exists)
        app.buttons["playPause"].tap()
        XCTAssertTrue(app.staticTexts["Playing synchronized score"].waitForExistence(timeout: 10))
        retainScreenshot("Supplied compressed Fantasy playing", app: app)
        app.buttons["stopPlayback"].tap()
        selectTab("Library", in: app)
        let imported = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'librarySong-' AND label CONTAINS 'Fantasy'")).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 10))
        let savedIdentifier = imported.identifier
        app.terminate()
        app.launch()
        selectTab("Library", in: app)
        let saved = app.buttons[savedIdentifier]
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.tap()
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 90), app.debugDescription)
        app.buttons["playPause"].tap()
        XCTAssertTrue(app.staticTexts["Playing synchronized score"].waitForExistence(timeout: 10))
        retainScreenshot("Compressed import reopened from local library", app: app)
        app.buttons["stopPlayback"].tap()
        selectTab("Library", in: app)
        app.buttons[savedIdentifier].press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Remove from library"].waitForExistence(timeout: 5))
        app.buttons["Remove from library"].tap()
    }

    /// Uses an actual supplied score in Simulator's Files provider, not an injected import.
    @MainActor
    func testExternalCrossVoiceScoreThroughFiles() throws {
        guard ProcessInfo.processInfo.environment["STRINGMAP_RUN_EXTERNAL_FILES"] == "1" else {
            throw XCTSkip("Requires supplied Fantasy QA.musicxml in Simulator Files/StringMap QA")
        }
        let app = XCUIApplication()
        app.launch()
        openExternalFile("Fantasy QA", in: app)
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 90), app.debugDescription)
        retainScreenshot("Supplied Fantasy imported through Files", app: app)
        app.buttons["playPause"].tap()
        XCTAssertTrue(app.staticTexts["Playing synchronized score"].waitForExistence(timeout: 10))
        retainScreenshot("Supplied Fantasy playing", app: app)
        app.buttons["playPause"].tap()
    }

    @MainActor
    func testExternalLowDScoreRetainedAndRecoveredWithTuning() throws {
        guard ProcessInfo.processInfo.environment["STRINGMAP_RUN_EXTERNAL_FILES"] == "1" else {
            throw XCTSkip("Requires supplied Drop D QA.musicxml in Simulator Files/StringMap QA")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-defaultTuning", "standard", "-defaultCapo", "0"]
        app.launch()
        openExternalFile("Drop D QA", in: app)
        let warning = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Tab needs attention:'")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 40))
        retainScreenshot("Supplied low D score preserved in standard tuning", app: app)
        app.buttons["playPause"].tap()
        XCTAssertTrue(app.staticTexts["Playing synchronized score"].waitForExistence(timeout: 10))
        app.buttons["stopPlayback"].tap()
        app.buttons["Tuning, capo, and transposition"].tap()
        let tuning = app.descendants(matching: .any).matching(identifier: "instrumentTuning").firstMatch
        XCTAssertTrue(tuning.waitForExistence(timeout: 5), app.debugDescription)
        tuning.tap()
        app.buttons["Drop D"].tap()
        app.buttons["Apply"].tap()
        XCTAssertTrue(app.buttons["showTrace"].waitForExistence(timeout: 40), app.debugDescription)
        XCTAssertFalse(warning.exists)
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 40))
        retainScreenshot("Supplied low D score recovered with Drop D tab", app: app)
        app.buttons["playPause"].tap()
        XCTAssertTrue(app.staticTexts["Playing synchronized score"].waitForExistence(timeout: 10))
        app.buttons["stopPlayback"].tap()
    }

    @MainActor
    private func openExternalFile(_ name: String, in app: XCUIApplication) {
        app.buttons["homeImportMusicXML"].tap()
        app.buttons["importMusicXML"].tap()
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        // Files may restore the last folder, in which case no navigation is needed.
        if file.waitForExistence(timeout: 3) { file.tap(); return }
        let browse = app.buttons.matching(identifier: "Browse")
        if browse.firstMatch.waitForExistence(timeout: 10), let tab = browse.allElementsBoundByAccessibilityElement.max(by: { $0.frame.minY < $1.frame.minY }) { tab.tap() }
        let local = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "On My i")).firstMatch
        if local.waitForExistence(timeout: 5) { local.tap() }
        let folder = app.cells["StringMap QA, Folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 10), app.debugDescription)
        folder.tap()
        XCTAssertTrue(file.waitForExistence(timeout: 5), app.debugDescription)
        file.tap()
    }

    /// Opt-in integration run. Seed Simulator Photos with study-13-clean.jpg
    /// and run the real development recognition service on port 8766.
    @MainActor
    func testLivePhotosRecognitionToTabAndPlayback() throws {
        guard ProcessInfo.processInfo.environment["STRINGMAP_RUN_LIVE_PHOTOS"] == "1" else {
            throw XCTSkip("Requires explicit real-service and Simulator Photos setup")
        }
        // External Fancy is a robustness fixture, not an accuracy-qualified
        // transcription. Its printed opening B5 must sound as B4 on guitar.
        continueAfterFailure = false
        let fixture = ProcessInfo.processInfo.environment["STRINGMAP_LIVE_PHOTO_FIXTURE"]
        let externalFancy = fixture == "external-fancy"
        let externalPavan = fixture == "external-pavan"
        let externalPage = externalFancy || externalPavan
        let serviceURL = ProcessInfo.processInfo.environment["STRINGMAP_LIVE_SERVICE_URL"] ?? "http://127.0.0.1:8766"
        let app = XCUIApplication()
        app.launchArguments += ["-enableScanPreview", "YES", "-omrServiceURL", serviceURL, "-defaultTuning", "standard", "-defaultCapo", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["homeScanSheetMusic"].waitForExistence(timeout: 10))
        app.buttons["homeScanSheetMusic"].tap()
        app.buttons["scanChoosePhoto"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 15))
        retainScreenshot("Actual Photos picker", app: app)
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,'")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        let pickerDetails = XCTAttachment(string: app.debugDescription)
        pickerDetails.name = "Photos accessibility before selection"
        pickerDetails.lifetime = .keepAlways
        add(pickerDetails)
        // Photos exposes the thumbnail image separately from its tappable cell
        // on iPhone. Use its observed center inside the system picker.
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // Wait for the asynchronous Photos transfer and picker dismissal. The
        // crop row is virtualized below the image on a fresh iPhone install.
        XCTAssertTrue(app.buttons["Cancel"].waitForNonExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.images["Selected guitar sheet music"].waitForExistence(timeout: 30), app.debugDescription)
        let crop = app.buttons["Crop, rotate, and straighten"]
        reveal(crop, in: app)
        crop.tap()
        XCTAssertTrue(app.navigationBars["Crop and straighten"].waitForExistence(timeout: 5))
        for _ in 0..<4 { app.buttons["Rotate 90°"].tap() }
        app.buttons["Full image"].tap()
        retainScreenshot("Real photo crop preparation", app: app)
        app.buttons["Use this crop"].tap()
        let convention = app.descendants(matching: .any).matching(identifier: "scanPitchConvention").firstMatch
        reveal(convention, in: app)
        XCTAssertTrue(convention.label.contains("Guitar notation"), "\(convention.label); \(String(describing: convention.value))")
        let consent = app.switches["Send this image for recognition"]
        reveal(consent, in: app)
        let switchControl = consent.switches.firstMatch
        if switchControl.exists { switchControl.tap() } else { consent.tap() }
        reveal(app.buttons["scanRecognize"], in: app)
        app.buttons["scanRecognize"].tap()
        XCTAssertTrue(app.navigationBars["Review Notes"].waitForExistence(timeout: 190))
        let recognizedCount = app.staticTexts["reviewNoteCount"].label
        if externalPage {
            // This scenario verifies the app flow. Record the model's count for
            // comparison with the retained raw XML; external-image accuracy is
            // a separate, currently failing benchmark, not a UI pass criterion.
            XCTAssertTrue(recognizedCount.hasSuffix(externalPavan ? "notes · 24 measures" : "notes · 21 measures"), recognizedCount)
            XCTAssertGreaterThan(Int(recognizedCount.components(separatedBy: " ")[0]) ?? 0, 0)
            let countAttachment = XCTAttachment(string: recognizedCount)
            countAttachment.name = "External recognized note count"
            countAttachment.lifetime = .keepAlways
            add(countAttachment)
        } else { XCTAssertEqual(recognizedCount, "48 notes · 4 measures") }
        if externalFancy {
            let warning = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Some stacked notes have the same pitch.")).firstMatch
            reveal(warning, in: app)
            XCTAssertTrue(warning.label.contains("All predicted notes were kept"))
        }
        retainScreenshot("Real recognized chord page", app: app)
        let title = "Live scan " + UUID().uuidString.prefix(8)
        let titleField = app.textFields["reviewTitle"]
        reveal(titleField, in: app)
        titleField.tap()
        if let previous = titleField.value as? String {
            titleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        titleField.typeText(title + "\n")
        let firstNote = app.buttons["reviewNote-event-0"]
        reveal(firstNote, in: app)
        let note = app.buttons[firstNote.identifier]
        let originalLabel = note.label
        // The independent study starts with written D4/F4/A4. Recognition may
        // order chord members differently; every member must sound in octave 3.
        XCTAssertTrue((externalFancy ? ["B4"] : externalPavan ? ["D4"] : ["D3", "F3", "A3"]).contains(originalLabel.components(separatedBy: " ·")[0]), originalLabel)
        note.tap()
        app.buttons["editOctave-Increment"].tap()
        app.buttons["Apply"].tap()
        XCTAssertNotEqual(note.label, originalLabel)
        reveal(app.buttons["Undo last edit"], in: app)
        app.buttons["Undo last edit"].tap()
        revealTowardTop(note, in: app)
        XCTAssertEqual(note.label, originalLabel)
        reveal(app.buttons["reviewPreview"], in: app)
        app.buttons["reviewPreview"].tap()
        let play = app.buttons["reviewPlay"]
        reveal(play, in: app)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: play)
        waitForExpectations(timeout: 40)
        play.tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'Pause preview'"), evaluatedWith: play)
        waitForExpectations(timeout: 8)
        retainScreenshot("Live scan playback", app: app)
        play.tap()
        reveal(app.buttons["reviewSave"], in: app)
        XCTAssertFalse(app.buttons["reviewSave"].isEnabled)
        let confirmed = app.switches["reviewConfirmed"]
        if confirmed.switches.firstMatch.exists { confirmed.switches.firstMatch.tap() } else { confirmed.tap() }
        app.buttons["reviewSave"].tap()
        XCTAssertTrue(app.navigationBars["Play"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 40))
        if externalPavan {
            let warning = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Tab needs attention:'")).firstMatch
            XCTAssertTrue(warning.waitForExistence(timeout: 10))
            retainScreenshot("Recovered scan retains notation in standard tuning", app: app)
            app.buttons["playPause"].tap()
            XCTAssertTrue(app.staticTexts["Playing synchronized score"].waitForExistence(timeout: 10))
            app.buttons["stopPlayback"].tap()
            app.buttons["Tuning, capo, and transposition"].tap()
            let tuning = app.descendants(matching: .any).matching(identifier: "instrumentTuning").firstMatch
            XCTAssertTrue(tuning.waitForExistence(timeout: 5))
            tuning.tap(); app.buttons["Drop D"].tap(); app.buttons["Apply"].tap()
            XCTAssertTrue(app.buttons["showTrace"].waitForExistence(timeout: 40))
            XCTAssertFalse(warning.exists)
            XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 40))
        }
        let board = app.descendants(matching: .any).matching(identifier: "guitarFretboard").firstMatch
        let spoken = board.value as? String ?? ""
        if externalFancy {
            XCTAssertTrue(spoken.hasPrefix("Now: string 1, fret 7"), spoken)
        } else if externalPavan {
            XCTAssertTrue(board.exists)
            XCTAssertFalse(spoken.isEmpty)
        } else {
            XCTAssertTrue(spoken.contains("Sounding chord:"))
            XCTAssertEqual(spoken.components(separatedBy: "Sounding chord: ").last?.components(separatedBy: ";").count, 3)
        }
        retainScreenshot("Saved live scan and tab", app: app)
        app.terminate()
        app.launch()
        selectTab("Library", in: app)
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
        app.staticTexts[title].press(forDuration: 1.2)
        app.buttons["Remove from library"].tap()
    }

    @MainActor
    func testUnplayableGuitarChordRetainsNotationPlaybackAndPractice() {
        let notes = ["C", "D", "E", "F", "G", "A", "B"].enumerated().map { i, pitch in
            "<note>\(i == 0 ? "" : "<chord/>")<pitch><step>\(pitch)</step><octave>4</octave></pitch><duration>4</duration></note>"
        }.joined()
        let xml = "<score-partwise><part-list><score-part id='P1'><part-name>Guitar</part-name></score-part></part-list><part id='P1'><measure number='1'><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes><direction><sound tempo='60'/></direction>\(notes)</measure><measure number='2'>\(notes)</measure></part></score-partwise>"
        let app = XCUIApplication()
        app.launchEnvironment["STRINGMAP_UI_TEST_XML_BASE64"] = Data(xml.utf8).base64EncodedString()
        app.launch()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Tab needs attention:'")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["showTrace"].exists)
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.buttons["playPause"].isEnabled)
        retainScreenshot("Notation retained for unplayable chord", app: app)
        app.buttons["playPause"].tap()
        XCTAssertTrue(app.staticTexts["Playing synchronized score"].waitForExistence(timeout: 8))
        app.buttons["stopPlayback"].tap()
        app.buttons["Practice"].tap()
        XCTAssertTrue(app.navigationBars["Practice"].waitForExistence(timeout: 5))
        app.buttons["Next measure"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["playbackTime"].label, "0:04")
    }

    @MainActor
    func testHomeSurfacesCoreFeaturesAndOpensPracticeTools() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["homeOpenScore"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["homeImportMusicXML"].exists)
        XCTAssertFalse(app.buttons["homeScanSheetMusic"].exists)
        XCTAssertTrue(app.buttons["homeIncludedStudies"].exists)
        XCTAssertTrue(app.buttons["homePracticeTools"].exists)
        XCTAssertTrue(app.buttons["homeInstrumentTools"].exists)

        app.buttons["homePracticeTools"].tap()
        XCTAssertTrue(app.navigationBars["Practice"].waitForExistence(timeout: 8))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Open String Walk"].waitForExistence(timeout: 8))
    }

    /// Debug scanning can use the local service; release uses its hosted URL.
    @MainActor
    func testPhotoRecognitionEntryShowsCameraAndPhotosChoicesWhenEnabled() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-enableScanPreview", "YES"]
        app.launch()

        XCTAssertTrue(app.buttons["homeScanSheetMusic"].waitForExistence(timeout: 8))
        app.buttons["homeScanSheetMusic"].tap()
        XCTAssertTrue(app.navigationBars["Scan Sheet Music"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["scanTakePhoto"].exists)
        XCTAssertTrue(app.buttons["scanChoosePhoto"].exists)
        XCTAssertTrue(app.staticTexts["Piano scores, chord names such as G minor, and existing tab are not interpreted."].exists)
        app.buttons["Close"].tap()
    }

    /// The debug-only toggle remains available for isolated developer tests.
    @MainActor
    func testPhotoRecognitionEntryIsHiddenWhenThePreviewIsOff() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-enableScanPreview", "NO"]
        app.launch()

        XCTAssertTrue(app.buttons["homeOpenScore"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["homeScanSheetMusic"].exists)

        selectTab("Learn", in: app)
        XCTAssertTrue(app.buttons["importMusicXML"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["importScanSheetMusic"].exists)
    }

    @MainActor
    func testStructuredScoreWorkflow() throws {
        let app = XCUIApplication()
        let fixture = """
        <score-partwise version="4.0">
          <work><work-title>UI test fixture</work-title></work>
          <part-list><score-part id="P1"><part-name>Lead</part-name></score-part></part-list>
          <part id="P1">
          <measure number="1">
            <attributes><divisions>1</divisions><time><beats>3</beats><beat-type>4</beat-type></time></attributes>
            <direction><sound tempo="90"/></direction>
            <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
            <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration></note>
            <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration></note>
          </measure>
          <measure number="2">
            <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration></note>
            <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration></note>
            <note><pitch><step>A</step><octave>4</octave></pitch><duration>1</duration></note>
          </measure>
          <measure number="3">
            <note><pitch><step>B</step><octave>4</octave></pitch><duration>1</duration></note>
            <note><pitch><step>A</step><octave>4</octave></pitch><duration>1</duration></note>
            <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration></note>
          </measure>
          <measure number="4">
            <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration></note>
            <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration></note>
            <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration></note>
          </measure>
          </part>
        </score-partwise>
        """
        app.launchEnvironment["STRINGMAP_UI_TEST_XML_BASE64"] = Data(fixture.utf8).base64EncodedString()
        app.launch()

        XCTAssertTrue(app.navigationBars["Play"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["UI test fixture"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["profilePicker"].exists)
        XCTAssertTrue(app.buttons["showTrace"].waitForExistence(timeout: 8))

        selectTab("Learn", in: app)
        XCTAssertTrue(app.buttons["importMusicXML"].waitForExistence(timeout: 3))
        selectTab("Play", in: app)
        XCTAssertTrue(app.staticTexts["UI test fixture"].waitForExistence(timeout: 5))

        app.buttons["profilePicker"].tap()
        app.buttons["Beginner"].tap()
        XCTAssertTrue(app.buttons["showTrace"].waitForExistence(timeout: 8))

        app.buttons["showTrace"].tap()
        XCTAssertTrue(app.navigationBars["Fingering Explanation"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        app.buttons["Practice"].tap()
        XCTAssertTrue(app.navigationBars["Practice"].waitForExistence(timeout: 3))
        if app.buttons["75%"].exists { app.buttons["75%"].tap() }
        app.buttons["Done"].tap()

        // The transport button is always actionable now — from another tab it
        // opens the player and queues the start — so readiness is asserted on
        // the player's own reported state rather than on the control.
        let play = app.buttons["playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 25))
        XCTAssertTrue(
            app.staticTexts["Playback ready"].waitForExistence(timeout: 40),
            "the alphaTab player should reach a ready state"
        )

        play.tap()
        XCTAssertTrue(app.staticTexts["Playing synchronized score"].waitForExistence(timeout: 8))

        // The fixture runs four measures so the cursor is observably in motion
        // for long enough to assert on; a two-second score finishes before the
        // query below can resolve.
        let playbackTime = app.staticTexts["playbackTime"]
        expectation(for: NSPredicate(format: "label != '0:00'"), evaluatedWith: playbackTime)
        waitForExpectations(timeout: 15)

        app.buttons["stopPlayback"].tap()
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 8))
    }

    /// The transport moved into the tab view's bottom accessory, so playback
    /// controls must survive leaving the Play tab.
    @MainActor
    func testTransportAccessoryStaysReachableFromEveryTab() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout: 10))
        for tab in ["Library", "Learn", "Settings", "Home"] {
            selectTab(tab, in: app)
            XCTAssertTrue(
                app.buttons["playPause"].waitForExistence(timeout: 5),
                "transport should remain docked on the \(tab) tab"
            )
        }
    }

    /// The explanation screen exists to say *why* a position won, so the
    /// interpretation must be on screen, not only raw cost numbers.
    @MainActor
    func testFingeringExplanationInterpretsCostsForTheReader() throws {
        let app = XCUIApplication()
        app.launch()

        selectTab("Play", in: app)
        let trace = app.buttons["showTrace"]
        XCTAssertTrue(trace.waitForExistence(timeout: 15))
        trace.tap()

        XCTAssertTrue(app.navigationBars["Fingering Explanation"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["What the bars mean"].waitForExistence(timeout: 5))
        let summarised = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH 'Mostly '")
        ).firstMatch
        XCTAssertTrue(summarised.waitForExistence(timeout: 5), "each note should name its dominant cost")
        app.buttons["Done"].tap()
    }

    /// The docked transport is reachable before the player has ever been
    /// instantiated. Tapping it from another tab must actually start playback
    /// rather than doing nothing.
    @MainActor
    func testTransportStartsPlaybackFromAnotherTab() throws {
        let app = XCUIApplication()
        app.launch()

        selectTab("Library", in: app)
        let play = app.buttons["playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()

        XCTAssertTrue(
            app.staticTexts["Playing synchronized score"].waitForExistence(timeout: 45),
            "tapping play from the Library tab should open the player and begin playback"
        )
        app.buttons["stopPlayback"].tap()
    }

    /// The app declares landscape support on iPhone, where the usable height is
    /// far shorter than the stacked player needs. The screen must stay usable
    /// rather than pushing content off the top.
    @MainActor
    func testPlayerRemainsUsableInLandscape() throws {
        let app = XCUIApplication()
        app.launch()
        selectTab("Play", in: app)
        XCTAssertTrue(app.buttons["showTrace"].waitForExistence(timeout: 20))

        let device = XCUIDevice.shared
        device.orientation = .landscapeLeft
        defer { device.orientation = .portrait }

        // Landscape moves the score title out of the body and into the
        // navigation bar, so the portrait "Play" bar disappearing is the signal
        // that the rotation has actually settled. Without waiting for it the
        // test can tap mid-animation, and a tap synthesized during the
        // transition is simply dropped.
        if UIDevice.current.userInterfaceIdiom == .phone {
            expectation(
                for: NSPredicate(format: "exists == false"),
                evaluatedWith: app.navigationBars["Play"]
            )
            waitForExpectations(timeout: 10)
        }

        // Everything the player needs must still be reachable, not clipped off
        // the top by an overflowing fixed-height stack.
        XCTAssertTrue(app.buttons["showTrace"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["profilePicker"].isHittable, "profile picker should stay tappable")
        XCTAssertTrue(app.buttons["playPause"].isHittable, "transport should stay tappable")
        XCTAssertTrue(app.staticTexts["playbackTime"].exists)

        app.buttons["showTrace"].tap()
        XCTAssertTrue(app.navigationBars["Fingering Explanation"].waitForExistence(timeout: 8))
        app.buttons["Done"].tap()
    }

    /// A known local draft tests correction and persistence, not recognition accuracy.
    @MainActor
    func testRecoveredScanCanBeCorrectedUndoneAuditionedAndSaved() throws {
        continueAfterFailure = false
        let bundle = Bundle(for: Self.self)
        let fixture = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "review-study", withExtension: "musicxml")))
        let title = "Review test \(UUID().uuidString.prefix(8))"
        var source = String(decoding: fixture, as: UTF8.self).replacingOccurrences(of: "StringMap reference 1", with: title)
        let firstMeasureEnd = try XCTUnwrap(source.range(of: "</measure>"))
        source.insert(contentsOf: "<forward><duration>4</duration></forward>", at: firstMeasureEnd.lowerBound)
        let firstNoteEnd = try XCTUnwrap(source.range(of: "</note>"))
        source.insert(contentsOf: "<notations><arpeggiate/></notations>", at: firstNoteEnd.lowerBound)
        let xml = Data(source.utf8)
        let image = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "review-study", withExtension: "jpg")))
        let app = XCUIApplication()
        app.launchArguments += ["-enableScanPreview", "YES"]
        app.launchEnvironment["STRINGMAP_UI_TEST_SCAN_XML_BASE64"] = xml.base64EncodedString()
        app.launchEnvironment["STRINGMAP_UI_TEST_SCAN_IMAGE_BASE64"] = image.base64EncodedString()
        app.launch()
        XCTAssertTrue(app.buttons["homeScanSheetMusic"].waitForExistence(timeout: 10))
        app.buttons["homeScanSheetMusic"].tap()
        reveal(app.buttons["scanRecognize"], in: app)
        app.buttons["scanRecognize"].tap()
        XCTAssertTrue(app.navigationBars["Review Notes"].waitForExistence(timeout: 10))
        app.buttons["Enlarge source page"].tap()
        XCTAssertTrue(app.navigationBars["Source page"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        let removeMark = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "reviewRemoveMark-")).firstMatch
        reveal(removeMark, in: app)
        XCTAssertTrue(removeMark.exists)
        retainScreenshot("Unresolved recognition mark", app: app)
        reveal(app.buttons["reviewPreview"], in: app)
        XCTAssertFalse(app.buttons["reviewPreview"].isEnabled)
        revealTowardTop(removeMark, in: app)
        removeMark.tap()
        app.buttons["reviewRemoveMarkConfirm"].firstMatch.tap()
        reveal(app.buttons["reviewPreview"], in: app)
        XCTAssertTrue(app.buttons["reviewPreview"].isEnabled)
        reveal(app.buttons["Undo last edit"], in: app)
        app.buttons["Undo last edit"].tap()
        revealTowardTop(removeMark, in: app)
        XCTAssertTrue(removeMark.exists)
        removeMark.tap()
        app.buttons["reviewRemoveMarkConfirm"].firstMatch.tap()

        let length = app.buttons["reviewMeasureLength"]
        reveal(length, in: app)
        XCTAssertTrue(length.label.contains("5 quarter notes"))
        length.tap()
        let lengthField = app.textFields["reviewMeasureLengthValue"]
        XCTAssertTrue(lengthField.waitForExistence(timeout: 5))
        lengthField.tap()
        lengthField.typeText(XCUIKeyboardKey.delete.rawValue + "6")
        app.buttons["reviewMeasureLengthSave"].tap()
        XCTAssertTrue(length.waitForExistence(timeout: 5))
        XCTAssertTrue(length.label.contains("6 quarter notes"))
        reveal(app.buttons["Undo last edit"], in: app)
        app.buttons["Undo last edit"].tap()
        revealTowardTop(length, in: app)
        XCTAssertTrue(length.label.contains("5 quarter notes"))
        length.tap()
        app.buttons["reviewMeasureLengthReset"].tap()
        XCTAssertTrue(length.waitForExistence(timeout: 5))
        XCTAssertTrue(length.label.contains("4 quarter notes"))
        reveal(app.buttons["Undo last edit"], in: app)
        app.buttons["Undo last edit"].tap()
        revealTowardTop(length, in: app)
        XCTAssertTrue(length.label.contains("5 quarter notes"))
        retainScreenshot("Imported trailing silence can be corrected and undone", app: app)

        let signatures = app.buttons["reviewSignatures"]
        revealTowardTop(signatures, in: app)
        let originalSignatures = signatures.label
        signatures.tap()
        XCTAssertTrue(app.navigationBars["Time and Key"].waitForExistence(timeout: 5))
        app.buttons["reviewTimeBeats-Decrement"].tap()
        app.buttons["reviewKeyFifths-Increment"].tap()
        app.buttons["reviewSignaturesSave"].tap()
        XCTAssertTrue(signatures.waitForExistence(timeout: 5))
        XCTAssertTrue(signatures.label.contains("3/4"), signatures.label)
        XCTAssertTrue(signatures.label.contains("1 sharp"), signatures.label)
        retainScreenshot("Time and key signatures corrected", app: app)

        let note = app.buttons["reviewNote-m0b0n0"]
        reveal(note, in: app)
        XCTAssertTrue(note.label.contains("F4"))
        retainScreenshot("Source and editable notes", app: app)
        note.tap()
        XCTAssertTrue(app.navigationBars["Edit Note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editOctave-Increment"].waitForExistence(timeout: 5))
        app.buttons["editOctave-Increment"].tap()
        app.buttons["Apply"].tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(note.label.contains("F5"))
        // Terminate before final save. The edit and its undo must be restored
        // from the ordinary scan draft, without reinjecting a test fixture.
        app.terminate()
        app.launchEnvironment = [:]
        app.launchArguments += ["-omrServiceURL", "invalid-recognition-service"]
        app.launchEnvironment["STRINGMAP_UI_TEST_RETAIN_COMMITTED_SCAN"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["homeScanSheetMusic"].waitForExistence(timeout: 10))
        app.buttons["homeScanSheetMusic"].tap()
        reveal(app.buttons["scanRecognize"], in: app)
        XCTAssertTrue(app.buttons["scanRecognize"].label.contains("Continue note review"))
        XCTAssertFalse(app.switches["Send this image for recognition"].exists)
        app.buttons["scanRecognize"].tap()
        XCTAssertTrue(app.navigationBars["Review Notes"].waitForExistence(timeout: 10))
        reveal(signatures, in: app)
        XCTAssertTrue(signatures.label.contains("3/4"), signatures.label)
        XCTAssertTrue(signatures.label.contains("1 sharp"), signatures.label)
        reveal(note, in: app)
        XCTAssertTrue(note.label.contains("F5"))
        retainScreenshot("Unfinished correction recovered after termination", app: app)
        reveal(app.buttons["Undo last edit"], in: app)
        app.buttons["Undo last edit"].tap()
        revealTowardTop(note, in: app)
        XCTAssertTrue(note.label.contains("F4"))
        reveal(app.buttons["Undo last edit"], in: app)
        app.buttons["Undo last edit"].tap()
        revealTowardTop(signatures, in: app)
        XCTAssertEqual(signatures.label, originalSignatures)

        reveal(app.buttons["reviewPreview"], in: app)
        app.buttons["reviewPreview"].tap()
        let play = app.buttons["reviewPlay"]
        reveal(play, in: app)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: play)
        waitForExpectations(timeout: 40)
        play.tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'Pause preview'"), evaluatedWith: play)
        waitForExpectations(timeout: 8)
        retainScreenshot("Correction audition", app: app)
        play.tap()

        reveal(app.buttons["reviewSave"], in: app)
        XCTAssertFalse(app.buttons["reviewSave"].isEnabled)
        let confirmation = app.switches["reviewConfirmed"]
        let switchControl = confirmation.switches.firstMatch
        if switchControl.exists { switchControl.tap() } else { confirmation.tap() }
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["reviewSave"])
        waitForExpectations(timeout: 5)
        app.buttons["reviewSave"].tap()
        XCTAssertTrue(app.navigationBars["Play"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
        app.terminate()
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.buttons["homeScanSheetMusic"].waitForExistence(timeout: 10))
        app.buttons["homeScanSheetMusic"].tap()
        let recoveredSong = app.buttons["scanOpenRecoveredSong"]
        reveal(recoveredSong, in: app)
        XCTAssertTrue(recoveredSong.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["scanRecognize"].exists)
        retainScreenshot("Committed scan recovers saved song without duplicate", app: app)
        recoveredSong.tap()
        XCTAssertTrue(app.navigationBars["Play"].waitForExistence(timeout: 10))
        selectTab("Library", in: app)
        let libraryCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'librarySong-' AND label CONTAINS %@", title))
        let librarySong = libraryCards.firstMatch
        XCTAssertTrue(librarySong.waitForExistence(timeout: 10))
        XCTAssertEqual(libraryCards.count, 1)
        librarySong.press(forDuration: 1.2)
        app.buttons["Review source and correct notes"].tap()
        XCTAssertTrue(app.navigationBars["Review Notes"].waitForExistence(timeout: 10))
        reveal(note, in: app)
        note.tap()
        XCTAssertTrue(app.buttons["editOctave-Increment"].waitForExistence(timeout: 5))
        app.buttons["editOctave-Increment"].tap()
        app.buttons["Apply"].tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(note.label.contains("F5"))
        app.terminate(); app.launch()
        selectTab("Library", in: app)
        XCTAssertTrue(librarySong.waitForExistence(timeout: 10))
        librarySong.press(forDuration: 1.2)
        app.buttons["Review source and correct notes"].tap()
        XCTAssertTrue(app.navigationBars["Review Notes"].waitForExistence(timeout: 10))
        reveal(note, in: app)
        XCTAssertTrue(note.label.contains("F5"))
        retainScreenshot("Library correction recovered after termination", app: app)
        reveal(app.buttons["reviewDiscard"], in: app)
        app.buttons["reviewDiscard"].tap()
        let discard = app.buttons["reviewDiscardConfirm"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        revealTowardTop(note, in: app)
        XCTAssertTrue(note.label.contains("F4"))
        reveal(app.buttons["Undo last edit"], in: app)
        XCTAssertFalse(app.buttons["Undo last edit"].isEnabled)
        app.buttons["Close"].tap()
        XCTAssertTrue(librarySong.waitForExistence(timeout: 10))
        librarySong.press(forDuration: 1.2)
        app.buttons["Remove from library"].tap()
    }

    @MainActor
    func testUnmatchedScanTieCanBeCorrectedBeforeAudition() throws {
        let bundle = Bundle(for: Self.self)
        let data = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "review-study", withExtension: "musicxml")))
        var xml = String(decoding: data, as: UTF8.self)
        let firstEnd = try XCTUnwrap(xml.range(of: "</note>"))
        xml.insert(contentsOf: "<tie type=\"start\"/>", at: firstEnd.lowerBound)
        let image = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "review-study", withExtension: "jpg")))
        let app = XCUIApplication()
        app.launchArguments += ["-enableScanPreview", "YES"]
        app.launchEnvironment["STRINGMAP_UI_TEST_SCAN_XML_BASE64"] = Data(xml.utf8).base64EncodedString()
        app.launchEnvironment["STRINGMAP_UI_TEST_SCAN_IMAGE_BASE64"] = image.base64EncodedString()
        app.launch()
        app.buttons["homeScanSheetMusic"].tap()
        reveal(app.buttons["scanRecognize"], in: app)
        app.buttons["scanRecognize"].tap()
        XCTAssertTrue(app.navigationBars["Review Notes"].waitForExistence(timeout: 10))
        reveal(app.buttons["reviewPreview"], in: app)
        app.buttons["reviewPreview"].tap()
        reveal(app.buttons["reviewPlay"], in: app)
        XCTAssertFalse(app.buttons["reviewPlay"].isEnabled)
        let tieError = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'A tied note has no continuation.'")).firstMatch
        reveal(tieError, in: app)
        XCTAssertTrue(tieError.waitForExistence(timeout: 5))
        let note = app.buttons["reviewNote-m0b0n0"]
        for _ in 0..<16 {
            if note.exists && note.isHittable { break }
            app.collectionViews["reviewList"].swipeDown()
        }
        XCTAssertTrue(note.isHittable)
        note.tap()
        let toggle = app.switches["Tie to next note"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.switches.firstMatch.exists { toggle.switches.firstMatch.tap() } else { toggle.tap() }
        app.buttons["Apply"].tap()
        reveal(app.buttons["reviewPreview"], in: app)
        app.buttons["reviewPreview"].tap()
        let play = app.buttons["reviewPlay"]
        reveal(play, in: app)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: play)
        waitForExpectations(timeout: 40)
        XCTAssertFalse(tieError.exists)
        play.tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'Pause preview'"), evaluatedWith: play)
        waitForExpectations(timeout: 8)
        retainScreenshot("Corrected unmatched scan tie audition", app: app)
        play.tap()
    }

    @MainActor
    private func selectTab(_ title: String, in app: XCUIApplication) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            let identifiers = ["Home": "house", "Library": "music.note.list", "Play": "guitars", "Import": "square.and.arrow.down", "Settings": "gearshape"]
            app.buttons.matching(identifier: identifiers[title]!).firstMatch.tap()
        } else {
            app.tabBars.buttons[title].tap()
        }
    }

    @MainActor
    private func reviewControlIsVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let review = app.collectionViews["reviewList"]
        guard review.exists else { return true }
        let bar = app.navigationBars["Review Notes"]
        let top = max(review.frame.minY, bar.exists ? bar.frame.maxY : review.frame.minY) + 8
        // UIKit can report a scrolled row behind the floating navigation bar as
        // hittable. Keep the entire control inside the visible list before tapping.
        return element.frame.minY >= top && element.frame.maxY <= review.frame.maxY - 8
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            if reviewControlIsVisible(element, in: app) { return }
            let review = app.collectionViews["reviewList"]
            let scan = app.collectionViews["scanList"]
            let scroll: XCUIElement = review.exists ? review : (scan.exists ? scan : app)
            let bar = app.navigationBars["Review Notes"]
            let top = review.exists && bar.exists ? max(scroll.frame.minY, bar.frame.maxY) + 8 : scroll.frame.minY + 80
            let above = element.exists && element.frame.minY < top
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: above ? 0.45 : 0.8))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: above ? 0.8 : 0.45))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(reviewControlIsVisible(element, in: app), "Expected a reachable control: \(element)")
    }

    @MainActor
    private func revealTowardTop(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.collectionViews["reviewList"]
        for _ in 0..<24 {
            if reviewControlIsVisible(element, in: app) { return }
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.35))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.8)))
        }
        XCTAssertTrue(reviewControlIsVisible(element, in: app), "Expected a reachable earlier review control")
    }

    @MainActor
    private func retainScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class OfflineReleaseUITests: XCTestCase {
    @MainActor
    func testEveryBundledExerciseRendersAndPlays() throws {
        continueAfterFailure = false
        for index in 1...18 {
            let app = XCUIApplication()
            app.launchArguments += ["-enableScanPreview", "NO"]
            app.launchEnvironment["STRINGMAP_SCREEN"] = "play"
            app.launchEnvironment["STRINGMAP_LOAD_DEMO"] = String(format: "exercise-%02d", index)
            app.launch()
            XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 45))
            // Launch routing loads the selected exercise after the initial view mounts.
            let titles = ["Open String Walk", "First Steps in C", "Two String Conversation", "Quiet Quarter Notes", "Room to Breathe", "Half Note Horizon", "Three Beat Stroll", "Eighth Note River", "Dotted Footsteps", "G Major Path", "D Major Turn", "A Minor Lantern", "Chromatic Neighbors", "Six Eight Drift", "Bass String Trail", "Upper String Answer", "Offbeat Echo", "Small Journey"]
            XCTAssertTrue(app.staticTexts[titles[index - 1]].firstMatch.waitForExistence(timeout: 15))
            XCTAssertTrue(app.otherElements["guitarFretboard"].exists)
            XCTAssertTrue(app.staticTexts["currentNotePosition"].exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = String(format: "exercise-%02d-ready", index); screenshot.lifetime = .keepAlways; add(screenshot)
            // Loop the opening bar so slow accessibility queries cannot let a
            // short exercise finish before the pause assertion.
            app.buttons["Practice"].tap()
            app.buttons["50%"].tap()
            app.buttons["practiceLoopCurrentMeasure"].tap()
            app.buttons["Done"].tap()
            app.buttons["playPause"].tap()
            XCTAssertTrue(app.staticTexts["Playing synchronized score"].waitForExistence(timeout: 10))
            let time = app.staticTexts["playbackTime"]
            expectation(for: NSPredicate(format: "label != '0:00'"), evaluatedWith: time)
            waitForExpectations(timeout: 12)
            app.buttons["playPause"].tap()
            XCTAssertTrue(app.staticTexts["Playback paused"].waitForExistence(timeout: 8))
            app.sliders["Playback position"].adjust(toNormalizedSliderPosition: 0.6)
            app.buttons["Practice"].tap()
            XCTAssertTrue(app.steppers["tempoBPM"].waitForExistence(timeout: 5))
            app.buttons["75%"].tap()
            app.buttons["Done"].tap()
            app.buttons["playPause"].tap()
            XCTAssertTrue(app.staticTexts["Playing synchronized score"].waitForExistence(timeout: 8))
            app.buttons["stopPlayback"].tap()
            XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 8))
            XCTAssertEqual(app.staticTexts["playbackTime"].label, "0:00")
            app.terminate()
        }
    }
}

final class TutorialUITests: XCTestCase {
    @MainActor
    func testAllTwelveLessonsAndPracticeControls() throws {
        continueAfterFailure = false
        let quizFrets = [0,0,1,1,2,2,0,3,2,1,2,3]
        for number in 1...12 {
            let app = XCUIApplication()
            app.launchEnvironment["STRINGMAP_TUTORIAL_ID"] = String(format: "lesson-%02d", number)
            app.launchArguments += ["-tutorialListeningPreview", "NO"]
            app.launch()
            let status = app.staticTexts["tutorialStatus"]
            XCTAssertTrue(status.waitForExistence(timeout: 40))
            expectation(for: NSPredicate(format: "label == 'Playback ready'"), evaluatedWith: status)
            waitForExpectations(timeout: 40)
            let hear = app.buttons["tutorial-stage-hear"]
            reveal(hear, app); hear.tap()
            let board = app.otherElements["guitarFretboard"]
            XCTAssertTrue(board.exists)
            if number >= 9 {
                let phrases = app.segmentedControls["tutorialPhrase"]
                reveal(phrases, app)
                phrases.buttons.element(boundBy: 1).tap()
                expectation(for: NSPredicate(format: "label == 'Playback ready'"), evaluatedWith: status)
                waitForExpectations(timeout: 20)
            }
            let tab = app.switches["tutorialShowTab"]
            reveal(tab, app); tab.tap()
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = String(format: "tutorial-%02d", number); shot.lifetime = .keepAlways; add(shot)
            let loop = app.switches["tutorialLoop"]
            reveal(loop, app); loop.tap()
            let play = app.buttons["tutorialPlay"]
            reveal(play, app); play.tap()
            expectation(for: NSPredicate(format: "label == 'Playing synchronized score'"), evaluatedWith: status)
            waitForExpectations(timeout: 10)
            play.tap()
            expectation(for: NSPredicate(format: "label == 'Playback paused'"), evaluatedWith: status)
            waitForExpectations(timeout: 10)
            app.sliders["Lesson position"].adjust(toNormalizedSliderPosition: 0.6)
            app.buttons["tutorialNext"].tap()
            app.buttons["tutorialPrevious"].tap()
            app.buttons["tutorialRestart"].tap()
            XCTAssertTrue(app.steppers["tutorialBPM"].exists)
            let practice = app.buttons["tutorial-stage-practice"]
            reveal(practice, app); practice.tap()
            let answer = app.buttons["tutorial-answer-\(quizFrets[number - 1])"]
            reveal(answer, app); answer.tap()
            XCTAssertTrue(app.staticTexts["tutorialFeedback"].label.contains("Found it"))
            let recap = app.buttons["tutorial-stage-recap"]
            reveal(recap, app); recap.tap()
            let complete = app.buttons["tutorialComplete"]
            reveal(complete, app); complete.tap()
            XCTAssertEqual(complete.label, "Completed")
            app.buttons["closeTutorial"].tap()
            XCTAssertTrue(app.buttons["homeTutorial"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }
    @MainActor
    func testLearnKeepsFreePracticeAndTutorialProgress() throws {
        let app = XCUIApplication(); app.launch()
        let tab = app.tabBars.buttons["Learn"]
        if tab.exists { tab.tap() } else { app.buttons["Learn"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["lesson-01"].waitForExistence(timeout: 10))
        app.buttons["lesson-01"].tap()
        XCTAssertTrue(app.buttons["closeTutorial"].waitForExistence(timeout: 15))
        app.buttons["closeTutorial"].tap()
        app.segmentedControls["learnMode"].buttons["Free Practice"].tap()
        XCTAssertTrue(app.buttons["exercise-exercise-01"].waitForExistence(timeout: 10))
        app.buttons["exercise-exercise-01"].tap()
        XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout: 15))
    }
    @MainActor
    func testNextLessonAndHomeResume() throws {
        let app = XCUIApplication()
        app.launchEnvironment["STRINGMAP_TUTORIAL_ID"] = "lesson-01"
        app.launch()
        let recap = app.buttons["tutorial-stage-recap"]
        XCTAssertTrue(recap.waitForExistence(timeout: 20)); reveal(recap, app); recap.tap()
        let next = app.buttons["Next lesson"]
        reveal(next, app); next.tap()
        XCTAssertTrue(app.navigationBars["Six open strings"].waitForExistence(timeout: 15))
        app.buttons["closeTutorial"].tap()
        app.buttons["homeTutorial"].tap()
        XCTAssertTrue(app.navigationBars["Six open strings"].waitForExistence(timeout: 15))
        app.buttons["closeTutorial"].tap()
    }
    @MainActor
    func testLargeTextRotationAndFreePracticeReturn() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        XCTAssertTrue(app.buttons["homeTutorial"].waitForExistence(timeout: 20))
        let freePracticeTitle = app.buttons["playbackStatus"].label
        reveal(app.buttons["homeTutorial"], app); app.buttons["homeTutorial"].tap()
        let hear = app.buttons["tutorial-stage-hear"]
        XCTAssertTrue(hear.waitForExistence(timeout: 20)); hear.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let status = app.staticTexts["tutorialStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 30))
        let next = app.buttons["tutorialNext"]
        reveal(next, app); next.tap()
        XCTAssertTrue(app.staticTexts["tutorialNote"].exists)
        let toggle = app.switches["tutorialShowTab"]
        reveal(toggle, app); toggle.tap()
        XCTAssertGreaterThan(app.frame.width, app.frame.height, "The lesson window should adopt landscape geometry")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "tutorial-large-text-landscape"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["tutorial-stage-recap"].tap()
        let complete = app.buttons["tutorialComplete"]
        reveal(complete, app); complete.tap()
        XCUIDevice.shared.orientation = .portrait
        app.buttons["closeTutorial"].tap()
        XCTAssertTrue(app.buttons["homeTutorial"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["playbackStatus"].label, freePracticeTitle)
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            let above = element.exists && element.frame.minY < app.frame.minY + 100
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: above ? 0.3 : 0.8))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: above ? 0.8 : 0.3))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable, "Unreachable tutorial control: \(element)")
    }
}

/// Exercises the public navigation in the actual Release configuration. No
/// debug score routing, seeded library, or scanner flags are needed.
final class ReleaseTutorialUITests: XCTestCase {
    @MainActor
    func testUpdatedLearnStoreScreen() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["homeTutorial"].waitForExistence(timeout: 20))
        selectTab("Learn", app)
        app.segmentedControls["learnMode"].buttons["Tutorial Mode"].tap()
        reveal(app.buttons["lesson-01"], app)
        XCTAssertTrue(app.staticTexts["24 lessons. See the shape, hear the sound, then take your turn. Every lesson is open to you."].exists)
        capture("02-learn")
    }

    @MainActor
    func testBarreContrastAndActiveNotation() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["homeTutorial"].waitForExistence(timeout: 20))
        for number in [20,21] {
            selectTab("Learn", app)
            app.segmentedControls["learnMode"].buttons["Tutorial Mode"].tap()
            let lesson = app.buttons["lesson-\(number)"]; reveal(lesson, app); lesson.tap()
            XCTAssertTrue(app.buttons["tutorial-stage-hear"].waitForExistence(timeout: 20))
            app.buttons["tutorial-stage-hear"].tap()
            let picker = app.segmentedControls["tutorialPhrase"]
            reveal(picker, app); picker.buttons.element(boundBy: number == 21 ? 1 : 0).tap()
            let status = app.staticTexts["tutorialStatus"]
            expectation(for: NSPredicate(format: "label == 'Playback ready'"), evaluatedWith: status)
            waitForExpectations(timeout: 40)
            let tab = app.switches["tutorialShowTab"]
            reveal(tab, app); if tab.value as? String != "1" { tab.tap() }
            let restart = app.buttons["tutorialRestart"]; reveal(restart, app); restart.tap()
            if number == 21 {
                reveal(app.otherElements["guitarFretboard"], app); capture("barre-clear-finger-numbers")
            } else {
                app.buttons["tutorialPlay"].tap()
                expectation(for: NSPredicate(format: "label == 'Playing synchronized score'"), evaluatedWith: status)
                waitForExpectations(timeout: 10)
                reveal(app.descendants(matching: .any).matching(identifier: "tutorialNotation").firstMatch, app)
                capture("active-triad-notation-highlight")
            }
            app.buttons["closeTutorial"].tap()
        }
    }

    @MainActor
    func testAuthoredTechniqueTransitions() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["homeTutorial"].waitForExistence(timeout: 20))
        let cases: [(Int,Int,[Int])] = [
            (16,0,Array(0...7)),(16,1,Array(0...7)),
            (20,0,[0,1]),(20,1,[0,1]),(21,0,[0,1,2,4]),(21,1,[0,2]),
            (22,0,[0,1,4,5]),(22,1,[0,1,4,5]),
            (23,0,[0,1,4,5]),(23,1,[0,1,2,4,5,6]),
            (24,0,[0,1,2,3,4,5,8,9,16,17,18,19,20,21]),
            (24,1,[0,1,2,3,8,16,24,32,40,48,56])
        ]
        for (number,phrase,steps) in cases {
            selectTab("Learn", app)
            app.segmentedControls["learnMode"].buttons["Tutorial Mode"].tap()
            let lesson = app.buttons["lesson-\(number)"]; reveal(lesson, app); lesson.tap()
            XCTAssertTrue(app.buttons["tutorial-stage-hear"].waitForExistence(timeout: 20))
            app.buttons["tutorial-stage-hear"].tap()
            let picker = app.segmentedControls["tutorialPhrase"]
            reveal(picker, app); picker.buttons.element(boundBy: phrase).tap()
            expectation(for: NSPredicate(format: "label == 'Playback ready'"), evaluatedWith: app.staticTexts["tutorialStatus"])
            waitForExpectations(timeout: 40)
            let mirror = app.switches["tutorialLeftHanded"]
            reveal(mirror, app); if mirror.value as? String == "1" { mirror.tap() }
            let tab = app.switches["tutorialShowTab"]
            reveal(tab, app); if tab.value as? String != "1" { tab.tap() }
            let next = app.buttons["tutorialNext"]
            reveal(next, app); app.buttons["tutorialRestart"].tap()
            for step in 0...steps.max()! {
                if step > 0 { reveal(next, app); next.tap() }
                if steps.contains(step) {
                    reveal(app.otherElements["guitarFretboard"], app)
                    capture("transition-\(number)-\(phrase+1)-step-\(step)")
                }
            }
            app.buttons["closeTutorial"].tap()
        }
    }

    @MainActor
    func testSixEightLoopWrapsWithoutStopping() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["homeTutorial"].waitForExistence(timeout: 20))
        selectTab("Learn", app)
        app.segmentedControls["learnMode"].buttons["Tutorial Mode"].tap()
        let lesson = app.buttons["lesson-15"]; reveal(lesson, app); lesson.tap()
        XCTAssertTrue(app.buttons["tutorial-stage-hear"].waitForExistence(timeout: 20))
        app.buttons["tutorial-stage-hear"].tap()
        let picker = app.segmentedControls["tutorialPhrase"]
        reveal(picker, app); picker.buttons.element(boundBy: 0).tap()
        expectation(for: NSPredicate(format: "label == 'Playback ready'"), evaluatedWith: app.staticTexts["tutorialStatus"])
        waitForExpectations(timeout: 40)
        let loop = app.switches["tutorialLoop"]
        reveal(loop, app); if loop.value as? String != "1" { loop.tap() }
        let cursor = app.sliders["Lesson position"]
        reveal(cursor, app); cursor.adjust(toNormalizedSliderPosition: 0.9)
        let positionValue = { Double((cursor.value as? String ?? "").filter { "0123456789.".contains($0) }) ?? .nan }
        let beforeWrap = positionValue()
        XCTAssertTrue(beforeWrap.isFinite && beforeWrap > 0)
        print("Six-eight loop starts at slider value: \(cursor.value ?? "missing")")
        let play = app.buttons["tutorialPlay"]; reveal(play, app); play.tap()
        expectation(for: NSPredicate { _, _ in
            return positionValue() < beforeWrap * 0.5 && play.label == "Pause"
        }, evaluatedWith: cursor)
        waitForExpectations(timeout: 12)
        play.tap(); capture("six-eight-loop-wrap")
        app.buttons["closeTutorial"].tap()
    }

    @MainActor
    func testTechniqueTutorialVisuals() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["homeTutorial"].waitForExistence(timeout: 20))
        for number in [15,19,21,22,23,24] {
            selectTab("Learn", app)
            app.segmentedControls["learnMode"].buttons["Tutorial Mode"].tap()
            let lesson = app.buttons["lesson-\(number)"]
            reveal(lesson, app); lesson.tap()
            XCTAssertTrue(app.buttons["tutorial-stage-hear"].waitForExistence(timeout: 20))
            app.buttons["tutorial-stage-hear"].tap()
            for phrase in 0...1 {
                let picker = app.segmentedControls["tutorialPhrase"]
                reveal(picker, app); picker.buttons.element(boundBy: phrase).tap()
                let status = app.staticTexts["tutorialStatus"]
                expectation(for: NSPredicate(format: "label == 'Playback ready'"), evaluatedWith: status)
                waitForExpectations(timeout: 40)
                let mirror = app.switches["tutorialLeftHanded"]
                reveal(mirror, app); if mirror.value as? String == "1" { mirror.tap() }
                let tab = app.switches["tutorialShowTab"]
                reveal(tab, app); if tab.value as? String != "1" { tab.tap() }
                let next = app.buttons["tutorialNext"]
                reveal(next, app); app.buttons["tutorialRestart"].tap(); next.tap()
                let board = app.otherElements["guitarFretboard"]
                reveal(board, app); capture("technique-\(number)-\(phrase+1)-fretboard")
                let notation = app.descendants(matching: .any).matching(identifier: "tutorialNotation").firstMatch
                reveal(notation, app); capture("technique-\(number)-\(phrase+1)-notation")
                let play = app.buttons["tutorialPlay"]
                reveal(play, app)
                let cursor = app.sliders["Lesson position"]; let old = cursor.value as? String
                play.tap()
                expectation(for: NSPredicate { _, _ in cursor.value as? String != old }, evaluatedWith: cursor)
                waitForExpectations(timeout: 12); play.tap()
                reveal(notation, app); capture("technique-\(number)-\(phrase+1)-playing-position")
            }
            app.buttons["closeTutorial"].tap()
        }
    }

    @MainActor
    func testContinuationLargeTextMirroringAndRotation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        XCTAssertTrue(app.buttons["homeTutorial"].waitForExistence(timeout: 20))
        selectTab("Learn", app)
        app.segmentedControls["learnMode"].buttons["Tutorial Mode"].tap()
        let lesson = app.buttons["lesson-17"]; reveal(lesson, app); lesson.tap()
        XCTAssertTrue(app.buttons["tutorial-stage-hear"].waitForExistence(timeout: 20))
        app.buttons["tutorial-stage-hear"].tap()
        let mirror = app.switches["tutorialLeftHanded"]
        reveal(mirror, app)
        if mirror.value as? String == "1" { mirror.tap() }
        let board = app.otherElements["guitarFretboard"]
        let high = app.buttons["tutorial-fret-1-8"]
        reveal(board, app)
        XCTAssertTrue(high.label.contains("C5"))
        let rightX = high.frame.midX
        reveal(mirror, app); mirror.tap()
        reveal(board, app)
        XCTAssertLessThan(high.frame.midX, rightX)
        capture("continuation-left-handed-large-text")
        high.tap()
        XCTAssertTrue(app.staticTexts["tutorialNote"].label.contains("C5"))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        reveal(board, app)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        capture("continuation-landscape-large-text")
        let tab = app.switches["tutorialShowTab"]
        reveal(tab, app); tab.tap()
        let play = app.buttons["tutorialPlay"]
        reveal(play, app)
        XCTAssertTrue(play.isHittable)
        app.buttons["closeTutorial"].tap()
    }

    @MainActor
    func testAllContinuationExamplesAndProgress() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["homeTutorial"].waitForExistence(timeout: 20))
        selectTab("Learn", app)
        app.segmentedControls["learnMode"].buttons["Tutorial Mode"].tap()
        let first = app.buttons["lesson-13"]
        reveal(first, app); first.tap()
        for number in 13...24 {
            let status = app.staticTexts["tutorialStatus"]
            XCTAssertTrue(status.waitForExistence(timeout: 30))
            app.buttons["tutorial-stage-hear"].tap()
            for phrase in 0...1 {
                let picker = app.segmentedControls["tutorialPhrase"]
                reveal(picker, app); picker.buttons.element(boundBy: phrase).tap()
                expectation(for: NSPredicate(format: "label == 'Playback ready'"), evaluatedWith: status)
                waitForExpectations(timeout: 40)
                let play = app.buttons["tutorialPlay"]
                reveal(play, app); app.buttons["tutorialRestart"].tap()
                let cursor = app.sliders["Lesson position"]
                let old = cursor.value as? String
                play.tap()
                expectation(for: NSPredicate { _, _ in cursor.value as? String != old }, evaluatedWith: cursor)
                waitForExpectations(timeout: 12)
                play.tap()
                expectation(for: NSPredicate(format: "label == 'Playback paused'"), evaluatedWith: status)
                waitForExpectations(timeout: 10)
                let tab = app.switches["tutorialShowTab"]
                reveal(tab, app)
                if tab.value as? String != "1" { tab.tap() }
                let board = app.otherElements["guitarFretboard"]
                for (label,position) in [("start",0.0),("middle",0.5),("end",0.95)] {
                    reveal(cursor, app); cursor.adjust(toNormalizedSliderPosition: position)
                    reveal(board, app); capture("lesson-\(number)-phrase-\(phrase+1)-\(label)")
                }
                reveal(play, app)
                app.buttons["tutorialPrevious"].tap(); app.buttons["tutorialNext"].tap()
                let bpm = app.steppers["tutorialBPM"]
                reveal(bpm, app); let oldBPM = bpm.label; bpm.buttons.element(boundBy: 1).tap()
                XCTAssertNotEqual(bpm.label, oldBPM)
                let loop = app.switches["tutorialLoop"]
                reveal(loop, app); loop.tap(); loop.tap()
            }
            app.buttons["tutorial-stage-practice"].tap()
            let wrong = app.buttons["tutorial-knowledge-1"]
            reveal(wrong, app); wrong.tap()
            XCTAssertFalse(app.staticTexts["tutorialFeedback"].label.contains("That’s right"))
            app.buttons["tutorial-knowledge-0"].tap()
            XCTAssertTrue(app.staticTexts["tutorialFeedback"].label.contains("That’s right"))
            app.buttons["tutorial-stage-recap"].tap()
            let complete = app.buttons["tutorialComplete"]
            reveal(complete, app); complete.tap(); XCTAssertEqual(complete.label,"Completed")
            if number < 24 { let next = app.buttons["Next lesson"]; reveal(next, app); next.tap() }
        }
        app.buttons["closeTutorial"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["homeTutorial"].waitForExistence(timeout: 20))
        app.buttons["homeTutorial"].tap()
        XCTAssertTrue(app.buttons["tutorialComplete"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["tutorialComplete"].label,"Completed")
        app.buttons["closeTutorial"].tap()
        selectTab("Learn", app)
        app.segmentedControls["learnMode"].buttons["Free Practice"].tap()
        let exercise=app.buttons["exercise-exercise-01"]
        reveal(exercise, app); exercise.tap()
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 40))
    }

    @MainActor
    func testPlaybackClockAdvancesAndResumes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["homeTutorial"].waitForExistence(timeout: 20))
        selectTab("Learn", app)
        app.segmentedControls["learnMode"].buttons["Tutorial Mode"].tap()
        let lesson = app.buttons["lesson-02"]
        reveal(lesson, app); lesson.tap()
        let status = app.staticTexts["tutorialStatus"]
        expectation(for: NSPredicate(format: "label == 'Playback ready'"), evaluatedWith: status)
        waitForExpectations(timeout: 40)
        app.buttons["tutorial-stage-hear"].tap()
        let play = app.buttons["tutorialPlay"]
        reveal(play, app)
        app.buttons["tutorialRestart"].tap()
        let cursor = app.sliders["Lesson position"]
        let initial = cursor.value as? String
        let board = app.otherElements["guitarFretboard"]
        let firstNote = board.value as? String
        play.tap()
        expectation(for: NSPredicate { _, _ in cursor.value as? String != initial }, evaluatedWith: cursor)
        waitForExpectations(timeout: 12)
        expectation(for: NSPredicate { _, _ in board.value as? String != firstNote }, evaluatedWith: board)
        waitForExpectations(timeout: 12)
        play.tap()
        expectation(for: NSPredicate(format: "label == 'Playback paused'"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        let paused = cursor.value as? String
        play.tap()
        expectation(for: NSPredicate { _, _ in cursor.value as? String != paused }, evaluatedWith: cursor)
        waitForExpectations(timeout: 12)
        play.tap()
        capture("playback-clock-regression")
        app.buttons["closeTutorial"].tap()
        app.segmentedControls["learnMode"].buttons["Free Practice"].tap()
        let exercise = app.buttons["exercise-exercise-01"]
        reveal(exercise, app); exercise.tap()
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 40))
        let practiceCursor = app.sliders["Playback position"]
        reveal(practiceCursor, app)
        practiceCursor.adjust(toNormalizedSliderPosition: 0)
        let practiceStart = practiceCursor.value as? String
        let practiceFirstNote = board.value as? String
        app.buttons["playPause"].tap()
        expectation(for: NSPredicate { _, _ in practiceCursor.value as? String != practiceStart }, evaluatedWith: practiceCursor)
        waitForExpectations(timeout: 12)
        expectation(for: NSPredicate { _, _ in board.value as? String != practiceFirstNote }, evaluatedWith: board)
        waitForExpectations(timeout: 12)
        app.buttons["playPause"].tap()
        XCTAssertTrue(app.staticTexts["Playback paused"].waitForExistence(timeout: 10))
        capture("free-practice-clock-regression")
    }

    @MainActor
    func testPublicCourseAndStoreScreenshots() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["homeTutorial"].waitForExistence(timeout: 20))
        capture("01-home")
        selectTab("Learn", app)
        app.segmentedControls["learnMode"].buttons["Tutorial Mode"].tap()
        let first = app.buttons["lesson-01"]
        reveal(first, app)
        capture("02-learn")
        first.tap()
        let quizFrets = [0, 0, 1, 1, 2, 2, 0, 3, 2, 1, 2, 3]
        for number in 1...12 {
            let status = app.staticTexts["tutorialStatus"]
            XCTAssertTrue(status.waitForExistence(timeout: 40))
            expectation(for: NSPredicate(format: "label == 'Playback ready'"), evaluatedWith: status)
            waitForExpectations(timeout: 40)
            app.buttons["tutorial-stage-hear"].tap()
            let board = app.otherElements["guitarFretboard"]
            XCTAssertTrue(board.exists)
            let tab = app.switches["tutorialShowTab"]
            reveal(tab, app)
            if (tab.value as? String) == "1" { tab.tap() }
            if number == 3 { reveal(board, app); capture("03-first-notes") }
            if number >= 9 {
                let examples = app.segmentedControls["tutorialPhrase"]
                reveal(examples, app); examples.buttons.element(boundBy: 1).tap()
                expectation(for: NSPredicate(format: "label == 'Playback ready'"), evaluatedWith: status)
                waitForExpectations(timeout: 30)
                if number == 9 { reveal(board, app); capture("04-chord-shape") }
            }
            let play = app.buttons["tutorialPlay"]
            reveal(play, app)
            let loop = app.switches["tutorialLoop"]
            reveal(loop, app)
            if (loop.value as? String) != "1" { loop.tap() }
            reveal(play, app); play.tap()
            expectation(for: NSPredicate(format: "label == 'Playing synchronized score'"), evaluatedWith: status)
            waitForExpectations(timeout: 10)
            play.tap()
            expectation(for: NSPredicate(format: "label == 'Playback paused'"), evaluatedWith: status)
            waitForExpectations(timeout: 10)
            app.sliders["Lesson position"].adjust(toNormalizedSliderPosition: 0.45)
            app.buttons["tutorialNext"].tap()
            app.buttons["tutorialPrevious"].tap()
            app.buttons["tutorialRestart"].tap()
            let bpm = app.steppers["tutorialBPM"]
            reveal(bpm, app)
            let oldBPM = bpm.label
            bpm.buttons.element(boundBy: 1).tap()
            XCTAssertNotEqual(bpm.label, oldBPM)
            reveal(tab, app); tab.tap()
            if number == 3 { reveal(board, app); capture("05-optional-tab") }
            app.buttons["tutorial-stage-practice"].tap()
            let wrong = app.buttons["tutorial-answer-\((quizFrets[number - 1] + 1) % 4)"]
            reveal(wrong, app); wrong.tap()
            XCTAssertFalse(app.staticTexts["tutorialFeedback"].label.contains("Found it"))
            app.buttons["tutorial-answer-\(quizFrets[number - 1])"].tap()
            XCTAssertTrue(app.staticTexts["tutorialFeedback"].label.contains("Found it"))
            XCTAssertFalse(app.buttons["Listen to me · Internal"].exists)
            app.buttons["tutorial-stage-recap"].tap()
            let complete = app.buttons["tutorialComplete"]
            reveal(complete, app); complete.tap()
            XCTAssertEqual(complete.label, "Completed")
            if number < 12 {
                let next = app.buttons["Next lesson"]
                reveal(next, app); next.tap()
            }
        }
        app.buttons["closeTutorial"].tap()
        app.segmentedControls["learnMode"].buttons["Free Practice"].tap()
        let exercise = app.buttons["exercise-exercise-01"]
        reveal(exercise, app); capture("06-free-practice"); exercise.tap()
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.otherElements["guitarFretboard"].exists)
        capture("07-play")
        selectTab("Settings", app)
        XCTAssertFalse(app.staticTexts["Developer preview"].exists)
        XCTAssertFalse(app.switches["Sheet music scanning"].exists)
        let privacy = app.buttons["Privacy policy"]
        reveal(privacy, app); privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy Policy"].waitForExistence(timeout: 10))
    }

    @MainActor private func selectTab(_ title: String, _ app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        if tab.exists { tab.tap() } else { app.buttons[title].firstMatch.tap() }
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<18 {
            let top = app.navigationBars.firstMatch.frame.maxY + 70
            if element.exists && element.isHittable && element.frame.midY > top && element.frame.midY < app.frame.maxY - 50 { return }
            let above = element.exists && element.frame.midY < top
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: above ? 0.35 : 0.8))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: above ? 0.8 : 0.35)))
        }
        XCTAssertTrue(element.isHittable, "Unreachable public control: \(element)")
    }
    @MainActor private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "store-\(name)"; shot.lifetime = .keepAlways; add(shot)
    }
}

final class ReleaseHomeUITests: XCTestCase {
    @MainActor
    func testHomeTransportLoadsPlayerAndUpdatesStatus() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let status = app.descendants(matching: .any).matching(identifier: "playbackStatus").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        XCTAssertTrue(status.label.contains("Tap to open player"), status.label)
        app.buttons["playPause"].tap()
        XCTAssertTrue(app.staticTexts["Playing synchronized score"].waitForExistence(timeout: 40))
        app.buttons["playPause"].tap()
        XCTAssertTrue(app.staticTexts["Playback paused"].waitForExistence(timeout: 10))
        let home = app.tabBars.buttons["Home"]
        if home.exists { home.tap() } else { app.buttons["Home"].firstMatch.tap() }
        XCTAssertFalse(status.label.contains("Tap to open player"), status.label)
        XCTAssertTrue(status.label.contains("Playback paused"), status.label)
    }
}
