import SwiftUI
import SwiftData
import FingeringEngine
import ScorePipeline

struct HomeView: View {
    @Bindable var model: AppModel
    let scanEnabled: Bool
    @Query(sort: \SongDocument.updatedAt, order: .reverse) private var songs: [SongDocument]
    let openScan: () -> Void
    let openImport: () -> Void
    let openTutorial: () -> Void
    let openSongbook: () -> Void
    let openWorkspace: () -> Void
    let openPractice: () -> Void
    let openInstrument: () -> Void
    let openArrangements: () -> Void
    let openTrace: () -> Void
    let openFretboard: () -> Void
    let openSong: (SongDocument) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                hero
                Button(action: openTutorial) {
                    Bezel {
                        HStack(spacing: Space.m) {
                            Image(systemName: "hand.point.up.left").font(.title2).foregroundStyle(Palette.brand)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Continue Tutorial").font(.headline).foregroundStyle(.primary)
                                Text("Your first notes, one step at a time.").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Palette.brand)
                        }.padding(Space.l)
                    }
                }.buttonStyle(PressableCard()).accessibilityIdentifier("homeTutorial")
                Button(action: openSongbook) {
                    Bezel {
                        HStack(spacing: Space.m) {
                            Image(systemName: "music.note.list").font(.title2).foregroundStyle(Palette.brand)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Play a classic").font(.headline)
                                Text("Familiar tunes · Melody and chords").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Palette.brand)
                        }.padding(Space.l)
                    }
                }.buttonStyle(PressableCard()).accessibilityIdentifier("homeSongbook")
                if !songs.isEmpty { recents }
                addMusic
                practiceTools
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: Space.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AmbientBackground())
        .navigationTitle("StringMap")
    }

    // MARK: - Hero

    private var hero: some View {
        Button(action: openWorkspace) {
            Bezel {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(model.pipelineResult == nil && model.notationScore == nil ? "Preparing" : "Continue").eyebrow()
                            Text(title)
                                .font(.title2.weight(.semibold))
                                .fontWidth(.expanded)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: Space.s)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, Space.m)
                    }

                    if let result = model.pipelineResult {
                        // One typographic line, which wraps honestly at large
                        // type sizes instead of ellipsising into badges.
                        MetaLine([
                            "\(result.fingering.steps.count) notes",
                            "\(Int((result.score.tempo * model.player.playbackSpeed).rounded())) BPM",
                            model.tuning.name,
                        ], font: .footnote)

                        // The hero shows the score's own route across the neck,
                        // so the card is a picture of the thing itself.
                        FretboardView(
                            tuning: result.fingering.tuning,
                            capo: result.fingering.capo,
                            maxFret: result.fingering.maxFret,
                            active: model.activeStep?.position,
                            sounding: model.activeSteps.map(\.position),
                            upcoming: model.upcomingStep?.position
                        )
                        .frame(height: 128)
                    } else {
                        HStack(spacing: Space.s) {
                            ProgressView().controlSize(.small)
                            Text(model.status)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(height: 128, alignment: .center)
                    }
                }
                .padding(Space.l)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeOpenScore")
        .accessibilityHint("Opens the player with notation, tablature, and playback")
    }

    private var title: String {
        model.pipelineResult?.score.title ?? model.notationScore?.title ?? model.sourceName
    }

    // MARK: - Recents

    private var recents: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeading(eyebrow: "Your library", title: "Pick up where you left off")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.m) {
                    ForEach(songs.prefix(6)) { song in
                        Button { openSong(song) } label: { SongTile(song: song) }
                            .buttonStyle(.plain)
                            .scrollTransition(.animated) { content, phase in
                                content
                                    .opacity(1 - abs(phase.value) * 0.25)
                                    .scaleEffect(1 - abs(phase.value) * 0.03)
                            }
                    }
                }
                .padding(.horizontal, Space.xs)
                .padding(.vertical, Space.xs)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Practice tools

    /// One inset-grouped list rather than a grid of cards with accent bars
    /// down their left edges. The list fits all five tools where the grid fit
    /// four, and it stops the section competing with the score above it.
    private var practiceTools: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeading(
                eyebrow: "Practice",
                title: "Tools",
                detail: "Everything below acts on the score currently open in the player."
            )

            Panel(padded: false) {
                VStack(spacing: 0) {
                    SourceRow(
                        title: "Playback, tempo, and loops",
                        detail: "Slow it down, repeat a measure, count in, run the metronome.",
                        symbol: "metronome",
                        action: openPractice
                    )
                    .accessibilityIdentifier("homePracticeTools")

                    GradientRule().padding(.horizontal, Space.l)

                    SourceRow(
                        title: "Tuning, capo, and transpose",
                        detail: "Standard, alternate, and custom six-string setups.",
                        symbol: "tuningfork",
                        action: openInstrument
                    )
                    .accessibilityIdentifier("homeInstrumentTools")

                    GradientRule().padding(.horizontal, Space.l)

                    SourceRow(
                        title: "Difficulty profiles",
                        detail: "Compare five ways to play the same passage.",
                        symbol: "square.stack.3d.up",
                        action: openArrangements
                    )
                    .accessibilityIdentifier("homeDifficultyProfiles")
                    .disabled(model.arrangements.isEmpty)

                    GradientRule().padding(.horizontal, Space.l)

                    SourceRow(
                        title: "Synchronized fretboard",
                        detail: "Follow the route as it plays.",
                        symbol: "guitars",
                        action: openFretboard
                    )
                    .accessibilityIdentifier("homeFretboard")
                    .disabled(model.pipelineResult == nil)

                    GradientRule().padding(.horizontal, Space.l)

                    SourceRow(
                        title: "Why this fingering?",
                        detail: "Every candidate position, its cost, and why it lost.",
                        symbol: "list.bullet.rectangle",
                        action: openTrace
                    )
                    .accessibilityIdentifier("homeFingeringExplanation")
                    .disabled(model.pipelineResult == nil)
                }
            }
        }
    }

    // MARK: - Add music

    private var addMusic: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeading(
                eyebrow: "Included music",
                title: "Choose your next exercise",
                detail: "Read each note, hear it, and see exactly where to play it on the fretboard."
            )

            Panel(padded: false) {
                VStack(spacing: 0) {
                    #if DEBUG
                    SourceRow(
                        title: "Import MusicXML",
                        detail: "Choose a .musicxml, .xml, or .mxl guitar score from Files.",
                        symbol: "doc.badge.plus",
                        action: openImport
                    )
                    .accessibilityIdentifier("homeImportMusicXML")

                    GradientRule().padding(.horizontal, Space.l)

                    #endif
                    SourceRow(
                        title: "Included exercises",
                        detail: "18 original single-note exercises, ready to play offline.",
                        symbol: "books.vertical",
                        action: openImport
                    )
                    .accessibilityIdentifier("homeIncludedStudies")

                    #if DEBUG
                    if scanEnabled {
                        GradientRule().padding(.horizontal, Space.l)
                        SourceRow(
                            title: "Scan guitar notation",
                            detail: "One page, including stacked notes. Review before saving. Internet required.",
                            symbol: "camera.viewfinder",
                            action: openScan
                        )
                        .accessibilityIdentifier("homeScanSheetMusic")
                    }
                    #endif
                }
            }
        }
    }
}

// MARK: - Components

private struct SourceRow: View {
    let title: String
    let detail: String
    let symbol: String
    var tint: Color = Palette.brand
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Space.l)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCard())
    }
}

/// A recent score reads as a row, not as a poster: the finish identifies it at
/// a glance and the words do the rest. A large block of artwork per score would
/// out-shout the one thing on this screen that matters, which is the score
/// already open above it.
struct SongTile: View {
    let song: SongDocument

    var body: some View {
        HStack(spacing: Space.s) {
            RouteGlyph(seed: song.title)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(song.updatedAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s)
        .frame(width: 212, alignment: .leading)
        .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.core, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.core, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        }
    }
}

/// Physical press feedback — the card yields slightly rather than flashing.
struct PressableCard: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(Motion.settle, value: configuration.isPressed)
    }
}
