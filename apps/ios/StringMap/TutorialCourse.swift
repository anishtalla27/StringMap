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
        guard course.version == 1, !course.lessons.isEmpty,
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
    let maxFret: Int?
    let rootPitchClass: Int?
    let question: TutorialQuestion?
    var section: String { number <= 12 ? "Foundations" : number <= 18 ? "Building Skills" : "Connected Playing" }
    var fretChoices: [Int] { Array(Set([quizFret, max(0, quizFret-1), min(maxFret ?? 5, quizFret+1), 0])).sorted() }
    let quizString: Int
    let quizFret: Int
    let phrases: [TutorialPhrase]
    var quizMIDI: Int { GuitarTuning.standard.openMIDIPitches[quizString - 1] + quizFret }
}
struct TutorialQuestion: Decodable {
    let question: String
    let answers: [String]
    let correctIndex: Int
    let hint: String
}
struct TutorialPhrase: Decodable, Identifiable {
    let id: String
    let name: String
    let events: [TutorialEvent]
    let mutedStrings: [Int]
    let barre: TeachingBarre?
    func result(bundle: Bundle = .main) throws -> PipelineResult {
        guard let url = bundle.url(forResource: id, withExtension: "musicxml", subdirectory: "Tutorial") else { throw CocoaError(.fileNoSuchFile) }
        let locks = Dictionary(uniqueKeysWithValues: events.compactMap { e in e.position.map { (e.id, $0) } })
        return try StructuredScorePipeline(importer: MusicXMLImporter(allowGuitarSlurs: true)).run(musicXML: Data(contentsOf: url), options: .init(maxFret: max(5, events.map(\.fret).max() ?? 5), lockedPositions: locks))
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
    var startQuarter: Double?
    let cue: String?
    let positionLabel: String?
    var start: Double { startQuarter ?? Double(measure) * 4 + onset }
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
        player.setTutorialPresentation(true)
        player.setShowTab(showTab)
        loadPhrase()
        player.setPlaybackSpeed(saved.speed)
        player.seek(milliseconds: saved.position)
    }
    func activate() { progress.activate(lesson.id) }
    var completed: Bool { progress.record(lesson.id).completed }
    var phrase: TutorialPhrase { lesson.phrases[phraseIndex] }
    var quarter: Double { player.cursorMilliseconds / 1000 } // All authored lessons use 60 quarter-note BPM.
    var events: [TutorialEvent] {
        guard let score = result?.score else { return [] }
        var offsets: [Double] = []; var sum = 0.0
        for measure in score.measures { offsets.append(sum); sum += measure.durationQuarters }
        return phrase.events.map { event in
            var resolved = event
            if offsets.indices.contains(event.measure) { resolved.startQuarter = offsets[event.measure] + event.onset }
            return resolved
        }
    }
    var activeEvents: [TutorialEvent] {
        let q = min(quarter, max(0, totalQuarters - 0.0001))
        return events.filter { $0.start <= q + 0.000001 && $0.start + $0.duration > q }
    }
    var currentAttack: TutorialEvent? { activeEvents.max { $0.start < $1.start } }
    var totalQuarters: Double { result?.score.measures.reduce(0) { $0 + $1.durationQuarters } ?? 0 }
    var upcoming: GuitarPosition? { events.first { $0.start > quarter + 0.0001 && $0.midi != nil }?.position }
    var fingers: [GuitarPosition: Int] {
        var mapping: [GuitarPosition: Int] = [:]
        let next = events.first { $0.start > quarter + 0.0001 && $0.midi != nil }
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
        let starts = Array(Set(events.map(\.start))).sorted()
        let next = direction > 0 ? starts.first { $0 > quarter + 0.001 } : starts.last { $0 < quarter - 0.001 }
        seek((next ?? (direction > 0 ? starts.last : starts.first) ?? 0) * 1000)
    }
    var auditionRange: Range<Double> {
        guard let attack = currentAttack else { return 0..<1 }
        var first = attack
        var last = attack
        let notes = result?.score.notes ?? []
        // Audition the complete authored slur, including its initial pick.
        // A destination alone cannot demonstrate a hammer-on or pull-off.
        while let note = notes.first(where: { $0.id == first.id }),
              let source = note.slurFromID, let event = events.first(where: { $0.id == source }) {
            first = event
        }
        while let destination = notes.first(where: { $0.slurFromID == last.id }),
              let event = events.first(where: { $0.id == destination.id }) {
            last = event
        }
        while let note = notes.first(where: { $0.id == first.id }), note.tieStop,
              let previous = notes.first(where: { candidate in
                  candidate.tieStart && candidate.midi == note.midi && candidate.voice == note.voice &&
                  events.contains { $0.id == candidate.id && abs($0.start + $0.duration - first.start) < 0.0001 }
              }), let event = events.first(where: { $0.id == previous.id }) { first = event }
        while let note = notes.first(where: { $0.id == last.id }), note.tieStart,
              let following = notes.first(where: { candidate in
                  candidate.tieStop && candidate.midi == note.midi && candidate.voice == note.voice &&
                  events.contains { $0.id == candidate.id && abs($0.start - last.start - last.duration) < 0.0001 }
              }), let event = events.first(where: { $0.id == following.id }) { last = event }
        if first.id != attack.id || last.id != attack.id { return first.start..<(last.start + last.duration) }
        let nextStart = events.first { $0.start > attack.start + 0.0001 }?.start ?? totalQuarters
        return attack.start..<min(attack.start + attack.duration, nextStart)
    }

    func hearCurrent() {
        guard player.isPlayerReady else { return }
        stop()
        player.clearLoop()
        let range = auditionRange
        let start = range.lowerBound
        let length = range.upperBound - start
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
        guard let event = events.first(where: { $0.position == position }) else {
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
    func answerKnowledge(_ index: Int) {
        guard let question = lesson.question else { return }
        quizMatched = index == question.correctIndex
        quizFeedback = quizMatched ? "That’s right. " + question.hint : question.hint
    }
    func save(completed: Bool? = nil) {
        progress.save(lesson.id, record: .init(stage: stage, phraseIndex: phraseIndex, position: player.cursorMilliseconds,
            speed: player.playbackSpeed, completed: completed ?? progress.record(lesson.id).completed))
    }
    func leave() { stop(); save() }
}
