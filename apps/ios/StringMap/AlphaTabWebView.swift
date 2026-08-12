@preconcurrency import WebKit
import Observation
import SwiftUI

enum AlphaTabEvent: Equatable, Sendable {
    case bridgeReady
    case rendered
    case soundFontLoad(loaded: Double, total: Double)
    case playerReady
    case playerState(state: Int, stopped: Bool)
    case position(milliseconds: Double, endMilliseconds: Double)
    case error(String)

    nonisolated static func parse(_ body: Any) -> AlphaTabEvent? {
        guard let payload = body as? [String: Any], let type = payload["type"] as? String else { return nil }
        switch type {
        case "bridgeReady": return .bridgeReady
        case "rendered": return .rendered
        case "soundFontLoad":
            return .soundFontLoad(
                loaded: payload["loaded"] as? Double ?? 0,
                total: payload["total"] as? Double ?? 0
            )
        case "playerReady": return .playerReady
        case "playerState":
            return .playerState(
                state: payload["state"] as? Int ?? 0,
                stopped: payload["stopped"] as? Bool ?? false
            )
        case "position": return .position(
            milliseconds: payload["currentTime"] as? Double ?? 0,
            endMilliseconds: payload["endTime"] as? Double ?? 0
        )
        case "error": return .error(payload["message"] as? String ?? "Unknown alphaTab error")
        default: return nil
        }
    }
}

@MainActor
@Observable
final class AlphaTabController {
    private(set) var isBridgeReady = false
    private(set) var isPlayerReady = false
    private(set) var isPlaying = false
    private(set) var cursorMilliseconds = 0.0
    private(set) var endMilliseconds = 0.0
    private(set) var playbackSpeed = 1.0
    private(set) var isLooping = false
    private(set) var isMetronomeEnabled = false
    private(set) var isCountInEnabled = false
    private(set) var playbackStatus = "Preparing notation…"

    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored private var pendingAlphaTex: String?
    @ObservationIgnored private var pendingSeekMilliseconds: Double?

    func queue(alphaTex: String) {
        pendingAlphaTex = alphaTex
        loadPendingScoreIfPossible()
    }

    func prepareForNewScore() {
        isPlayerReady = false
        isPlaying = false
        cursorMilliseconds = 0
        endMilliseconds = 0
        playbackStatus = "Preparing notation…"
    }

    func playPause() {
        call("window.stringMap.playPause();")
    }

    func stop() {
        call("window.stringMap.stop();")
    }

    func seek(milliseconds: Double) {
        cursorMilliseconds = max(0, milliseconds)
        pendingSeekMilliseconds = cursorMilliseconds
        applyPendingSeekIfPossible()
    }

    func setPlaybackSpeed(_ speed: Double) {
        playbackSpeed = min(2, max(0.25, speed))
        callAsync("window.stringMap.setSpeed(speed);", arguments: ["speed": playbackSpeed])
    }

    func setLoop(startTick: Int, endTick: Int) {
        guard startTick >= 0, endTick > startTick else { return }
        isLooping = true
        callAsync(
            "window.stringMap.setLoop(startTick, endTick);",
            arguments: ["startTick": startTick, "endTick": endTick]
        )
    }

    func clearLoop() {
        isLooping = false
        call("window.stringMap.clearLoop();")
    }

    func setMetronome(enabled: Bool) {
        isMetronomeEnabled = enabled
        callAsync("window.stringMap.setMetronome(enabled);", arguments: ["enabled": enabled])
    }

    func setCountIn(enabled: Bool) {
        isCountInEnabled = enabled
        callAsync("window.stringMap.setCountIn(enabled);", arguments: ["enabled": enabled])
    }

    func receive(_ event: AlphaTabEvent) {
        switch event {
        case .bridgeReady:
            isBridgeReady = true
            loadPendingScoreIfPossible()
            applyPracticeSettings()
        case .rendered:
            if !isPlayerReady { playbackStatus = "Notation ready · preparing playback" }
        case let .soundFontLoad(loaded, total):
            let percent = total > 0 ? Int((loaded / total * 100).rounded()) : 0
            playbackStatus = "Loading playback sounds · \(percent)%"
        case .playerReady:
            isPlayerReady = true
            playbackStatus = "Playback ready"
            applyPendingSeekIfPossible()
        case let .playerState(state, stopped):
            isPlaying = state == 1
            playbackStatus = isPlaying ? "Playing synchronized score" : (stopped ? "Playback ready" : "Playback paused")
        case let .position(milliseconds, endMilliseconds):
            cursorMilliseconds = milliseconds
            self.endMilliseconds = endMilliseconds
        case let .error(message):
            isPlaying = false
            playbackStatus = "alphaTab: \(message)"
        }
    }

    private func loadPendingScoreIfPossible() {
        guard isBridgeReady, let alphaTex = pendingAlphaTex, let webView else { return }
        pendingAlphaTex = nil
        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.stringMap.load(alphaTex);",
                    arguments: ["alphaTex": alphaTex],
                    in: nil,
                    contentWorld: .page
                )
                self.applyPracticeSettings()
            } catch {
                receive(.error(error.localizedDescription))
            }
        }
    }

    private func call(_ script: String) {
        guard let webView else { return }
        Task {
            do { _ = try await webView.evaluateJavaScript(script) }
            catch { receive(.error(error.localizedDescription)) }
        }
    }


    private func callAsync(_ script: String, arguments: [String: Any]) {
        guard isBridgeReady, let webView else { return }
        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    script,
                    arguments: arguments,
                    in: nil,
                    contentWorld: .page
                )
            } catch {
                receive(.error(error.localizedDescription))
            }
        }
    }

    private func applyPracticeSettings() {
        setPlaybackSpeed(playbackSpeed)
        setMetronome(enabled: isMetronomeEnabled)
        setCountIn(enabled: isCountInEnabled)
    }

    private func applyPendingSeekIfPossible() {
        guard isPlayerReady, let milliseconds = pendingSeekMilliseconds else { return }
        pendingSeekMilliseconds = nil
        callAsync("window.stringMap.seek(milliseconds);", arguments: ["milliseconds": milliseconds])
    }
}

struct AlphaTabWebView: UIViewRepresentable {
    let controller: AlphaTabController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "stringMap")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        controller.webView = webView

        guard let resourceRoot = Bundle.main.resourceURL?.appending(path: "AlphaTab", directoryHint: .isDirectory) else {
            controller.receive(.error("Bundled alphaTab page is missing."))
            return webView
        }
        context.coordinator.startResourceServer(root: resourceRoot, webView: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        controller.webView = webView
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "stringMap")
        coordinator.stopResourceServer()
        uiView.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private weak var controller: AlphaTabController?
        private var resourceServer: LoopbackResourceServer?

        init(controller: AlphaTabController) {
            self.controller = controller
        }

        func startResourceServer(root: URL, webView: WKWebView) {
            let server = LoopbackResourceServer(root: root)
            resourceServer = server
            server.start { [weak self, weak webView] result in
                Task { @MainActor in
                    switch result {
                    case let .success(url): webView?.load(URLRequest(url: url))
                    case let .failure(error): self?.controller?.receive(.error(error.localizedDescription))
                    }
                }
            }
        }

        func stopResourceServer() {
            resourceServer?.stop()
            resourceServer = nil
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let event = AlphaTabEvent.parse(message.body) else { return }
            controller?.receive(event)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            controller?.receive(.error(error.localizedDescription))
        }
    }
}
