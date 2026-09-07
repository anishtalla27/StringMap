import SwiftUI

struct SongbookView: View {
    let search: String
    let open: (ClassicSong, ClassicArrangement) -> Void
    private let catalog = Result { try Songbook.load() }

    var body: some View {
        switch catalog {
        case .failure:
            ContentUnavailableView("Songbook unavailable", systemImage: "music.note.list", description: Text("The bundled song catalog could not be loaded."))
        case .success(let book):
            LazyVStack(alignment: .leading, spacing: Space.m) {
                Text("Songbook · Familiar Classics").font(.title2.weight(.semibold))
                Text("\(book.songs.count) familiar tunes. Play the melody or practice the chords. Everything works offline.")
                    .font(.subheadline).foregroundStyle(.secondary)
                let matches = book.songs.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.composer.localizedCaseInsensitiveContains(search) }
                if matches.isEmpty { ContentUnavailableView.search(text: search) }
                ForEach(matches) { song in
                    Bezel {
                        VStack(alignment: .leading, spacing: Space.m) {
                            Text(song.title).font(.headline)
                            Text("\(song.composer) · \(song.difficulty)").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                ForEach(song.arrangements) { arrangement in
                                    Button(arrangement.label) { open(song, arrangement) }
                                        .buttonStyle(.bordered)
                                        .accessibilityLabel("\(song.title), \(arrangement.label)")
                                        .accessibilityIdentifier("songbook-\(arrangement.id)")
                                }
                            }
                            DisclosureGroup("About this tune") {
                                Text(song.sourceEdition).font(.caption)
                                Text("Original StringMap guitar arrangement. Chords plays accompaniment, not the melody.").font(.caption)
                                Text("For Chords, strum the highlighted strings once at each measure and let them ring. Skip unmarked strings. Finger 0 means an open string; F uses a small index-finger barre across strings 1–2.").font(.caption)
                                if let url = URL(string: song.sourceURL) { Link("Historical source", destination: url).font(.caption) }
                            }.font(.caption)
                        }.padding(Space.l)
                    }
                }
            }.padding(Space.l).frame(maxWidth: Space.readingWidth).frame(maxWidth: .infinity)
        }
    }
}
