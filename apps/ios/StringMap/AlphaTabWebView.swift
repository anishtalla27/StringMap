@preconcurrency import WebKit
import Observation
import SwiftUI
import AVFoundation
import ScorePipeline

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


/// The notation palette handed to alphaTab so the score is engraved in the
/// app's own ink rather than sitting in the layout as a white rectangle.
struct ScoreTheme: Equatable, Sendable {
    let dark: Bool

    var payload: [String: Any] {
        dark
            ? [
                "dark": true,
                "paper": "#1E1812",
                "staffLine": "#847767",
                "barSeparator": "#A2937E",
                "barNumber": "#E0765C",
                "mainGlyph": "#EFE6D6",
                "secondaryGlyph": "#B0A18B",
                "scoreInfo": "#EFE6D6",
                "cursorBar": "rgba(224, 118, 92, 0.10)",
                "cursorBeat": "rgba(224, 118, 92, 0.45)",
            ]
            : [
                "dark": false,
                "paper": "#FFFDF7",
                "staffLine": "#6A6053",
                "barSeparator": "#2A2318",
                "barNumber": "#C43A25",
                "mainGlyph": "#17140F",
                "secondaryGlyph": "#6A6053",
                "scoreInfo": "#17140F",
                "cursorBar": "rgba(196, 58, 37, 0.07)",
                "cursorBeat": "rgba(196, 58, 37, 0.32)",
            ]
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
    private(set) var showTab = true
    private(set) var isLooping = false
    private(set) var isMetronomeEnabled = false
    private(set) var isCountInEnabled = false
    private(set) var playbackStatus = "Preparing notation…"

    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored private var pendingAlphaTex: String?
    @ObservationIgnored private var latestAlphaTex: String?
    @ObservationIgnored private var pendingSourceNotes: [[String: Any]] = []
    @ObservationIgnored private var pendingSeekMilliseconds: Double?
    @ObservationIgnored private var theme: ScoreTheme?
    @ObservationIgnored private var startsWhenReady = false
    @ObservationIgnored private var reportedError: String?

    // SwiftUI can recreate the notation view when tabs or layouts change.
    // Readiness belongs to one WebKit page; the score belongs to this controller.
    func attach(_ view: WKWebView) {
        guard webView !== view else { return }
        webView = view
        reportedError = nil
        isBridgeReady = false
        isPlayerReady = false
        isPlaying = false
        pendingAlphaTex = latestAlphaTex
        if cursorMilliseconds > 0 { pendingSeekMilliseconds = cursorMilliseconds }
        playbackStatus = "Preparing notation…"
    }

    func detach(_ view: WKWebView) {
        guard webView === view else { return }
        webView = nil
        isBridgeReady = false
        isPlayerReady = false
        isPlaying = false
        startsWhenReady = false
        pendingAlphaTex = latestAlphaTex
    }

    func setShowTab(_ enabled: Bool) {
        showTab = enabled
        callAsync("window.stringMap.setShowTab(enabled);", arguments: ["enabled": enabled])
    }

    func setTheme(_ newTheme: ScoreTheme) {
        guard theme != newTheme else { return }
        theme = newTheme
        applyThemeIfPossible()
    }

    private func applyThemeIfPossible() {
        guard isBridgeReady, let theme else { return }
        callAsync("window.stringMap.setTheme(theme);", arguments: ["theme": theme.payload])
    }

    func queue(alphaTex: String, score: NormalizedScore? = nil) {
        reportedError = nil
        pendingSourceNotes = []
        if let score {
            let voiceIndices = score.renderedVoiceIndices
            var start = 0.0
            for measure in score.measures {
                for event in measure.events {
                    if case let .note(n) = event {
                        pendingSourceNotes.append(["id": n.id, "midi": n.midi, "voice": n.voice, "voiceIndex": voiceIndices[n.id] ?? 0,
                            "startTick": Int(((start + n.onsetQuarters) * 960).rounded()),
                            "endTick": Int(((start + n.onsetQuarters + n.durationQuarters) * 960).rounded())])
                    }
                }
                start += measure.durationQuarters
            }
        }
        latestAlphaTex = alphaTex
        pendingAlphaTex = alphaTex
        loadPendingScoreIfPossible()
    }

    /// Blanks the rendered score. Used when optimization fails, so the previous
    /// arrangement cannot be mistaken for the current one.
    func clearScore() {
        isPlayerReady = false; isPlaying = false; startsWhenReady = false; pendingAlphaTex = nil
        latestAlphaTex = nil
        playbackStatus = "Notation unavailable"
        call("window.stringMap.clear();")
    }

    func prepareForNewScore() {
        stop()
        reportedError = nil
        // A queued start belongs to the score the listener asked for, not to
        // whatever replaces it.
        startsWhenReady = false
        isPlayerReady = false
        isPlaying = false
        cursorMilliseconds = 0
        endMilliseconds = 0
        playbackStatus = "Preparing notation…"
    }

    func playPause() {
        // WebKit owns the synthesizer's media session. Activating a second,
        // exclusive native session here interrupts Web Audio before it starts.
        call("window.stringMap.playPause();")
    }

    /// The transport is docked outside the player, so it can be tapped before
    /// the renderer has ever been instantiated. Remember the intent and honour
    /// it once the player reports ready, rather than presenting a dead control.
    func playWhenReady() {
        if isPlayerReady {
            playPause()
        } else {
            startsWhenReady = true
        }
    }

    func pause() {
        startsWhenReady = false
        call("window.stringMap.pause();")
    }

    func stop() {
        startsWhenReady = false
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
            applyThemeIfPossible()
            loadPendingScoreIfPossible()
            applyPracticeSettings()
        case .rendered:
            if reportedError == nil && !isPlayerReady { playbackStatus = "Notation ready · preparing playback" }
        case let .soundFontLoad(loaded, total):
            guard reportedError == nil else { return }
            let percent = total > 0 ? Int((loaded / total * 100).rounded()) : 0
            playbackStatus = "Loading playback sounds · \(percent)%"
        case .playerReady:
            guard reportedError == nil else { return }
            isPlayerReady = true
            playbackStatus = "Playback ready"
            applyPendingSeekIfPossible()
            if startsWhenReady {
                startsWhenReady = false
                playPause()
            }
        case let .playerState(state, stopped):
            guard reportedError == nil else { return }
            isPlaying = state == 1
            playbackStatus = isPlaying ? "Playing synchronized score" : (isPlayerReady ? (stopped ? "Playback ready" : "Playback paused") : "Preparing notation…")
        case let .position(milliseconds, endMilliseconds):
            cursorMilliseconds = milliseconds
            self.endMilliseconds = endMilliseconds
        case let .error(message):
            reportedError = message
            isPlayerReady = false
            isPlaying = false
            playbackStatus = "alphaTab: \(message)"
        }
    }

