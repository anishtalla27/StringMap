import SwiftUI
import FingeringEngine
import ScorePipeline

struct WorkspaceView: View {
    @Bindable var model: AppModel
    let save: () -> Void
    var openClassic: ((ClassicSong, ClassicArrangement) -> Void)? = nil
    @AppStorage("leftHanded") private var leftHanded = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isAccessibilitySize: Bool { typeSize.isAccessibilitySize }

    /// iPhone landscape leaves roughly 390pt of height — less than the header,
    /// fretboard, transport, and score need stacked. Treat it like an
    /// accessibility size and let the screen scroll.
    private var isShortScreen: Bool { verticalSizeClass == .compact }

    /// Only accessibility sizes need the scrolling fallback. A short screen has
    /// width to spare instead, so it gets a side-by-side layout.
    private var needsScrollingLayout: Bool { isAccessibilitySize }

    private var isSideBySide: Bool { isShortScreen && !isAccessibilitySize }

    var body: some View {
        content
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.s)
            .background(AmbientBackground())
        .navigationTitle(isSideBySide ? scoreTitle : "Play")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $model.isTracePresented) {
            if let result = model.pipelineResult {
                FingeringTraceView(result: result.fingering)
            }
        }
        .sheet(isPresented: $model.isInstrumentPresented) {
            InstrumentSettingsView(model: model)
        }
        .sheet(isPresented: $model.isArrangementsPresented) {
            ArrangementPickerView(model: model)
        }
        .sheet(isPresented: $model.isPracticePresented) {
            PracticeSettingsView(model: model)
        }
        .sheet(isPresented: $model.isFretboardExpanded) {
            ExpandedFretboardView(model: model, leftHanded: leftHanded)
        }
        .sheet(isPresented: Binding(
            get: { model.editingNoteID != nil },
            set: { if !$0 { model.editingNoteID = nil } }
        )) {
            FingeringOverrideView(model: model)
        }
        .onChange(of: model.status) { _, newValue in
            if newValue.hasPrefix("Ready") { save() }
        }
        .onDisappear(perform: save)
    }

    /// At accessibility text sizes the chrome alone is taller than the screen,
    /// so the whole screen scrolls and the score takes a definite height
    /// instead of being crushed to nothing.
    @ViewBuilder
    private var content: some View {
        if needsScrollingLayout {
            ScrollView {
                VStack(spacing: Space.m) {
                    stack
                }
                .padding(.top, Space.s)
                .padding(.bottom, Space.l)
            }
        } else if isSideBySide {
            // Landscape is short but wide: the neck and the score sit beside
            // each other rather than fighting for 390pt of height.
            VStack(spacing: Space.s) {
                header
                HStack(alignment: .top, spacing: Space.m) {
                    VStack(spacing: Space.s) {
                        if let result = model.pipelineResult {
                            fretboard(result)
                        }
                        scrubRow
                        Spacer(minLength: 0)
                    }
                    notation
                }
            }
        } else {
            VStack(spacing: Space.m) {
                stack
            }
        }
    }

    @ViewBuilder
    private var stack: some View {
        header

        if let result = model.pipelineResult {
            fretboard(result)
        }

        if let step = model.activeStep {
            Text("\((model.pipelineResult?.score.notes.first { $0.id == step.note.id }?.pitch ?? String(step.note.midi))) · String \(step.position.string) · \(step.position.fret == 0 ? "Open" : "Fret \(step.position.fret)")")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("currentNotePosition")
        } else {
            Text("Rest").font(.subheadline).accessibilityIdentifier("currentNotePosition")
        }

        scrubRow

        notation
            .frame(height: needsScrollingLayout ? 460 : nil)
    }

    // MARK: - Header

    private var scoreTitle: String {
        model.pipelineResult?.score.title ?? model.notationScore?.title ?? model.sourceName
    }

    @ViewBuilder
    private var header: some View {
        if let (song, selected) = model.classicSelection {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .top) {
                    Text(scoreTitle).font(.title3.weight(.semibold)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    profilePicker
                }
                HStack {
                    ForEach(song.arrangements) { arrangement in
                        Button(arrangement.label) { openClassic?(song, arrangement) }
                            .buttonStyle(.bordered)
                            .tint(arrangement.id == selected.id ? Palette.brand : .secondary)
                            .accessibilityIdentifier("switch-\(arrangement.kind)")
                    }
                    Spacer(minLength: Space.s)
                    Toggle("Tab", isOn: Binding(get: { model.player.showTab }, set: { model.player.setShowTab($0) }))
                        .toggleStyle(.button).accessibilityIdentifier("songbookShowTab")
                }.font(.caption)
                if selected.kind == "chords" {
                    HStack {
                        Text("Accompaniment · \(model.classicChordLabel ?? "Rest")")
                            .font(.subheadline.weight(.semibold)).accessibilityIdentifier("activeChord")
                        Spacer()
                        Button("Previous measure", systemImage: "chevron.left") { model.player.pause(); model.previousMeasure() }
                            .labelStyle(.iconOnly).accessibilityIdentifier("songbookPreviousMeasure")
                        Button("Next measure", systemImage: "chevron.right") { model.player.pause(); model.nextMeasure() }
                            .labelStyle(.iconOnly).accessibilityIdentifier("songbookNextMeasure")
                    }
                    if let guidance = model.classicFingerGuidanceCompact {
                        Text(guidance).font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel(model.classicFingerGuidance ?? guidance)
                    }
                }
                HStack {
                    metaRow
                    Spacer(minLength: Space.xs)
                    if model.pipelineResult != nil {
                        Button("Expand fretboard", systemImage: "arrow.up.left.and.arrow.down.right") {
                            model.isFretboardExpanded = true
                        }.labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(Palette.brand)
                        Button { model.isTracePresented = true } label: {
                            Image(systemName: "list.bullet.rectangle")
                        }
                        .buttonStyle(.plain).foregroundStyle(Palette.brand)
                        .accessibilityLabel("Why this fingering?")
                        .accessibilityIdentifier("showTrace")
                    }
                }
                if model.pipelineResult == nil || !(model.pipelineResult?.score.warnings.isEmpty ?? true) {
                    statusLine
                }
                if model.pipelineResult == nil && !model.isProcessing {
                    Button("Restore original guitar settings") {
                        model.load(data: model.sourceData ?? Data(), sourceName: selected.resource,
                                   songID: model.currentSongID, profile: model.profile,
                                   lastPositionMilliseconds: model.player.cursorMilliseconds,
                                   lockedPositions: selected.positions,
                                   playbackSpeed: model.player.playbackSpeed,
                                   loopStartMeasure: model.loopStartMeasure, loopEndMeasure: model.loopEndMeasure,
                                   metronomeEnabled: model.player.isMetronomeEnabled,
                                   countInEnabled: model.player.isCountInEnabled, showTab: model.player.showTab)
                    }
                }
            }
        } else if isSideBySide {
            statusLine
        } else {
            fullHeader
        }
    }

    private var fullHeader: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            let layout = isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Space.m))
            layout {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(model.pipelineResult == nil ? "Score" : "Now playing")
                        .eyebrow()
                        .lineLimit(1)
                    Text(scoreTitle)
                        .font(.title3.weight(.semibold))
                        .fontWidth(.expanded)
                        .lineLimit(isAccessibilitySize ? 3 : 1)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                profilePicker
            }

            metaRow

            statusLine
        }
    }

    private var profilePicker: some View {
        Picker("Profile", selection: Binding(
                    get: { model.profile },
                    set: { model.selectProfile($0) }
                )) {
                    ForEach(FingeringProfile.allCases, id: \.self) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
        .pickerStyle(.menu)
        .tint(Palette.brand)
        .accessibilityIdentifier("profilePicker")
        .sensoryFeedback(.selection, trigger: model.profile)
    }

    /// The score's facts read as one line rather than a row of pills: a pill
    /// per fact fragments a sentence into badges and costs more room than the
    /// words it holds.
    @ViewBuilder
    private var metaRow: some View {
        if let result = model.pipelineResult {
            MetaLine(metaParts(result), font: .footnote)
        }
    }

    private func metaParts(_ result: PipelineResult) -> [String] {
        var parts = [
            "\(result.fingering.steps.count) notes",
            "\(Int((result.score.tempo * model.player.playbackSpeed).rounded())) BPM",
            model.tuning.name,
        ]
        if model.capo > 0 { parts.append("Capo \(model.capo)") }
        if model.transposition != 0 {
            parts.append(String(format: "%+d semitones", model.transposition))
        }
        if !model.lockedNoteIDs.isEmpty {
            parts.append("\(model.lockedNoteIDs.count) locked")
        }
        return parts
    }

    private var statusLine: some View {
        HStack(spacing: Space.s) {
            if model.isProcessing {
                ProgressView().controlSize(.mini)
            } else {
                // Blue and green carry fixed meanings on the fretboard, so a
                // status dot borrows neither: the word next to it says the
                // state, and only a real failure earns a colour.
                Circle()
                    .fill(model.pipelineResult == nil ? Color.red : Palette.neutralData)
                    .frame(width: 6, height: 6)
            }
            Text(model.status)
                .font(.caption)
                .foregroundStyle(model.pipelineResult == nil && !model.isProcessing ? Color.red : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.xs)
            if model.pipelineResult != nil {
                Button {
                    model.isTracePresented = true
                } label: {
                    // The label is the first thing to overflow at accessibility
                    // sizes, so it drops to the glyph alone.
                    if isAccessibilitySize {
                        Image(systemName: "list.bullet.rectangle")
                    } else {
                        Label("Why?", systemImage: "list.bullet.rectangle")
                    }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(Palette.brand)
                .fixedSize()
                .accessibilityLabel("Why this fingering?")
                .accessibilityIdentifier("showTrace")
            }
        }
    }

    // MARK: - Fretboard

    /// Landscape has roughly 240pt of column to share between the neck, the
    /// scrub row and the transport, so the board takes a smaller share of it
    /// than it does in portrait where the whole screen is its to fill.
    private var fretboardHeight: CGFloat {
        if isAccessibilitySize { return 132 }
        if model.classicSelection != nil { return isSideBySide ? 120 : 132 }
        return isSideBySide ? 138 : 168
    }

    private func fretboard(_ result: PipelineResult) -> some View {
        // The board now carries its own mounted plate, so a second cream frame
        // around it would read as a picture of a picture.
        Group {
            FretboardView(
                tuning: result.fingering.tuning,
                capo: result.fingering.capo,
                maxFret: result.fingering.maxFret,
                active: model.activeStep?.position,
                sounding: model.activeSteps.map(\.position),
                upcoming: model.upcomingStep?.position,
                leftHanded: leftHanded
            )
            .frame(height: fretboardHeight)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.editingNoteID = model.activeStep?.note.id ?? result.fingering.steps.first?.note.id
        }
        .accessibilityHint("Tap to choose another valid fingering for the current note")
        .overlay(alignment: .topTrailing) {
            if model.classicSelection == nil {
            Button("Expand fretboard", systemImage: "arrow.up.left.and.arrow.down.right") {
                model.isFretboardExpanded = true
            }
            .labelStyle(.iconOnly)
            .font(.caption)
            .buttonStyle(.glass)
            .padding(Space.s)
            }
        }
    }

    // MARK: - Scrub row

    /// Position, looping, and stop sit with the score rather than in the docked
    /// accessory, which stays a one-line mini player.
    private var scrubRow: some View {
        HStack(spacing: Space.s) {
            Text(formatTime(model.player.cursorMilliseconds))
                .stableNumber(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityIdentifier("playbackTime")

            Slider(value: Binding(
                get: {
                    model.player.endMilliseconds > 0
                        ? model.player.cursorMilliseconds / model.player.endMilliseconds
                        : 0
                },
                set: { model.seek(fraction: $0) }
            ), in: 0...1)
            .disabled(model.player.endMilliseconds <= 0)
            .controlSize(.small)
            .tint(Palette.brand)
            .accessibilityLabel("Playback position")

            if !isAccessibilitySize {
                Text(formatTime(model.player.endMilliseconds))
                    .stableNumber(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            if !isAccessibilitySize {
                Button("Loop current measure", systemImage: model.player.isLooping ? "repeat.1.circle.fill" : "repeat.1") {
                    model.loopCurrentMeasure()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(model.player.isLooping ? Palette.brand : Color.secondary)
                .accessibilityValue(model.player.isLooping ? "Loop on" : "Loop off")
                .disabled(model.currentMeasureIndex == nil)
                .sensoryFeedback(.selection, trigger: model.player.isLooping)
            }

            Button("Restart", systemImage: "backward.end.fill") { model.restartPiece() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(!model.player.isPlayerReady)
                .accessibilityIdentifier("stopPlayback")
        }
        .font(.footnote)
    }

    private func formatTime(_ milliseconds: Double) -> String {
        let seconds = max(0, Int(milliseconds / 1_000))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Notation

    private var notation: some View {
        // alphaTab paints its own themed paper; the container only supplies the
        // edge treatment so the score reads as an inset panel, not a hole.
        // The web view stays mounted even with no result so the soundfont does
        // not reload; the overlay explains the blank instead.
        AlphaTabWebView(controller: model.player)
            .overlay { unplayableOverlay }
            .accessibilityIdentifier("notationView")
            .frame(maxWidth: .infinity, minHeight: 170, maxHeight: .infinity)
            .background(Palette.scorePaper)
            .clipShape(RoundedRectangle(cornerRadius: Radius.core, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.core, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.5)
            }
            .shadow(color: Palette.shadowTint.opacity(0.10), radius: 6, y: 3)
    }

    @ViewBuilder
    private var unplayableOverlay: some View {
        if model.pipelineResult == nil && model.notationScore == nil && !model.isProcessing {
            ContentUnavailableView {
                Label("No playable tab", systemImage: "guitars.fill")
            } description: {
                Text(model.status)
            } actions: {
                Button("Change instrument", systemImage: "tuningfork") {
                    model.isInstrumentPresented = true
                }
                .buttonStyle(.glassProminent)
            }
            .background(Palette.scorePaper)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Instrument", systemImage: "tuningfork") {
                model.isInstrumentPresented = true
            }
            .accessibilityLabel("Tuning, capo, and transposition")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isSideBySide { profilePicker }

            Button("Edit", systemImage: "hand.tap") {
                model.editingNoteID = model.activeStep?.note.id
                    ?? model.pipelineResult?.fingering.steps.first?.note.id
            }
            .disabled(model.pipelineResult == nil)

            Button("Arrangements", systemImage: "square.stack.3d.up") {
                model.isArrangementsPresented = true
            }
            .disabled(model.arrangements.isEmpty)

            Button("Practice", systemImage: "metronome") {
                model.isPracticePresented = true
            }
        }
    }


}

// MARK: - Expanded fretboard

private struct ExpandedFretboardView: View {
    @Bindable var model: AppModel
    let leftHanded: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.l) {
                if let result = model.pipelineResult {
                    Bezel {
                        FretboardView(
                            tuning: result.fingering.tuning,
                            capo: result.fingering.capo,
                            maxFret: result.fingering.maxFret,
                            active: model.activeStep?.position,
                            sounding: model.activeSteps.map(\.position),
                            upcoming: model.upcomingStep?.position,
                            leftHanded: leftHanded,
                            isExpanded: true
                        )
                        .frame(minHeight: 240)
                        .padding(Space.s)
                    }

                    HStack(spacing: Space.m) {
                        legend("Now", tint: Palette.positionActive)
                        legend("Next", tint: Palette.positionUpcoming)
                        if result.fingering.capo > 0 {
                            legend("Capo", tint: Palette.positionLocked)
                        }
                        Spacer()
                    }
                } else {
                    ContentUnavailableView(
                        "No score loaded",
                        systemImage: "guitars",
                        description: Text("Import a melody to see its route across the neck.")
                    )
                }
                Spacer(minLength: 0)
            }
            .padding(Space.l)
            .background(AmbientBackground())
            .navigationTitle("Fretboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func legend(_ text: String, tint: Color) -> some View {
        HStack(spacing: Space.xs) {
            Circle().fill(tint).frame(width: 9, height: 9)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }


}
