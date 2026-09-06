import Foundation
import XCTest
import ZIPFoundation
@testable import ScorePipeline

final class MusicXMLContainerTests: XCTestCase {
    private let xml = Data("<score-partwise><part id='P1'><measure number='1'><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes><note id='original-note'><pitch><step>E</step><octave>4</octave></pitch><duration>4</duration></note></measure></part></score-partwise>".utf8)

    func testCompressedAndPlainScoresHaveIdenticalNotesAndSourceIDs() throws {
        for method in [CompressionMethod.none, .deflate] {
            let mxl = try archive(metadata: metadata("scores/Etude.musicxml"), path: "scores/Etude.musicxml", method: method)
            XCTAssertEqual(try MusicXMLContainer.scoreData(from: mxl), xml)
            XCTAssertEqual(try MusicXMLImporter().importScore(from: mxl), try MusicXMLImporter().importScore(from: xml))
        }
    }

    func testFirstRootfileWinsAndAlternatePDFIsNotRead() throws {
        let meta = "<container><rootfiles><rootfile full-path='score.xml'/><rootfile full-path='unavailable.pdf' media-type='application/pdf'/></rootfiles></container>"
        XCTAssertEqual(try MusicXMLContainer.scoreData(from: archive(metadata: meta)), xml)
        let wrongFirst = "<container><rootfiles><rootfile full-path='score.xml' media-type='application/pdf'/><rootfile full-path='score.xml'/></rootfiles></container>"
        XCTAssertThrowsError(try MusicXMLContainer.scoreData(from: archive(metadata: wrongFirst)))
    }

    func testMissingMalformedAndUnsafeContainersAreRejected() throws {
        for meta in ["<container/>", "<container>", "<other><rootfiles><rootfile full-path='score.xml'/></rootfiles></other>", metadata("missing.xml"), metadata("../score.xml"), metadata("/score.xml"), metadata("https://example.com/score.xml")] {
            XCTAssertThrowsError(try MusicXMLContainer.scoreData(from: archive(metadata: meta)), meta)
        }
        XCTAssertThrowsError(try MusicXMLContainer.scoreData(from: Data([0x50, 0x4b, 0x03, 0x04])))
    }

    func testDeclaredRootCannotBeASymlink() throws {
        XCTAssertThrowsError(try MusicXMLContainer.scoreData(from: archive(metadata: metadata("score.xml"), type: .symlink)))
    }

    func testChecksumCorruptionIsRejectedEvenIfXMLWouldStillParse() throws {
        var bytes = try archive(metadata: metadata("score.xml"), method: .none)
        let range = try XCTUnwrap(bytes.range(of: xml))
        let pitchOffset = try XCTUnwrap(xml.range(of: Data("<step>E".utf8))).upperBound - 1
        bytes[range.lowerBound + pitchOffset] = Character("F").asciiValue!
        XCTAssertThrowsError(try MusicXMLContainer.scoreData(from: bytes))
    }

    func testInflatedDocumentAndMetadataLimits() throws {
        let oversized = Data(repeating: 32, count: MusicXMLContainer.maximumScoreBytes + 1)
        XCTAssertThrowsError(try MusicXMLContainer.scoreData(from: archive(metadata: metadata("score.xml"), payload: oversized)))
        let oversizedMetadata = metadata("score.xml") + String(repeating: " ", count: 64 * 1024)
        XCTAssertThrowsError(try MusicXMLContainer.scoreData(from: archive(metadata: oversizedMetadata)))
        XCTAssertThrowsError(try MusicXMLContainer.scoreData(from: oversized))
    }

    func testEntityDeclarationsAreRejectedForPlainAndCompressedXML() throws {
        let meta = "<!DOCTYPE container [<!ENTITY location 'score.xml'>]><container><rootfiles><rootfile full-path='&location;'/></rootfiles></container>"
        XCTAssertThrowsError(try MusicXMLContainer.scoreData(from: archive(metadata: meta)))
        let entityXML = Data(("<!DOCTYPE score-partwise [<!ENTITY title 'Expanded'>]>" + String(decoding: xml, as: UTF8.self)).utf8)
        XCTAssertThrowsError(try MusicXMLImporter().importScore(from: entityXML))
        XCTAssertThrowsError(try MusicXMLImporter().importScore(from: archive(metadata: metadata("score.xml"), payload: entityXML)))
    }

    func testFileReadingStopsAtInputLimit() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        try Data(repeating: 32, count: MusicXMLContainer.maximumInputBytes + 1).write(to: path)
        XCTAssertThrowsError(try MusicXMLContainer.read(from: path))
        try xml.write(to: path)
        XCTAssertEqual(try MusicXMLContainer.read(from: path), xml)
    }

    private func metadata(_ path: String) -> String {
        "<container><rootfiles><rootfile full-path='\(path)' media-type='application/vnd.recordare.musicxml+xml'/></rootfiles></container>"
    }

    private func archive(metadata: String, path: String = "score.xml", payload: Data? = nil,
                         method: CompressionMethod = .deflate, type: Entry.EntryType = .file) throws -> Data {
        let archive = try Archive(accessMode: .create)
        for (name, data, entryType) in [("META-INF/container.xml", Data(metadata.utf8), Entry.EntryType.file), (path, payload ?? xml, type)] {
            try archive.addEntry(with: name, type: entryType, uncompressedSize: Int64(data.count), compressionMethod: method) { offset, size in
                data.subdata(in: Int(offset)..<(Int(offset) + size))
            }
        }
        return try XCTUnwrap(archive.data)
    }
}
