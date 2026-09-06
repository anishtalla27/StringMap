import SwiftUI
import FingeringEngine
import ScorePipeline

// MARK: - Practice

struct PracticeSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Playback speed", selection: Binding(
                        get: { model.player.playbackSpeed },
                        set: { model.setPlaybackSpeed($0) }
                    )) {
                        ForEach([0.5, 0.6, 0.75, 0.9, 1.0], id: \.self) { speed in
                            Text("\(Int(speed * 100))%").tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: model.player.playbackSpeed)

                    if let tempo = (model.pipelineResult?.score ?? model.notationScore)?.tempo {
                        Stepper(value: Binding(
                            get: { Int((tempo * model.player.playbackSpeed).rounded()) },
                            set: { model.setPlaybackSpeed(Double($0) / tempo) }
                        ), in: Int(ceil(tempo * 0.25))...Int(floor(tempo * 2))) {
                            Text("Tempo: \(Int((tempo * model.player.playbackSpeed).rounded())) BPM")
                        }
                        .accessibilityIdentifier("tempoBPM")
                        LabeledContent("Effective tempo") {
                            Text("\(Int((tempo * model.player.playbackSpeed).rounded())) BPM")
                                .stableNumber(.body)
                        }
                    }
                    Button("Reset to score tempo", systemImage: "arrow.counterclockwise") {
                        model.setPlaybackSpeed(1)
                    }
                    .disabled(model.player.playbackSpeed == 1)
                } header: {
                    Text("Tempo").eyebrow()
                } footer: {
                    Text("BPM counts quarter notes. Changing tempo keeps pitch intact.")
                }
                .listRowBackground(Palette.surfaceRaised)

                Section {
                    Button("Previous measure", systemImage: "backward.end") { model.previousMeasure() }
                    Button("Back five seconds", systemImage: "gobackward.5") { model.jumpBackward() }
                    Button("Next measure", systemImage: "forward.end") { model.nextMeasure() }
                    Button("Loop current measure", systemImage: "repeat.1") { model.loopCurrentMeasure() }
                        .accessibilityIdentifier("practiceLoopCurrentMeasure")
                        .disabled(model.currentMeasureIndex == nil)
                    Button("Restart loop", systemImage: "arrow.uturn.backward") { model.restartLoop() }
                        .disabled(model.loopStartMeasure == nil)
                } header: {
                    Text("Navigation").eyebrow()
                }
                .listRowBackground(Palette.surfaceRaised)

                Section {
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
                } header: {
                    Text("A/B loop").eyebrow()
                } footer: {
                    Text("Both ends are inclusive, so a start and end on the same measure repeats that measure alone.")
                }
                .listRowBackground(Palette.surfaceRaised)

                Section {
                    Toggle("Count-in", isOn: Binding(
                        get: { model.player.isCountInEnabled },
                        set: { model.setCountIn($0) }
                    ))
                    Toggle("Metronome", isOn: Binding(
                        get: { model.player.isMetronomeEnabled },
                        set: { model.setMetronome($0) }
                    ))
                } header: {
                    Text("Timing").eyebrow()
                }
                .listRowBackground(Palette.surfaceRaised)
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func measurePicker(_ title: String, selection: Binding<Int?>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(Int?.none)
            ForEach((model.pipelineResult?.score ?? model.notationScore)?.measures.indices ?? 0..<0, id: \.self) { index in
                Text("Measure \(index + 1)").tag(Int?.some(index))
            }
        }
    }
}

// MARK: - Instrument

