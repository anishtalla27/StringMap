import SwiftUI
import ScorePipeline

struct ScoreReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editState: ScoreReviewState
    private var score: NormalizedScore { editState.score }
    private var history: [NormalizedScore] { editState.history }
    @State private var editing: EventSelection?
    @State private var removingIssue: ScoreReviewIssue?
    @State private var showIssueConfirmation = false
    @State private var showSource = false
    @State private var showMeasureLength = false
    @State private var showSignatures = false
    @State private var showDiscard = false
    @State private var selectedMeasure = 0
    @State private var checked = false
    @State private var message: String?
    @State private var previewCurrent = false
    @State private var player = AlphaTabController()
    let imageData: Data
    let persist: (ScoreReviewState) throws -> Void
    let discard: () throws -> ScoreReviewState
    let save: (Data, NormalizedScore) throws -> Void

    init(state: ScoreReviewState, imageData: Data, persist: @escaping (ScoreReviewState) throws -> Void,
         discard: @escaping () throws -> ScoreReviewState,
         save: @escaping (Data, NormalizedScore) throws -> Void) {
        _editState = State(initialValue: state); self.imageData = imageData; self.persist = persist; self.discard = discard; self.save = save
    }

    var body: some View {
        List {
            Section {
                Text("\(score.measures.reduce(0) { $0 + $1.events.filter { if case .note = $0 { true } else { false } }.count }) notes · \(score.measures.count) measures")
                    .font(.headline).accessibilityIdentifier("reviewNoteCount")
                Text("Note names and octaves below show sounding pitch. Standard guitar notation is written one octave higher.")
                    .font(.caption).foregroundStyle(.secondary)
                if let image = UIImage(data: imageData) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320)
                        .accessibilityLabel("Original guitar notation for comparison")
                }
                Button("Enlarge source page", systemImage: "arrow.up.left.and.arrow.down.right") { showSource = true }
                Text("Check every pitch, rhythm, rest, and stacked note against the page. Recognition can miss or invent notes, especially in handwriting.")
                ForEach(score.warnings, id: \.self) { Text($0).foregroundStyle(.orange) }
            } header: { Text("Compare with your page") }

            if let issues = score.reviewIssues, !issues.isEmpty {
                Section("Unresolved marks") {
                    Text("These marks cannot be played yet. Compare each with the source page. Remove a mark only if recognition invented it; an actual mark on the page remains unsupported.")
                    ForEach(issues) { issue in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Measure \(issue.measureNumber): \(issue.mark)")
                            Text(issueLocation(issue)).font(.caption).foregroundStyle(.secondary)
                            Button("Inspect source and measure") {
                                selectedMeasure = min(issue.measureIndex, score.measures.count - 1)
                                showSource = true
                            }
                            Button("Remove incorrect mark") {
                                removingIssue = issue; showIssueConfirmation = true
                            }.accessibilityIdentifier("reviewRemoveMark-\(issue.id)")
                        }.buttonStyle(.borderless)
                    }
                }
            }

            Section {
                TextField("Title", text: Binding(get: { score.title }, set: { value in change { $0.title = value } }))
                    .accessibilityLabel("Score title").accessibilityIdentifier("reviewTitle")
                Stepper("Tempo: \(Int(score.tempo)) BPM", value: Binding(get: { score.tempo }, set: { value in change { $0.tempo = value } }), in: 10...600)
                HStack {
                    Button("Lower octave") { change { $0 = try $0.transposed(by: -12) } }
                    Spacer()
                    Button("Raise octave") { change { $0 = try $0.transposed(by: 12) } }
                }
                .buttonStyle(.borderless)
                Text("Guitar sounds an octave below conventional written guitar notation. Use the octave controls only if the detected pitches need that correction; it is never applied silently.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Detected music") }

            Section {
                Picker("Measure", selection: $selectedMeasure) {
                    ForEach(score.measures.indices, id: \.self) { i in Text(score.measures[i].number).tag(i) }
                }
                if score.measures.indices.contains(selectedMeasure) {
                    let measure = score.measures[selectedMeasure]
                    Button("Signatures: \(measure.timeSignature.beats)/\(measure.timeSignature.beatType) · \(SignatureEditorView.keyLabel(measure.keyFifths))") {
                        showSignatures = true
                    }.accessibilityIdentifier("reviewSignatures")
                    Button("Measure length: \(ScoreTimingInput.format(score.measures[selectedMeasure].durationQuarters)) quarter notes") {
                        showMeasureLength = true
                    }.accessibilityIdentifier("reviewMeasureLength")
                    ForEach(score.measures[selectedMeasure].events, id: \.id) { event in
                        Button {
                            editing = EventSelection(measure: selectedMeasure, event: event)
                        } label: {
                            HStack {
                                Text(eventTitle(event)).font(.body.monospaced())
                                Spacer()
                                Text("Offset \(ScoreTimingInput.format(event.onsetQuarters)) · voice \(event.voice)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("reviewNote-\(event.id)")
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                change { $0.measures[selectedMeasure].events.removeAll { $0.id == event.id } }
                            }
                        }
                    }
                    HStack {
                        Button("Add note", systemImage: "plus") { add(rest: false) }
                        Spacer()
                        Button("Add rest") { add(rest: true) }
                    }.buttonStyle(.borderless)
                }
                Button("Add measure") {
                    change { value in
                        let last = value.measures.last!
                        let index = value.measures.count
                        value.measures.append(NormalizedMeasure(id: UUID().uuidString, index: index,
                            number: String(index + 1), timeSignature: last.timeSignature, keyFifths: last.keyFifths, events: []))
                    }
                    selectedMeasure = score.measures.count - 1
                }
                Button("Undo last edit", systemImage: "arrow.uturn.backward") {
                    do {
                        try editState.undo(persist: persist)
                        invalidatePreview(); message = nil
                        selectedMeasure = min(selectedMeasure, score.measures.count - 1)
                    } catch { message = "Could not save the unfinished review. \(error.localizedDescription)" }
                }.disabled(history.isEmpty)
                Button("Discard unfinished edits", role: .destructive) { showDiscard = true }
                    .accessibilityIdentifier("reviewDiscard")
            } header: { Text("Correct notes and rhythms") } footer: {
                Text("Offsets and durations use quarter-note units in every time signature. Offset 0 is the start of the measure.")
            }

            Section {
                Button("Update notation and playback", systemImage: "music.note.list") { updatePreview() }
                    .accessibilityIdentifier("reviewPreview")
                    .disabled(!(score.reviewIssues ?? []).isEmpty)
                AlphaTabWebView(controller: player).frame(height: 280)
                Button(player.isPlaying ? "Pause preview" : "Play preview", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
                    player.playPause()
                }.disabled(!previewCurrent || !player.isPlayerReady)
                    .accessibilityIdentifier("reviewPlay")
                if let message { Text(message).foregroundStyle(.red).textSelection(.enabled) }
            } header: { Text("Listen and compare") }

            Section {
                Toggle("I checked the notes and rhythms against the page", isOn: $checked)
                    .accessibilityIdentifier("reviewConfirmed")
                Button("Save and open player") {
                    do {
                        let validated = try ScoreValidator.validate(score)
                        // A score must be renderable before it enters the library.
                        _ = try AlphaTexGenerator.notation(score: validated)
                        try save(MusicXMLWriter.data(for: validated), validated)
                        player.stop(); dismiss()
                    } catch { message = error.localizedDescription }
                }
                .disabled(!checked || !(score.reviewIssues ?? []).isEmpty)
                .accessibilityIdentifier("reviewSave")
            } footer: {
                Text("Edits and undo history are saved on this device as you work. Close this screen to resume later. If a passage cannot fit on your guitar, you can still hear the notation and correct it. Your source image is saved with the score.")
            }
        }
        .accessibilityIdentifier("reviewList")
        .scrollContentBackground(.hidden).background(AmbientBackground())
        .navigationTitle("Review Notes")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { player.stop(); dismiss() } } }
        .onDisappear { player.stop() }
        .confirmationDialog("Discard unfinished edits?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard edits", role: .destructive) {
                do {
                    editState = try discard(); selectedMeasure = 0
                    invalidatePreview(); message = nil
                } catch { message = error.localizedDescription }
            }.accessibilityIdentifier("reviewDiscardConfirm")
        } message: {
            Text("Restore the starting notes and rhythms and clear this review’s undo history. Your photo and saved music remain available.")
        }
        .confirmationDialog("Is this mark absent from your page?", isPresented: $showIssueConfirmation, titleVisibility: .visible) {
            Button("This mark is not on my page", role: .destructive) {
                guard let issue = removingIssue else { return }
                change { $0.reviewIssues?.removeAll { $0.id == issue.id } }
                removingIssue = nil
            }.accessibilityIdentifier("reviewRemoveMarkConfirm")
        } message: {
            Text("Remove only the incorrect recognized mark. The note stays unchanged. You can undo this correction.")
        }
        .sheet(isPresented: $showSource) { SourceImagePreview(data: imageData) }
        .sheet(isPresented: $showMeasureLength) {
            NavigationStack {
                MeasureLengthEditorView(measure: score.measures[selectedMeasure]) { length in
                    change { $0.measures[selectedMeasure].minimumDurationQuarters = length }
                }
            }
        }
        .sheet(isPresented: $showSignatures) {
            NavigationStack {
                SignatureEditorView(measure: score.measures[selectedMeasure]) { time, key, following in
                    try editState.change({ value in
                        value = try value.updatingSignatures(at: selectedMeasure, timeSignature: time,
                                                             keyFifths: key, includeFollowing: following)
                    }, persist: persist)
                    invalidatePreview(); message = nil
                }
            }
        }
        .sheet(item: $editing) { selection in
            NavigationStack {
                NoteEditorView(event: selection.event) { replacement, stack in
                    change { value in
                        guard let index = value.measures[selection.measure].events.firstIndex(where: { $0.id == selection.event.id }) else { return }
                        value.measures[selection.measure].events[index] = replacement
                        if stack, case var .note(note) = replacement {
                            note.id = UUID().uuidString; note.tieStart = false; note.tieStop = false; note.tieFromID = nil
                            value.measures[selection.measure].events.append(.note(note))
                        }
                    }
                }
            }
        }
    }

    private func issueLocation(_ issue: ScoreReviewIssue) -> String {
        guard score.measures.indices.contains(issue.measureIndex),
              let event = score.measures[issue.measureIndex].events.first(where: { $0.id == issue.eventID }) else {
            return "The associated note or rest was deleted. Check this mark on the source page."
        }
        return "\(eventTitle(event)) · offset \(ScoreTimingInput.format(event.onsetQuarters)) · voice \(event.voice)"
    }

    private func eventTitle(_ event: NormalizedEvent) -> String {
        let name: String
        switch event { case let .note(n): name = ScoreValidator.pitchName(n.midi); case .rest: name = "Rest" }
        return "\(name) · \(ScoreTimingInput.format(event.durationQuarters)) \(event.durationQuarters == 1 ? "quarter" : "quarters")"
    }
    private func invalidatePreview() { checked = false; previewCurrent = false; player.stop() }
    private func change(_ action: (inout NormalizedScore) throws -> Void) {
        do {
            try editState.change(action, persist: persist)
            invalidatePreview(); message = nil
        } catch { message = error.localizedDescription }
    }
    private func add(rest: Bool) {
        change { value in
            let m = selectedMeasure; let onset = value.measures[m].events.map { $0.onsetQuarters + $0.durationQuarters }.max() ?? 0
            let id = UUID().uuidString
            value.measures[m].events.append(rest ? .rest(NormalizedRest(id: id, measureIndex: m, onsetQuarters: onset, durationQuarters: 1)) :
                .note(NormalizedNote(id: id, measureIndex: m, onsetQuarters: onset, durationQuarters: 1, midi: 64, pitch: "E4")))
        }
    }
    private func updatePreview() {
        do {
            let checked = try ScoreValidator.validate(score)
            let alphaTex = try AlphaTexGenerator.notation(score: checked)
            player.stop(); player.prepareForNewScore(); player.queue(alphaTex: alphaTex, score: try checked.expandingRepeats())
            previewCurrent = true
            do { _ = try StructuredScorePipeline().run(score: checked); message = nil }
            catch { message = "Notation is available. Tab needs attention: \(error.localizedDescription)" }
        } catch { message = error.localizedDescription; previewCurrent = false }
    }
}

