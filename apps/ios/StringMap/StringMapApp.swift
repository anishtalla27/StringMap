import SwiftUI
import SwiftData

@main
struct StringMapApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SongDocument.self)
    }
}
