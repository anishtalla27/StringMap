import XCTest
import FingeringEngine
@testable import ScorePipeline

final class GuitarSlurTests: XCTestCase {
    private func xml(_ kind: String, highFirst: Bool = false, close: Bool = true) -> Data {
        let a = highFirst ? "G" : "E", b = highFirst ? "E" : "G"
        return Data("""
        <score-partwise><part-list><score-part id="P1"><part-name>Guitar</part-name></score-part></part-list><part id="P1"><measure number="1"><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
        <note id="a"><pitch><step>\(a)</step><octave>4</octave></pitch><duration>1</duration><notations><technical><\(kind) type="start" number="1"/></technical></notations></note>
        <note id="b"><pitch><step>\(b)</step><octave>4</octave></pitch><duration>1</duration>\(close ? "<notations><technical><\(kind) type=\"stop\" number=\"1\"/></technical></notations>" : "")</note>
        <note><rest/><duration>2</duration></note></measure></part></score-partwise>
        """.utf8)
    }
    func testBundledSlursPreserveLinksAndTechnique() throws {
        for kind in ["hammer-on", "pull-off"] {
            let data = xml(kind, highFirst: kind == "pull-off")
            XCTAssertThrowsError(try MusicXMLImporter().importScore(from: data), "General import remains out of scope")
            let score = try MusicXMLImporter(allowGuitarSlurs: true).importScore(from: data)
            XCTAssertEqual(score.notes[1].slurFromID, "a")
            let locks = Dictionary(uniqueKeysWithValues: score.notes.map { ($0.id, GuitarPosition(string: 1, fret: $0.midi-64, midi: $0.midi)) })
            let result = try StructuredScorePipeline().run(score: score, options: .init(lockedPositions: locks))
            XCTAssertTrue(result.alphaTex.contains("{h}"))
            let roundTrip = try MusicXMLImporter(allowGuitarSlurs: true).importScore(from: MusicXMLWriter.data(for: score))
            XCTAssertEqual(roundTrip.notes[1].slurFromID, "a")
            XCTAssertEqual(try score.transposed(by: 1).notes[1].slurFromID, "a")
            XCTAssertEqual(try JSONDecoder().decode(NormalizedScore.self, from: JSONEncoder().encode(score)), score)
        }
    }
    func testUnclosedWrongDirectionAndWrongStringAreRejected() throws {
        XCTAssertThrowsError(try MusicXMLImporter(allowGuitarSlurs: true).importScore(from: xml("hammer-on", close: false)))
        let wrong = try MusicXMLImporter(allowGuitarSlurs: true).importScore(from: xml("hammer-on", highFirst: true))
        XCTAssertThrowsError(try StructuredScorePipeline().run(score: wrong))
        let score = try MusicXMLImporter(allowGuitarSlurs: true).importScore(from: xml("hammer-on"))
        XCTAssertThrowsError(try StructuredScorePipeline().run(score: score, options: .init(lockedPositions: ["a": .init(string: 1, fret: 0, midi: 64), "b": .init(string: 2, fret: 8, midi: 67)])))
    }
}