private struct EventSelection: Identifiable {
    let measure: Int
    let event: NormalizedEvent
    var id: String { event.id }
}

private struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let event: NormalizedEvent
    let save: (NormalizedEvent, Bool) -> Void
    @State private var isRest: Bool
    @State private var pitchClass: Int
    @State private var octave: Int
    @State private var onsetText: String
    @State private var duration: Double
    @State private var voice: String
    @State private var tieStart: Bool
    @State private var tieStop: Bool
    @State private var stack = false

    init(event: NormalizedEvent, save: @escaping (NormalizedEvent, Bool) -> Void) {
        self.event = event; self.save = save
        var midi = 64; var rest = true; var starts = false; var stops = false
        if case let .note(n) = event { midi = n.midi; rest = false; starts = n.tieStart; stops = n.tieStop }
        _isRest = State(initialValue: rest); _pitchClass = State(initialValue: midi % 12); _octave = State(initialValue: midi / 12 - 1)
        _onsetText = State(initialValue: ScoreTimingInput.format(event.onsetQuarters)); _duration = State(initialValue: event.durationQuarters)
        _voice = State(initialValue: event.voice); _tieStart = State(initialValue: starts); _tieStop = State(initialValue: stops)
    }
    var body: some View {
        Form {
            Toggle("Rest", isOn: $isRest)
            if !isRest {
                Picker("Pitch / accidental", selection: $pitchClass) {
                    ForEach(0..<12, id: \.self) { i in Text(["C", "C♯ / D♭", "D", "D♯ / E♭", "E", "F", "F♯ / G♭", "G", "G♯ / A♭", "A", "A♯ / B♭", "B"][i]).tag(i) }
                }
                Stepper("Sounding octave: \(octave)", value: $octave, in: -1...9)
                    .accessibilityIdentifier("editOctave")
                Toggle("Tied from previous note", isOn: $tieStop)
                Toggle("Tie to next note", isOn: $tieStart)
                Toggle("Add another note at this onset", isOn: $stack)
            }
            LabeledContent("Onset in quarter notes") {
                TextField("Onset", text: $onsetText).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
            }
            Text("0 is the start of the measure. Use a decimal or fraction: 1/2 is an eighth note; 1/3 is an eighth-note triplet.").font(.caption)
            if onset == nil { Text("Enter an onset from 0 to 128 quarter notes.").foregroundStyle(.red) }
            Picker("Duration", selection: $duration) {
                ForEach(Self.rhythms, id: \.value) { item in Text(item.name).tag(item.value) }
                if !Self.rhythms.contains(where: { abs($0.value - duration) < 1e-8 }) { Text("Original: \(ScoreTimingInput.format(duration)) quarter notes").tag(duration) }
            }
            TextField("Voice", text: $voice)
            Text("Notes with the same onset are stacked. Voices let a bass note sustain while the melody moves.").font(.caption)
        }
        .navigationTitle("Edit Note")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Apply") {
                guard let onset else { return }
                let midi = (octave + 1) * 12 + pitchClass
                let m: Int
                switch event { case let .note(n): m = n.measureIndex; case let .rest(r): m = r.measureIndex }
                let value: NormalizedEvent = isRest ? .rest(NormalizedRest(id: event.id, measureIndex: m, onsetQuarters: onset, durationQuarters: duration, voice: voice)) :
                    .note(NormalizedNote(id: event.id, measureIndex: m, onsetQuarters: onset, durationQuarters: duration,
                        midi: midi, pitch: ScoreValidator.pitchName(midi), tieStart: tieStart, tieStop: tieStop, voice: voice))
                save(value, stack); dismiss()
            }.disabled(onset == nil || voice.isEmpty || (!isRest && (octave + 1) * 12 + pitchClass > 127)) }
        }
    }
    private var onset: Double? { ScoreTimingInput.parse(onsetText) }
    private struct Rhythm { let name: String; let value: Double }
    private static let rhythms = [Rhythm(name: "Whole", value: 4), Rhythm(name: "Dotted half", value: 3), Rhythm(name: "Half", value: 2),
        Rhythm(name: "Dotted quarter", value: 1.5), Rhythm(name: "Quarter", value: 1), Rhythm(name: "Dotted eighth", value: 0.75),
        Rhythm(name: "Eighth", value: 0.5), Rhythm(name: "Sixteenth", value: 0.25), Rhythm(name: "32nd", value: 0.125),
        Rhythm(name: "Quarter triplet", value: 2.0 / 3), Rhythm(name: "Eighth triplet", value: 1.0 / 3), Rhythm(name: "Sixteenth triplet", value: 1.0 / 6)]
}

