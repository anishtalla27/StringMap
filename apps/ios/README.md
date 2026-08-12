# StringMap for iOS

This directory contains the native SwiftUI application. `project.yml` is the reproducible source for the checked-in Xcode project; regenerate the project after adding targets, files, or build settings.

## Prerequisites

- Xcode 26 with an iOS 26 simulator runtime
- XcodeGen
- Node.js 20 or newer when refreshing alphaTab resources

## Build and test

```bash
cd Packages/StringMapCore
swift test

cd ../..
xcodegen generate
xcodebuild \
  -project StringMap.xcodeproj \
  -scheme StringMap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test CODE_SIGNING_ALLOWED=NO
```

The UI test exercises native tab navigation, profile changes, the cost explanation, a practice tempo change, alphaTab player readiness, synchronized cursor advance, and stop. Unit coverage also opens every bundled study and verifies every generated string/fret pair against the intended sounding MIDI pitch.

## Bundled alphaTab resources

The checked-in resources make the app offline-capable. After `npm install` at the repository root, refresh them with:

```bash
./scripts/sync-alphatab-assets.sh
```

The web view loads only these allowlisted resources through an ephemeral HTTP listener bound to `127.0.0.1`. No remote URL, analytics, persistence, or backend is used.

## Module boundaries

- `FingeringEngine` owns tuning, candidate generation, profiles, exact dynamic programming, tie constraints, and cost explanations.
- `ScorePipeline` owns strict MusicXML normalization, orchestration, and alphaTex output.
- `ScoreImporter` is the future OMR/MIDI ingestion seam. Future importers must produce `NormalizedScore`; they do not bypass optimization or rendering boundaries.
- The app target owns SwiftUI, SwiftData song persistence, product state, and the alphaTab bridge.

## Implemented native flows

- Home, Library, Play, Import, and Settings tabs
- persistent local MusicXML library and practice resume
- five genuine fingering profiles and cached measurable arrangement comparisons
- standard and alternate/custom tuning, capo, fret count, capo suggestion, and transposition
- native synchronized and expandable fretboard, physical-fret labels, left-handed layout, and note-level manual fingering locks
- tempo presets/reset, measure navigation, five-second jump-back, current-measure and A/B loops, count-in, metronome, seek, and stop
- per-song persistence for speed, loop, timing options, profile, instrument, manual locks, and practice position
- candidate-level optimizer diagnostics that compare the best complete route through every position
- four library-ready original studies plus the immediate launch sample

## Manual end-to-end check

1. Import **Open or Shift?** and confirm it appears in Library.
2. In Play, switch Beginner, Balanced, and Stay in Position; open Arrangements and compare measured movement, shifts, string changes, and fret range.
3. Open Why?, expand a candidate comparison, and confirm rejected positions have a route-cost reason.
4. Play, set 75%, loop the current measure, jump back, then stop.
5. Change tuning/capo/transposition, select a valid alternate fingering, lock it, and change profile; confirm the lock remains.
6. Background and relaunch the app, open the library song, and confirm profile, instrument, lock, speed, loop, and practice position resume.
7. Import **Low D Resonance** and confirm it opens in Drop D. Switch to Standard and confirm the app reports the low note as unplayable rather than generating incorrect tab.

Physical-device audio interruption, silent-mode, headphone, Files-provider, and full accessibility checks remain in the repository release checklist.

Camera/Photos/PDF OMR, `.mxl`, MIDI, chords, and polyphony are intentionally not exposed as working features yet. See the repository architecture document for the implementation and licensing gate.
