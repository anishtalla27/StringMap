import Foundation
import Observation
import FingeringEngine
import ScorePipeline

@MainActor
@Observable
final class AppModel {
    var profile: FingeringProfile = .balanced
    var tuningPreset: GuitarTuningPreset = .standard
    var customTuningMIDIs = GuitarTuning.standard.openMIDIPitches
    var capo = 0
    var maxFret = 20
    var transposition = 0
    var pipelineResult: PipelineResult?
    var arrangements: [FingeringProfile: PipelineResult] = [:]
    var status = "Loading sample…"
    var sourceName = "Known melody"
    var isProcessing = false
    var isTracePresented = false
    var isInstrumentPresented = false
    var isArrangementsPresented = false
    var editingNoteID: String?
    var loopStartMeasure: Int?
    var loopEndMeasure: Int?
    private(set) var lastOptimizationMilliseconds = 0.0
    var currentSongID: UUID?
    let player = AlphaTabController()

    @ObservationIgnored private(set) var sourceData: Data?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var lockedPositions: [String: GuitarPosition] = [:]

    init(loadSample: Bool = true) {
        guard loadSample else { return }
        let defaults = UserDefaults.standard
        profile = defaults.string(forKey: "defaultProfile")
            .flatMap(FingeringProfile.init(rawValue:)) ?? .balanced
        tuningPreset = defaults.string(forKey: "defaultTuning")
            .flatMap(GuitarTuningPreset.init(rawValue:)) ?? .standard
        capo = defaults.object(forKey: "defaultCapo") as? Int ?? 0
        maxFret = defaults.object(forKey: "defaultFrets") as? Int ?? 20
        player.setMetronome(enabled: defaults.bool(forKey: "defaultMetronome"))
        let testXML = ProcessInfo.processInfo.environment["STRINGMAP_UI_TEST_XML_BASE64"]
            .flatMap { Data(base64Encoded: $0) }
        let bundledXML = Bundle.main.url(
            forResource: "known-melody",
            withExtension: "musicxml",
            subdirectory: "Samples"
        ).flatMap { try? Data(contentsOf: $0) }
        if let data = testXML ?? bundledXML {
            sourceData = data
            process(data)
        } else {
            status = "Bundled sample is missing."
        }
    }

    var tuning: GuitarTuning {
        if let preset = tuningPreset.tuning { return preset }
        return (try? GuitarTuning(name: "Custom", openMIDIPitches: customTuningMIDIs)) ?? .standard
    }

    var selectedStep: FingeringStep? {
        guard let editingNoteID else { return activeStep }
        return pipelineResult?.fingering.steps.first { $0.note.id == editingNoteID }
    }

    var activeStep: FingeringStep? {
        guard let result = pipelineResult else { return nil }
        let quarterPosition = player.cursorMilliseconds * result.score.tempo / 60_000
        var measureStart = 0.0
        for measure in result.score.measures {
            for event in measure.events {
                guard case let .note(note) = event else { continue }
                let start = measureStart + note.onsetQuarters
                if quarterPosition >= start && quarterPosition < start + note.durationQuarters {
                    return result.fingering.steps.first { $0.note.id == note.id }
                }
            }
            measureStart += Self.duration(of: measure)
        }
        return result.fingering.steps.first
    }

    var lockedNoteIDs: Set<String> { Set(lockedPositions.keys) }
    var lockedPositionsForPersistence: [String: GuitarPosition] { lockedPositions }

