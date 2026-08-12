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

The UI test exercises native tab navigation, profile changes, the cost explanation, a practice tempo change, alphaTab player readiness, synchronized cursor advance, and stop.

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
- five genuine fingering profiles plus three arrangement comparisons
- standard and alternate/custom tuning, capo, fret count, capo suggestion, and transposition
- native synchronized fretboard and note-level manual fingering locks
- tempo presets, measure A/B loop, count-in, metronome, seek, and stop

Camera/Photos/PDF OMR, `.mxl`, MIDI, chords, and polyphony are intentionally not exposed as working features yet. See the repository architecture document for the implementation and licensing gate.
