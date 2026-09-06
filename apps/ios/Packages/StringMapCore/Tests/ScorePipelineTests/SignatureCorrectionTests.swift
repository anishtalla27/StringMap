import XCTest
@testable import ScorePipeline

final class SignatureCorrectionTests: XCTestCase {
    private func fixture() throws -> NormalizedScore {
        let xml = """
        <score-partwise><part id="P1">
        <measure number="1"><attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time></attributes><note id="a"><pitch><step>E</step><octave>4</octave></pitch><duration>4</duration><tie type="start"/></note></measure>
        <measure number="2"><note id="b"><pitch><step>E</step><octave>4</octave></pitch><duration>4</duration><tie type="stop"/></note></measure>
        <measure number="3"><attributes><key><fifths>2</fifths></key></attributes><note id="c"><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>2</duration></note><note id="r"><rest/><duration>2</duration></note></measure>
        <measure number="4"><attributes><time><beats>3</beats><beat-type>4</beat-type></time></attributes><note id="d"><pitch><step>G</step><octave>4</octave></pitch><duration>3</duration></note></measure>
        <measure number="5"><attributes><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time></attributes><note id="e"><pitch><step>A</step><octave>4</octave></pitch><duration>4</duration></note></measure>
        </part></score-partwise>
        """
        return try MusicXMLImporter().importScore(from: Data(xml.utf8))
    }

    func testSignatureCorrectionsStopIndependentlyAndPreserveMusicThroughXML() throws {
        let original = try fixture()
        let edited = try original.updatingSignatures(at: 0, timeSignature: .init(beats: 6, beatType: 8),
                                                     keyFifths: -2, includeFollowing: true)
        XCTAssertEqual(edited.measures.map(\.keyFifths), [-2, -2, 2, 2, 0])
        XCTAssertEqual(edited.measures.map(\.timeSignature), [.init(beats: 6, beatType: 8), .init(beats: 6, beatType: 8),
                       .init(beats: 6, beatType: 8), .init(beats: 3, beatType: 4), .init(beats: 4, beatType: 4)])
        XCTAssertEqual(edited.measures.map(\.events), original.measures.map(\.events))
        XCTAssertEqual(edited.measures.map(\.durationQuarters), original.measures.map(\.durationQuarters))
        let reopened = try MusicXMLImporter().importScore(from: MusicXMLWriter.data(for: edited))
        XCTAssertEqual(reopened.measures.map(\.timeSignature), edited.measures.map(\.timeSignature))
        XCTAssertEqual(reopened.measures.map(\.keyFifths), edited.measures.map(\.keyFifths))
        XCTAssertEqual(reopened.notes.map(\.midi), original.notes.map(\.midi))
        XCTAssertEqual(reopened.notes.map(\.id), original.notes.map(\.id))
        XCTAssertEqual(reopened.notes.map(\.tieFromID), original.notes.map(\.tieFromID))
        XCTAssertNoThrow(try AlphaTexGenerator.notation(score: reopened))
    }

    func testSelectedMeasureScopeAndInvalidSignaturesLeaveOtherMusicUntouched() throws {
        let original = try fixture()
        let edited = try original.updatingSignatures(at: 1, timeSignature: .init(beats: 7, beatType: 8),
                                                     keyFifths: 3, includeFollowing: false)
        XCTAssertEqual(edited.measures[0], original.measures[0])
        XCTAssertEqual(Array(edited.measures[2...]), Array(original.measures[2...]))
        XCTAssertEqual(edited.measures[1].keyFifths, 3)
        for index in [-1, 5] {
            XCTAssertThrowsError(try original.updatingSignatures(at: index, timeSignature: .init(beats: 4, beatType: 4), keyFifths: 0, includeFollowing: true))
        }
        for (beats, unit, key) in [(0, 4, 0), (33, 4, 0), (4, 3, 0), (4, 4, 8)] {
            XCTAssertThrowsError(try original.updatingSignatures(at: 0, timeSignature: .init(beats: beats, beatType: unit), keyFifths: key, includeFollowing: true))
        }
    }
}
