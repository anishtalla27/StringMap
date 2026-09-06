import XCTest
@testable import ScorePipeline

final class CrossVoiceTieTests: XCTestCase {
    func testTieChangesVoiceWithoutChangingSourceIdentityOrVoice() throws {
        let xml = Self.xml(Self.note("anchor", voice: "2", tie: "start") + Self.note("continuation", voice: "1", tie: "stop"))
        let score = try MusicXMLImporter().importScore(from: Data(xml.utf8))
        XCTAssertEqual(score.notes.map(\.voice), ["2", "1"])
        XCTAssertEqual(score.notes.last?.tieFromID, "anchor")
        XCTAssertEqual(score.renderedVoices["continuation"], "2")
        XCTAssertEqual(score.renderedVoiceIndices["anchor"], score.renderedVoiceIndices["continuation"])
        let restored = try MusicXMLImporter().importScore(from: MusicXMLWriter.data(for: score))
        XCTAssertEqual(restored.notes.map(\.id), score.notes.map(\.id))
        XCTAssertEqual(restored.notes.map(\.voice), score.notes.map(\.voice))
        XCTAssertEqual(restored.notes.last?.tieFromID, "anchor")
    }

    func testAmbiguousCrossVoiceUnisonIsNotGuessed() throws {
        let xml = Self.xml(Self.note("a", voice: "2", tie: "start") + "<backup><duration>1</duration></backup>" + Self.note("b", voice: "3", tie: "start") + Self.note("end", voice: "1", tie: "stop"))
        XCTAssertThrowsError(try MusicXMLImporter().importScore(from: Data(xml.utf8)))
        let review = try MusicXMLImporter().importScore(from: Data(xml.utf8), forReview: true)
        XCTAssertEqual(review.notes.count, 3)
        XCTAssertNil(review.notes.last?.tieFromID)
        XCTAssertFalse(review.warnings.isEmpty)
    }

    func testTieReviewWarningsRefreshWithoutDiscardingRecognitionWarnings() throws {
        let xml = Self.xml(Self.note("a", voice: "1", tie: "start"))
        var review = try MusicXMLImporter().importScore(from: Data(xml.utf8), forReview: true)
        review.warnings.append("Check the source image for missing notes.")
        let repeated = try ScoreValidator.validate(review, allowUnresolvedTies: true)
        XCTAssertEqual(repeated.warnings, review.warnings.filter { !$0.contains("A tied note needs") } + ["A tied note needs a continuation or removal of its tie mark."])
        guard case var .note(note) = review.measures[0].events[0] else { return XCTFail("Expected a note") }
        note.tieStart = false
        review.measures[0].events[0] = .note(note)
        let corrected = try ScoreValidator.validate(review)
        XCTAssertEqual(corrected.warnings, ["Check the source image for missing notes."])
        XCTAssertEqual(corrected.notes.map(\.id), ["a"])
        XCTAssertEqual(corrected.notes.map(\.midi), [64])
        XCTAssertNoThrow(try MusicXMLWriter.data(for: corrected))
    }

    private static func xml(_ notes: String) -> String {
        "<score-partwise><part-list><score-part id=\"P1\"><part-name>Guitar</part-name></score-part></part-list><part id=\"P1\"><measure number=\"1\"><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>\(notes)</measure></part></score-partwise>"
    }
    private static func note(_ id: String, voice: String, tie: String) -> String {
        "<note id=\"\(id)\"><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><tie type=\"\(tie)\"/><voice>\(voice)</voice></note>"
    }
}
