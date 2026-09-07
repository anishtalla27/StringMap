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
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  test CODE_SIGNING_ALLOWED=NO
```

The UI tests exercise native tab navigation, profile changes, the cost explanation, a practice tempo change, alphaTab player readiness, synchronized cursor advance, stop, the docked transport remaining reachable from every tab, and both sides of the recognition-preview gate. Unit coverage opens every bundled study, verifies every generated string/fret pair against the intended sounding MIDI pitch, and asserts that both score themes keep a readable paper-to-ink contrast.

### Driving a specific screen

Debug builds accept launch environment variables so a screen can be opened
directly — used for verification and for generating store screenshots. They are
compiled out of release builds.

```bash
SIMCTL_CHILD_STRINGMAP_SCREEN=trace \
SIMCTL_CHILD_STRINGMAP_LOAD_DEMO=profile-contrast \
SIMCTL_CHILD_STRINGMAP_SEED_LIBRARY=1 \
  xcrun simctl launch booted com.anishtalla.StringMap
```

`STRINGMAP_SCREEN` accepts `home`, `library`, `play`, `import`, `settings`,
`trace`, `practice`, `instrument`, `arrangements`, `fretboard`, `override`, and
`scan`.

## Bundled alphaTab resources

The checked-in resources make the app offline-capable. After `npm install` at the repository root, refresh them with:

```bash
./scripts/sync-alphatab-assets.sh
```

The web view loads only these allowlisted resources through an ephemeral HTTP listener bound to `127.0.0.1`. This renderer makes no external connection. Photo recognition uses a separate HTTPS API; source images and corrected scores are saved by the native app.

## Module boundaries

- `FingeringEngine` owns tuning, candidate generation, profiles, exact dynamic programming, tie constraints, and cost explanations.
- `ScorePipeline` owns strict MusicXML normalization, orchestration, and alphaTex output.
- `ScoreImporter` is the stable ingestion seam. Photo OMR returns MusicXML through it, and future MIDI/direct importers must produce `NormalizedScore`; none bypass optimization or rendering boundaries.
- The app target owns SwiftUI, SwiftData song persistence, product state, and the alphaTab bridge.

### Interface layer

| File | Responsibility |
| --- | --- |
| `DesignSystem.swift` | Palette, score finishes, spacing and radius scales, motion, nested `Bezel`/`Panel`/`InstrumentPlate` surfaces, `MetaLine`, `NumberColumn`, section headings |
| `ContentView.swift` | Tab shell, docked transport accessory, `RouteGlyph` score artwork, debug-only launch routing |
| `FretboardView.swift` | The neck as a mounted rosewood faceplate: blended logarithmic fret spacing, graded string gauges, nickel wire, bone nut, capo, and the glowing route between the current and next position |
| `WorkspaceView.swift` | The player, plus the accessibility-size layout switch |
| `WorkspaceSheets.swift` | Practice, Instrument, Arrangements, and fingering-override sheets |
| `FingeringTraceView.swift` | The cost explanation, including the four-bucket cost bar |
| `HomeView.swift`, `LibraryView.swift`, `ImportScoreView.swift`, `SettingsView.swift` | Remaining tabs |

Light and dark are authored as equal appearances; every interface colour in `Palette` declares both, while the instrument's own materials are fixed across appearances because the neck is the same piece of wood in either room. One accent (fiesta red) drives the interface; lake blue and surf green appear only inside data. The alphaTab page is themed through `ScoreTheme` so the notation matches, and its engraving scale follows the panel width so iPad does not render a tiny score in a large panel.

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
- Camera/Photos capture for one guitar page, crop/rotation/perspective preparation, explicit upload, resumable cancellable recognition, editable notes/rests/chords/voices, undo, audition, source-image persistence and the same tab/player workflow

## Run photo recognition

The recognition engine stays in a separate service. Use the pinned setup and production candidate described in [the service README](../../services/omr/README.md). The old `server.py` is retained only for adapter regression tests.

Debug builds enable scanning and default to `http://127.0.0.1:8765`; Settings exposes development configuration only under `#if DEBUG`. Release builds use `OMR_SERVICE_URL` from their build settings and production App Attest. They fail configuration validation until the hosted HTTPS endpoint and signing team are provided. Customers do not configure a server.

Recognition accuracy is currently failing. Printed-page support must meet the benchmark before release; handwriting is unverified. The editor can correct pitch, accidental, octave, onset, duration, rest/note state, voices, chord membership, ties, time/key signatures and measure length. Bounded unsupported note annotations are retained as unresolved review issues: a false recognized mark can be explicitly removed and undone, while actual unsupported marks block export and playback. It retains source identities, supports insertion/deletion and undo, and requires review before saving corrected MusicXML and the image. Unplayable passages retain notation and audition rather than dropping notes.

## Manual end-to-end check

1. Import **Open or Shift?** and confirm it appears in Library.
2. In Play, switch Beginner, Balanced, and Stay in Position; open Arrangements and compare measured movement, shifts, string changes, and fret range.
3. Open Why?, expand a candidate comparison, and confirm rejected positions have a route-cost reason.
4. Play, set 75%, loop the current measure, jump back, then stop.
5. Change tuning/capo/transposition, select a valid alternate fingering, lock it, and change profile; confirm the lock remains.
6. Background and relaunch the app, open the library song, and confirm profile, instrument, lock, speed, loop, and practice position resume.
7. Import **Low D Resonance** and confirm it opens in Drop D. Switch to Standard and confirm the app reports the low note as unplayable rather than generating incorrect tab.
8. Switch the system appearance and confirm both the app and the notation follow it.
9. Raise Dynamic Type to an accessibility size and confirm the player stacks and scrolls rather than truncating.

Physical-device audio interruption, silent-mode, headphone, Files-provider, and VoiceOver checks remain in the repository release checklist.

MusicXML file import supports `.xml`, `.musicxml`, and compressed `.mxl` scores. Container input is limited to 20 MB and extracted score XML to 10 MB; ancillary files are not extracted. PDF/multi-page OMR, MIDI and piano scores remain excluded. Handwriting cannot be advertised until recognition and practical correction are demonstrated. See [release evidence](../../docs/release/evidence.md) for test results and unresolved gates.
