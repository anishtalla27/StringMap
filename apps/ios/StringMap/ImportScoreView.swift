import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import FingeringEngine
import ScorePipeline

struct ImportScoreView: View {
    let scanEnabled: Bool
    let openScan: () -> Void
    let didImport: (SongDocument) -> Void

    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                studiesSection
                #if DEBUG
                fileSection
                #endif
                #if DEBUG
                if scanEnabled { scanSection }
                #endif
                if let errorMessage { errorBanner(errorMessage) }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: Space.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AmbientBackground())
        .navigationTitle("Learn")
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: allowedMusicXMLTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { importFile(url) }
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Sections

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeading(
                eyebrow: "Structured score",
                title: "Import a file",
                detail: "Single-part guitar scores with melodies and stacked notes. Conversion runs on this device."
            )

            Button {
                isImporterPresented = true
            } label: {
                Bezel {
                    HStack(spacing: Space.m) {
                        Image(systemName: "folder")
                            .font(.title3)
                            .foregroundStyle(Palette.brand)
                            .frame(width: 34, height: 34)
                            .background(Palette.brand.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Choose MusicXML file")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("MusicXML (.musicxml, .xml, or .mxl)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Space.xs)
                        if isImporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(Space.l)
                }
            }
            .buttonStyle(PressableCard())
            .disabled(isImporting)
            .accessibilityIdentifier("importMusicXML")

            if isImporting {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Validating score…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var studiesSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeading(
                eyebrow: "Included studies",
                title: "Written for this app",
                detail: "18 original single-note exercises. Follow the notation and glowing fretboard at your own tempo. All music works offline."
            )

            VStack(spacing: Space.m) {
                if DemoScore.all.isEmpty { Text("The exercise catalog could not be loaded. Please reinstall StringMap or contact support.") }
                ForEach(DemoScore.all) { demo in
                    Button { importDemo(demo) } label: { StudyCard(demo: demo) }
                        .buttonStyle(PressableCard())
                        .disabled(isImporting)
                        .accessibilityIdentifier("exercise-\(demo.resource)")
                }
            }
        }
    }

    #if DEBUG
    private var scanSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeading(
                eyebrow: "Photo import",
                title: "Scan guitar notation",
                detail: "Photograph one page of guitar notation, then check and correct the notes before creating tab. Scanning requires internet."
            )

            Button(action: openScan) {
                Panel {
                    HStack(spacing: Space.m) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title3)
                            .foregroundStyle(Palette.brand)
                            .frame(width: 34, height: 34)
                            .background(Palette.brand.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Take or choose a photo")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("You review every detected pitch before saving")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Space.xs)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(PressableCard())
            .accessibilityIdentifier("importScanSheetMusic")
        }
    }

    #endif

    private func errorBanner(_ message: String) -> some View {
        Panel {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.amber)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("That score couldn’t be imported").font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Import

    private func importFile(_ url: URL) {
        guard !isImporting else { return }
        isImporting = true
        errorMessage = nil
        Task {
            do {
                let (xml, score) = try await Task.detached(priority: .userInitiated) {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    let data = try MusicXMLContainer.read(from: url)
                    let xml = try MusicXMLContainer.scoreData(from: data)
                    return (xml, try MusicXMLImporter().importScore(from: xml))
                }.value
                let document = SongDocument(
                    title: score.title,
                    composer: score.composer,
                    sourceName: url.deletingPathExtension().lastPathComponent,
                    musicXML: xml
                )
                modelContext.insert(document)
                do { try modelContext.save() }
                catch { modelContext.delete(document); throw error }
                isImporting = false
                didImport(document)
            } catch {
                isImporting = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importDemo(_ demo: DemoScore) {
        guard !isImporting else { return }
        let source = "Bundled exercise: " + demo.resource
        do {
            let matches = try modelContext.fetch(FetchDescriptor<SongDocument>(predicate: #Predicate { $0.sourceName == source }))
            if let saved = matches.first { didImport(saved); return }
        } catch { errorMessage = error.localizedDescription; return }
        guard let url = Bundle.main.url(
            forResource: demo.resource,
            withExtension: "musicxml",
            subdirectory: demo.subdirectory
        ) else {
            errorMessage = "The bundled \(demo.title) score is missing."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            isImporting = true
            errorMessage = nil
            Task {
                do {
                    let options = OptimizationOptions(tuning: demo.tuning.tuning ?? .standard)
                    let score = try await Task.detached(priority: .userInitiated) {
                        try StructuredScorePipeline().run(musicXML: data, options: options).score
                    }.value
                    let document = SongDocument(
                        title: score.title,
                        composer: score.composer,
                        sourceName: source,
                        musicXML: data
                    )
                    document.tuningPresetRaw = demo.tuning.rawValue
                    document.capo = 0
                    document.transposition = 0
                    modelContext.insert(document)
                    do { try modelContext.save() }
                    catch { modelContext.delete(document); throw error }
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
        for suffix in ["musicxml", "mxl"] {
            if let type = UTType(filenameExtension: suffix) { types.append(type) }
        }
        return types
    }
}

private struct StudyCard: View {
    let demo: DemoScore

    var body: some View {
        HStack(spacing: Space.m) {
            RouteGlyph(seed: demo.title, finish: demo.finish)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(demo.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(demo.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                MetaLine([demo.level, demo.tuning.displayName], font: .caption)
            }
            Spacer(minLength: Space.xs)
            Image(systemName: "plus.circle")
                .font(.title3)
                .foregroundStyle(Palette.brand)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceRaised, in: shape)
        .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 0.5) }
        .shadow(color: Palette.shadowTint.opacity(0.08), radius: 4, y: 2)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.core, style: .continuous)
    }
}

struct DemoScore: Identifiable {
    let resource: String
    let title: String
    let detail: String
    let symbol: String
    let level: String
    let finish: ScoreFinish
    let tuning: GuitarTuningPreset
    var id: String { resource }

    var subdirectory: String { resource.hasPrefix("exercise-") ? "Exercises" : "Samples" }

    static let all: [DemoScore] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "Exercises"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([CatalogEntry].self, from: data) else { return [] }
        let finishes: [ScoreFinish] = [.surf, .sunburst, .cherry, .lake]
        return entries.enumerated().map { index, entry in
            DemoScore(resource: entry.resource, title: entry.title, detail: entry.detail,
                      symbol: "music.note", level: "\(entry.tempo) BPM", finish: finishes[index % finishes.count], tuning: .standard)
        }
    }()

    private struct CatalogEntry: Decodable {
        let resource: String
        let title: String
        let detail: String
        let tempo: Int
    }
}
