import SwiftUI
import FingeringEngine
import ScorePipeline

struct WorkspaceView: View {
    @Bindable var model: AppModel
    let save: () -> Void
    @State private var isPracticePresented = false
    @State private var isFretboardExpanded = false
    @AppStorage("leftHanded") private var leftHanded = false

    var body: some View {
        VStack(spacing: 8) {
            workspaceHeader
            if let result = model.pipelineResult {
                FretboardView(
                    tuning: result.fingering.tuning,
                    capo: result.fingering.capo,
                    maxFret: result.fingering.maxFret,
                    active: model.activeStep?.position,
                    upcoming: upcomingPosition(in: result),
                    leftHanded: leftHanded
                )
                .frame(height: 124)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.editingNoteID = model.activeStep?.note.id
                }
                .accessibilityHint("Tap to choose another valid fingering for the current note")
                .overlay(alignment: .topTrailing) {
                    Button("Expand fretboard", systemImage: "arrow.up.left.and.arrow.down.right") {
                        isFretboardExpanded = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .padding(4)
                }
            }
            AlphaTabWebView(controller: model.player)
                .accessibilityIdentifier("notationView")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // alphaTab's engraving palette is designed as dark ink on paper.
                // Keep the score readable as a light document in both app themes.
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5) }
        }
        .padding(.horizontal)
        .navigationTitle("StringMap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) {
            TransportBar(model: model, showPractice: { isPracticePresented = true })
        }
        .sheet(isPresented: $model.isTracePresented) {
            if let result = model.pipelineResult { FingeringTraceView(result: result.fingering) }
        }
        .sheet(isPresented: $model.isInstrumentPresented) {
            InstrumentSettingsView(model: model)
        }
        .sheet(isPresented: $model.isArrangementsPresented) {
            ArrangementPickerView(model: model)
        }
        .sheet(isPresented: $isPracticePresented) {
            PracticeSettingsView(model: model)
        }
        .sheet(isPresented: $isFretboardExpanded) {
            NavigationStack {
                if let result = model.pipelineResult {
                    FretboardView(
                        tuning: result.fingering.tuning,
                        capo: result.fingering.capo,
                        maxFret: result.fingering.maxFret,
                        active: model.activeStep?.position,
                        upcoming: upcomingPosition(in: result),
                        leftHanded: leftHanded
                    )
                    .frame(minHeight: 260)
                    .padding()
                }
            }
            .presentationDetents([.medium])
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button("Instrument", systemImage: "tuningfork") { model.isInstrumentPresented = true }
                .accessibilityLabel("Tuning, capo, and transposition")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Arrangements", systemImage: "square.stack.3d.up") {
                model.isArrangementsPresented = true
            }
            .disabled(model.arrangements.isEmpty)
            Button("Practice", systemImage: "metronome") { isPracticePresented = true }
        }
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.pipelineResult?.score.title ?? model.sourceName)
                        .font(.headline)
                        .lineLimit(1)
                    if let result = model.pipelineResult {
                        Text("\(result.fingering.steps.count) notes · \(format(result.score.tempo)) BPM · \(model.tuning.name)\(model.capo > 0 ? " · Capo \(model.capo)" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Picker("Profile", selection: Binding(
                    get: { model.profile },
                    set: { model.selectProfile($0) }
                )) {
                    ForEach(FingeringProfile.allCases, id: \.self) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("profilePicker")
            }

            HStack(spacing: 8) {
                if model.isProcessing { ProgressView().controlSize(.small) }
                Text(model.status)
                    .font(.footnote)
                    .foregroundStyle(model.pipelineResult == nil && !model.isProcessing ? .red : .secondary)
                    .lineLimit(1)
                Spacer()
                if let result = model.pipelineResult {
                    Button("Edit", systemImage: "hand.tap") {
                        model.editingNoteID = model.activeStep?.note.id ?? result.fingering.steps.first?.note.id
                    }
                    .font(.footnote)
                    Button("Why?", systemImage: "list.bullet.rectangle") { model.isTracePresented = true }
                        .font(.footnote)
                        .accessibilityIdentifier("showTrace")
                        .accessibilityValue("Total cost \(format(result.fingering.totalCost))")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func upcomingPosition(in result: PipelineResult) -> GuitarPosition? {
        guard let active = model.activeStep,
              let index = result.fingering.steps.firstIndex(where: { $0.note.id == active.note.id }),
              result.fingering.steps.indices.contains(index + 1) else { return nil }
        return result.fingering.steps[index + 1].position
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}

private struct TransportBar: View {
    @Bindable var model: AppModel
    let showPractice: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Text(formatTime(model.player.cursorMilliseconds))
                    .accessibilityIdentifier("playbackTime")
                Slider(value: Binding(
                    get: { model.player.endMilliseconds > 0 ? model.player.cursorMilliseconds / model.player.endMilliseconds : 0 },
                    set: { model.seek(fraction: $0) }
                ), in: 0...1)
                .disabled(model.player.endMilliseconds <= 0)
                Text(formatTime(model.player.endMilliseconds))
            }
            .font(.caption.monospacedDigit())

            HStack(spacing: 14) {
                Button("Stop", systemImage: "stop.fill") { model.player.stop() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(!model.player.isPlayerReady)
                    .accessibilityIdentifier("stopPlayback")

                Button("Jump back five seconds", systemImage: "gobackward.5") { model.jumpBackward() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(!model.player.isPlayerReady)

                Button(model.player.isPlaying ? "Pause" : "Play", systemImage: model.player.isPlaying ? "pause.fill" : "play.fill") {
                    model.player.playPause()
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 46, height: 36)
                .buttonStyle(.borderedProminent)
                .disabled(!model.player.isPlayerReady)
                .accessibilityIdentifier("playPause")

                Button("Loop current measure", systemImage: model.player.isLooping ? "repeat.1.circle.fill" : "repeat.1") {
                    model.loopCurrentMeasure()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(model.currentMeasureIndex == nil)

                Button(action: showPractice) {
                    HStack(spacing: 4) {
                        Image(systemName: model.player.isLooping ? "repeat.circle.fill" : "speedometer")
                        Text("\(Int((model.player.playbackSpeed * 100).rounded()))%")
                    }
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity)

            Text(model.player.playbackStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("playbackStatus")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private func formatTime(_ milliseconds: Double) -> String {
        let seconds = max(0, Int(milliseconds / 1_000))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct FretboardView: View {
    let tuning: GuitarTuning
    let capo: Int
    let maxFret: Int
    let active: GuitarPosition?
    let upcoming: GuitarPosition?
    var leftHanded = false

    var body: some View {
        GeometryReader { geometry in
            let leftInset = 34.0
            let rightInset = 34.0
            let topInset = 14.0
            let bottomInset = 10.0
            let boardWidth = max(1, geometry.size.width - leftInset - rightInset)
            let boardHeight = max(1, geometry.size.height - topInset - bottomInset)
            let visibleFrets = max(5, min(maxFret - capo, max(12, active?.fret ?? 0)))

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for stringIndex in 0..<6 {
                        let y = topInset + Double(stringIndex) * boardHeight / 5
                        var path = Path()
                        path.move(to: CGPoint(x: leftInset, y: y))
                        path.addLine(to: CGPoint(x: leftInset + boardWidth, y: y))
                        context.stroke(path, with: .color(.secondary.opacity(0.65)), lineWidth: Double(stringIndex + 1) * 0.22 + 0.5)
                    }
                    for fret in 0...visibleFrets {
                        let x = leftInset + Double(fret) * boardWidth / Double(visibleFrets)
                        let renderedX = leftHanded ? leftInset + boardWidth - (x - leftInset) : x
                        var path = Path()
                        path.move(to: CGPoint(x: renderedX, y: topInset))
                        path.addLine(to: CGPoint(x: renderedX, y: topInset + boardHeight))
                        context.stroke(path, with: .color(fret == 0 ? .primary : .secondary.opacity(0.4)), lineWidth: fret == 0 ? 2 : 0.7)
                    }
                }

                ForEach(0..<6, id: \.self) { index in
                    Text(tuning.pitchNames[index].replacingOccurrences(of: "#", with: "♯"))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .position(x: leftHanded ? geometry.size.width - 15 : 15, y: topInset + Double(index) * boardHeight / 5)
                }

                ForEach([0, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24].filter { $0 <= visibleFrets }, id: \.self) { fret in
                    Text(String(fret + capo))
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .position(
                            x: fretX(fret, left: leftInset, width: boardWidth, frets: visibleFrets),
                            y: topInset + boardHeight + 7
                        )
                }

                if let upcoming, upcoming.fret <= visibleFrets {
                    marker(upcoming, color: .secondary.opacity(0.35), boardWidth: boardWidth, boardHeight: boardHeight, left: leftInset, top: topInset, frets: visibleFrets)
                }
                if let active, active.fret <= visibleFrets {
                    marker(active, color: .indigo, boardWidth: boardWidth, boardHeight: boardHeight, left: leftInset, top: topInset, frets: visibleFrets)
                }

                Text(capo > 0 ? "Capo \(capo)" : "Open")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .position(x: leftInset + boardWidth / 2, y: 5)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Guitar fretboard")
        .accessibilityValue(active.map { "Current note string \($0.string), fret \($0.fret)" } ?? "Waiting for playback")
    }

    private func marker(
        _ position: GuitarPosition,
        color: Color,
        boardWidth: Double,
        boardHeight: Double,
        left: Double,
        top: Double,
        frets: Int
    ) -> some View {
        let naturalX = position.fret == 0
            ? left
            : left + (Double(position.fret) - 0.5) * boardWidth / Double(frets)
        let x = leftHanded ? left + boardWidth - (naturalX - left) : naturalX
        let y = top + Double(position.string - 1) * boardHeight / 5
        return Circle()
            .fill(color)
            .overlay { Text(String(position.fret)).font(.caption2.bold()).foregroundStyle(.white) }
            .frame(width: 24, height: 24)
            .position(x: x, y: y)
    }

    private func fretX(_ fret: Int, left: Double, width: Double, frets: Int) -> Double {
        let natural = left + Double(fret) * width / Double(frets)
        return leftHanded ? left + width - (natural - left) : natural
    }
}

private struct PracticeSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Tempo") {
                    Picker("Playback speed", selection: Binding(
                        get: { model.player.playbackSpeed },
                        set: { model.setPlaybackSpeed($0) }
                    )) {
                        ForEach([0.5, 0.6, 0.75, 0.9, 1.0], id: \.self) { speed in
                            Text("\(Int(speed * 100))%").tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    if let tempo = model.pipelineResult?.score.tempo {
                        LabeledContent("Effective tempo", value: "\(Int((tempo * model.player.playbackSpeed).rounded())) BPM")
                    }
                    Button("Reset to score tempo", systemImage: "arrow.counterclockwise") {
                        model.setPlaybackSpeed(1)
                    }
                    .disabled(model.player.playbackSpeed == 1)
                }

                Section("Navigation") {
                    ControlGroup {
                        Button("Previous measure", systemImage: "backward.end") { model.previousMeasure() }
                        Button("Jump back five seconds", systemImage: "gobackward.5") { model.jumpBackward() }
                        Button("Next measure", systemImage: "forward.end") { model.nextMeasure() }
                    }
                    Button("Loop current measure", systemImage: "repeat.1") { model.loopCurrentMeasure() }
                    Button("Restart loop", systemImage: "arrow.uturn.backward") { model.restartLoop() }
                        .disabled(model.loopStartMeasure == nil)
                }

                Section("A/B loop") {
                    measurePicker("Start measure", selection: Binding(
                        get: { model.loopStartMeasure },
                        set: { model.setLoop(startMeasure: $0, endMeasure: model.loopEndMeasure) }
                    ))
                    measurePicker("End measure", selection: Binding(
                        get: { model.loopEndMeasure },
                        set: { model.setLoop(startMeasure: model.loopStartMeasure, endMeasure: $0) }
                    ))
                    Button("Clear loop", systemImage: "xmark.circle", action: model.clearLoop)
                        .disabled(model.loopStartMeasure == nil && model.loopEndMeasure == nil)
                }

                Section("Timing") {
                    Toggle("Count-in", isOn: Binding(
                        get: { model.player.isCountInEnabled },
                        set: { model.setCountIn($0) }
                    ))
                    Toggle("Metronome", isOn: Binding(
                        get: { model.player.isMetronomeEnabled },
                        set: { model.setMetronome($0) }
                    ))
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func measurePicker(_ title: String, selection: Binding<Int?>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(Int?.none)
            ForEach(model.pipelineResult?.score.measures.indices ?? 0..<0, id: \.self) { index in
                Text("Measure \(index + 1)").tag(Int?.some(index))
            }
        }
    }
}

private struct InstrumentSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var preset: GuitarTuningPreset
    @State private var customMIDIs: [Int]
    @State private var capo: Int
    @State private var maxFret: Int
    @State private var transposition: Int

    init(model: AppModel) {
        self.model = model
        _preset = State(initialValue: model.tuningPreset)
        _customMIDIs = State(initialValue: model.customTuningMIDIs)
        _capo = State(initialValue: model.capo)
        _maxFret = State(initialValue: model.maxFret)
        _transposition = State(initialValue: model.transposition)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tuning") {
                    Picker("Tuning", selection: $preset) {
                        ForEach(GuitarTuningPreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    if preset == .custom {
                        ForEach(customMIDIs.indices, id: \.self) { index in
                            Stepper(
                                "String \(index + 1): \(pitchName(customMIDIs[index]))",
                                value: Binding(
                                    get: { customMIDIs[index] },
                                    set: { customMIDIs[index] = $0 }
                                ),
                                in: 24...84
                            )
                        }
                    } else if let tuning = preset.tuning {
                        Text(tuning.pitchNames.joined(separator: "  "))
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Instrument") {
                    Stepper("Capo: \(capo)", value: $capo, in: 0...min(12, maxFret))
                    Stepper("Last fret: \(maxFret)", value: $maxFret, in: 12...30)
                    Button("Suggest an easier capo", systemImage: "wand.and.stars") {
                        if let suggestion = model.suggestCapo() { capo = suggestion }
                    }
                }
                Section("Transpose") {
                    HStack {
                        Button("Down", systemImage: "minus") { transposition = max(-24, transposition - 1) }
                        Spacer()
                        Text(transposition == 0 ? "Original key" : String(format: "%+d semitones", transposition))
                            .monospacedDigit()
                        Spacer()
                        Button("Up", systemImage: "plus") { transposition = min(24, transposition + 1) }
                    }
                    Button("Reset to original key") { transposition = 0 }
                        .disabled(transposition == 0)
                }
            }
            .navigationTitle("Instrument")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        model.applyInstrument(
                            preset: preset,
                            customMIDIs: customMIDIs,
                            capo: capo,
                            maxFret: maxFret,
                            transposition: transposition
                        )
                        dismiss()
                    }
                }
            }
        }
    }

    private func pitchName(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[midi % 12])\(midi / 12 - 1)"
    }
}

private struct FingeringOverrideView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let result = model.pipelineResult {
                    Section {
                        Picker("Note", selection: Binding(
                            get: { model.editingNoteID ?? result.fingering.steps.first?.note.id ?? "" },
                            set: { model.editingNoteID = $0 }
                        )) {
                            ForEach(Array(result.fingering.steps.enumerated()), id: \.element.note.id) { index, step in
                                Text("\(index + 1). MIDI \(step.note.midi)").tag(step.note.id)
                            }
                        }
                    }
                }
                if let step = model.selectedStep,
                   let positions = model.pipelineResult?.candidates[step.note.id] {
                    Section("MIDI \(step.note.midi) · \(positions.count) valid positions") {
                        ForEach(positions, id: \.self) { position in
                            Button {
                                model.lockFingering(noteID: step.note.id, at: position)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("String \(position.string), fret \(position.fret)")
                                        Text("Physical fret \(position.physicalFret)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if position == step.position { Image(systemName: "checkmark") }
                                    if model.lockedNoteIDs.contains(step.note.id) { Image(systemName: "lock.fill") }
                                }
                            }
                        }
                    }
                    if model.lockedNoteIDs.contains(step.note.id) {
                        Section {
                            Button("Unlock fingering", systemImage: "lock.open", role: .destructive) {
                                model.unlockFingering(noteID: step.note.id)
                                dismiss()
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No active note", systemImage: "music.note", description: Text("Start playback, then tap the fretboard."))
                }
            }
            .navigationTitle("Lock Fingering")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct ArrangementPickerView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(FingeringProfile.allCases, id: \.self) { profile in
                    if let result = model.arrangements[profile] {
                        Button { model.useArrangement(profile); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(profile.displayName).font(.headline)
                                    Spacer()
                                    if model.profile == profile { Image(systemName: "checkmark.circle.fill").foregroundStyle(.indigo) }
                                }
                                let metrics = result.fingering.metrics
                                Text("Difficulty \(Int(metrics.estimatedDifficulty.rounded())) · \(metrics.positionShifts) shifts · \(metrics.stringChanges) string changes")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text("Movement \(metrics.totalFretMovement) · average fret \(metrics.averagePhysicalFret, format: .number.precision(.fractionLength(1))) · max \(metrics.maximumPhysicalFret)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Arrangements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
