import Foundation
import Observation
import FingeringEngine
import ScorePipeline

struct TutorialCourse: Decodable {
    let version: Int
    let lessons: [TutorialLesson]
    static func load(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "course", withExtension: "json", subdirectory: "Tutorial") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let course = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard course.version == 1, course.lessons.count == 12,
              Set(course.lessons.map(\.id)).count == course.lessons.count else { throw CocoaError(.coderReadCorrupt) }
        return course
    }
}
struct TutorialLesson: Decodable, Identifiable {
    let id: String
    let number: Int
    let title: String
    let summary: String
    let see: String
    let detail: String
    let practice: String
    let recap: String
    let quizString: Int
    let quizFret: Int
    let phrases: [TutorialPhrase]
    var quizMIDI: Int { GuitarTuning.standard.openMIDIPitches[quizString - 1] + quizFret }
}
struct TutorialPhrase: Decodable, Identifiable {
    let id: String
    let name: String
    let events: [TutorialEvent]
    let mutedStrings: [Int]
    func result(bundle: Bundle = .main) throws -> PipelineResult {
        guard let url = bundle.url(forResource: id, withExtension: "musicxml", subdirectory: "Tutorial") else { throw CocoaError(.fileNoSuchFile) }
        let locks = Dictionary(uniqueKeysWithValues: events.compactMap { e in e.position.map { (e.id, $0) } })
        return try StructuredScorePipeline().run(musicXML: Data(contentsOf: url), options: .init(maxFret: 5, lockedPositions: locks))
    }
}
struct TutorialEvent: Decodable, Identifiable {
    let id: String
    let measure: Int
    let onset: Double
    let duration: Double
    let string: Int
    let fret: Int
    let finger: Int
    let midi: Int?
    var start: Double { Double(measure) * 4 + onset }
    var position: GuitarPosition? { midi.map { GuitarPosition(string: string, fret: fret, midi: $0) } }
}
func tutorialPitchName(_ midi: Int) -> String {
    let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    return "\(names[midi % 12])\(midi / 12 - 1)"
}

enum TutorialStage: String, Codable, CaseIterable {
    case see, hear, practice, recap
    var title: String { switch self { case .see: "See it"; case .hear: "Hear it"; case .practice: "Try it"; case .recap: "Recap" } }
}
struct TutorialProgressRecord: Codable, Equatable {
    var stage: TutorialStage = .see
    var phraseIndex = 0
    var position = 0.0
    var speed = 1.0
    var completed = false
}
@MainActor @Observable final class TutorialProgress {
    private struct Archive: Codable { var version = 1; var lastLesson: String?; var records: [String: TutorialProgressRecord] = [:] }
    private var archive = Archive()
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "tutorialProgress.v1"), let saved = try? JSONDecoder().decode(Archive.self, from: data), saved.version == 1 { archive = saved }
    }
    var lastLesson: String? { archive.lastLesson }
    var completedCount: Int { archive.records.values.filter(\.completed).count }
    func record(_ id: String) -> TutorialProgressRecord { archive.records[id] ?? .init() }
    func activate(_ id: String) {
        guard archive.lastLesson != id else { return }
        archive.lastLesson = id
        persist()
    }
    func save(_ id: String, record: TutorialProgressRecord) {
        archive.records[id] = record
        persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(archive) { defaults.set(data, forKey: "tutorialProgress.v1") }
    }
}

