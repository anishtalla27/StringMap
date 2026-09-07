import XCTest
import ScorePipeline
@testable import StringMap

private final class RequestScript: @unchecked Sendable {
    let lock = NSLock()
    var requests: [URLRequest] = []
    var handler: @Sendable (URLRequest, Int) throws -> (Int, Data)
    init(_ handler: @escaping @Sendable (URLRequest, Int) throws -> (Int, Data)) { self.handler = handler }
    func respond(_ request: URLRequest) throws -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request); return try handler(request, requests.count)
    }
    var methods: [String] { lock.lock(); defer { lock.unlock() }; return requests.map { $0.httpMethod ?? "GET" } }
}

private final class RecognitionProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var script: RequestScript?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let result = try Self.script!.respond(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: result.0, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.1); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class OMRRecoveryTests: XCTestCase {
    private func reviewState() throws -> ScoreReviewState {
        let xml = "<score-partwise><part id='P1'><measure number='1'><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes><note id='a'><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration></note></measure></part></score-partwise>"
        return ScoreReviewState(score: try MusicXMLImporter().importScore(from: Data(xml.utf8)))
    }

    func testCorrectionsAndUndoSurviveDiskRecoveryAndFailedWrites() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "draft.plist")
        var state = try reviewState()
        var draft = ScanDraft(requestID: UUID().uuidString, serviceURL: "http://127.0.0.1:8765", sourceName: "Test", imageData: Data([1,2,3]), reviewState: state)
        try draft.save(to: url)
        try state.change({ $0 = try $0.transposed(by: 1) }, persist: { next in
            draft.reviewState = next; try draft.save(to: url)
        })
        var restored = try XCTUnwrap(ScanDraft.load(from: url)?.reviewState)
        XCTAssertEqual(restored.score.notes.first?.midi, 65)
        XCTAssertEqual(restored.history.first?.notes.first?.midi, 64)
        XCTAssertEqual(try ScanDraft.load(from: url)?.imageData, Data([1,2,3]))
        let prior = restored
        // A file cannot serve as the parent directory of a replacement file.
        XCTAssertThrowsError(try restored.change({ $0.title = "Not committed" }, persist: { next in
            var failed = draft; failed.reviewState = next
            try failed.save(to: url.appending(path: "impossible"))
        }))
        XCTAssertEqual(restored, prior)
        XCTAssertEqual(try ScanDraft.load(from: url)?.reviewState, prior)
        try restored.undo(persist: { next in draft.reviewState = next; try draft.save(to: url) })
        XCTAssertEqual(try ScanDraft.load(from: url)?.reviewState?.score.notes.first?.midi, 64)
        XCTAssertTrue(try XCTUnwrap(ScanDraft.load(from: url)?.reviewState).history.isEmpty)
    }

    func testUnsupportedMarkCorrectionPersistsAndUndoRestoresBlocker() throws {
        let xml = "<score-partwise><part id='P1'><measure number='1'><note id='a'><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><notations><arpeggiate/></notations></note></measure></part></score-partwise>"
        var state = ScoreReviewState(score: try MusicXMLImporter().importScore(from: Data(xml.utf8), forReview: true))
        let original = state
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".plist")
        defer { try? FileManager.default.removeItem(at: url) }
        var draft = ScanDraft(requestID: UUID().uuidString, serviceURL: "https://example.invalid", sourceName: "Mark review", imageData: Data([1]), reviewState: state)
        try draft.save(to: url)
        XCTAssertThrowsError(try state.change({ $0.reviewIssues?.removeAll() }, persist: { _ in throw CocoaError(.fileWriteNoPermission) }))
        XCTAssertEqual(state, original)
        try state.change({ $0.reviewIssues?.removeAll() }, persist: { next in draft.reviewState = next; try draft.save(to: url) })
        state = try XCTUnwrap(ScanDraft.load(from: url)?.reviewState)
        XCTAssertEqual(state.score.notes, original.score.notes)
        XCTAssertNoThrow(try MusicXMLWriter.data(for: state.score))
        try state.undo(persist: { next in draft.reviewState = next; try draft.save(to: url) })
        let recovered = try XCTUnwrap(ScanDraft.load(from: url)?.reviewState)
        XCTAssertEqual(recovered, original)
        XCTAssertThrowsError(try MusicXMLWriter.data(for: recovered.score))
        // Deleting a note must not silently remove an unresolved source annotation.
        try state.change({ $0.measures[0].events.removeAll() }, persist: { _ in })
        XCTAssertEqual(state.score.reviewIssues, original.score.reviewIssues)
        XCTAssertThrowsError(try AlphaTexGenerator.notation(score: state.score))
    }

    func testIncompleteTieIsDurableAndActiveCorrectionsRenewDraftExpiry() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".plist")
        defer { try? FileManager.default.removeItem(at: url) }
        var state = try reviewState()
        try state.change({ score in
            guard case var .note(note) = score.measures[0].events[0] else { return }
            note.tieStart = true; score.measures[0].events[0] = .note(note)
        }, persist: { _ in })
        var draft = ScanDraft(requestID: UUID().uuidString, serviceURL: "http://127.0.0.1:8765", sourceName: "Old active draft", imageData: Data([1]), createdAt: .now.addingTimeInterval(-8*86400), reviewState: state)
        try draft.save(to: url)
        XCTAssertEqual(try ScanDraft.load(from: url)?.reviewState, state)
        XCTAssertThrowsError(try MusicXMLWriter.data(for: state.score))
        draft.modifiedAt = .now.addingTimeInterval(-8*86400)
        try PropertyListEncoder().encode(draft).write(to: url)
        XCTAssertNil(try ScanDraft.load(from: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLargePhotoAndThirtyCorrectionsRecoverTogether() throws {
        var score = try reviewState().score
        let template = score.measures[0]
        score.measures = (0..<128).map { index in
            var measure = template; measure.id = "measure-\(index)"; measure.index = index; measure.number = "\(index+1)"
            measure.events = (0..<4).map { beat in
                var note = score.notes[0]; note.id = "m\(index)-n\(beat)"; note.measureIndex = index; note.onsetQuarters = Double(beat)
                return .note(note)
            }
            return measure
        }
        var state = ScoreReviewState(score: try ScoreValidator.validate(score))
        for index in 0..<30 {
            try state.change({ value in value.title = "Correction \(index)" }, persist: { _ in })
        }
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let photo = Data(repeating: 127, count: 8*1024*1024)
        let draft = ScanDraft(requestID: UUID().uuidString, serviceURL: "http://127.0.0.1:8765", sourceName: "Large local draft", imageData: photo, reviewState: state)
        let start = Date.now
        try draft.save(to: url)
        let writeSeconds = Date.now.timeIntervalSince(start)
        let loaded = try XCTUnwrap(ScanDraft.load(from: url))
        XCTAssertEqual(loaded.imageData, photo)
        XCTAssertEqual(loaded.reviewState, state)
        XCTAssertEqual(loaded.reviewState?.score.notes.count, 512)
        XCTAssertEqual(loaded.reviewState?.history.count, 30)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let evidence = XCTAttachment(string: "512 notes; 30 undo states; 8 MiB image; stored bytes: \(size); atomic write seconds: \(writeSeconds)")
        evidence.name = "Large review draft persistence"; evidence.lifetime = .keepAlways; add(evidence)
    }

    func testDraftPitchConventionRoundTripAndEarlierDraftCompatibility() throws {
        let draft = ScanDraft(requestID: UUID().uuidString, serviceURL: "http://127.0.0.1:8765",
                              sourceName: "Guitar", imageData: Data([1]), pitchConvention: .guitarWritten)
        let encoded = try PropertyListEncoder().encode(draft)
        XCTAssertEqual(try PropertyListDecoder().decode(ScanDraft.self, from: encoded).pitchConvention, .guitarWritten)
        var legacy = try XCTUnwrap(PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any])
        legacy.removeValue(forKey: "pitchConvention")
        legacy.removeValue(forKey: "reviewState")
        legacy.removeValue(forKey: "modifiedAt")
        let old = try PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0)
        let reopened = try PropertyListDecoder().decode(ScanDraft.self, from: old)
        XCTAssertNil(reopened.pitchConvention)
        XCTAssertNil(reopened.reviewState)
        XCTAssertNil(reopened.modifiedAt)
        XCTAssertEqual(reopened.requestID, draft.requestID)
        XCTAssertEqual(reopened.imageData, draft.imageData)
    }

    private func client(_ script: RequestScript) throws -> OMRClient {
        RecognitionProtocol.script = script
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [RecognitionProtocol.self]
        return try OMRClient(serviceURL: "http://127.0.0.1:8765", session: URLSession(configuration: configuration))
    }
    private static func completed(_ id: String) -> Data {
        Data("{\"id\":\"\(id)\",\"status\":\"completed\",\"sourceName\":\"test\",\"musicXMLBase64\":\"\(Data("<score-partwise/>".utf8).base64EncodedString())\"}".utf8)
    }

    @MainActor
    func testResumeFetchesExistingResultAndPersistsBeforeDeletion() async throws {
        let id = UUID().uuidString
        var received = false
        let script = RequestScript { request, _ in
            XCTAssertEqual(request.url?.lastPathComponent, id.lowercased())
            return (request.httpMethod == "DELETE" ? 204 : 200, Self.completed(id.lowercased()))
        }
        let service = try client(script)
        let result = try await service.recognize(jpegData: Data([1]), sourceName: "test", requestID: id, resume: true, received: { _ in received = true }) { _ in }
        XCTAssertTrue(received); XCTAssertEqual(String(decoding: result, as: UTF8.self), "<score-partwise/>")
        XCTAssertEqual(script.methods, ["GET", "DELETE"])
    }

    @MainActor
    func testConnectionRetryReusesSubmissionID() async throws {
        let id = UUID().uuidString
        let script = RequestScript { request, count in
            if count == 1 { throw URLError(.networkConnectionLost) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), id)
            return (202, Self.completed(id))
        }
        _ = try await client(script).submit(jpegData: Data([1]), sourceName: "test", requestID: id)
        XCTAssertEqual(script.methods, ["POST", "POST"])
    }

    @MainActor
    func testCancelPollingStillSendsDeletion() async throws {
        let id = UUID().uuidString
        let script = RequestScript { request, _ in
            if request.httpMethod == "DELETE" { XCTAssertEqual(request.url?.lastPathComponent, id.lowercased()) }
            return (request.httpMethod == "DELETE" ? 204 : 202, Data("{\"id\":\"\(id.lowercased())\",\"status\":\"processing\",\"sourceName\":\"test\"}".utf8))
        }
        let service = try client(script)
        let task = Task { try await service.recognize(jpegData: Data([1]), sourceName: "test", requestID: id) { _ in } }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Wrong failure: \(error)") }
        XCTAssertEqual(script.methods, ["POST", "DELETE"])
    }

    @MainActor
    func testMalformedAndMismatchedResponsesAreRejectedWithoutRetry() async throws {
        for response in [Data("not JSON".utf8), Self.completed("wrong-id")] {
            let script = RequestScript { _, _ in (202, response) }
            do { _ = try await client(script).submit(jpegData: Data([1]), sourceName: "test"); XCTFail("Expected invalid response") }
            catch OMRClientError.invalidResponse {} catch { XCTFail("Wrong failure: \(error)") }
            XCTAssertEqual(script.methods, ["POST"])
        }
    }
}
