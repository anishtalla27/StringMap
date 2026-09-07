import SwiftUI
import SwiftData
import ScorePipeline

struct LibraryView: View {
    @Query(sort: \SongDocument.updatedAt, order: .reverse) private var songs: [SongDocument]
    @Environment(\.modelContext) private var modelContext
    @State private var deletionError: String?
    @State private var search = ""
    @State private var review: LibraryReview?
    @State private var savedReview: SongDocument?
    @Binding var showSongbook: Bool
    let openClassic: (ClassicSong, ClassicArrangement) -> Void
    let openSong: (SongDocument) -> Void
    let willReview: () -> Void

    private var filtered: [SongDocument] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return songs }
        return songs.filter {
            $0.title.lowercased().contains(query)
                || ($0.composer ?? "").lowercased().contains(query)
        }
    }

    var body: some View {
        ScrollView {
            Picker("Library collection", selection: $showSongbook) {
                Text("Songbook").tag(true)
                Text("My Library").tag(false)
            }.pickerStyle(.segmented).padding(.horizontal, Space.l)
            if showSongbook {
                SongbookView(search: search, open: openClassic)
            } else if songs.isEmpty {
                ContentUnavailableView {
                    Label("Nothing saved yet", systemImage: "music.note.list")
                } description: {
                    Text("Songs and exercises you open are saved here with your practice settings and stay available offline.")
                }
                .padding(.top, Space.xxl)
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
                    .padding(.top, Space.xxl)
            } else {
                LazyVStack(spacing: Space.m) {
                    ForEach(filtered) { song in
                        Button { openSong(song) } label: { SongCard(song: song) }
                            .buttonStyle(PressableCard())
                            .accessibilityIdentifier("librarySong-\(song.id.uuidString)")
                            .contextMenu {
                                if song.sourceImageData != nil {
                                    Button("Review source and correct notes", systemImage: "pencil") { reviewScore(song) }
                                }
                                Button("Remove from library", systemImage: "trash", role: .destructive) {
                                    delete(song)
                                }
                            }
                            .scrollTransition(.animated) { content, phase in
                                content.opacity(1 - abs(phase.value) * 0.2)
                            }
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
                .frame(maxWidth: Space.readingWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .background(AmbientBackground())
        .navigationTitle("Library")
        .searchable(text: $search, prompt: "Search scores")
        .sheet(item: $review, onDismiss: {
            if let document = savedReview { savedReview = nil; openSong(document) }
        }) { item in
            NavigationStack {
                ScoreReviewView(state: item.state, imageData: item.song.sourceImageData ?? Data(), persist: { state in
                    let previous = item.song.reviewDraftData
                    item.song.reviewDraftData = try PropertyListEncoder().encode(state)
                    do { try modelContext.save() }
                    catch { item.song.reviewDraftData = previous; throw error }
                }, discard: {
                    let original = try MusicXMLImporter().importScore(from: item.song.musicXML)
                    let previous = item.song.reviewDraftData; item.song.reviewDraftData = nil
                    do { try modelContext.save() }
                    catch { item.song.reviewDraftData = previous; throw error }
                    return ScoreReviewState(score: original)
                }) { xml, score in
                    let oldXML = item.song.musicXML; let oldTitle = item.song.title
                    let oldDate = item.song.recognitionReviewedAt; let oldUpdated = item.song.updatedAt
                    let oldDraft = item.song.reviewDraftData
                    item.song.musicXML = xml; item.song.title = score.title
                    item.song.recognitionReviewedAt = .now; item.song.updatedAt = .now
                    item.song.reviewDraftData = nil
                    do { try modelContext.save() }
                    catch {
                        item.song.musicXML = oldXML; item.song.title = oldTitle
                        item.song.recognitionReviewedAt = oldDate; item.song.updatedAt = oldUpdated
                        item.song.reviewDraftData = oldDraft
                        throw error
                    }
                    savedReview = item.song
                }
            }
        }
        .alert("Couldn’t update the library", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "Unknown persistence error")
        }
    }

    private func reviewScore(_ song: SongDocument) {
        do {
            let state = try song.reviewDraftData.map { try PropertyListDecoder().decode(ScoreReviewState.self, from: $0) }
                ?? ScoreReviewState(score: MusicXMLImporter().importScore(from: song.musicXML))
            review = LibraryReview(song: song, state: state)
            willReview()
        }
        catch { deletionError = error.localizedDescription }
    }

    private func delete(_ song: SongDocument) {
        modelContext.delete(song)
        do { try modelContext.save() }
        catch { modelContext.rollback(); deletionError = error.localizedDescription }
    }
}

private struct LibraryReview: Identifiable {
    let id = UUID()
    let song: SongDocument
    let state: ScoreReviewState
}

private struct SongCard: View {
    let song: SongDocument

    var body: some View {
        HStack(spacing: Space.m) {
            RouteGlyph(seed: song.title)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(song.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let composer = song.composer, !composer.isEmpty {
                    Text(composer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                MetaLine(
                    [song.generatedArrangementState, song.sourceType == "MusicXML" ? "" : song.sourceType],
                    font: .caption
                )
            }

            Spacer(minLength: Space.xs)

            VStack(alignment: .trailing, spacing: Space.xs) {
                Text(song.updatedAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(Space.m)
        .background(Palette.surfaceRaised, in: shape)
        .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 0.5) }
        .shadow(color: Palette.shadowTint.opacity(0.08), radius: 4, y: 2)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.core, style: .continuous)
    }
}
