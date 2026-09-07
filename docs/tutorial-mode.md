# Tutorial Mode

Learn contains Tutorial Mode and Free Practice. The course has 12 original lessons and 16 score examples; the existing 18 exercises and libraries are retained. Release finalization has since resumed at the user’s request; its current signing, policy, simulator and physical-device status is in [finalization.md](release/finalization.md).

## Course and session

The editable source is `scripts/build-tutorial-course.py`. It generates a versioned course manifest and MusicXML resources in `apps/ios/StringMap/Resources/Tutorial`. Authored events carry stable IDs, sounding MIDI, rhythm, exact string/fret, and finger numbers. TutorialPhrase feeds the existing StructuredScorePipeline with a lock for every note. The teaching layer adds finger numbers and open/muted marks without changing free-practice fingering optimization.

A TutorialSession owns its own AlphaTabController. ContentView pauses free practice and replaces the tab view with the lesson screen while preserving AppModel. Keeping an obscured iPad tab bar alive behind a modal caused an iOS layout loop during appearance/rotation changes, so Tutorial Mode uses a dedicated root screen. Closing restores the previous navigation destination. Tutorials never open or overwrite a SongDocument. Exiting stops playback/listening and preserves the free-practice score and settings. Backgrounding and audio interruptions pause playback. The stage selector stays visible while scrolling. Active-lesson writes happen on appearance, not during view construction, and closing a previous lesson cannot overwrite the next lesson's resume destination. TutorialProgress persists versioned records in UserDefaults under tutorialProgress.v1; missing or undecodable progress starts a fresh course without modifying song records. Show-tab and left-handed preferences are local.

All lesson scores use 60 quarter-note BPM as their canonical score clock; users choose 15–120 BPM. Display changes alter alphaTab's stave profile and re-render without changing playback state. Guitar notation is written an octave above sounding pitch. Reference tones are not an automatic tuner. Chord support here is limited to the authored Em, Am, and D examples.

## Internal listening experiment

TutorialPitchListener and TutorialYIN compile only in DEBUG. Set the Debug launch argument `-tutorialListeningPreview YES` to expose the internal button during a single-note Try it activity. The Release Info.plist contains no microphone purpose string and Release has no listening button or detector. Guided practice needs no permission, server, account, or audio recognition.

The native detector uses normalized YIN difference, a signal-level gate, pitch confidence, and a 250 ms stable match within 35 cents. Matching includes octave. It waits for silence before a target and latches a successful result until silence. Demonstration audio is paused and given 650 ms to decay; microphone audio is analyzed in bounded buffers off the render thread and is never stored or sent. Route changes, interruptions, exit, and backgrounding stop capture. The first implementation checks one requested note at a time, not rhythm, chord correctness, or which string/finger produced a pitch.

Synthetic harmonic fixtures cover E2–G4, stronger upper harmonics, wrong octaves, repeated notes, silence, and deterministic noise. These are not recordings of users or proof of device accuracy. Listening remains internal until independent real-guitar trials on physical iPhone/iPad meet at least 95% correct acceptance, less than 1% false acceptance, and median response below 700 ms. Do not advertise listening before that evidence exists.

## Reproducible verification

- Run the StringMapTests target: TutorialTests compares all 16 phrases with separately written pitch references, validates every duration/rest/string/fret and all six speeds, checks session isolation, progress, quiz feedback, finger labels, and DSP fixtures. It exports native score/alphaTex evidence to the test app's Library/Caches/TutorialEvidence.
- Copy that directory to artifacts/tutorial-verification, then run `node scripts/verify-tutorial-playback.mjs`. It checks the actual alphaTab MIDI generator, source IDs, PCM synthesis, and both notation modes for every phrase.
- `node scripts/test-tutorial-bridge.mjs` checks display-switch transport invariants; `node scripts/test-playback-clock.mjs` retains the 3,108 checks for the original 18 exercises.
- TutorialUITests runs the complete course on iPhone/iPad, retaining screenshots and exercising playback, loops, seeking, tab, note stepping, quizzes, completion, and return navigation. Evidence and any remaining device-only checks are recorded in artifacts/tutorial-evidence.json.

The 16 full notation/tab previews were visually reviewed against the original pitch/rhythm references. Speaker/headphone/Bluetooth audibility, microphone accuracy, and physical accessibility qualification remain device work. Updated legal/support pages were published and verified during release finalization; see [policy-deployment.json](release/policy-deployment.json).
