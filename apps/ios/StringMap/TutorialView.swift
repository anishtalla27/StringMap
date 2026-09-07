import SwiftUI
import FingeringEngine

struct LearnView: View {
    let course: TutorialCourse?
    let progress: TutorialProgress
    let scanEnabled: Bool
    let openScan: () -> Void
    let didImport: (SongDocument) -> Void
    let openLesson: (TutorialLesson) -> Void
    @Binding var freePractice: Bool

    var body: some View {
        VStack(spacing: 0) {
            Picker("Learning activity", selection: $freePractice) {
                Text("Tutorial Mode").tag(false)
                Text("Free Practice").tag(true)
            }.pickerStyle(.segmented).padding(.horizontal, Space.l).padding(.bottom, Space.s)
                .accessibilityIdentifier("learnMode")
            if freePractice {
                ImportScoreView(scanEnabled: scanEnabled, openScan: openScan, didImport: didImport)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        SectionHeading(eyebrow: "Tutorial Mode", title: "Your first notes start here", detail: "\(course?.lessons.count ?? 0) lessons. See the shape, hear the sound, then take your turn. Every lesson is open to you.")
                        Text("\(progress.completedCount) of \(course?.lessons.count ?? 0) lessons completed · At your own pace")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let course {
                            ForEach(course.lessons) { lesson in
                                if [1, 13, 19].contains(lesson.number) {
                                    Text(lesson.section).font(.title2).padding(.top, Space.m)
                                }
                                Button { openLesson(lesson) } label: {
                                    Bezel {
                                        HStack(spacing: Space.m) {
                                            Text(String(format: "%02d", lesson.number))
                                                .font(.title2.monospacedDigit().weight(.medium)).foregroundStyle(Palette.brand)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(lesson.title).font(.headline).foregroundStyle(.primary)
                                                Text(lesson.summary).font(.subheadline).foregroundStyle(.secondary)
                                                Text("\(lesson.number <= 12 ? "3–7" : "5–10") min · \(progress.record(lesson.id).completed ? "Completed" : "Guided practice")")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: progress.record(lesson.id).completed ? "checkmark.circle.fill" : "chevron.right")
                                                .foregroundStyle(Palette.brand)
                                        }.padding(Space.l)
                                    }
                                }.buttonStyle(PressableCard()).accessibilityIdentifier(lesson.id)
                            }
                        } else { ContentUnavailableView("Lessons unavailable", systemImage: "exclamationmark.triangle", description: Text("The bundled course could not be loaded. Free Practice is still available.")) }
                    }.padding(Space.l).frame(maxWidth: Space.readingWidth).frame(maxWidth: .infinity)
                }
            }
        }.background(AmbientBackground()).navigationTitle("Learn")
    }
}

struct TutorialView: View {
    @State private var session: TutorialSession
    @AppStorage("tutorialShowTab") private var showTab = false
    @AppStorage("leftHanded") private var leftHanded = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    let lessonCount: Int
    let nextLesson: (() -> Void)?
    let close: () -> Void