@MainActor @Observable final class TutorialSession {
    let player = AlphaTabController()
    let lesson: TutorialLesson
    var stage: TutorialStage
    var phraseIndex: Int
    var error: String?
    var explorationHint: String?
    var quizFeedback: String?
    var quizMatched = false
    private(set) var result: PipelineResult?
    private let progress: TutorialProgress
    private var auditionTask: Task<Void, Never>?
    #if DEBUG
    let listener = TutorialPitchListener()
    #endif
    init(lesson: TutorialLesson, progress: TutorialProgress, showTab: Bool) {
        self.lesson = lesson; self.progress = progress
        let saved = progress.record(lesson.id)
        stage = saved.stage; phraseIndex = min(max(0, saved.phraseIndex), lesson.phrases.count - 1)
        player.setShowTab(showTab)
        loadPhrase()
        player.setPlaybackSpeed(saved.speed)
        player.seek(milliseconds: saved.position)
    }
    func activate() { progress.activate(lesson.id) }
    var completed: Bool { progress.record(lesson.id).completed }
    var phrase: TutorialPhrase { lesson.phrases[phraseIndex] }
    var quarter: Double { player.cursorMilliseconds / 1000 } // All authored lessons use 60 quarter-note BPM.
    var activeEvents: [TutorialEvent] {
        let q = min(quarter, max(0, totalQuarters - 0.0001))
        return phrase.events.filter { $0.start <= q + 0.000001 && $0.start + $0.duration > q }
    }
    var totalQuarters: Double { phrase.events.map { $0.start + $0.duration }.max() ?? 0 }
    var upcoming: GuitarPosition? { phrase.events.first { $0.start > quarter + 0.0001 && $0.midi != nil }?.position }
    var fingers: [GuitarPosition: Int] {
        var mapping: [GuitarPosition: Int] = [:]
        let next = phrase.events.first { $0.start > quarter + 0.0001 && $0.midi != nil }
        for event in activeEvents + (next.map { [$0] } ?? []) {
            if let position = event.position, mapping[position] == nil { mapping[position] = event.finger }
        }
        return mapping
    }
    var mutedStrings: Set<Int> {
        let notes = activeEvents.filter { $0.midi != nil }
        return notes.count > 1 ? Set(1...6).subtracting(notes.map(\.string)) : Set(phrase.mutedStrings)
    }
    func loadPhrase() {
        stop(); player.prepareForNewScore(); error = nil
        do { let value = try phrase.result(); result = value; player.queue(alphaTex: value.alphaTex, score: value.score) }
        catch { result = nil; self.error = "Couldn’t load this lesson. \(error.localizedDescription)"; player.clearScore() }
    }
    func choosePhrase(_ index: Int) {
        guard lesson.phrases.indices.contains(index) else { return }
        phraseIndex = index; loadPhrase(); save()
    }
    func stop() {
        auditionTask?.cancel(); auditionTask = nil
        #if DEBUG
        listener.stop()
        #endif
        player.pause()
    }
    func playPause() { auditionTask?.cancel(); auditionTask = nil
        #if DEBUG
        listener.stop()
        #endif
        player.playPause()
    }
    func restart() { stop(); player.clearLoop(); player.stop(); player.seek(milliseconds: 0); save() }
    func seek(_ milliseconds: Double) { stop(); player.seek(milliseconds: min(totalQuarters * 1000, max(0, milliseconds))); save() }
    func step(_ direction: Int) {
        let starts = Array(Set(phrase.events.map(\.start))).sorted()
        let next = direction > 0 ? starts.first { $0 > quarter + 0.001 } : starts.last { $0 < quarter - 0.001 }
        seek((next ?? (direction > 0 ? starts.last : starts.first) ?? 0) * 1000)
    }
    func hearCurrent() {
        guard player.isPlayerReady else { return }
        stop()
        player.clearLoop()
        let start = activeEvents.first?.start ?? 0
        let length = activeEvents.map(\.duration).min() ?? 1
        player.seek(milliseconds: start * 1000)
        player.playPause()
        auditionTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .seconds(length / player.playbackSpeed)) } catch { return }
            player.pause(); player.seek(milliseconds: start * 1000)
        }
    }
    func changeStage(_ stage: TutorialStage) { stop(); self.stage = stage; save() }
    func explore(_ position: GuitarPosition) {
        guard let event = phrase.events.first(where: { $0.position == position }) else {
            explorationHint = "That position is not in this example. Follow the lit notes, or use Next to explore the phrase."
            return
        }
        explorationHint = "\(tutorialPitchName(position.midi)) · String \(position.string) · \(position.fret == 0 ? "Open" : "Fret \(position.fret), finger \(event.finger)")"
        seek(event.start * 1000)
        hearCurrent()
    }
    func answer(_ position: GuitarPosition) {
        if position.string == lesson.quizString && position.fret == lesson.quizFret {
            quizMatched = true; quizFeedback = "Found it: \(tutorialPitchName(position.midi)), string \(position.string), \(position.fret == 0 ? "open" : "fret \(position.fret)")."
        } else {
            quizMatched = false; quizFeedback = "That is \(tutorialPitchName(position.midi)). Try string \(lesson.quizString), \(lesson.quizFret == 0 ? "open" : "fret \(lesson.quizFret)")."
        }
    }
    func save(completed: Bool? = nil) {
        progress.save(lesson.id, record: .init(stage: stage, phraseIndex: phraseIndex, position: player.cursorMilliseconds,
            speed: player.playbackSpeed, completed: completed ?? progress.record(lesson.id).completed))
    }
    func leave() { stop(); save() }
}
