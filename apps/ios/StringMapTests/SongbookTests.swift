import XCTest
import SwiftData
import ScorePipeline
import FingeringEngine
@testable import StringMap

final class SongbookTests: XCTestCase {
    @MainActor
    func testEveryArrangementImportsWithExactPinnedPitchAndTiming() throws {
        let book = try Songbook.load()
        XCTAssertEqual(book.songs.count, 20)
        XCTAssertEqual(Set(book.songs.map(\.id)).count, 20)
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "SongbookEvidence")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        struct Evidence: Encodable { let score: NormalizedScore; let alphaTex: String }
        for song in book.songs {
            XCTAssertEqual(song.arrangements.map(\.kind), ["melody", "chords"])
            var timeline: [Double]?
            for arrangement in song.arrangements {
                do {
                    let result = try StructuredScorePipeline().run(musicXML: arrangement.data(), options: .init(lockedPositions: arrangement.positions))
                    XCTAssertTrue(result.score.warnings.isEmpty, "\(arrangement.id): \(result.score.warnings)")
                    XCTAssertEqual(result.score.notes.count, arrangement.positions.count)
                    for step in result.fingering.steps {
                        XCTAssertEqual(step.position, arrangement.positions[step.note.id])
                        XCTAssertEqual(step.position.midi, step.note.midi)
                        XCTAssertEqual(GuitarTuning.standard.openMIDIPitches[step.position.string-1] + step.position.fret, step.note.midi)
                    }
                    let durations = result.score.measures.map(\.durationQuarters)
                    XCTAssertEqual(durations.reduce(0, +), arrangement.durationQuarters)
                    if let timeline { XCTAssertEqual(durations, timeline) } else { timeline = durations }
                    let model = AppModel(loadSample: false)
                    model.pipelineResult = result
                    model.sourceName = arrangement.resource
                    for (index, _) in result.score.measures.enumerated() {
                        model.seekToMeasure(index)
                        XCTAssertEqual(model.currentMeasureIndex, index, "\(arrangement.id): exact measure seek")
                        let q = durations.prefix(index).reduce(0, +)
                        let expected = Set(arrangement.events.filter {
                            $0.midi != nil && q >= $0.onsetQuarters && q < $0.onsetQuarters + $0.durationQuarters
                        }.map(\.id))
                        XCTAssertEqual(Set(model.activeSteps.map(\.note.id)), expected, "\(arrangement.id): measure boundary")
                    }
                    for event in arrangement.events {
                        let at = event.onsetQuarters + event.durationQuarters * 0.75
                        let expected = Set(arrangement.events.filter {
                            $0.midi != nil && at >= $0.onsetQuarters && at < $0.onsetQuarters + $0.durationQuarters
                        }.map(\.id))
                        for bpm in [30.0, 60, 90, 120, result.score.tempo] {
                            model.setPlaybackSpeed(bpm / result.score.tempo)
                            model.player.seek(milliseconds: at * 60_000 / result.score.tempo)
                            XCTAssertEqual(Set(model.activeSteps.map(\.note.id)), expected, "\(arrangement.id): sustained highlight at \(at)")
                            if let chord = arrangement.chords.first(where: { at >= $0.onset && at < $0.onset + $0.duration }) {
                                XCTAssertEqual(model.classicChordLabel, chord.name(transposition: 0))
                            }
                        }
                    }
                    for m in result.score.measures {
                        for event in m.events {
                            let at = event.onsetQuarters
                            let sounding = m.events.compactMap { e -> String? in
                                guard case let .note(n) = e, at >= n.onsetQuarters, at < n.onsetQuarters + n.durationQuarters else { return nil }
                                return n.id
                            }
                            let strings = sounding.compactMap { arrangement.positions[$0]?.string }
                            XCTAssertEqual(Set(strings).count, strings.count)
                        }
                    }
                    try JSONEncoder().encode(Evidence(score: result.score, alphaTex: result.alphaTex)).write(to: folder.appending(path: arrangement.id + "-native.json"))
                } catch { XCTFail("\(arrangement.id): \(error)") }
            }
        }
    }

    @MainActor
    func testArrangementPersistenceAndExistingLibraryCompatibility() throws {
        let container = try ModelContainer(for: SongDocument.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let song = try XCTUnwrap(Songbook.load().songs.first)
        let first = try song.arrangements[0].document(song: song, context: container.mainContext)
        first.lastPracticedPosition = 4321; first.practiceSpeed = 0.75; first.showTabEnabled = false
        try container.mainContext.save()
        let again = try song.arrangements[0].document(song: song, context: container.mainContext)
        XCTAssertEqual(first.id, again.id); XCTAssertEqual(again.lastPracticedPosition, 4321)
        XCTAssertEqual(again.showTabEnabled, false)
        let chords = try song.arrangements[1].document(song: song, context: container.mainContext)
        XCTAssertNotEqual(first.id, chords.id); XCTAssertEqual(chords.lastPracticedPosition, 0)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SongDocument>()).count, 2)
    }

    @MainActor
    func testBundledCorrectionPreservesPracticeAndCompatibleLocks() throws {
        let container = try ModelContainer(for: SongDocument.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let song = try XCTUnwrap(Songbook.load().songs.first)
        let arrangement = song.arrangements[0]
        let document = try arrangement.document(song: song, context: container.mainContext)
        let identity = document.id
        document.musicXML = Data("older bundled revision".utf8)
        document.lastPracticedPosition = 1234
        document.practiceSpeed = 0.8
        document.metronomeEnabled = true
        document.countInEnabled = true
        let refreshed = try arrangement.document(song: song, context: container.mainContext)
        XCTAssertEqual(refreshed.id, identity)
        XCTAssertEqual(refreshed.musicXML, try arrangement.data())
        XCTAssertEqual(refreshed.lastPracticedPosition, 1234)
        XCTAssertEqual(refreshed.practiceSpeed, 0.8)
        XCTAssertEqual(refreshed.metronomeEnabled, true)
        XCTAssertEqual(refreshed.countInEnabled, true)
        XCTAssertEqual(refreshed.lockedPositions, arrangement.positions)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SongDocument>()).count, 1)
    }

    func testChordLabelTransposition() {
        let chord = ClassicChord(onset: 0, duration: 4, root: 9, quality: "m")
        XCTAssertEqual(chord.name(transposition: 0), "Am")
        XCTAssertEqual(chord.name(transposition: -2), "Gm")
        XCTAssertEqual(chord.name(transposition: 3), "Cm")
    }

    @MainActor
    func testAlternateConfigurationsPreserveEveryPitchOrReportUnplayable() throws {
        let options: [OptimizationOptions] = [
            .init(tuning: .dropD), .init(tuning: .halfStepDown),
            .init(capo: 2, transposeSemitones: 2), .init(transposeSemitones: -2)
        ]
        for song in try Songbook.load().songs {
            for arrangement in song.arrangements {
                let source = try MusicXMLImporter().importScore(from: arrangement.data())
                for option in options {
                    do {
                        let result = try StructuredScorePipeline().run(score: source, options: option)
                        XCTAssertEqual(result.score.notes.map(\.id), source.notes.map(\.id))
                        XCTAssertEqual(result.score.notes.map(\.midi), source.notes.map { $0.midi + option.transposeSemitones })
                        XCTAssertEqual(result.fingering.steps.count, source.notes.count)
                        for step in result.fingering.steps {
                            XCTAssertEqual(option.tuning.openMIDIPitches[step.position.string - 1] + step.position.physicalFret, step.note.midi)
                        }
                        XCTAssertEqual(result, try StructuredScorePipeline().run(score: source, options: option))
                    } catch let error as FingeringError {
                        switch error {
                        case .unplayableNote, .unplayableChord, .noValidPath: break
                        default: XCTFail("Unexpected failure for \(arrangement.id): \(error)")
                        }
                        XCTAssertEqual(source.notes.count, arrangement.positions.count)
                    }
                }
            }
        }
    }
}
