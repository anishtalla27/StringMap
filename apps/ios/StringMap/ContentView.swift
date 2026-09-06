import SwiftUI
import SwiftData
import FingeringEngine
import ScorePipeline

enum AppSection: Hashable {
    case home
    case library
    case workspace
    case importScore
    case settings
}

/// Recognition is an internal experiment and is never enabled in Release.
enum FeatureFlags {
    static var scanEnabledByDefault: Bool { false }
}


#if DEBUG
/// Debug-only launch routing so a screen can be opened directly for
/// verification and for generating store screenshots. Never compiled into a
/// release build.
enum LaunchRoute {
    static var screen: String? { ProcessInfo.processInfo.environment["STRINGMAP_SCREEN"] }
    static var seedsLibrary: Bool { ProcessInfo.processInfo.environment["STRINGMAP_SEED_LIBRARY"] != nil }
    /// Resource name of a bundled study to open, so a screen can be shown with
    /// the score that actually demonstrates it.
    static var demoResource: String? { ProcessInfo.processInfo.environment["STRINGMAP_LOAD_DEMO"] }

    static var section: AppSection? {
        switch screen {
        case "home": .home
        case "library": .library
        case "play", "trace", "practice", "instrument", "arrangements", "fretboard", "override": .workspace
        case "import": .importScore
        case "settings": .settings
        default: nil
        }
    }
}
#endif

struct ContentView: View {
    @State private var model = AppModel()
    @State private var tutorialProgress = TutorialProgress()
    @State private var tutorialLesson: TutorialLesson?
    @State private var freePractice = false
    #if DEBUG
    @State private var didApplyLaunchRoute = false
    #endif
    private let tutorialCourse = try? TutorialCourse.load()
    @State private var selection: AppSection
    @State private var persistenceError: String?
    @State private var isScanPresented = false
    #if DEBUG
    @AppStorage("enableScanPreview") private var scanEnabled = FeatureFlags.scanEnabledByDefault
    #else
    private let scanEnabled = false
    #endif
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    init() {
        #if DEBUG
        let isUITesting = ProcessInfo.processInfo.environment["STRINGMAP_UI_TEST_XML_BASE64"] != nil
        var initial: AppSection = isUITesting ? .workspace : .home
        #else
        let initial: AppSection = .home
        #endif
        #if DEBUG
        if let routed = LaunchRoute.section { initial = routed }
        #endif
        _selection = State(initialValue: initial)
    }

    private func openTutorial(_ lesson: TutorialLesson) {
        model.player.pause()
        tutorialLesson = lesson
    }

    var body: some View {
        Group {
            if let lesson = tutorialLesson {
                TutorialView(lesson: lesson, progress: tutorialProgress,
                    nextLesson: tutorialCourse?.lessons.first(where: { $0.number == lesson.number + 1 }).map { next in
                        { tutorialLesson = next }
                    }, close: { tutorialLesson = nil })
                    .id(lesson.id)
            } else {
                mainTabs
            }
        }
        .tint(Palette.brand)
        #if DEBUG
        .task { applyLaunchRoute() }
        #endif
    }

