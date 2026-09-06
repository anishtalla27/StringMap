> **Current release scope:** bundled original single-note exercises. `Resources/Exercises/catalog.json` records the authored sounding pitches and rhythms, and `DemoScore.all` loads its 18 entries. MusicXML carries explicit guitar octave transposition into the existing NormalizedScore pipeline. The release excludes camera/Photos permissions, a recognition URL, and App Attest entitlements. Scanner UI and networking compile only under DEBUG. The playback bridge normalizes alphaTab's speed-adjusted clock before Swift maps the current note to the fretboard.

# Structured-score architecture

## Boundaries

```text
Input adapter               Stable local core             Output adapter
─────────────               ─────────────────             ──────────────
MusicXML parser ───────▶ NormalizedScore ───────▶ alphaTex generator
photo + OMR API adapter     │        ▲                    │
future MIDI adapter         ▼        │                    ▼
                     FingeringNote[] │                 alphaTab
                            │        │            render + synth + cursor
                            ▼        │
                    candidate layers │
                            │        │
                            ▼        │
                      DP optimizer ──┘
```

`NormalizedScore` is the stable ingestion seam. Current photo OMR returns MusicXML through the existing importer; future direct/PDF adapters must return stable measure/note IDs plus confidence and provenance metadata. No importer reaches into candidate generation or alphaTab. The deterministic optimizer remains local so tuning, capo, profile, transposition, and manual overrides update immediately offline.

## Major decisions

### Native Swift product with a narrow alphaTab host

The shipping implementation is a local Swift package with independent `FingeringEngine` and `ScorePipeline` products. SwiftUI owns tab navigation, SwiftData library persistence, importing, instrument settings, the native fretboard, arrangement/profile selection, practice state, transport, manual locks, and the explanation trace. `WKWebView` is restricted to alphaTab engraving, cursor synchronization, and synthesis. The TypeScript packages remain behavioral references rather than runtime dependencies.

alphaTab assets are bundled in the application. A static server bound only to `127.0.0.1` exposes those files to the private web view because WebKit workers cannot import sibling `file://` resources reliably. This creates no external connection: the server has an explicit resource allowlist, accepts no writes, and ends with the view. alphaTex is passed through `callAsyncJavaScript` arguments rather than interpolated into script source.

### A deliberately bounded normalized score

The model preserves stable IDs, title/composer, measures, time/key metadata, events, quarter-note durations, MIDI/display pitch, rests, and ties. It still does not mirror all of MusicXML. It additionally preserves simultaneous notes, independent voices, stable tie predecessors, and simple repeats. Supported rhythms are binary/dotted values and 3:2 triplets. Other notation is rejected explicitly before a successful conversion. The writer emits precise canonical MusicXML for correction and round trips.

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

## OMR service and correction

The app prepares one page with cropping, 90-degree rotation and perspective correction, strips image metadata, and uploads only after consent. `OMRClient` uses owned idempotent jobs, retries transient failures, resumes polling and deletes accepted results. A protected atomic local draft preserves the image, job identity and accepted XML across process death. The user compares the source with editable note/rest events, auditions corrections and explicitly confirms review. SwiftData saves corrected XML, source image and practice settings. A real SQLite migration test covers older library records.

`services/omr/production.py` is the production candidate. It has App Attest-backed anonymous sessions, bounded queues/uploads/concurrency, ownership checks, rate limits, process-group cancellation, one-hour result expiry and cleanup on terminal states and restart. The Docker/Railway configuration requires one process and a private volume. The development bypass is restricted to loopback clients; public hosting and real Apple attestation remain unverified. The engine is pinned separately from the Swift pipeline. No Python or recognition model ships in the app.

Chord optimization uses a layer for every new onset and includes all still-sounding notes. Each complete shape assigns notes to distinct strings with conservative reach and finger-count constraints. Edges retain held strings and tied identities. A bounded forward and reverse search gives deterministic best complete routes and alternate-position explanations. Monophonic input retains the prior optimizer. Chord movement metrics use voice transitions between onsets; simultaneous notes do not count as sequential movement.

When tab is unplayable, the app retains the normalized score and a notation-only alphaTex path. The same actual alphaTab parser and MIDI generator are tested for exact sounding pitch, onset and sustain duration. Source-note IDs are mapped back onto rendered notes, including split tied durations and independent voices.

## Remaining gates

Recognition is currently failing clean-page accuracy. A synthetic 102-image batch is underway; it is not a substitute for real camera photographs, genuine handwriting, independently checked references and in-app correction comparisons. Handwriting remains a release blocker, consistent with the pinned engine's own caution.

Piano/multipart scores, chord-name interpretation, complex repeats, unsupported articulations/techniques, tempo changes, PDF/multiple pages, `.mxl` and MIDI are excluded. Complete manual/device testing, Linux resource measurements, real App Attest validation, signing, a signed Release archive and seven days of TestFlight remain outstanding. See [release evidence](release/evidence.md).
