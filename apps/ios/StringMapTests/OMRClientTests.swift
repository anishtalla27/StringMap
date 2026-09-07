import XCTest
@testable import StringMap

final class OMRClientTests: XCTestCase {
    func testRecognitionJobDecodesCompletedMusicXML() throws {
        let xml = Data("<score-partwise/>".utf8)
        let payload = """
        {
          "id": "job-1",
          "status": "completed",
          "sourceName": "Camera page",
          "musicXMLBase64": "\(xml.base64EncodedString())",
          "error": null
        }
        """
        let job = try JSONDecoder().decode(OMRRecognitionJob.self, from: Data(payload.utf8))
        XCTAssertEqual(job.id, "job-1")
        XCTAssertEqual(job.status, .completed)
        XCTAssertEqual(job.sourceName, "Camera page")
        XCTAssertEqual(job.musicXMLBase64.flatMap { Data(base64Encoded: $0) }, xml)
    }

    func testClientRejectsInvalidOrUnsupportedServiceURLs() {
        XCTAssertThrowsError(try OMRClient(serviceURL: "not a url"))
        XCTAssertThrowsError(try OMRClient(serviceURL: "ftp://example.com"))
        XCTAssertThrowsError(try OMRClient(serviceURL: "https://user:password@example.com"))
        XCTAssertThrowsError(try OMRClient(serviceURL: "https://example.com?token=secret"))
        XCTAssertNoThrow(try OMRClient(serviceURL: "https://recognition.example.com"))
    }

    func testUnreachableServiceErrorNamesTheAddressAndTheCause() {
        let message = OMRClientError.unreachable(host: "http://127.0.0.1:8765").errorDescription ?? ""
        XCTAssertTrue(message.contains("http://127.0.0.1:8765"))
        XCTAssertTrue(message.lowercased().contains("check your connection"))
        XCTAssertTrue(message.contains("offline"))
    }
}
