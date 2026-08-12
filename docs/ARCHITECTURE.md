# Structured-score architecture

## Boundaries

```text
Input adapter               Stable local core             Output adapter
─────────────               ─────────────────             ──────────────
MusicXML parser ───────▶ NormalizedScore ───────▶ alphaTex generator
future OMR API adapter      │        ▲                    │
future MIDI adapter         ▼        │                    ▼
                     FingeringNote[] │                 alphaTab
                            │        │            render + synth + cursor
                            ▼        │
                    candidate layers │
                            │        │
                            ▼        │
                      DP optimizer ──┘
```

`NormalizedScore` is the seam for future image/PDF OMR. An OMR client must return stable measure/note IDs plus confidence and provenance metadata; it must not reach into candidate generation or alphaTab. The deterministic optimizer remains local so tuning, capo, profile, transposition, and manual overrides update immediately offline.

## Major decisions

### Native Swift product with a narrow alphaTab host

The shipping implementation is a local Swift package with independent `FingeringEngine` and `ScorePipeline` products. SwiftUI owns tab navigation, SwiftData library persistence, importing, instrument settings, the native fretboard, arrangement/profile selection, practice state, transport, manual locks, and the explanation trace. `WKWebView` is restricted to alphaTab engraving, cursor synchronization, and synthesis. The TypeScript packages remain behavioral references rather than runtime dependencies.

alphaTab assets are bundled in the application. A static server bound only to `127.0.0.1` exposes those files to the private web view because WebKit workers cannot import sibling `file://` resources reliably. This creates no external connection: the server has an explicit resource allowlist, accepts no writes, and ends with the view. alphaTex is passed through `callAsyncJavaScript` arguments rather than interpolated into script source.

### A deliberately bounded normalized score

The model preserves stable IDs, title/composer, measures, time/key metadata, events, quarter-note durations, MIDI/display pitch, rests, and ties. It still does not mirror all of MusicXML. Unsupported polyphony and rhythm are rejected at the adapter boundary, preventing plausible-looking but incorrect tablature. This model must expand before OMR or chord support is declared reliable.

### Exact layered-graph optimization

Greedy choices are locally attractive and globally poor when an upcoming run favors another string. With at most six candidates per note, exact dynamic programming is simpler and fast enough. Each table cell stores total cost and a predecessor; backtracking yields the minimum path. A reverse dynamic-programming pass computes the cheapest suffix from each candidate. Prefix plus suffix therefore gives the best complete score route through every candidate—not merely a local heuristic—so the debug trace can quantify why an alternative lost. Complexity remains `O(notes × candidates²)`.

### Real tuning and capo geometry

Candidate generation treats `maxFret` as the instrument's last physical fret. For a sounding pitch `p`, open string pitch `s`, and capo `c`, a candidate exists when `physicalFret = p - s` lies in `c...maxFret`; displayed tab fret is `physicalFret - c`. Alternate tuning, capo, and transposition therefore change actual candidates rather than labels.

### Explicit node and edge costs

Fret height, capo-relative open-string preference, and initial hand-position distance describe a position itself. Physical fret movement, hand-position shift, string change, string skipping, stretch, repeated-note consistency, and awkward jumps describe a transition. The split makes profile weights legible and lets every chosen step expose a reconciled breakdown.

Profiles are weight sets, not UI labels:

- Beginner strongly favors low/open positions and small transitions.
- Balanced provides a general-purpose tradeoff.
- Stay in Position heavily penalizes region changes.
- Minimum Movement emphasizes physical left-hand travel.
- Performance permits advanced positioning and lightly discourages uncontrolled open strings.

### Locked constraints and alternatives

A locked note reduces its candidate layer to the exact valid `GuitarPosition` selected by the user. Invalid locks fail explicitly after a tuning/capo/range change. The surrounding passage is solved normally, so reoptimization cannot move the lock. The app caches and compares all five independently optimized, measurable alternatives rather than inventing opaque ratings. Different profiles may legitimately agree when one route is globally dominant; the UI exposes weights and physical metrics so that agreement can be inspected rather than hidden.

### alphaTex as the alphaTab handoff

The optimizer controls the chosen string and fret. Generated alphaTex expresses those exact positions, selected tuning, capo, tempo, measures, rests, durations, and ties while delegating engraving, MIDI synthesis, playback cursor synchronization, tempo scaling, metronome, count-in, looping, and transport to alphaTab. StringMap does not implement notation rendering or audio synthesis.

### Local product state

SwiftData persists source MusicXML, source metadata, instrument/profile settings, locked positions, arrangement summary, speed, loop range, metronome/count-in choices, and last practice time. `AppModel` owns transient pipeline and playback state. Dynamic work runs outside the main actor and is cancelled when a newer profile or instrument request supersedes it. Profile changes reuse cached arrangements for the current instrument and lock configuration; instrument or lock changes invalidate and rebuild the cache.

## OMR and chord gate

Camera/Photos/PDF capture is not yet a primary journey because there is no compliant recognition service or correction model. If homr or Audiveris is used, it belongs behind a versioned upload/status/result API in a separately licensed deployment; both inspected engines are AGPL-3.0. The iOS app should retain page order, upload only with explicit user action, show recognition confidence, and require review before arrangement. No AGPL implementation is copied into the app.

Chord support similarly waits for a simultaneous-note candidate layer with unique string assignment, fret-span/finger-count constraints, and transition search. MoChord's MIT-licensed shape/transition distinction is a useful reference, but the app will not silently flatten chords into melodies.

## Next structured-score steps

1. Tuplet and arbitrary-duration representation.
2. Tempo changes, articulations, repeats, chord symbols, techniques, and more tie cases.
3. Multi-voice normalization with a clear melody-selection policy.
4. Chord candidate generation and multi-note hand-state optimization.
5. `.mxl` and reliable MIDI adapters.
6. Corpus tests against exported MusicXML from MuseScore, Finale, and Dorico.
7. Versioned OMR API, confidence-bearing normalization, and minimal correction UI.
