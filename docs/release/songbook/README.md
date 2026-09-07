# Songbook candidate evidence

Implementation and automated music/playback verification are complete. Distribution signing, Apple validation and export passed on September 7. TestFlight/App Store completion remains. The user confirmed physical playback, output-route, interruption and VoiceOver testing passed on September 7. No new binary has been uploaded or submitted.

## Implemented

- 20 songs, separate Melody/Chords arrangements, 40 offline MusicXML resources. The existing 24 tutorials and 18 exercises remain intact.
- Library Songbook/My Library sections and Home Play a classic entry; historical version/source descriptions and accompaniment instructions.
- Shared notation/tab, audio clock, complete chord-tone fretboard highlighting, authored positions/fingers, transposed chord names, and original-configuration recovery.
- Per-arrangement stable local identity, independent position/tempo/loop/count-in/metronome/tab settings, deduplication and corrected-bundle refresh without losing practice state.
- Chord measure-stepping controls. A discovered floating-point boundary bug was fixed in the shared quarter-position calculation: exact seeks no longer highlight the preceding chord or get stuck on the same measure.
- Reopening waits for the pending seek before accepting an old zero-position event, preventing saved positions from being overwritten during score loading. Restart/seek scrolls after alphaTab updates cursor bounds. The expand control sits outside the Songbook fretboard so left-handed open-string markers remain visible.
- Orange Frame icon preserved. Scanning and microphone grading remain outside the public release.

## Source and harmony evidence

`source-review.json` contains independently entered historical-pitch and rhythm references for all 20 melodies. `harmony-review.json` records the separately reviewed original guitar harmony and exact voiced pitches, strings, frets and fingers. `rights.md` explains the historical composition basis and international assessment; it makes no blanket worldwide-clearance claim.

Run `python3 scripts/verify-songbook-sources.py` and `python3 scripts/verify-songbook-harmony.py`. Release builds run both checks and reject a mismatching/incomplete catalog.

Two shortlist entries were replaced in the requested order: The Water Is Wide → Flow Gently, Sweet Afton; When the Saints Go Marching In → Drink to Me Only with Thine Eyes. Exact historical variants and classical-theme boundaries are disclosed.

## Verification status

- 77 Swift core tests passed.
- 49 native iOS tests passed on both simulators, including all 40 imports, alternate configurations, exact measure boundaries and the restored-seek regression.
- All 40 final arrangements passed alphaTab MIDI/source-identity, notation/tab rendering, and SoundFont PCM checks in 196 distinct tempo trials: 30, 60, 90, 120 and authored BPM. Hashes bind this result to the bundled XML.
- All 40 arrangements passed strict iPhone and iPad clock/seek/restart and exact fretboard-chord assertions. Visual review found a Restart scrolling race and an obscured left-handed open-string marker; both were corrected and all 40 arrangements passed the subsequent control and strict fretboard runs on both devices.
- The bundled SoundFont passed three fundamental-frequency estimates for each of the 23 distinct Songbook pitches (E2–B4), within ±35 cents. This is separate from physical listening.
- All 40 existing tutorial phrases and 18 exercises passed their renderer/MIDI/audio regression checks. The shipping bridge passed 3,108 position/seek checks and Reduce Motion/display-state tests.
- Large text, landscape geometry, and unplayable-configuration restoration passed on both simulators. Two iPad rotation failures in the final regression suite passed unchanged after restarting the simulator; they were simulator state failures, retained in test-runs.json. All 40 arrangements passed pause/resume, restart, seeking, tempo, loops, metronome, count-in, tab switching, arrangement switching and saved-position restoration after relaunch on both simulators.
- A development Release archive was produced, then Xcode Organizer refreshed signing and passed Apple validation for build 5. App Store distribution export subsequently succeeded; the IPA passes signature/content checks with get-task-allow=false. The earlier No Accounts/certificate failures are resolved. No new binary has been uploaded.
- Physical audible playback, Bluetooth/headphones, interruptions and VoiceOver passed according to the user’s September 7 confirmation. These are user-reported checks; no device-by-device trial log was supplied. TestFlight evidence remains pending. Simulator indicators and finite PCM do not establish physical-device audio correctness.

All 40 arrangements were visually compared on each simulator, including every changed chord. Post-fix ending/restart captures for all 40 arrangements on both devices confirm the scrolling and unobstructed left-handed markers; the final strict regression captures are retained as well. The 24 tutorials and all 18 exercises passed UI playback regressions on both simulators. App-scoped landscape captures can use stale portrait crop coordinates, so the capture helper now uses the full display. See `visual-review.json` for capture-specific scope.

Raw local test bundles and screenshots are under `artifacts/songbook-*`; compact reports and contact sheets are retained here for GitHub. Source PDFs/images remain research artifacts and are not app resources.

## Reproducing the checks

Run the source and harmony Python verifiers, then `SongbookTests` through the `StringMap` Xcode scheme on an iOS simulator. The native test writes the actual imported score and optimized alphaTex to the app container's `Library/Caches/SongbookEvidence`. Copy those 40 `*-native.json` files to `artifacts/songbook-verification`, then run:

```sh
node scripts/verify-songbook-playback.mjs artifacts/songbook-verification
node scripts/verify-songbook-soundfont.mjs
node scripts/test-playback-clock.mjs
node scripts/test-tutorial-bridge.mjs
```

Run `SongbookUITests` on both iPhone and iPad using the `StringMap` scheme, except the public store screenshot method, which uses `ReleaseValidation`. Run the existing tutorial and exercise playback UI regression methods as well. Use `xcresulttool export attachments` on completed result bundles. `scripts/export-songbook-review.py` builds review-only contact sheets from exported attachments; `scripts/export-store-screenshots.py` exports the unaltered Release store captures separately. Inspect the images: creating a contact sheet does not establish visual correctness.

## Remaining release gates — September 7

1. Distribution signing is complete: Apple Distribution certificate created, Organizer validation passed for build 5, and App Store export succeeded. The exported IPA passes strict signature verification, has get-task-allow=false and passes the offline release audit. No build-5 upload or submission has occurred.
2. Physical audible playback, Bluetooth/headphones, interruptions and VoiceOver are accepted as passed per the user’s September 7 confirmation. Device models, OS versions and detailed trials were not supplied, so retain the distinction from instrumented simulator evidence.
3. Upload the qualified candidate separately, update the App Store draft with current metadata/screenshots, verify country availability and account-holder content-rights/trader declarations, and complete the planned seven-day TestFlight exercise. Earlier build-1 draft/contact/privacy work remains historical evidence; it does not establish the new candidate is ready. Submission and public release remain separate actions.

The optional white-background icon image is saved under docs/design/icon; it has not replaced the selected Orange Frame app icon.