    private var mainTabs: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: AppSection.home) {
                NavigationStack {
                    HomeView(
                        model: model,
                        scanEnabled: scanEnabled,
                        openScan: { isScanPresented = true },
                        openImport: { freePractice = true; selection = .importScore },
                        openTutorial: {
                            freePractice = false
                            if let lesson = tutorialCourse?.lessons.first(where: { $0.id == tutorialProgress.lastLesson }) ?? tutorialCourse?.lessons.first {
                                openTutorial(lesson)
                            } else { selection = .importScore }
                        },
                        openWorkspace: { selection = .workspace },
                        openPractice: { open(.workspace) { model.isPracticePresented = true } },
                        openInstrument: { open(.workspace) { model.isInstrumentPresented = true } },
                        openArrangements: { open(.workspace) { model.isArrangementsPresented = true } },
                        openTrace: { open(.workspace) { model.isTracePresented = true } },
                        openFretboard: { open(.workspace) { model.isFretboardExpanded = true } },
                        openSong: openSong
                    )
                }
            }

            Tab("Library", systemImage: "music.note.list", value: AppSection.library) {
                NavigationStack {
                    LibraryView(openSong: openSong, willReview: { model.player.pause() })
                }
            }

            Tab("Play", systemImage: "guitars", value: AppSection.workspace) {
                NavigationStack {
                    WorkspaceView(model: model, save: saveCurrentSong)
                }
            }

            Tab("Learn", systemImage: "book", value: AppSection.importScore) {
                NavigationStack {
                    LearnView(course: tutorialCourse, progress: tutorialProgress, scanEnabled: scanEnabled,
                        openScan: { isScanPresented = true }, didImport: { document in
                            document.open(in: model); selection = .workspace
                        }, openLesson: openTutorial, freePractice: $freePractice)
                }
            }

            Tab("Settings", systemImage: "gearshape", value: AppSection.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tint(Palette.brand)
        // Minimizing belongs to the compact bottom tab bar. On iPad the bar
        // sits in the top toolbar, where minimizing leaves a ghost of the
        // accessory behind the leading toolbar item.
        .tabBarMinimizeBehavior(sizeClass == .compact ? .onScrollDown : .never)
        .tabViewBottomAccessory {
            TransportAccessory(model: model, openPlayer: { selection = .workspace })
        }
        #if DEBUG
        .sheet(isPresented: $isScanPresented) {
            NavigationStack {
                SheetMusicScanView { document in
                    document.open(in: model)
                    selection = .workspace
                }
            }
        }
        .onChange(of: isScanPresented) { _, presented in if presented { model.player.pause() } }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveCurrentSong(); model.player.pause() }
        }
        .alert("Couldn’t save your practice state", isPresented: Binding(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "Unknown persistence error")
        }
    }

    #if DEBUG
    private func applyLaunchRoute() {
        guard !didApplyLaunchRoute else { return }
        didApplyLaunchRoute = true
        if let id = ProcessInfo.processInfo.environment["STRINGMAP_TUTORIAL_ID"],
           let lesson = tutorialCourse?.lessons.first(where: { $0.id == id }) {
            openTutorial(lesson)
        }
        if LaunchRoute.screen == "import" { freePractice = true }

        if LaunchRoute.seedsLibrary { seedLibrary() }
        if let resource = LaunchRoute.demoResource { loadDemo(resource) }
        guard let screen = LaunchRoute.screen else { return }
        Task {
            // Let the pipeline finish so sheets have a result to render.
            try? await Task.sleep(for: .seconds(3))
            switch screen {
            case "trace": model.isTracePresented = true
            case "practice": model.isPracticePresented = true
            case "instrument": model.isInstrumentPresented = true
            case "arrangements": model.isArrangementsPresented = true
            case "fretboard": model.isFretboardExpanded = true
            case "override": model.editingNoteID = model.pipelineResult?.fingering.steps.first?.note.id
            case "scan": isScanPresented = true
            default: break
            }
        }
    }

    private func loadDemo(_ resource: String) {
        guard let demo = DemoScore.all.first(where: { $0.resource == resource }),
              let url = Bundle.main.url(
                forResource: demo.resource,
                withExtension: "musicxml",
                subdirectory: demo.subdirectory
              ),
              let data = try? Data(contentsOf: url) else { return }
        model.load(
            data: data,
            sourceName: demo.title,
            tuningPreset: demo.tuning
        )
    }

    private func seedLibrary() {
        let existing = (try? modelContext.fetchCount(FetchDescriptor<SongDocument>())) ?? 0
        guard existing == 0 else { return }
        for demo in DemoScore.all {
            guard let url = Bundle.main.url(
                forResource: demo.resource,
                withExtension: "musicxml",
                subdirectory: demo.subdirectory
            ), let data = try? Data(contentsOf: url) else { continue }
            let options = OptimizationOptions(tuning: demo.tuning.tuning ?? .standard)
            guard let score = try? StructuredScorePipeline().run(musicXML: data, options: options).score else { continue }
            let document = SongDocument(
                title: score.title,
                composer: score.composer,
                sourceName: demo.title,
                musicXML: data
            )
            document.tuningPresetRaw = demo.tuning.rawValue
            document.generatedArrangementState = "\(score.notes.count) notes · Balanced"
            modelContext.insert(document)
        }
        try? modelContext.save()
    }
    #endif

    private func open(_ section: AppSection, then action: @escaping () -> Void) {
        selection = section
        action()
    }

    private func openSong(_ document: SongDocument) {
        document.open(in: model)
        selection = .workspace
    }

    private func saveCurrentSong() {
        guard let id = model.currentSongID else { return }
        let descriptor = FetchDescriptor<SongDocument>(predicate: #Predicate { $0.id == id })
        do {
            guard let document = try modelContext.fetch(descriptor).first else { return }
            document.update(from: model)
            try modelContext.save()
        } catch {
            persistenceError = error.localizedDescription
        }
    }
}