    private func loadPendingScoreIfPossible() {
        guard isBridgeReady, let alphaTex = pendingAlphaTex, let webView else { return }
        pendingAlphaTex = nil
        let identities = pendingSourceNotes
        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.stringMap.load(alphaTex, identities);",
                    arguments: ["alphaTex": alphaTex, "identities": identities],
                    in: nil,
                    contentWorld: .page
                )
                guard self.webView === webView else { return }
                self.applyPracticeSettings()
            } catch {
                guard self.webView === webView else { return }
                receive(.error(error.localizedDescription))
            }
        }
    }

    private func call(_ script: String) {
        guard isBridgeReady, let webView else { return }
        Task {
            do {
                _ = try await webView.evaluateJavaScript(script)
            }
            catch { if self.webView === webView { receive(.error(error.localizedDescription)) } }
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
        setShowTab(showTab)
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
    @Environment(\.colorScheme) private var colorScheme

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
        controller.attach(webView)

        guard let resourceRoot = Bundle.main.resourceURL?.appending(path: "AlphaTab", directoryHint: .isDirectory) else {
            controller.receive(.error("Bundled alphaTab page is missing."))
            return webView
        }
        context.coordinator.startResourceServer(root: resourceRoot, webView: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        controller.attach(webView)
        controller.setTheme(ScoreTheme(dark: colorScheme == .dark))
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "stringMap")
        coordinator.controllerWillDisappear(uiView)
        coordinator.stopResourceServer()
        uiView.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private weak var controller: AlphaTabController?
        private var resourceServer: LoopbackResourceServer?
        private var origin: URL?

        init(controller: AlphaTabController) {
            self.controller = controller
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        }
        deinit { NotificationCenter.default.removeObserver(self) }
        @objc private func interrupted(_ notification: Notification) {
            if notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue { controller?.pause() }
        }
        @objc private func routeChanged(_ notification: Notification) {
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { controller?.pause() }
        }
        func controllerWillDisappear(_ view: WKWebView) {
            view.evaluateJavaScript("window.stringMap?.stop();", completionHandler: nil)
            controller?.detach(view)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, let origin,
                  url.scheme == origin.scheme, url.host == origin.host, url.port == origin.port else {
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        func startResourceServer(root: URL, webView: WKWebView) {
            let server = LoopbackResourceServer(root: root)
            resourceServer = server
            server.start { [weak self, weak webView] result in
                Task { @MainActor in
                    switch result {
                    case let .success(url):
                        self?.origin = url; webView?.load(URLRequest(url: url))
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
            guard message.webView === controller?.webView,
                  message.frameInfo.isMainFrame, let origin,
                  message.frameInfo.securityOrigin.host == origin.host,
                  message.frameInfo.securityOrigin.port == origin.port,
                  let event = AlphaTabEvent.parse(message.body) else { return }
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