    init(lesson: TutorialLesson, progress: TutorialProgress, lessonCount: Int, nextLesson: (() -> Void)?, close: @escaping () -> Void) {
        _session = State(initialValue: TutorialSession(lesson: lesson, progress: progress, showTab: UserDefaults.standard.bool(forKey: "tutorialShowTab")))
        self.lessonCount = lessonCount
        self.nextLesson = nextLesson; self.close = close
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("LESSON \(session.lesson.number) OF \(lessonCount) · STANDARD TUNING · NO CAPO").eyebrow()
                    if sizeClass == .regular && !typeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: Space.l) {
                            instruction.frame(maxWidth: 310)
                            music.frame(maxWidth: .infinity)
                        }
                    } else { instruction; music }
                    activity
                }.padding(Space.l).frame(maxWidth: 1200).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                stagePicker.padding(.horizontal, Space.l).padding(.vertical, Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surfaceBase)
            }
            .background(AmbientBackground())
            .navigationTitle(session.lesson.title).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.surfaceBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { session.leave(); close() }.accessibilityIdentifier("closeTutorial") }
            }
        }
        .onAppear { session.activate() }
        .onChange(of: showTab) { _, value in session.player.setShowTab(value) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.leave() } }
        .onDisappear { session.leave() }
    }
    private var stagePicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack { stageButtons }
            VStack(alignment: .leading) { stageButtons }
        }
    }
    private var stageButtons: some View {
        ForEach(TutorialStage.allCases, id: \.self) { stage in
            Button { session.changeStage(stage) } label: {
                Text(stage.title).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Space.m).padding(.vertical, 12)
                    .foregroundStyle(session.stage == stage ? Color.white : Palette.brand)
                    .background(session.stage == stage ? Palette.brand : Palette.surfaceRaised, in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("tutorial-stage-\(stage.rawValue)")
                .accessibilityAddTraits(session.stage == stage ? .isSelected : [])
        }
    }
    private var instruction: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(session.stage.title).font(.title2.weight(.semibold))
            Text(instructionText).font(.body).fixedSize(horizontal: false, vertical: true)
            if session.stage == .see {
                Text(session.lesson.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let hint = session.explorationHint { Text(hint).font(.callout).foregroundStyle(Palette.brand) }
            if session.stage != .recap {
                Button("Continue", systemImage: "arrow.right") {
                    let stages = TutorialStage.allCases
                    if let index = stages.firstIndex(of: session.stage), index + 1 < stages.count { session.changeStage(stages[index + 1]) }
                }.buttonStyle(.bordered).tint(Palette.brand)
            }
        }
    }
    private var instructionText: String {
        switch session.stage {
        case .see: session.lesson.see
        case .hear: "Listen to the example. Follow the lit note on the staff and the matching position on the board. Slow the BPM whenever you want. Use Hear this step to audition the current note, chord, or connected group."
        case .practice: session.lesson.practice
        case .recap: session.lesson.recap
        }
    }
    private var music: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if session.lesson.phrases.count > 1 {
                Picker("Example", selection: Binding(get: { session.phraseIndex }, set: { session.choosePhrase($0) })) {
                    ForEach(session.lesson.phrases.indices, id: \.self) { index in Text(session.lesson.phrases[index].name).tag(index) }
                }.pickerStyle(.segmented).accessibilityIdentifier("tutorialPhrase")
            }
            FretboardView(tuning: .standard, capo: 0, maxFret: session.lesson.maxFret ?? 5, active: session.activeEvents.compactMap(\.position).first,
                sounding: session.activeEvents.compactMap(\.position), upcoming: session.upcoming, leftHanded: leftHanded, isExpanded: true,
                teaching: .init(fingers: session.fingers, mutedStrings: session.mutedStrings, maxFret: session.lesson.maxFret ?? 5, rootPitchClass: session.lesson.rootPitchClass, barre: session.phrase.barre,
                    select: { position in
                        if session.stage == .practice { session.answer(position) } else { session.explore(position) }
                    }))
                .frame(height: typeSize.isAccessibilitySize ? 330 : 270)
            Text(noteDescription).font(.callout.weight(.medium)).accessibilityIdentifier("tutorialNote")
            if let cue = session.currentAttack?.cue {
                Label(cue, systemImage: "hand.draw").font(.headline).accessibilityIdentifier("tutorialHandCue")
            }
            if let position = session.currentAttack?.positionLabel {
                Text(position).font(.subheadline).accessibilityIdentifier("tutorialPositionLabel")
            }
            if session.lesson.rootPitchClass != nil { Text("Gold rings = A roots").font(.caption) }
            if session.lesson.number >= 22 { Text("Synthesized technique reference · Practice the movement on your guitar").font(.caption).foregroundStyle(.secondary) }
            if session.lesson.number == 15 { Text("BPM counts quarter notes · 60 BPM = 40 dotted-quarter pulses/min").font(.caption) }
            Text("Marker number = finger · ○ = open · × = do not play · Fret numbers below")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Toggle("Show tab", isOn: $showTab).accessibilityIdentifier("tutorialShowTab")
                Toggle("Left-handed", isOn: $leftHanded).accessibilityIdentifier("tutorialLeftHanded")
            }.font(.subheadline)
            if let error = session.error { Text(error).foregroundStyle(Palette.brand) }
            AlphaTabWebView(controller: session.player)
                .frame(height: typeSize.isAccessibilitySize ? 420 : (showTab ? 380 : 280))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("tutorialNotation")
            controls
        }
    }
    private var noteDescription: String {
        let notes = session.activeEvents.filter { $0.midi != nil }
        if notes.isEmpty { return "Rest · Keep counting" }
        return notes.map { "\(tutorialPitchName($0.midi!)) · String \($0.string) · \($0.fret == 0 ? "Open" : "Fret \($0.fret), finger \($0.finger)")" }.joined(separator: "\n")
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(session.player.playbackStatus).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("tutorialStatus")
            ViewThatFits(in: .horizontal) {
                HStack { transport }
                VStack(alignment: .leading) { transport }
            }
            Slider(value: Binding(get: { session.player.cursorMilliseconds }, set: { session.seek($0) }), in: 0...max(1, session.totalQuarters * 1000))
                .accessibilityLabel("Lesson position").disabled(!session.player.isPlayerReady)
            Stepper("\(Int((60 * session.player.playbackSpeed).rounded())) BPM", value: Binding(get: { Int((60 * session.player.playbackSpeed).rounded()) }, set: { session.stop(); session.player.setPlaybackSpeed(Double($0)/60); session.save() }), in: 15...120)
                .accessibilityIdentifier("tutorialBPM")
            Toggle("Loop this example", isOn: Binding(get: { session.player.isLooping }, set: { enabled in
                session.stop()
                if enabled { session.player.setLoop(startTick: 0, endTick: Int(session.totalQuarters * 960)) }
                else { session.player.clearLoop() }
            })).accessibilityIdentifier("tutorialLoop")
        }
    }
    private var transport: some View {
        Group {
            Button(session.player.isPlaying ? "Pause" : "Play", systemImage: session.player.isPlaying ? "pause.fill" : "play.fill") { session.playPause() }
                .buttonStyle(.borderedProminent).tint(Palette.brand).accessibilityIdentifier("tutorialPlay")
            Button("Restart", systemImage: "backward.end") { session.restart() }.accessibilityIdentifier("tutorialRestart")
            Button("Previous", systemImage: "chevron.left") { session.step(-1) }.accessibilityIdentifier("tutorialPrevious")
            Button("Next", systemImage: "chevron.right") { session.step(1) }.accessibilityIdentifier("tutorialNext")
            Button("Hear this step", systemImage: "speaker.wave.2") { session.hearCurrent() }.accessibilityIdentifier("tutorialAudition")
        }.disabled(!session.player.isPlayerReady).buttonStyle(.bordered)
    }
    @ViewBuilder private var activity: some View {
        if session.stage == .practice {
            Bezel {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Find this note").font(.title3.bold())
                    Text("Tap \(tutorialPitchName(session.lesson.quizMIDI)) on string \(session.lesson.quizString) on the fretboard. You can also choose its fret below.")
                    HStack {
                        ForEach(session.lesson.number <= 12 ? Array(0...3) : session.lesson.fretChoices, id: \.self) { fret in
                            Button(fret == 0 ? "Open" : "Fret \(fret)") {
                                session.answer(GuitarPosition(string: session.lesson.quizString, fret: fret, midi: GuitarTuning.standard.openMIDIPitches[session.lesson.quizString - 1] + fret))
                            }.buttonStyle(.bordered).accessibilityIdentifier("tutorial-answer-\(fret)")
                        }
                    }
                    if let question = session.lesson.question {
                        Text(question.question).font(.headline)
                        ForEach(question.answers.indices, id: \.self) { index in
                            Button(question.answers[index]) { session.answerKnowledge(index) }
                                .buttonStyle(.bordered).accessibilityIdentifier("tutorial-knowledge-\(index)")
                        }
                    }
                    if let feedback = session.quizFeedback {
                        Label(feedback, systemImage: session.quizMatched ? "checkmark.circle" : "lightbulb")
                            .accessibilityIdentifier("tutorialFeedback")
                    }
                    #if DEBUG
                    if UserDefaults.standard.bool(forKey: "tutorialListeningPreview"), session.activeEvents.filter({ $0.midi != nil }).count == 1 {
                        Button("Listen to me · Internal") {
                            let midi = session.activeEvents.compactMap(\.midi).first!
                            session.stop()
                            session.listener.start(target: midi)
                        }.buttonStyle(.bordered)
                        Text(session.listener.status).font(.callout)
                        Button("Continue without microphone") { session.listener.stop() }
                    }
                    #endif
                }.padding(Space.l)
            }
        } else if session.stage == .recap {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Completion records that you practiced, not a test of mastery.").font(.footnote).foregroundStyle(.secondary)
                Button("Practice again") { session.restart(); session.changeStage(.practice) }.buttonStyle(.bordered)
                Button(session.completed ? "Completed" : "Mark complete", systemImage: "checkmark.circle") { session.save(completed: true) }.buttonStyle(.borderedProminent).tint(Palette.brand).accessibilityIdentifier("tutorialComplete")
                if let nextLesson { Button("Next lesson", systemImage: "arrow.right") { session.leave(); nextLesson() }.buttonStyle(.bordered) }
            }
        }
    }
}