    func importMusicXML(from url: URL, songID: UUID? = nil) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            load(
                data: data,
                sourceName: url.deletingPathExtension().lastPathComponent,
                songID: songID
            )
        } catch {
            status = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func load(
        data: Data,
        sourceName: String,
        songID: UUID? = nil,
        profile: FingeringProfile = .balanced,
        tuningPreset: GuitarTuningPreset = .standard,
        customTuningMIDIs: [Int] = GuitarTuning.standard.openMIDIPitches,
        capo: Int = 0,
        maxFret: Int = 20,
        transposition: Int = 0,
        lastPositionMilliseconds: Double = 0,
        lockedPositions: [String: GuitarPosition] = [:],
        playbackSpeed: Double = 1,
        loopStartMeasure: Int? = nil,
        loopEndMeasure: Int? = nil,
        metronomeEnabled: Bool = false,
        countInEnabled: Bool = false
    ) {
        sourceData = data
        self.sourceName = sourceName
        currentSongID = songID
        self.profile = profile
        self.tuningPreset = tuningPreset
        self.customTuningMIDIs = customTuningMIDIs
        self.capo = capo
        self.maxFret = maxFret
        self.transposition = transposition
        self.lockedPositions = lockedPositions
        self.loopStartMeasure = loopStartMeasure
        self.loopEndMeasure = loopEndMeasure
        player.setPlaybackSpeed(playbackSpeed)
        player.setMetronome(enabled: metronomeEnabled)
        player.setCountIn(enabled: countInEnabled)
        player.seek(milliseconds: lastPositionMilliseconds)
        process(data)
    }

    func selectProfile(_ newProfile: FingeringProfile) {
        guard profile != newProfile else { return }
        profile = newProfile
        if let cached = arrangements[newProfile] {
            activate(cached)
        } else {
            reprocess()
        }
    }

    func applyInstrument(
        preset: GuitarTuningPreset,
        customMIDIs: [Int],
        capo: Int,
        maxFret: Int,
        transposition: Int
    ) {
        let normalizedMaxFret = max(12, min(30, maxFret))
        let normalizedCapo = max(0, min(capo, normalizedMaxFret))
        let normalizedTransposition = max(-24, min(24, transposition))
        let changed = tuningPreset != preset
            || customTuningMIDIs != customMIDIs
            || self.maxFret != normalizedMaxFret
            || self.capo != normalizedCapo
            || self.transposition != normalizedTransposition
        guard changed else { return }
        tuningPreset = preset
        customTuningMIDIs = customMIDIs
        self.maxFret = normalizedMaxFret
        self.capo = normalizedCapo
        self.transposition = normalizedTransposition
        lockedPositions.removeAll()
        reprocess()
    }

    func transpose(by semitones: Int) {
        let updated = max(-24, min(24, transposition + semitones))
        guard updated != transposition else { return }
        transposition = updated
        lockedPositions.removeAll()
        reprocess()
    }

    func resetTransposition() {
        guard transposition != 0 else { return }
        transposition = 0
        lockedPositions.removeAll()
        reprocess()
    }

    func suggestCapo() -> Int? {
        guard let score = pipelineResult?.score else { return nil }
        let notes = score.notes.map {
            FingeringNote(id: $0.id, midi: $0.midi, tieStop: $0.tieStop, durationQuarters: $0.durationQuarters)
        }
        var suggestionOptions = options
        suggestionOptions.transposeSemitones = 0
        suggestionOptions.lockedPositions = [:]
        return try? FingeringEngine.suggestCapo(for: notes, options: suggestionOptions)?.capo
    }

    func lockFingering(noteID: String, at position: GuitarPosition) {
        lockedPositions[noteID] = position
        editingNoteID = nil
        reprocess()
    }

    func unlockFingering(noteID: String) {
        lockedPositions.removeValue(forKey: noteID)
        editingNoteID = nil
        reprocess()
    }

    func useArrangement(_ arrangementProfile: FingeringProfile) {
        selectProfile(arrangementProfile)
        isArrangementsPresented = false
    }

    func setPlaybackSpeed(_ speed: Double) {
        player.setPlaybackSpeed(speed)
    }

    func setMetronome(_ enabled: Bool) {
        player.setMetronome(enabled: enabled)
    }

    func setCountIn(_ enabled: Bool) {
        player.setCountIn(enabled: enabled)
    }

    func setLoop(startMeasure: Int?, endMeasure: Int?) {
        loopStartMeasure = startMeasure
        loopEndMeasure = endMeasure
        guard let result = pipelineResult,
              let startMeasure,
              let endMeasure,
              startMeasure >= 0,
              endMeasure >= startMeasure,
              endMeasure < result.score.measures.count else {
            player.clearLoop()
            return
        }
        var startQuarters = 0.0
        for measure in result.score.measures.prefix(startMeasure) {
            startQuarters += Self.duration(of: measure)
        }
        var endQuarters = startQuarters
        for measure in result.score.measures[startMeasure...endMeasure] {
            endQuarters += Self.duration(of: measure)
        }
        player.setLoop(
            startTick: Int((startQuarters * 960).rounded()),
            endTick: Int((endQuarters * 960).rounded())
        )
    }

    func clearLoop() {
        setLoop(startMeasure: nil, endMeasure: nil)
    }

    func seek(fraction: Double) {
        player.seek(milliseconds: player.endMilliseconds * min(1, max(0, fraction)))
    }

    var currentMeasureIndex: Int? {
        guard let score = pipelineResult?.score, !score.measures.isEmpty else { return nil }
        let quarterPosition = player.cursorMilliseconds * score.tempo / 60_000
        var start = 0.0
        for measure in score.measures {
            let end = start + Self.duration(of: measure)
            if quarterPosition < end { return measure.index }
            start = end
        }
        return score.measures.indices.last
    }

    func seekToMeasure(_ index: Int) {
        guard let score = pipelineResult?.score, score.measures.indices.contains(index) else { return }
        let startQuarters = score.measures.prefix(index).reduce(0) { $0 + Self.duration(of: $1) }
        player.seek(milliseconds: startQuarters * 60_000 / score.tempo)
    }

    func previousMeasure() {
        guard let currentMeasureIndex else { return }
        seekToMeasure(max(0, currentMeasureIndex - 1))
    }

    func nextMeasure() {
        guard let score = pipelineResult?.score, let currentMeasureIndex else { return }
        seekToMeasure(min(score.measures.count - 1, currentMeasureIndex + 1))
    }

    func loopCurrentMeasure() {
        guard let currentMeasureIndex else { return }
        setLoop(startMeasure: currentMeasureIndex, endMeasure: currentMeasureIndex)
    }

    func restartLoop() {
        guard let start = loopStartMeasure else { return }
        seekToMeasure(start)
    }

    func jumpBackward(seconds: Double = 5) {
        player.seek(milliseconds: max(0, player.cursorMilliseconds - seconds * 1_000))
    }

    private var options: OptimizationOptions {
        OptimizationOptions(
            tuning: tuning,
            maxFret: maxFret,
            capo: capo,
            profile: profile,
            lockedPositions: lockedPositions,
            transposeSemitones: transposition
        )
    }

    private func reprocess() {
        if let sourceData { process(sourceData) }
    }

    private func process(_ data: Data) {
        processingTask?.cancel()
        // Cached paths are valid only for the exact tuning/capo/transposition/lock set.
        arrangements = [:]
        isProcessing = true
        status = "Optimizing full passage…"
        let resumePosition = player.cursorMilliseconds
        player.prepareForNewScore()
        if resumePosition > 0 { player.seek(milliseconds: resumePosition) }
        let selectedOptions = options

        processingTask = Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    let started = ContinuousClock.now
                    let pipeline = StructuredScorePipeline()
                    let primary = try pipeline.run(musicXML: data, options: selectedOptions)
                    var alternatives: [FingeringProfile: PipelineResult] = [selectedOptions.profile: primary]
                    for alternativeProfile in FingeringProfile.allCases {
                        try Task.checkCancellation()
                        guard alternatives[alternativeProfile] == nil else { continue }
                        var alternativeOptions = selectedOptions
                        alternativeOptions.profile = alternativeProfile
                        alternatives[alternativeProfile] = try pipeline.run(
                            musicXML: data,
                            options: alternativeOptions
                        )
                    }
                    let elapsed = started.duration(to: .now)
                    let components = elapsed.components
                    let milliseconds = Double(components.seconds) * 1_000
                        + Double(components.attoseconds) / 1_000_000_000_000_000
                    return ProcessingOutput(primary: primary, alternatives: alternatives, milliseconds: milliseconds)
                }.value
                guard !Task.isCancelled else { return }
                pipelineResult = output.primary
                arrangements = output.alternatives
                lastOptimizationMilliseconds = output.milliseconds
                isProcessing = false
                let warning = output.primary.score.warnings.first.map { " · \($0)" } ?? ""
                status = "Ready · \(output.primary.fingering.steps.count) notes · \(Int(output.milliseconds.rounded())) ms\(warning)"
                player.queue(alphaTex: output.primary.alphaTex)
                setLoop(startMeasure: loopStartMeasure, endMeasure: loopEndMeasure)
            } catch is CancellationError {
                // A newer document or instrument request superseded this run.
            } catch {
                guard !Task.isCancelled else { return }
                pipelineResult = nil
                arrangements = [:]
                isProcessing = false
                status = error.localizedDescription
            }
        }
    }

    private func activate(_ result: PipelineResult) {
        let resumePosition = player.cursorMilliseconds
        pipelineResult = result
        status = "Ready · cached \(profile.displayName) arrangement"
        player.prepareForNewScore()
        player.seek(milliseconds: resumePosition)
        player.queue(alphaTex: result.alphaTex)
        setLoop(startMeasure: loopStartMeasure, endMeasure: loopEndMeasure)
    }

    private static func duration(of measure: NormalizedMeasure) -> Double {
        let encoded = measure.events.map { event -> Double in
            switch event {
            case let .note(note): note.onsetQuarters + note.durationQuarters
            case let .rest(rest): rest.onsetQuarters + rest.durationQuarters
            }
        }.max() ?? 0
        if encoded > 0 { return encoded }
        return Double(measure.timeSignature.beats) * 4 / Double(measure.timeSignature.beatType)
    }
}

private struct ProcessingOutput: Sendable {
    let primary: PipelineResult
    let alternatives: [FingeringProfile: PipelineResult]
    let milliseconds: Double
}
