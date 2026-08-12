import XCTest
import SwiftData
@testable import StringMap

final class SongLibraryTests: XCTestCase {
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
        writeContext.insert(document)
        try writeContext.save()

        let readContext = ModelContext(container)
        let fetched = try XCTUnwrap(readContext.fetch(FetchDescriptor<SongDocument>()).first)
        XCTAssertEqual(fetched.id, document.id)
        XCTAssertEqual(fetched.title, "Saved melody")
        XCTAssertEqual(fetched.composer, "Test Composer")
        XCTAssertEqual(fetched.capo, 3)
        XCTAssertEqual(fetched.lastPracticedPosition, 4_250)
    }
}
