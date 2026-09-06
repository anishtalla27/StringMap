import Foundation
import XCTest
@testable import ScorePipeline

final class GuitarPhotoPitchTests: XCTestCase {
    private func source(_ transpose: String = "", octave: Int = 4) -> Data {
        Data("""
        <score-partwise><part id="P1"><measure number="1"><attributes>
        <divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef>
        \(transpose)</attributes><note id="held"><pitch><step>E</step><octave>\(octave)</octave></pitch>
        <duration>4</duration><voice>2</voice><tie type="start"/></note>
        <note id="chord"><chord/><pitch><step>B</step><octave>4</octave></pitch><duration>4</duration><voice>2</voice></note>
        <backup><duration>4</duration></backup><note id="silence"><rest/><duration>4</duration><voice>1</voice></note></measure>
        <measure number="2"><note id="continuation"><pitch><step>E</step><octave>\(octave)</octave></pitch>
        <duration>4</duration><voice>2</voice><tie type="stop"/></note></measure></part></score-partwise>
        """.utf8)
    }

    func testWrittenGuitarPhotoSoundsOneOctaveLowerPreservingEventsAndTies() throws {
        let importer = MusicXMLImporter()
        let encoded = try importer.importScore(from: source())
        let photo = try importer.importScore(from: source(), forReview: false, pitchConvention: .guitarWritten)
        XCTAssertEqual(photo, try encoded.transposed(by: -12))
        XCTAssertEqual(photo.notes.map(\.midi), [59, 52, 52])
        XCTAssertEqual(photo.notes.last?.tieFromID, "held")
    }

    func testExplicitTranspositionOverridesPhotoDefaultRatherThanDoublingIt() throws {
        for transpose in ["<transpose><chromatic>0</chromatic><octave-change>-1</octave-change></transpose>",
                          "<transpose><chromatic>0</chromatic></transpose>",
                          "<transpose><chromatic>2</chromatic></transpose>"] {
            let xml = source(transpose)
            XCTAssertEqual(try MusicXMLImporter().importScore(from: xml, forReview: false, pitchConvention: .guitarWritten),
                           try MusicXMLImporter().importScore(from: xml))
        }
    }

    func testCorrectedPhotoSaveReopenDoesNotApplyTheOctaveAgain() throws {
        let photo = try MusicXMLImporter().importScore(from: source(), forReview: false, pitchConvention: .guitarWritten)
        let reopened = try MusicXMLImporter().importScore(from: MusicXMLWriter.data(for: photo))
        XCTAssertEqual(reopened.notes, photo.notes)
        XCTAssertEqual(reopened.measures.flatMap(\.events), photo.measures.flatMap(\.events))
    }

    func testPhotoPitchOutsideMIDIRangeFailsWithoutWrappingOrDroppingNotes() {
        XCTAssertThrowsError(try MusicXMLImporter().importScore(from: source(octave: -1), forReview: true, pitchConvention: .guitarWritten))
    }
}
