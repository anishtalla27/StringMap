#if DEBUG
import Foundation
import AVFoundation
import Observation

/// Original implementation of the YIN difference/normalized-difference method.
/// Pure DSP: no microphone, persistence, networking, or target-biased octave correction.
enum TutorialYIN {
    struct Estimate: Sendable { let frequency: Double; let confidence: Double }
    static func estimate(_ input: [Float], sampleRate: Double) -> Estimate? {
        guard input.count >= 512, sampleRate >= 8000 else { return nil }
        let mean = input.reduce(0.0) { $0 + Double($1) } / Double(input.count)
        let data = input.map { Double($0) - mean }
        let energy = data.reduce(0) { $0 + $1 * $1 } / Double(data.count)
        guard energy > 0.000036, input.allSatisfy({ $0.isFinite }), input.filter({ abs($0) >= 0.99 }).count < input.count / 20 else { return nil }
        let minLag = max(2, Int(sampleRate / 800))
        let maxLag = min(input.count / 2, Int(sampleRate / 65))
        guard maxLag > minLag else { return nil }
        let count = input.count - maxLag
        var normalized = Array(repeating: 1.0, count: maxLag + 1)
        var sum = 0.0
        for lag in 1...maxLag {
            var difference = 0.0
            for i in 0..<count { let delta = data[i] - data[i + lag]; difference += delta * delta }
            sum += difference
            normalized[lag] = sum > 0 ? difference * Double(lag) / sum : 1
        }
        var lag = minLag
        while lag < maxLag {
            if normalized[lag] < 0.15 {
                while lag + 1 < maxLag && normalized[lag + 1] < normalized[lag] { lag += 1 }
                let left = normalized[lag - 1], mid = normalized[lag], right = normalized[lag + 1]
                let denominator = left - 2 * mid + right
                let adjustment = abs(denominator) > 1e-12 ? 0.5 * (left - right) / denominator : 0
                return Estimate(frequency: sampleRate / (Double(lag) + adjustment), confidence: 1 - mid)
            }
            lag += 1
        }
        return nil
    }
}

struct TutorialPitchMatch {
    let target: Int
    init(target: Int) { self.target = target }
    private var candidateSince: Double?
    private var lastFrameTime: Double?
    private var armed = false
    private var latched = false
    mutating func update(frequency: Double?, time: Double) -> String {
        if let lastFrameTime, time - lastFrameTime > 0.15 { candidateSince = nil }
        lastFrameTime = time
        guard let frequency, frequency > 0, frequency.isFinite else {
            candidateSince = nil; armed = true; latched = false
            return "Couldn’t hear clearly · Play one string gently."
        }
        guard armed else { return "Let the strings settle, then play one note." }
        if latched { return "Matched · Let the string stop before trying again." }
        let midi = 69 + 12 * log2(frequency / 440)
        let cents = (midi - Double(target)) * 100
        guard abs(cents) <= 35 else {
            candidateSince = nil
            return cents < 0 ? "Try a higher note" : "Try a lower note"
        }
        if candidateSince == nil { candidateSince = time }
        if time - (candidateSince ?? time) >= 0.25 { latched = true; return "Matched" }
        return "Hold that note…"
    }
}

/// The callback copies a bounded buffer; DSP runs off the real-time audio thread.
private final class TutorialPitchProcessor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "StringMap.tutorial.pitch", qos: .userInitiated)
    private let capacity = DispatchSemaphore(value: 1)
    private var ring: [Float] = []
    let output: @Sendable (Double?) -> Void
    init(output: @escaping @Sendable (Double?) -> Void) { self.output = output }
    func accept(_ samples: [Float], rate: Double) {
        guard capacity.wait(timeout: .now()) == .success else { return }
        queue.async { [self] in
            defer { capacity.signal() }
            let stride = max(1, Int(rate / 12000))
            let reduced = Swift.stride(from: 0, to: samples.count - stride + 1, by: stride).map { index in
                samples[index..<(index + stride)].reduce(0,+) / Float(stride)
            }
            ring += reduced
            if ring.count > 2048 { ring.removeFirst(ring.count - 2048) }
            guard ring.count >= 1024 else { return }
            output(TutorialYIN.estimate(Array(ring.suffix(1024)), sampleRate: rate / Double(stride))?.frequency)
        }
    }
}

@MainActor @Observable final class TutorialPitchListener {
    var status = "Optional pitch check · No audio is saved."
    private var engine: AVAudioEngine?
    private var startTask: Task<Void, Never>?
    private var generation = UUID()
    private var matcher = TutorialPitchMatch(target: 64)
    private var observers: [NSObjectProtocol] = []
    func start(target: Int) {
        stop(); let generation = self.generation
        matcher = TutorialPitchMatch(target: target)
        startTask = Task { [weak self] in
            guard let self else { return }
            let allowed = await AVAudioApplication.requestRecordPermission()
            guard !Task.isCancelled, self.generation == generation else { return }
            guard allowed else { status = "Microphone access is off. Continue with guided practice."; return }
            do {
                // Demo and metronome have stopped; let their acoustic tail decay.
                try await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled, self.generation == generation else { return }
                let audio = AVAudioSession.sharedInstance()
                try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
                try audio.setActive(true)
                let engine = AVAudioEngine()
                let format = engine.inputNode.outputFormat(forBus: 0)
                guard format.channelCount > 0, format.sampleRate > 0 else { throw CocoaError(.featureUnsupported) }
                let processor = TutorialPitchProcessor { [weak self] frequency in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == generation else { return }
                        self.status = self.matcher.update(frequency: frequency, time: ProcessInfo.processInfo.systemUptime)
                    }
                }
                engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    guard let channel = buffer.floatChannelData?[0] else { return }
                    processor.accept(Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))), rate: buffer.format.sampleRate)
                }
                self.engine = engine
                try engine.start()
                status = "Let the strings settle, then play \(tutorialPitchName(target))."
                for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification, Notification.Name.AVAudioEngineConfigurationChange] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                        Task { @MainActor [weak self] in self?.stop(); self?.status = "Audio changed. Try again or continue with guided practice." }
                    })
                }
            } catch {
                guard self.generation == generation else { return }
                stop(); status = "Listening unavailable. Continue with guided practice."
            }
        }
    }
    func stop() {
        generation = UUID(); startTask?.cancel(); startTask = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers = []
        if let engine {
            engine.stop(); engine.inputNode.removeTap(onBus: 0); self.engine = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        status = "Listening stopped · Guided practice is always available."
    }
}
#endif
