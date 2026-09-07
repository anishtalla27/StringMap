import XCTest
@testable import ScorePipeline

final class MeasureTimingTests: XCTestCase {
    func testTrailingForwardPreservesSilenceThroughSaveAndTransposition() throws {
        let score = try read(measure(note("a") + forward(3)) + measure(note("b"), number: 2))
        XCTAssertEqual(score.measures.map(\.durationQuarters), [4, 1])
        XCTAssertEqual(score.measures[0].minimumDurationQuarters, 4)
        XCTAssertEqual(score.notes.map(\.id), ["a", "b"])
        XCTAssertEqual(score.measures[0].events.count, 1, "Do not invent a printed rest")
        let restored = try MusicXMLImporter().importScore(from: MusicXMLWriter.data(for: score))
        XCTAssertEqual(restored.measures, score.measures)
        let transposed = try score.transposed(by: 2)
        XCTAssertEqual(transposed.measures.map(\.durationQuarters), [4, 1])
        XCTAssertEqual(transposed.notes.map(\.midi), [66, 66])
        let stored = try JSONDecoder().decode(NormalizedScore.self, from: JSONEncoder().encode(score))
        XCTAssertEqual(stored, score)
    }

    func testForwardEndSurvivesBackupAndPartialSilentMeasure() throws {
        let score = try read(measure(forward(4) + "<backup><duration>4</duration></backup>" + note("a"))
            + measure(forward(2), number: 2) + measure(note("b"), number: 3))
        XCTAssertEqual(score.measures.map(\.durationQuarters), [4, 2, 1])
        XCTAssertTrue(score.measures[1].events.isEmpty)
        XCTAssertEqual(try MusicXMLImporter().importScore(from: MusicXMLWriter.data(for: score)).measures, score.measures)
    }

    func testPickupAndInternalForwardAreNotPadded() throws {
        let score = try read(measure(note("a")) + measure(forward(1) + note("b"), number: 2))
        XCTAssertEqual(score.measures.map(\.durationQuarters), [1, 2])
        XCTAssertTrue(score.measures.allSatisfy { $0.minimumDurationQuarters == nil })
        XCTAssertEqual(try MusicXMLImporter().importScore(from: MusicXMLWriter.data(for: score)).measures, score.measures)
        let legacy = try JSONEncoder().encode(score)
        XCTAssertFalse(String(decoding: legacy, as: UTF8.self).contains("minimumDurationQuarters"))
        XCTAssertEqual(try JSONDecoder().decode(NormalizedScore.self, from: legacy), score)
    }

    func testTieCannotCrossAnExplicitSilentGap() throws {
        let content = measure(note("a", tie: "start") + forward(3)) + measure(note("b", tie: "stop"), number: 2)
        XCTAssertThrowsError(try read(content))
        let review = try MusicXMLImporter().importScore(from: Data(xml(content).utf8), forReview: true)
        XCTAssertNil(review.notes.last?.tieFromID)
        XCTAssertEqual(review.notes.count, 2)
        XCTAssertFalse(review.warnings.isEmpty)
    }

    func testRepeatsAndExplicitExtentNeverTruncateNotes() throws {
        var score = try read(measure(note("a") + forward(3) + "<barline><repeat direction='backward' times='2'/></barline>"))
        XCTAssertEqual(try score.expandingRepeats().measures.map(\.durationQuarters), [4, 4])
        score.measures[0].minimumDurationQuarters = 0.5
        XCTAssertEqual(score.measures[0].durationQuarters, 1)
        for invalid in [0.0, -1, 161, .infinity, .nan] {
            score.measures[0].minimumDurationQuarters = invalid
            XCTAssertThrowsError(try ScoreValidator.validate(score))
        }
    }

    private func read(_ content: String) throws -> NormalizedScore {
        try MusicXMLImporter().importScore(from: Data(xml(content).utf8))
    }
    private func xml(_ content: String) -> String {
        "<score-partwise><part id='P1'>\(content)</part></score-partwise>"
    }
    private func measure(_ content: String, number: Int = 1) -> String {
        "<measure number='\(number)'><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>\(content)</measure>"
    }
    private func note(_ id: String, tie: String? = nil) -> String {
        "<note id='\(id)'><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration>\(tie.map { "<tie type='\($0)'/>" } ?? "")</note>"
    }
    private func forward(_ value: Int) -> String { "<forward><duration>\(value)</duration></forward>" }
}
