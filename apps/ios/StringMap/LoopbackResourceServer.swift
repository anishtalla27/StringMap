import Foundation
import Network

/// Serves only alphaTab's bundled assets to this app's WKWebView.
///
/// WebKit does not allow alphaTab's playback worker to import another
/// `file://` resource. A loopback-only HTTP origin gives the worker normal web
/// semantics while remaining offline and inaccessible from other interfaces.
final class LoopbackResourceServer: @unchecked Sendable {
    enum ServerError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "The bundled alphaTab resource server could not start."
        }
    }

    private let root: URL
    private let queue = DispatchQueue(label: "com.anishtalla.StringMap.alphaTabResources")
    private var listener: NWListener?

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func start(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            let listener = try NWListener(using: parameters, on: .any)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                self?.serve(connection)
            }
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    guard let port = listener?.port,
                          let url = URL(string: "http://127.0.0.1:\(port.rawValue)/index.html") else {
                        completion(.failure(ServerError.unavailable))
                        return
                    }
                    completion(.success(url))
                case let .failed(error):
                    completion(.failure(error))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        } catch {
            completion(.failure(error))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data,
                  let request = String(data: data, encoding: .utf8),
                  let requestLine = request.split(separator: "\r\n", maxSplits: 1).first else {
                connection.cancel()
                return
            }
            let pieces = requestLine.split(separator: " ")
            let path = pieces.count > 1 ? String(pieces[1]) : "/"
            send(path: path, over: connection)
        }
    }

    private func send(path: String, over connection: NWConnection) {
        let relativePath = path == "/" ? "index.html" : String(path.dropFirst())
        let allowed = [
            "index.html", "bridge.js", "alphaTab.min.js",
            "font/Bravura.woff2", "soundfont/sonivox.sf2",
            "LICENSE-MPL-2.0.txt",
        ]
        guard allowed.contains(relativePath),
              let body = try? Data(contentsOf: root.appending(path: relativePath)) else {
            send(status: "404 Not Found", contentType: "text/plain", body: Data("Not found".utf8), over: connection)
            return
        }
        send(status: "200 OK", contentType: mimeType(for: relativePath), body: body, over: connection)
    }

    private func send(status: String, contentType: String, body: Data, over connection: NWConnection) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func mimeType(for path: String) -> String {
        if path.hasSuffix(".html") { return "text/html; charset=utf-8" }
        if path.hasSuffix(".js") { return "application/javascript; charset=utf-8" }
        if path.hasSuffix(".woff2") { return "font/woff2" }
        if path.hasSuffix(".sf2") { return "application/octet-stream" }
        return "text/plain; charset=utf-8"
    }
}