private struct SignatureEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var beats: Int
    @State private var beatType: Int
    @State private var keyFifths: Int
    @State private var includeFollowing = true
    @State private var error: String?
    let save: (TimeSignature, Int, Bool) throws -> Void

    init(measure: NormalizedMeasure, save: @escaping (TimeSignature, Int, Bool) throws -> Void) {
        _beats = State(initialValue: measure.timeSignature.beats)
        _beatType = State(initialValue: measure.timeSignature.beatType)
        _keyFifths = State(initialValue: measure.keyFifths)
        self.save = save
    }

    static func keyLabel(_ fifths: Int) -> String {
        if fifths == 0 { return "No sharps or flats" }
        return "\(abs(fifths)) \(fifths > 0 ? (fifths == 1 ? "sharp" : "sharps") : (fifths == -1 ? "flat" : "flats"))"
    }

    var body: some View {
        Form {
            Section("Time signature") {
                Stepper("Beats: \(beats)", value: $beats, in: 1...32)
                    .accessibilityIdentifier("reviewTimeBeats")
                Picker("Beat unit", selection: $beatType) {
                    ForEach([1, 2, 4, 8, 16, 32], id: \.self) { Text("1/\($0) note").tag($0) }
                }.accessibilityIdentifier("reviewBeatUnit")
                Text("\(beats)/\(beatType)").accessibilityIdentifier("reviewTimeSignatureValue")
            }
            Section("Key signature") {
                Stepper(Self.keyLabel(keyFifths), value: $keyFifths, in: -7...7)
                    .accessibilityIdentifier("reviewKeyFifths")
            }
            Section {
                Toggle("Continue until the next signature change", isOn: $includeFollowing)
                    .accessibilityIdentifier("reviewSignaturesFollowing")
            } footer: {
                Text("Each signature continues until its next existing change. Turn this off to edit only the selected measure. Existing note pitches, onsets and lengths stay as entered; correct individual notes and rests against the page.")
            }
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("reviewSignatureError") }
        }
        .navigationTitle("Time and Key")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        try save(TimeSignature(beats: beats, beatType: beatType), keyFifths, includeFollowing)
                        dismiss()
                    } catch { self.error = "Could not save the correction. \(error.localizedDescription)" }
                }.accessibilityIdentifier("reviewSignaturesSave")
            }
        }
    }
}

