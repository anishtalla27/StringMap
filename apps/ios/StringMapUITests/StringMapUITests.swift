import XCTest

final class StringMapUITests: XCTestCase {
    @MainActor
    func testStructuredScoreWorkflow() throws {
        let app = XCUIApplication()
        let fixture = """
        <score-partwise version="4.0">
          <work><work-title>UI test fixture</work-title></work>
          <part-list><score-part id="P1"><part-name>Lead</part-name></score-part></part-list>
          <part id="P1"><measure number="1">
            <attributes><divisions>1</divisions><time><beats>3</beats><beat-type>4</beat-type></time></attributes>
            <direction><sound tempo="90"/></direction>
            <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
            <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration></note>
            <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration></note>
          </measure></part>
        </score-partwise>
        """
        app.launchEnvironment["STRINGMAP_UI_TEST_XML_BASE64"] = Data(fixture.utf8).base64EncodedString()
        app.launch()

        XCTAssertTrue(app.navigationBars["StringMap"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["UI test fixture"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["profilePicker"].exists)
        XCTAssertTrue(app.buttons["showTrace"].waitForExistence(timeout: 8))

        app.tabBars.buttons["Import"].tap()
        XCTAssertTrue(app.buttons["importMusicXML"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Play"].tap()
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

        let play = app.buttons["playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 25))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: play)
        waitForExpectations(timeout: 25)

        play.tap()
        XCTAssertTrue(app.staticTexts["Playing synchronized score"].waitForExistence(timeout: 8))

        let playbackTime = app.staticTexts["playbackTime"]
        expectation(for: NSPredicate(format: "label != '0:00'"), evaluatedWith: playbackTime)
        waitForExpectations(timeout: 8)

        app.buttons["stopPlayback"].tap()
        XCTAssertTrue(app.staticTexts["Playback ready"].waitForExistence(timeout: 8))
    }
}
