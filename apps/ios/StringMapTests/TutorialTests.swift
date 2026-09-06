import XCTest
import ScorePipeline
import FingeringEngine
@testable import StringMap

final class TutorialTests: XCTestCase {
    @MainActor
    func testAllLessonsAgainstIndependentPitchReferencesAndPinnedPositions() throws {
        let course = try TutorialCourse.load()
        let references: [[Int]] = [
            [40,45,50,55,59,64], [40,45,50,55,59,64,59,55,50,45,40,40],
            [64,65,67,65,64,67,64], [59,60,62,64,67,65,62,60,59,64],
            [50,52,53,55,57,55,52,50,55], [40,41,43,45,47,48,47,45,43,40],
            [64,64,64,64,64,64], [64,67,65,64,62,60,59,60,62,64,65,64],
            [40,47,52,55,59,64], [40,47,52,55,59,64,40,47,52,55,59,64],
            [45,52,57,60,64], [40,47,52,55,59,64,45,52,57,60,64],
            [50,57,62,66], [50,57,62,66,50,57,62,66],
            [59,60,62,64,67,65,64,62,60,59,64],
            [40,47,52,55,59,64,45,52,57,60,64,50,57,62,66,40,47,52,55,59,64]
        ]
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "TutorialEvidence")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "TutorialTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let progress = TutorialProgress(defaults: defaults)
        var phraseNumber = 0
        for lesson in course.lessons {
            XCTAssertTrue((1...6).contains(lesson.quizString)); XCTAssertTrue((0...3).contains(lesson.quizFret))
            let session = TutorialSession(lesson: lesson, progress: progress, showTab: false)
            for (index, phrase) in lesson.phrases.enumerated() {
                let result = try phrase.result()
                XCTAssertEqual(result.score.notes.map(\.midi), references[phraseNumber], phrase.id)
                phraseNumber += 1
                XCTAssertEqual(result, try phrase.result(), "Deterministic pinned arrangement")
                XCTAssertEqual(result.score.tempo, 60)
                XCTAssertTrue(result.score.warnings.isEmpty, "\(phrase.id): \(result.score.warnings)")
                XCTAssertEqual(result.score.measures.flatMap(\.events).count, phrase.events.count)
                XCTAssertTrue(result.score.measures.allSatisfy { $0.durationQuarters == 4 })
                XCTAssertEqual(result.fingering.steps.count, phrase.events.filter { $0.midi != nil }.count)
                session.choosePhrase(index)
                XCTAssertNil(session.error)
                for expected in phrase.events {
                    let event = try XCTUnwrap(result.score.measures[expected.measure].events.first { $0.id == expected.id })
                    XCTAssertEqual(event.onsetQuarters, expected.onset)
                    XCTAssertEqual(event.durationQuarters, expected.duration)
                    if let position = expected.position {
                        let step = try XCTUnwrap(result.fingering.steps.first { $0.note.id == expected.id })
                        XCTAssertEqual(step.position, position)
                        XCTAssertEqual(position.midi, [64,59,55,50,45,40][position.string - 1] + position.fret)
                        XCTAssertEqual(position.fret == 0, expected.finger == 0)
                        XCTAssertTrue((0...4).contains(expected.finger))
                    }
                    for speed in [0.25,0.5,0.75,1,1.5,2] {
                        session.player.setPlaybackSpeed(speed)
                        let q = expected.start + expected.duration / 2
                        session.seek(q * 1000)
                        let sounding = phrase.events.filter { $0.midi != nil && $0.start <= q && $0.start + $0.duration > q }
                        XCTAssertEqual(Set(session.activeEvents.compactMap(\.position)), Set(sounding.compactMap(\.position)))
                        XCTAssertEqual(Set(sounding.map(\.string)).count, sounding.count)
                    }
                }
                struct Evidence: Encodable { let score: NormalizedScore; let alphaTex: String }
                try JSONEncoder().encode(Evidence(score: result.score, alphaTex: result.alphaTex)).write(to: folder.appending(path: phrase.id + "-native.json"))
            }
            session.leave()
        }
        XCTAssertEqual(phraseNumber, 16)
    }

    @MainActor
    func testProgressRestoresWithoutChangingFreePracticeAndQuizHasHelpfulFallback() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TutorialTests.progress"))
        defaults.removePersistentDomain(forName: "TutorialTests.progress")
        defer { defaults.removePersistentDomain(forName: "TutorialTests.progress") }
        let lesson = try TutorialCourse.load().lessons[2]
        let progress = TutorialProgress(defaults: defaults)
        let practice = AppModel(loadSample: false)
        practice.player.seek(milliseconds: 2500); practice.player.setPlaybackSpeed(0.75)
        let session = TutorialSession(lesson: lesson, progress: progress, showTab: false)
        XCTAssertEqual(session.fingers[.init(string: 1, fret: 0, midi: 64)], 0)
        XCTAssertEqual(session.fingers[.init(string: 1, fret: 1, midi: 65)], 1)
        session.explore(.init(string: 1, fret: 3, midi: 67))
        XCTAssertEqual(session.player.cursorMilliseconds, 2000)
        session.changeStage(.practice); session.player.setPlaybackSpeed(0.5); session.seek(1000); session.save(completed: true)
        let resumed = TutorialSession(lesson: lesson, progress: TutorialProgress(defaults: defaults), showTab: true)
        XCTAssertEqual(resumed.stage, .practice); XCTAssertEqual(resumed.player.cursorMilliseconds, 1000)
        XCTAssertEqual(resumed.player.playbackSpeed, 0.5); XCTAssertTrue(resumed.completed); XCTAssertTrue(resumed.player.showTab)
        XCTAssertEqual(practice.player.cursorMilliseconds, 2500); XCTAssertEqual(practice.player.playbackSpeed, 0.75)
        resumed.answer(.init(string: 1, fret: 0, midi: 64)); XCTAssertFalse(resumed.quizMatched)
        XCTAssertTrue(resumed.quizFeedback?.contains("fret 1") == true)
        resumed.answer(.init(string: 1, fret: 1, midi: 65)); XCTAssertTrue(resumed.quizMatched)
        resumed.restart(); XCTAssertEqual(resumed.player.cursorMilliseconds, 0)
        resumed.step(1); XCTAssertEqual(resumed.player.cursorMilliseconds, 1000)
        resumed.step(-1); XCTAssertEqual(resumed.player.cursorMilliseconds, 0)
        let following = try TutorialCourse.load().lessons[3]
        let next = TutorialSession(lesson: following, progress: progress, showTab: false)
        next.activate()
        session.leave() // SwiftUI can dismiss the old lesson after constructing the next.
        XCTAssertEqual(progress.lastLesson, following.id)
        next.leave()
    }

    func testPitchMatchDoesNotCountMissingAudioAsStableEvidence() {
        var matcher = TutorialPitchMatch(target: 69)
        _ = matcher.update(frequency: nil, time: 0)
        XCTAssertEqual(matcher.update(frequency: 440, time: 0.1), "Hold that note…")
        XCTAssertEqual(matcher.update(frequency: 440, time: 0.8), "Hold that note…")
        _ = matcher.update(frequency: 440, time: 0.9)
        _ = matcher.update(frequency: 440, time: 1.0)
        XCTAssertEqual(matcher.update(frequency: 440, time: 1.1), "Matched")
    }

    func testYINHarmonicGuitarRangeAndWrongOctaves() throws {
        let rate = 12000.0
        for midi in 40...67 {
            let frequency = 440 * pow(2, Double(midi - 69)/12)
            for harmonics in [[1.0,0.45,0.2], [0.35,1,0.4], [1,0,0]] {
                let samples: [Float] = (0..<2048).map { i in
                    Float(harmonics.enumerated().reduce(0.0) { value, item in
                        value + 0.18 * item.element * sin(2 * .pi * frequency * Double(item.offset + 1) * Double(i) / rate)
                    })
                }
                let estimate = try XCTUnwrap(TutorialYIN.estimate(samples, sampleRate: rate), "MIDI \(midi)")
                XCTAssertLessThan(abs(1200 * log2(estimate.frequency / frequency)), 15, "MIDI \(midi)")
            }
            var matcher = TutorialPitchMatch(target: midi)
            _ = matcher.update(frequency: nil, time: 0)
            XCTAssertNotEqual(matcher.update(frequency: frequency * 2, time: 0.1), "Matched")
            XCTAssertNotEqual(matcher.update(frequency: frequency / 2, time: 0.5), "Matched")
            XCTAssertEqual(matcher.update(frequency: frequency, time: 1), "Hold that note…")
            _ = matcher.update(frequency: frequency, time: 1.1)
            _ = matcher.update(frequency: frequency, time: 1.2)
            XCTAssertEqual(matcher.update(frequency: frequency, time: 1.3), "Matched")
            XCTAssertTrue(matcher.update(frequency: frequency, time: 2) .contains("Let the string stop"))
            _ = matcher.update(frequency: nil, time: 3)
            XCTAssertEqual(matcher.update(frequency: frequency, time: 3.1), "Hold that note…")
        }
        XCTAssertNil(TutorialYIN.estimate(Array(repeating: 0, count: 2048), sampleRate: rate))
        // Deterministic broad-band noise; no microphone fixtures masquerading as real guitar recordings.
        var seed: UInt64 = 1
        let noise: [Float] = (0..<2048).map { _ in seed = seed &* 6364136223846793005 &+ 1; return Float(Double(seed >> 32) / Double(UInt32.max) - 0.5) }
        XCTAssertNil(TutorialYIN.estimate(noise, sampleRate: rate))
    }
}