struct InstrumentSettingsView: View {
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
                Section {
                    Picker("Tuning", selection: $preset) {
                        ForEach(GuitarTuningPreset.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .accessibilityIdentifier("instrumentTuning")
                    if preset == .custom {
                        ForEach(customMIDIs.indices, id: \.self) { index in
                            Stepper(
                                value: Binding(
                                    get: { customMIDIs[index] },
                                    set: { customMIDIs[index] = $0 }
                                ),
                                in: 24...84
                            ) {
                                LabeledContent("String \(index + 1)") {
                                    Text(pitchName(customMIDIs[index])).stableNumber(.body)
                                }
                            }
                        }
                    } else if let tuning = preset.tuning {
                        // The tuning is a fact about the instrument, so it is
                        // stamped on a rosewood strip the way it would be on a
                        // headstock rather than listed as six badges.
                        InstrumentPlate {
                            HStack(spacing: 0) {
                                ForEach(Array(tuning.pitchNames.enumerated()), id: \.offset) { _, name in
                                    Text(name.replacingOccurrences(of: "#", with: "♯"))
                                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                        .foregroundStyle(Palette.stringLine)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: Space.s, leading: Space.l, bottom: Space.s, trailing: Space.l))
                    }
                } header: {
                    Text("Tuning").eyebrow()
                } footer: {
                    Text("Changing the instrument clears manual fingering locks, because a locked position may no longer exist.")
                }
                .listRowBackground(Palette.surfaceRaised)

                Section {
                    Stepper(value: $capo, in: 0...min(12, maxFret)) {
                        LabeledContent("Capo") {
                            Text(capo == 0 ? "None" : "Fret \(capo)").stableNumber(.body)
                        }
                    }
                    Stepper(value: $maxFret, in: 12...30) {
                        LabeledContent("Last fret") { Text("\(maxFret)").stableNumber(.body) }
                    }
                    Button("Suggest an easier capo", systemImage: "wand.and.stars") {
                        if let suggestion = model.suggestCapo() { capo = suggestion }
                    }
                } header: {
                    Text("Instrument").eyebrow()
                }
                .listRowBackground(Palette.surfaceRaised)

                Section {
                    HStack {
                        Button("Down", systemImage: "minus.circle") {
                            transposition = max(-24, transposition - 1)
                        }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        Spacer()
                        Text(transposition == 0 ? "Original key" : String(format: "%+d semitones", transposition))
                            .stableNumber(.body)
                            .fontWeight(.medium)
                        Spacer()
                        Button("Up", systemImage: "plus.circle") {
                            transposition = min(24, transposition + 1)
                        }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.brand)

                    Button("Reset to original key") { transposition = 0 }
                        .disabled(transposition == 0)
                } header: {
                    Text("Transpose").eyebrow()
                }
                .listRowBackground(Palette.surfaceRaised)
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
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
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func pitchName(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[midi % 12])\(midi / 12 - 1)"
    }
}

// MARK: - Arrangements

struct ArrangementPickerView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// Difficulty is compared against the hardest arrangement on offer, so the
    /// bars answer "which of these is easier" rather than showing an abstract
    /// number with no reference point.
    private var hardest: Double {
        max(1, model.arrangements.values.map(\.fingering.metrics.estimatedDifficulty).max() ?? 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.m) {
                    ForEach(FingeringProfile.allCases, id: \.self) { profile in
                        if let result = model.arrangements[profile] {
                            Button {
                                model.useArrangement(profile)
                                dismiss()
                            } label: {
                                card(profile: profile, result: result)
                            }
                            .buttonStyle(PressableCard())
                        }
                    }
                }
                .padding(Space.l)
                .frame(maxWidth: Space.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .background(AmbientBackground())
            .navigationTitle("Arrangements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func card(profile: FingeringProfile, result: PipelineResult) -> some View {
        let metrics = result.fingering.metrics
        let isSelected = model.profile == profile
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(profile.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Label("In use", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.brand)
                }
            }

            DifficultyBar(
                value: metrics.estimatedDifficulty,
                maximum: hardest,
                tint: isSelected ? Palette.brand : Palette.neutralData
            )

            // Comparing arrangements is comparing numbers, so they line up in
            // columns that can be read down the list.
            HStack(alignment: .top, spacing: 0) {
                NumberColumn(label: "Shifts", value: "\(metrics.positionShifts)")
                NumberColumn(label: "Strings", value: "\(metrics.stringChanges)", showsLeadingRule: true)
                NumberColumn(label: "Open", value: "\(metrics.openStrings)", showsLeadingRule: true)
                NumberColumn(label: "Movement", value: "\(metrics.totalFretMovement)", showsLeadingRule: true)
            }
            .padding(.top, Space.hair)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(metrics.positionShifts) shifts, \(metrics.stringChanges) string changes, \(metrics.openStrings) open strings, \(metrics.totalFretMovement) frets of movement")

            Text("Average fret \(metrics.averagePhysicalFret, format: .number.precision(.fractionLength(1))) · highest \(metrics.maximumPhysicalFret)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceRaised, in: shape)
        .overlay {
            shape.strokeBorder(
                isSelected ? Palette.brand.opacity(0.55) : Palette.hairline,
                lineWidth: isSelected ? 1.5 : 0.5
            )
        }
        .shadow(color: Palette.shadowTint.opacity(0.08), radius: 4, y: 2)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.core, style: .continuous)
    }
}

private struct DifficultyBar: View {
    let value: Double
    let maximum: Double
    var tint: Color = Palette.brand

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text("Difficulty").eyebrow()
                Spacer()
                Text("\(Int(value.rounded()))").stableNumber(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceInset)
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geometry.size.width * min(1, value / maximum)))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Estimated difficulty \(Int(value.rounded())) of \(Int(maximum.rounded()))")
    }
}

// MARK: - Fingering override

struct FingeringOverrideView: View {
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
                                Text("Note \(index + 1) · \(pitchName(step.note.midi))").tag(step.note.id)
                            }
                        }
                    } header: {
                        Text("Which note").eyebrow()
                    }
                    .listRowBackground(Palette.surfaceRaised)
                }

                if let step = model.selectedStep,
                   let positions = model.pipelineResult?.candidates[step.note.id] {
                    Section {
                        ForEach(positions, id: \.self) { position in
                            Button {
                                model.lockFingering(noteID: step.note.id, at: position)
                                dismiss()
                            } label: {
                                HStack(spacing: Space.m) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("String \(position.string) · fret \(position.fret)")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text("Physical fret \(position.physicalFret)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if position == step.position {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Palette.brand)
                                    }
                                    if model.lockedNoteIDs.contains(step.note.id) {
                                        Image(systemName: "lock.fill")
                                            .foregroundStyle(Palette.positionLocked)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            // Without this the whole row takes the accent
                            // colour and stops reading as content.
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("\(pitchName(step.note.midi)) · \(positions.count) valid position\(positions.count == 1 ? "" : "s")").eyebrow()
                    } footer: {
                        Text("Locking a position keeps it fixed and re-optimizes everything around it.")
                    }
                    .listRowBackground(Palette.surfaceRaised)

                    if model.lockedNoteIDs.contains(step.note.id) {
                        Section {
                            Button("Unlock this note", systemImage: "lock.open", role: .destructive) {
                                model.unlockFingering(noteID: step.note.id)
                                dismiss()
                            }
                        }
                        .listRowBackground(Palette.surfaceRaised)
                    }
                } else {
                    ContentUnavailableView(
                        "No note selected",
                        systemImage: "music.note",
                        description: Text("Start playback, then tap the fretboard to choose the note you want to pin.")
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Lock fingering")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.success, trigger: model.lockedNoteIDs.count)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func pitchName(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[midi % 12])\(midi / 12 - 1)"
    }
}
