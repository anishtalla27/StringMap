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
        for lesson in course.lessons.prefix(12) {
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
    func testContinuationCourseAgainstIndependentReferences() throws {
        let course = try TutorialCourse.load()
        XCTAssertEqual(course.lessons.count, 24)
        // Hand-reviewed sounding MIDI, independent of the content generator.
        let references: [[Int]] = [
            [64,64,64,64,64,64,64,64,59,64,59,64,59,64,59,64],
            [59,60,62,64,67,65,64,62,60,59,64,65,67,64,62,59],
            [64,65,67,64,67,65,64], [64,65,67,64,64,64,64],
            [48,52,55,57,55,52,53,55], [57,55,52,50,52,55,48],
            [65,67,69,71,69,67,65,64], [62,64,67,69,64,66,69,71],
            [45,48,50,52,55,57,60,62,64,67,69,72],
            [72,69,67,64,62,60,57,55,52,50,48,45],
            [69,72,67,64,62,60,57], [64,67,69,72,69,64,69],
            [40,55,59,64,40,55,59,64,40,55,59,64,40,55,59,64],
            [45,57,60,64,45,57,60,64,45,57,60,64,45,57,60,64],
            [57,62,66,57,62,65], [57,61,64,57,60,64],
            [57,60,65,57,60,65], [57,60,65,55,59,64],
            [64,67,64,59,62,59], [65,67,65,60,62,60],
            [67,65,67,62,60,62], [65,67,65,60,62,60],
            [67,69,69,72,69,72,69,67,64,67,62,60,57,64,67,69,72,72,69,72,62,60,57,55,57],
            [50,57,62,66,50,57,62,66,50,57,62,65,50,57,62,65,45,57,61,64,45,57,61,64,45,57,60,64,45,57,60,64,
             50,57,62,66,50,57,62,66,50,57,62,65,50,57,62,65,45,57,61,64,45,57,61,64,45,57,60,64,45,57,60,64]
        ]
        // Independently specified rhythmic cells include rests and each chord tone.
        let eighths = Array(repeating: 0.5, count: 16)
        let quarters = Array(repeating: 1.0, count: 8)
        let ringingBar = [2.0,2,2,2,2,1.5,1,0.5]
        let rhythms: [[Double]] = [
            eighths, eighths,
            [0.5,1.5,0.5,0.5,1,1.5,0.5,1,1], quarters,
            [0.5,0.5,0.5,0.5,0.5,0.5,1.5,1.5], [0.5,0.5,0.5,0.5,0.5,0.5,3],
            quarters, quarters, Array(repeating: 1, count: 12), Array(repeating: 1, count: 12),
            [0.5,0.5,1,1,1,1,1,1,1], [1,0.5,0.5,2,1.5,0.5,1,1],
            ringingBar + ringingBar, ringingBar + ringingBar,
            [4,4,4,4,4,4], [4,4,4,4,4,4],
            [1,1,1,1,2,2,2,2], Array(repeating: 2, count: 8),
            quarters, quarters, quarters, quarters,
            Array(repeating: 1, count: 12) + [1.5,0.5] + Array(repeating: 1, count: 14) + [2,2],
            Array(repeating: ringingBar, count: 8).flatMap { $0 }
        ]
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "TutorialEvidence")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TutorialContinuationTests"))
        defer { defaults.removePersistentDomain(forName: "TutorialContinuationTests") }
        var index = 0
        for lesson in course.lessons.dropFirst(12) {
            XCTAssertEqual(lesson.phrases.count, 2)
            XCTAssertTrue(lesson.fretChoices.contains(lesson.quizFret))
            XCTAssertTrue((5...8).contains(lesson.maxFret ?? 5))
            let question = try XCTUnwrap(lesson.question)
            XCTAssertTrue(question.answers.indices.contains(question.correctIndex))
            XCTAssertFalse(question.hint.isEmpty)
            let session = TutorialSession(lesson: lesson, progress: TutorialProgress(defaults: defaults), showTab: false)
            for (phraseIndex, phrase) in lesson.phrases.enumerated() {
                let result = try phrase.result()
                XCTAssertEqual(result.score.notes.map(\.midi), references[index], phrase.id)
                XCTAssertEqual(result, try phrase.result())
                XCTAssertEqual(result.score.measures.flatMap(\.events).map(\.durationQuarters), rhythms[index], phrase.id)
                let expectedSlurs = [18:2,19:2,20:2,21:4,22:3][index] ?? 0
                XCTAssertEqual(result.score.notes.filter { $0.slurFromID != nil }.count, expectedSlurs, phrase.id)
                XCTAssertEqual(result.score.notes.filter(\.tieStop).count, index == 3 ? 1 : 0)
                if let barre = phrase.barre {
                    XCTAssertEqual([barre.fret, barre.firstString, barre.lastString, barre.finger], [1,1,2,1])
                    XCTAssertEqual(lesson.number, 21)
                }
                XCTAssertEqual(result.score.tempo, 60)
                XCTAssertTrue(result.score.warnings.isEmpty, "\(phrase.id): \(result.score.warnings)")
                XCTAssertEqual(result.score.measures.count, lesson.number == 24 ? 8 : lesson.number == 17 ? 3 : 2)
                XCTAssertTrue(result.score.measures.allSatisfy { $0.durationQuarters == (lesson.number == 15 ? 3 : 4) })
                session.choosePhrase(phraseIndex)
                for event in session.events {
                    let actual = try XCTUnwrap(result.score.measures[event.measure].events.first { $0.id == event.id })
                    XCTAssertEqual(actual.onsetQuarters, event.onset)
                    XCTAssertEqual(actual.durationQuarters, event.duration)
                    if let p = event.position {
                        XCTAssertEqual(result.fingering.steps.first { $0.note.id == event.id }?.position, p)
                        XCTAssertEqual(p.midi, [64,59,55,50,45,40][p.string-1]+p.fret)
                        XCTAssertEqual(p.fret == 0, event.finger == 0)
                        XCTAssertTrue((0...4).contains(event.finger))
                    }
                    for speed in [0.5,1,1.5,2] {
                        session.player.setPlaybackSpeed(speed)
                        let time = event.start + min(event.duration/2, 0.1)
                        session.seek(time*1000)
                        let expected = session.events.filter { $0.start <= time && $0.start+$0.duration > time && $0.midi != nil }
                        XCTAssertEqual(Set(session.activeEvents.compactMap(\.position)), Set(expected.compactMap(\.position)))
                        XCTAssertEqual(Set(expected.map(\.string)).count, expected.count)
                    }
                }
                struct Evidence: Encodable { let score: NormalizedScore; let alphaTex: String }
                try JSONEncoder().encode(Evidence(score: result.score, alphaTex: result.alphaTex)).write(to: folder.appending(path: phrase.id + "-native.json"))
                index += 1
            }
            session.leave()
        }
        XCTAssertEqual(index, 24)
    }

    @MainActor
    func testSlurAuditionIncludesInitialPickAndConnectedPitches() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TutorialSlurAudition"))
        defer { defaults.removePersistentDomain(forName: "TutorialSlurAudition") }
        let course = try TutorialCourse.load()
        let session = TutorialSession(lesson: course.lessons[22], progress: TutorialProgress(defaults: defaults), showTab: false)
        session.choosePhrase(1)
        for time in [0.0,1,2] {
            session.seek(time*1000)
            XCTAssertEqual(session.auditionRange, 0..<3)
        }
        session.leave()
        let tied = TutorialSession(lesson: course.lessons[13], progress: TutorialProgress(defaults: defaults), showTab: false)
        tied.choosePhrase(1)
        for time in [3.0,4] {
            tied.seek(time*1000)
            XCTAssertEqual(tied.auditionRange, 3..<5)
        }
        tied.leave()
    }

    @MainActor
    func testFingerpickingCueFollowsNewAttackWhileBassSustains() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TutorialAttackTests"))
        defer { defaults.removePersistentDomain(forName: "TutorialAttackTests") }
        let course = try TutorialCourse.load()
        let session = TutorialSession(lesson: course.lessons[18], progress: TutorialProgress(defaults: defaults), showTab: false)
        for (time, cue) in [(0.0, "p · thumb"), (0.5, "i · index"), (1.0, "m · middle"), (1.5, "a · ring")] {
            session.seek(time * 1000)
            XCTAssertEqual(session.currentAttack?.cue, cue)
            XCTAssertEqual(session.currentAttack?.start, time)
            XCTAssertEqual(session.auditionRange, time..<(time+0.5))
            XCTAssertTrue(session.activeEvents.contains { $0.midi == 40 })
        }
        session.leave()
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