private struct MeasureLengthEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var length: String
    let save: (Double?) -> Void

    init(measure: NormalizedMeasure, save: @escaping (Double?) -> Void) {
        _length = State(initialValue: ScoreTimingInput.format(measure.durationQuarters))
        self.save = save
    }

    private var parsedLength: Double? {
        guard let value = ScoreTimingInput.parse(length, maximum: 160), value > 0 else { return nil }
        return value
    }

    var body: some View {
        Form {
            Section {
                TextField("Length in quarter notes", text: $length)
                    .accessibilityIdentifier("reviewMeasureLengthValue")
            } footer: {
                Text("Preserve silence at the end of this measure. Enter a number or fraction, such as 4 or 3/2. Notes and rests always retain their full duration; shorten them individually if needed.")
            }
            Button("Use note and rest lengths") { save(nil); dismiss() }
                .accessibilityIdentifier("reviewMeasureLengthReset")
        }
        .navigationTitle("Measure Length")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if let value = parsedLength { save(value); dismiss() } }
                    .disabled(parsedLength == nil).accessibilityIdentifier("reviewMeasureLengthSave")
            }
        }
    }
}

enum ScoreTimingInput {
    static func parse(_ text: String, maximum: Double = 128) -> Double? {
        let parts = text.replacingOccurrences(of: ",", with: ".").split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let numerator = Double(parts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
        let denominator = parts.count == 2 ? Double(parts[1].trimmingCharacters(in: .whitespaces)) : 1
        guard let denominator, denominator > 0 else { return nil }
        let value = numerator / denominator
        return value.isFinite && (0...maximum).contains(value) ? value : nil
    }
    static func format(_ value: Double) -> String {
        for denominator in [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64] {
            let numerator = value * Double(denominator)
            if abs(numerator - numerator.rounded()) < 1e-9 {
                return denominator == 1 ? String(Int(numerator.rounded())) : "\(Int(numerator.rounded()))/\(denominator)"
            }
        }
        return String(value)
    }
}
