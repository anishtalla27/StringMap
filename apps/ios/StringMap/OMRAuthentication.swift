#if DEBUG
import Foundation
import DeviceCheck
import CryptoKit

/// Anonymous, short-lived sessions backed by an App Attest key. No account or
/// reusable shared secret is embedded in the application.
actor OMRAuthentication {
    static let shared = OMRAuthentication()
    private var sessions: [String: (token: String, expires: Date)] = [:]
    private var pending: [String: Task<String, Error>] = [:]

    func token(for baseURL: URL) async throws -> String {
        let origin = baseURL.absoluteString
        if let session = sessions[origin], session.expires > .now.addingTimeInterval(60) { return session.token }
        if let task = pending[origin] { return try await task.value }
        let task = Task { try await createSession(baseURL) }
        pending[origin] = task
        defer { pending[origin] = nil }
        return try await task.value
    }

    func invalidate(_ base: URL) { sessions[base.absoluteString] = nil }

    private func createSession(_ base: URL) async throws -> String {
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            throw OMRClientError.service(status: 401, message: "Secure photo recognition requires a supported physical device. Your saved music and MusicXML imports work offline.")
        }
        let preference = "appAttestKey-" + base.absoluteString
        let key: String
        if let saved = UserDefaults.standard.string(forKey: preference) { key = saved }
        else { key = try await service.generateKey(); UserDefaults.standard.set(key, forKey: preference) }
        let challenge: Challenge = try await post(base.appending(path: "v1/attest/challenge"), body: ["keyID": key])
        let clientData = Data("StringMap:session:\(challenge.id):\(challenge.nonce)".utf8)
        let digest = Data(SHA256.hash(data: clientData))
        let proof: Data
        do {
            if challenge.registered { proof = try await service.generateAssertion(key, clientDataHash: digest) }
            else { proof = try await service.attestKey(key, clientDataHash: digest) }
        } catch {
            if (error as NSError).domain == DCError.errorDomain && (error as NSError).code == DCError.Code.invalidKey.rawValue {
                // A restored preference can refer to a Secure Enclave key that
                // no longer exists. Generate a replacement on the next attempt.
                UserDefaults.standard.removeObject(forKey: preference)
            }
            throw error
        }
        let response: Session = try await post(base.appending(path: "v1/attest/session"), body: [
            "keyID": key, "challengeID": challenge.id,
            "kind": challenge.registered ? "assertion" : "attestation", "proof": proof.base64EncodedString(),
        ])
        sessions[base.absoluteString] = (response.token, .now.addingTimeInterval(Double(min(3600, response.expiresIn))))
        return response.token
    }

    private func post<T: Decodable>(_ url: URL, body: [String: String]) async throws -> T {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OMRClientError.service(status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: "Could not securely connect to photo recognition. Please try again.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private struct Challenge: Decodable { let id: String; let nonce: String; let registered: Bool }
    private struct Session: Decodable { let token: String; let expiresIn: Int }
}

#endif
