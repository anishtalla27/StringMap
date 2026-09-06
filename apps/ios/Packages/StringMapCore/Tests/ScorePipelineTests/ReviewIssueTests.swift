import XCTest
@testable import ScorePipeline

final class ReviewIssueTests: XCTestCase {
    private func xml(_ mark: String) -> Data {
        Data("""
        <score-partwise><part id="P1"><measure number="7"><attributes><divisions>1</divisions></attributes>
        <note id="source-a"><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><notations>\(mark)</notations></note>
        <note id="source-r"><rest/><duration>1</duration></note></measure></part></score-partwise>
        """.utf8)
    }

    func testReviewKeepsExactEventsAndAllMarksWhileStrictImportRejects() throws {
        let baseline = try MusicXMLImporter().importScore(from: xml(""))
        for mark in ["<arpeggiate/>", "<fermata/>", "<ornaments><trill-mark/><turn/><mordent/></ornaments>", "<articulations><staccato/><staccatissimo/></articulations>"] {
            let data = xml(mark)
            XCTAssertThrowsError(try MusicXMLImporter().importScore(from: data))
            let review = try MusicXMLImporter().importScore(from: data, forReview: true)
            XCTAssertEqual(review.measures, baseline.measures)
            XCTAssertFalse(try XCTUnwrap(review.reviewIssues).isEmpty)
            for issue in review.reviewIssues ?? [] {
                XCTAssertEqual(issue.eventID, "source-a")
                XCTAssertEqual(issue.measureNumber, "7")
                XCTAssertEqual(issue.measureIndex, 0)
            }
            XCTAssertEqual(Set(review.reviewIssues!.map(\.id)).count, review.reviewIssues!.count)
        }
    }

    func testUnresolvedMarksCannotBypassSerializationPlaybackOrTransposition() throws {
        let review = try MusicXMLImporter().importScore(from: xml("<arpeggiate/>"), forReview: true)
        let baseline = try MusicXMLImporter().importScore(from: xml(""))
        let fingering = try StructuredScorePipeline().run(score: baseline).fingering
        for score in [review, try review.transposed(by: -12), try review.expandingRepeats()] {
            XCTAssertEqual(score.reviewIssues, review.reviewIssues)
            XCTAssertThrowsError(try ScoreValidator.validate(score, allowUnresolvedTies: true))
            XCTAssertThrowsError(try MusicXMLWriter.data(for: score))
            XCTAssertThrowsError(try AlphaTexGenerator.notation(score: score))
            XCTAssertThrowsError(try AlphaTexGenerator.generate(score: score, fingering: fingering))
            XCTAssertThrowsError(try StructuredScorePipeline().run(score: score))
        }
        var corrected = review
        corrected.reviewIssues?.removeAll()
        let reopened = try MusicXMLImporter().importScore(from: MusicXMLWriter.data(for: corrected))
        XCTAssertEqual(reopened.notes, baseline.notes)
        XCTAssertNoThrow(try StructuredScorePipeline().run(score: reopened))
    }

    func testReviewDoesNotAdmitStructuralOrTimingUnsupportedNotation() {
        for mark in ["<tremolo>3</tremolo>", "<slide/>", "<bend/>", "<octave-shift/>", "<ending/>"] {
            XCTAssertThrowsError(try MusicXMLImporter().importScore(from: xml(mark), forReview: true))
        }
        let outside = String(decoding: xml(""), as: UTF8.self).replacingOccurrences(of: "<notations></notations>", with: "<staccato/>")
        XCTAssertThrowsError(try MusicXMLImporter().importScore(from: Data(outside.utf8), forReview: true))
    }

    func testCodablePreservesIssuesAndDecodesOlderScores() throws {
        let score = try MusicXMLImporter().importScore(from: xml("<arpeggiate/>"), forReview: true)
        let data = try JSONEncoder().encode(score)
        XCTAssertEqual(try JSONDecoder().decode(NormalizedScore.self, from: data), score)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "reviewIssues")
        XCTAssertNil(try JSONDecoder().decode(NormalizedScore.self, from: JSONSerialization.data(withJSONObject: old)).reviewIssues)
    }
}