// MARK: - Docked transport

/// The transport lives in the tab view's bottom accessory rather than inside
/// the Play screen, so playback stays reachable from every tab and the system
/// handles its material and its collapse behaviour.
private struct TransportAccessory: View {
    @Bindable var model: AppModel
    let openPlayer: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        // The system sizes this accessory for a single compact row; a taller
        // stack overflows it and collides with the content behind. Scrubbing
        // and stop live on the Play screen, where there is room for them.
        HStack(spacing: Space.m) {
            Button(action: openPlayer) {
                HStack(spacing: Space.s) {
                    RouteGlyph(seed: title)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(hasNoPlayableScore ? Color.red : .secondary)
                            .lineLimit(1)
                            .accessibilityIdentifier("playbackStatus")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            playButton
        }
        .padding(.horizontal, Space.m)
        .sensoryFeedback(.impact(weight: .light), trigger: model.player.isPlaying)
    }

    private var playButton: some View {
        Button {
            if model.player.isPlayerReady {
                model.player.playPause()
            } else {
                // The renderer lives in the Play tab and is created lazily, so
                // from another tab this both opens the player and queues the
                // start the listener actually asked for.
                openPlayer()
                model.player.playWhenReady()
            }
        } label: {
            Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .symbolEffect(.bounce, value: model.player.isPlaying)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.brand)
        .disabled(hasNoPlayableScore)
        .accessibilityIdentifier("playPause")
        .accessibilityLabel(model.player.isPlaying ? "Pause" : "Play")
    }

    private var title: String {
        model.pipelineResult?.score.title ?? model.notationScore?.title ?? model.sourceName
    }

    /// A guitar arrangement can fail while notation remains playable.
    private var hasNoPlayableScore: Bool {
        model.pipelineResult == nil && model.notationScore == nil && !model.isProcessing
    }

    private var subtitle: String {
        hasNoPlayableScore ? "No playable score" : model.player.playbackStatus
    }

    private func formatTime(_ milliseconds: Double) -> String {
        let seconds = max(0, Int(milliseconds / 1_000))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// A score's artwork. Scores are told apart the way guitars are — by finish:
/// a sunburst or a lake-placid or a cherry body, with the optimizer's route
/// lit across it. The finish and the route are both derived from the title, so
/// a score keeps the same mark for its whole life.
struct RouteGlyph: View {
    let seed: String
    var finish: ScoreFinish?

    private var resolvedFinish: ScoreFinish { finish ?? .forSeed(seed) }

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            // Every feature is sized off the shorter edge, so the mark reads the
            // same at 28pt in the transport as it does at 56pt in a list.
            let unit = min(w, h)
            let points = Self.points(for: seed).map { CGPoint(x: $0.x * w, y: $0.y * h) }
            ZStack {
                RoundedRectangle(cornerRadius: unit * 0.22, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: resolvedFinish.stops,
                            center: UnitPoint(x: 0.42, y: 0.38),
                            startRadius: 0,
                            endRadius: unit * 0.9
                        )
                    )
                Path { path in
                    for index in 0..<3 {
                        let y = h * (0.28 + Double(index) * 0.22)
                        path.move(to: CGPoint(x: w * 0.12, y: y))
                        path.addLine(to: CGPoint(x: w * 0.88, y: y))
                    }
                }
                .stroke(.white.opacity(0.20), lineWidth: max(0.5, unit * 0.02))

                Path { path in
                    path.move(to: points[0])
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(Palette.bone, style: StrokeStyle(lineWidth: max(1, unit * 0.05), lineCap: .round))

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Palette.bone)
                        .frame(width: unit * 0.15, height: unit * 0.15)
                        .position(point)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: unit * 0.22, style: .continuous)
                    .strokeBorder(Palette.plateEdge.opacity(0.9), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }

    private static func points(for seed: String) -> [CGPoint] {
        var hash: UInt64 = 5_381
        for byte in seed.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        let rows = [0.28, 0.50, 0.72]
        return (0..<3).map { index in
            let shifted = hash >> UInt64(index * 5)
            let x = 0.22 + Double(shifted % 5) / 4 * 0.56
            let y = rows[Int((shifted / 7) % 3)]
            return CGPoint(x: x, y: y)
        }
    }
}

#Preview {
    ContentView().modelContainer(for: SongDocument.self, inMemory: true)
}
