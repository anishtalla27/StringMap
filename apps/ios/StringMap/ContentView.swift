import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import FingeringEngine
import ScorePipeline

private enum AppSection: Hashable {
    case home
    case library
    case workspace
    case importScore
    case settings
}

struct ContentView: View {
    @State private var model = AppModel()
    @State private var selection: AppSection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let isUITesting = ProcessInfo.processInfo.environment["STRINGMAP_UI_TEST_XML_BASE64"] != nil
        _selection = State(initialValue: isUITesting ? .workspace : .home)
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(
                    openImport: { selection = .importScore },
                    openWorkspace: { selection = .workspace },
                    openSong: open
                )
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(AppSection.home)

            NavigationStack {
                LibraryView(openSong: open)
            }
            .tabItem { Label("Library", systemImage: "music.note.list") }
            .tag(AppSection.library)

            NavigationStack {
                WorkspaceView(model: model, save: saveCurrentSong)
            }
            .tabItem { Label("Play", systemImage: "guitars") }
            .tag(AppSection.workspace)

            NavigationStack {
                ImportScoreView { document in
                    document.open(in: model)
                    selection = .workspace
                }
            }
            .tabItem { Label("Import", systemImage: "square.and.arrow.down") }
            .tag(AppSection.importScore)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppSection.settings)
        }
        .tint(.indigo)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveCurrentSong() }
        }
    }

    private func open(_ document: SongDocument) {
        document.open(in: model)
        selection = .workspace
    }

    private func saveCurrentSong() {
        guard let id = model.currentSongID else { return }
        let descriptor = FetchDescriptor<SongDocument>(predicate: #Predicate { $0.id == id })
        guard let document = try? modelContext.fetch(descriptor).first else { return }
        document.update(from: model)
        try? modelContext.save()
    }
}

private struct HomeView: View {
    @Query(sort: \SongDocument.updatedAt, order: .reverse) private var songs: [SongDocument]
    let openImport: () -> Void
    let openWorkspace: () -> Void
    let openSong: (SongDocument) -> Void

    var body: some View {
        List {
            Section {
                Button(action: openImport) {
                    Label("Import MusicXML", systemImage: "doc.badge.plus")
                }
                Button(action: openWorkspace) {
                    Label("Open bundled example", systemImage: "music.note")
                }
            } header: {
                Text("Start arranging")
            } footer: {
                Text("Printed-score scanning will be enabled after the structured-score path supports reliable score review.")
            }

            Section("Recent songs") {
                if songs.isEmpty {
                    ContentUnavailableView(
                        "No saved songs",
                        systemImage: "music.note.house",
                        description: Text("Import a MusicXML melody to add it to your library.")
                    )
                } else {
                    ForEach(songs.prefix(5)) { song in
                        SongRow(song: song).contentShape(Rectangle()).onTapGesture { openSong(song) }
                    }
                }
            }
        }
        .navigationTitle("StringMap")
    }
}

private struct LibraryView: View {
    @Query(sort: \SongDocument.updatedAt, order: .reverse) private var songs: [SongDocument]
    @Environment(\.modelContext) private var modelContext
    let openSong: (SongDocument) -> Void

    var body: some View {
        List {
            if songs.isEmpty {
                ContentUnavailableView(
                    "Your library is empty",
                    systemImage: "music.note.list",
                    description: Text("Imported MusicXML scores appear here and remain available offline.")
                )
            } else {
                ForEach(songs) { song in
                    Button { openSong(song) } label: { SongRow(song: song) }
                        .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Library")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(songs[index]) }
        try? modelContext.save()
    }
}

private struct SongRow: View {
    let song: SongDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .frame(width: 38, height: 38)
                .background(.indigo.opacity(0.12), in: Circle())
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title).font(.headline).foregroundStyle(.primary)
                Text([song.composer, song.generatedArrangementState].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(song.updatedAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

private struct ImportScoreView: View {
    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @Environment(\.modelContext) private var modelContext
    let didImport: (SongDocument) -> Void

    var body: some View {
        List {
            Section {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Choose MusicXML file", systemImage: "folder")
                }
                .accessibilityIdentifier("importMusicXML")
            } header: {
                Text("Structured score")
            } footer: {
                Text("StringMap currently accepts monophonic .musicxml and .xml files. Processing stays on this device.")
            }

            Section("Scan sheet music") {
                LabeledContent {
                    Text("Not enabled").foregroundStyle(.secondary)
                } label: {
                    Label("Camera, Photos, and PDF", systemImage: "doc.viewfinder")
                }
                Text("OMR is intentionally gated until recognition review and licensing boundaries are implemented.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if isImporting {
                Section { HStack { ProgressView(); Text("Validating score…") } }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Import")
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: allowedMusicXMLTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                if case let .failure(error) = result { errorMessage = error.localizedDescription }
                return
            }
            importFile(url)
        }
    }

    private func importFile(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            isImporting = true
            errorMessage = nil
            Task {
                do {
                    let score = try await Task.detached(priority: .userInitiated) {
                        try StructuredScorePipeline().run(musicXML: data).score
                    }.value
                    let document = SongDocument(
                        title: score.title,
                        composer: score.composer,
                        sourceName: url.deletingPathExtension().lastPathComponent,
                        musicXML: data
                    )
                    modelContext.insert(document)
                    try modelContext.save()
                    isImporting = false
                    didImport(document)
                } catch {
                    isImporting = false
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var allowedMusicXMLTypes: [UTType] {
        var types: [UTType] = [.xml]
        if let musicXML = UTType(filenameExtension: "musicxml") { types.append(musicXML) }
        return types
    }
}

private struct SettingsView: View {
    @AppStorage("defaultProfile") private var profileRaw = FingeringProfile.balanced.rawValue
    @AppStorage("defaultTuning") private var tuningRaw = GuitarTuningPreset.standard.rawValue
    @AppStorage("defaultCapo") private var capo = 0
    @AppStorage("defaultFrets") private var frets = 20
    @AppStorage("leftHanded") private var leftHanded = false
    @AppStorage("defaultMetronome") private var metronome = false

    var body: some View {
        Form {
            Section("Instrument defaults") {
                Picker("Tuning", selection: $tuningRaw) {
                    ForEach(GuitarTuningPreset.allCases.filter { $0 != .custom }, id: \.rawValue) {
                        Text($0.displayName).tag($0.rawValue)
                    }
                }
                Stepper("Capo: \(capo)", value: $capo, in: 0...12)
                Stepper("Frets: \(frets)", value: $frets, in: 12...30)
                Toggle("Left-handed fretboard", isOn: $leftHanded)
            }
            Section("Arrangement") {
                Picker("Default profile", selection: $profileRaw) {
                    ForEach(FingeringProfile.allCases, id: \.rawValue) {
                        Text($0.displayName).tag($0.rawValue)
                    }
                }
            }
            Section("Practice") {
                Toggle("Metronome by default", isOn: $metronome)
            }
            Section("About") {
                LabeledContent("Processing", value: "Local and offline")
                LabeledContent("Score renderer", value: "alphaTab")
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    ContentView().modelContainer(for: SongDocument.self, inMemory: true)
}
