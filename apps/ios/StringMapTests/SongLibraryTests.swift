import XCTest
import SwiftData
import ScorePipeline
@testable import StringMap

final class SongLibraryTests: XCTestCase {
    @MainActor
    func testSavingWhileOpeningAnotherSongCannotCopyPreviousMetadata() async throws {
        func xml(_ title: String, step: String) -> Data {
            Data("<score-partwise><work><work-title>\(title)</work-title></work><part id='P1'><measure number='1'><attributes><divisions>1</divisions></attributes><note id='a'><pitch><step>\(step)</step><octave>4</octave></pitch><duration>1</duration></note></measure></part></score-partwise>".utf8)
        }
        let oldXML = xml("Previous score", step: "E")
        let newXML = xml("Next score", step: "G")
        let model = AppModel(loadSample: false)
        model.pipelineResult = try StructuredScorePipeline().run(musicXML: oldXML)
        model.editingNoteID = "a"
        let next = SongDocument(title: "Next score", composer: "Next composer", sourceName: "next.xml", musicXML: newXML)
        next.open(in: model)
        XCTAssertTrue(model.isProcessing)
        XCTAssertNil(model.pipelineResult)
        XCTAssertNil(model.editingNoteID)
        // This is the same save performed when the scene becomes inactive,
        // before the asynchronous new-score pipeline can finish.
        next.update(from: model)
        XCTAssertEqual(next.title, "Next score")
        XCTAssertEqual(next.composer, "Next composer")
        XCTAssertEqual(next.musicXML, newXML)
        let deadline = ContinuousClock.now + .seconds(5)
        while model.isProcessing && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isProcessing)
        XCTAssertEqual(model.pipelineResult?.score.title, "Next score")
        XCTAssertEqual(model.pipelineResult?.score.notes.first?.midi, 67)
    }

    @MainActor
    func testCommittedScanSurvivesDraftCleanupFailureWithoutDuplicateOrOverwrite() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appending(path: "library.store")
        let draftURL = folder.appending(path: "draft.plist")
        let xml = Data("<score-partwise><part id='P1'><measure number='1'><attributes><divisions>1</divisions></attributes><note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration></note></measure></part></score-partwise>".utf8)
        let score = try MusicXMLImporter().importScore(from: xml)
        let draft = ScanDraft(requestID: UUID().uuidString, serviceURL: "http://127.0.0.1:8765", sourceName: "Recovered scan", imageData: Data([4,5,6]), musicXML: xml)
        try draft.save(to: draftURL)
        let songID = try autoreleasepool {
            let container = try ModelContainer(for: SongDocument.self, configurations: ModelConfiguration(url: storeURL))
            let context = ModelContext(container)
            let song = try SongDocument.saveReviewedScan(draft, score: score, musicXML: xml, in: context)
            song.capo = 3; song.practiceSpeed = 0.75; song.title = "Practiced version"
            try context.save()
            // Keep the draft, as happens if the process stops before cleanup.
            return song.id
        }
        let container = try ModelContainer(for: SongDocument.self, configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(container)
        let recovered = try XCTUnwrap(ScanDraft.load(from: draftURL))
        XCTAssertEqual(try SongDocument.savedScan(requestID: recovered.requestID, in: context)?.id, songID)
        // A repeated save must return the committed song, even if its original
        // draft is stale. It cannot overwrite later practice or music edits.
        let changed = try score.transposed(by: 1)
        let repeated = try SongDocument.saveReviewedScan(recovered, score: changed,
            musicXML: MusicXMLWriter.data(for: changed), in: context)
        XCTAssertEqual(repeated.id, songID)
        XCTAssertEqual(repeated.musicXML, xml)
        XCTAssertEqual(repeated.title, "Practiced version")
        XCTAssertEqual(repeated.capo, 3); XCTAssertEqual(repeated.practiceSpeed, 0.75)
        XCTAssertEqual(repeated.sourceImageData, Data([4,5,6]))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongDocument>()), 1)
        // Another intentional import of the same photo remains a separate song.
        var another = recovered; another.requestID = UUID().uuidString
        let second = try SongDocument.saveReviewedScan(another, score: score, musicXML: xml, in: context)
        XCTAssertNotEqual(second.id, songID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongDocument>()), 2)
    }

    @MainActor
    func testUnfinishedLibraryCorrectionsSurviveReopenWithoutReplacingSavedMusic() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "library.store")
        let xml = Data("<score-partwise><part id='P1'><measure number='1'><attributes><divisions>1</divisions></attributes><note id='a'><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration></note></measure></part></score-partwise>".utf8)
        try autoreleasepool {
            let container = try ModelContainer(for: SongDocument.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            let song = SongDocument(title: "Saved music", composer: nil, sourceName: "Photo", musicXML: xml)
            song.sourceImageData = Data([1,2,3]); song.capo = 3
            context.insert(song); try context.save()
            var state = ScoreReviewState(score: try MusicXMLImporter().importScore(from: xml))
            try state.change({ $0 = try $0.transposed(by: 1) }, persist: { next in
                song.reviewDraftData = try PropertyListEncoder().encode(next); try context.save()
            })
            XCTAssertEqual(song.musicXML, xml)
        }
        let container = try ModelContainer(for: SongDocument.self, configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        let song = try XCTUnwrap(context.fetch(FetchDescriptor<SongDocument>()).first)
        let state = try PropertyListDecoder().decode(ScoreReviewState.self, from: XCTUnwrap(song.reviewDraftData))
        XCTAssertEqual(state.score.notes.first?.midi, 65)
        XCTAssertEqual(state.history.first?.notes.first?.midi, 64)
        XCTAssertEqual(song.musicXML, xml)
        XCTAssertEqual(song.sourceImageData, Data([1,2,3]))
        XCTAssertEqual(song.capo, 3)
        song.musicXML = try MusicXMLWriter.data(for: state.score)
        song.reviewDraftData = nil; try context.save()
        XCTAssertEqual(try MusicXMLImporter().importScore(from: song.musicXML).notes.first?.midi, 65)
        XCTAssertNil(song.reviewDraftData)
    }

    @MainActor
    func testSongSurvivesASeparateModelContext() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SongDocument.self, configurations: configuration)
        let writeContext = ModelContext(container)
        let document = SongDocument(
            title: "Saved melody",
            composer: "Test Composer",
            sourceName: "saved-melody",
            musicXML: Data("<score-partwise/>".utf8)
        )
        document.capo = 3
        document.lastPracticedPosition = 4_250
        document.practiceSpeed = 0.75
        document.loopStartMeasure = 1
        document.loopEndMeasure = 2
        document.metronomeEnabled = true
        document.countInEnabled = true
        writeContext.insert(document)
        try writeContext.save()

        let readContext = ModelContext(container)
        let fetched = try XCTUnwrap(readContext.fetch(FetchDescriptor<SongDocument>()).first)
        XCTAssertEqual(fetched.id, document.id)
        XCTAssertEqual(fetched.title, "Saved melody")
        XCTAssertEqual(fetched.composer, "Test Composer")
        XCTAssertEqual(fetched.capo, 3)
        XCTAssertEqual(fetched.lastPracticedPosition, 4_250)
        XCTAssertEqual(fetched.practiceSpeed, 0.75)
        XCTAssertEqual(fetched.loopStartMeasure, 1)
        XCTAssertEqual(fetched.loopEndMeasure, 2)
        XCTAssertEqual(fetched.metronomeEnabled, true)
        XCTAssertEqual(fetched.countInEnabled, true)
    }
    @MainActor
    func testScanFieldsMigrateWithoutLosingExistingPracticeState() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "library.store")
        let savedID = UUID()
        try autoreleasepool {
            let configuration = ModelConfiguration(url: url)
            let old = try ModelContainer(for: LibraryBeforeScanning.SongDocument.self, configurations: configuration)
            let context = ModelContext(old)
            let song = LibraryBeforeScanning.SongDocument(id: savedID, title: "Before scanning", composer: nil, sourceName: "migration", musicXML: Data("<score-partwise/>".utf8))
            song.capo = 4; song.practiceSpeed = 0.75; song.lastPracticedPosition = 2345
            song.loopStartMeasure = 1; song.loopEndMeasure = 3; song.metronomeEnabled = true
            context.insert(song); try context.save()
        }
        try autoreleasepool {
            let current = try ModelContainer(for: SongDocument.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(current)
            let song = try XCTUnwrap(context.fetch(FetchDescriptor<SongDocument>()).first)
            XCTAssertEqual(song.id, savedID); XCTAssertEqual(song.title, "Before scanning")
            XCTAssertEqual(song.capo, 4); XCTAssertEqual(song.practiceSpeed, 0.75)
            XCTAssertEqual(song.lastPracticedPosition, 2345); XCTAssertEqual(song.loopEndMeasure, 3)
            XCTAssertEqual(song.metronomeEnabled, true); XCTAssertNil(song.sourceImageData)
            XCTAssertNil(song.reviewDraftData)
            XCTAssertNil(song.originScanID)
            song.sourceImageData = Data(repeating: 127, count: 100_000)
            song.recognitionReviewedAt = .now; try context.save()
        }
        let reopened = try ModelContainer(for: SongDocument.self, configurations: ModelConfiguration(url: url))
        let song = try XCTUnwrap(ModelContext(reopened).fetch(FetchDescriptor<SongDocument>()).first)
        XCTAssertEqual(song.sourceImageData?.count, 100_000); XCTAssertEqual(song.capo, 4)
        XCTAssertNotNil(song.recognitionReviewedAt)
    }

}
