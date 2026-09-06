#if DEBUG
import Foundation

struct OMRRecognitionJob: Decodable, Sendable {
    enum Status: String, Decodable, Sendable {
        case queued
        case processing
        case completed
        case failed
        case cancelled
    }

    let id: String
    let status: Status
    let sourceName: String
    let musicXMLBase64: String?
    let error: String?
}

enum OMRClientError: LocalizedError, Sendable {
    case notConfigured
    case invalidServiceURL
    case invalidResponse
    case service(status: Int, message: String)
    case missingMusicXML
    case timedOut
    case unreachable(host: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Photo recognition is not configured in this build. You can still import MusicXML and play saved scores offline."
        case .invalidServiceURL:
            #if DEBUG
            "Enter a valid HTTP or HTTPS recognition-service URL in Settings."
            #else
            "Photo recognition is unavailable in this build. Please contact support."
            #endif
        case .invalidResponse:
            "The recognition service returned an unreadable response."
        case let .service(_, message):
            message
        case .missingMusicXML:
            "Recognition completed without returning MusicXML."
        case .timedOut:
            "Recognition took longer than 20 minutes. Try a smaller, clearer photo."
        case let .unreachable(host):
            "Couldn't reach the recognition service at \(host). Check your connection and try again. Your saved music still works offline."
        }
    }
}

struct OMRClient: Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(serviceURL: String, session: URLSession = .shared) throws {
        guard let url = URL(string: serviceURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw OMRClientError.invalidServiceURL
        }
        #if !DEBUG
        guard scheme == "https" else { throw OMRClientError.invalidServiceURL }
        #endif
        baseURL = url
        self.session = session
    }

    func submit(jpegData: Data, sourceName: String, requestID: String = UUID().uuidString) async throws -> OMRRecognitionJob {
        var request = URLRequest(url: endpoint("v1", "recognitions"))
        request.httpMethod = "POST"
        request.httpBody = jpegData
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue(sourceName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), forHTTPHeaderField: "X-StringMap-Source-Name")
        request.setValue(requestID, forHTTPHeaderField: "Idempotency-Key")
        let value = try await perform(request, expectedStatus: 202)
        guard value.id.lowercased() == requestID.lowercased() else { throw OMRClientError.invalidResponse }
        return value
    }

    func job(id: String) async throws -> OMRRecognitionJob {
        let request = URLRequest(url: endpoint("v1", "recognitions", id.lowercased()))
        let value = try await perform(request, expectedStatus: 200)
        guard value.id.lowercased() == id.lowercased() else { throw OMRClientError.invalidResponse }
        return value
    }

    func delete(id: String) async {
        // Cleanup must get its own uncancelled task: URLSession immediately
        // cancels requests made from an already cancelled recognition task.
        await Task.detached {
            var request = URLRequest(url: endpoint("v1", "recognitions", id.lowercased()))
            request.httpMethod = "DELETE"; request.timeoutInterval = 10
            if let token = try? await authorization() { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
            _ = try? await session.data(for: request)
        }.value
    }

    func recognize(
        jpegData: Data,
        sourceName: String,
        requestID: String = UUID().uuidString,
        resume: Bool = false,
        received: @MainActor @escaping (Data) throws -> Void = { _ in },
        statusChanged: @MainActor @escaping (OMRRecognitionJob.Status) -> Void
    ) async throws -> Data {
        do {
            let submitted: OMRRecognitionJob
            if resume {
                do { submitted = try await job(id: requestID) }
                catch OMRClientError.service(status: 404, message: _) {
                    submitted = try await submit(jpegData: jpegData, sourceName: sourceName, requestID: requestID)
                }
            } else { submitted = try await submit(jpegData: jpegData, sourceName: sourceName, requestID: requestID) }
            await statusChanged(submitted.status)
            let deadline = ContinuousClock.now + .seconds(20 * 60)
            var current = submitted
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                switch current.status {
                case .completed:
                    guard let encoded = current.musicXMLBase64,
                          let data = Data(base64Encoded: encoded),
                          !data.isEmpty, data.count <= 10 * 1024 * 1024 else {
                        throw OMRClientError.missingMusicXML
                    }
                    try await received(data)
                    await delete(id: current.id)
                    return data
                case .cancelled:
                    throw CancellationError()
                case .failed:
                    throw OMRClientError.service(
                        status: 422,
                        message: current.error ?? "The recognition engine could not read this page."
                    )
                case .queued, .processing:
                    try await Task.sleep(for: .seconds(2))
                    current = try await job(id: current.id)
                    await statusChanged(current.status)
                }
            }
            throw OMRClientError.timedOut
        } catch {
            if Task.isCancelled || error is CancellationError { await delete(id: requestID) }
            throw error
        }
    }

    private func authorization() async throws -> String? {
        #if DEBUG
        if baseURL.scheme == "http" { return nil }
        #endif
        return try await OMRAuthentication.shared.token(for: baseURL)
    }

    private static let connectionFailures: Set<URLError.Code> = [
        .cannotConnectToHost,
        .cannotFindHost,
        .networkConnectionLost,
        .notConnectedToInternet,
        .timedOut,
        .dnsLookupFailed,
        .secureConnectionFailed,
    ]

    private func endpoint(_ components: String...) -> URL {
        components.reduce(baseURL) { url, component in
            url.appending(path: component)
        }
    }

    private func perform(_ request: URLRequest, expectedStatus: Int) async throws -> OMRRecognitionJob {
        for attempt in 0..<3 {
            do { return try await performOnce(request, expectedStatus: expectedStatus) }
            catch {
                try Task.checkCancellation()
                let retry: Bool
                switch error {
                case OMRClientError.unreachable: retry = true
                case OMRClientError.service(let status, _):
                    retry = [401, 502, 503, 504].contains(status)
                    if status == 401 { await OMRAuthentication.shared.invalidate(baseURL) }
                default: retry = false
                }
                guard retry, attempt < 2 else { throw error }
                try await Task.sleep(for: .seconds((attempt + 1) * 2))
            }
        }
        throw OMRClientError.invalidResponse
    }

    private func performOnce(_ request: URLRequest, expectedStatus: Int) async throws -> OMRRecognitionJob {
        var request = request
        request.timeoutInterval = 30
        if let token = try await authorization() { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.connectionFailures.contains(error.code) {
            throw OMRClientError.unreachable(host: baseURL.absoluteString)
        }
        guard data.count <= 16 * 1024 * 1024 else { throw OMRClientError.invalidResponse }
        guard let http = response as? HTTPURLResponse else { throw OMRClientError.invalidResponse }
        guard http.statusCode == expectedStatus else {
            let serviceError = try? JSONDecoder().decode(ServiceError.self, from: data)
            throw OMRClientError.service(
                status: http.statusCode,
                message: serviceError?.error ?? "Recognition service error (HTTP \(http.statusCode))."
            )
        }
        do { return try JSONDecoder().decode(OMRRecognitionJob.self, from: data) }
        catch { throw OMRClientError.invalidResponse }
    }
}

private struct ServiceError: Decodable {
    let error: String
}

#endif
