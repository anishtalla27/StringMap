# StringMap first-release gates — offline exercises

The current candidate includes a 12-lesson beginner tutorial and 18 original single-note guitar exercises. The tutorial includes three authored chord shapes. Scanning, handwriting, general chord import and public file import are outside this release. App Store finalization is paused; see docs/tutorial-mode.md for feature verification. Historical recognition work is retained in `docs/release/scanning-checklist-historical.md`; those recognition gates are not prerequisites for this version.

- [x] Preserve unrelated work and internal recognition development.
- [x] Compile scanner UI/networking only in Debug; no public placeholder.
- [x] Bundle 18 newly authored exercises with pitch/rhythm provenance.
- [x] Verify every authored event through Swift, alphaTab MIDI, source identities and exact fret pitch reconstruction.
- [x] Verify score-time conversion and seeking across six playback speeds.
- [x] Visually review full standard notation for all 18 exercises.
- [x] Pass 75 Swift core tests and 40 iOS unit tests.
- [ ] Complete iPhone/iPad simulator interaction and Release-binary checks.
- [ ] Verify physical-device audio, routes, interruptions, accessibility and long practice sessions.
- [x] Update bundled privacy/support/license documents for offline-only operation.
- [ ] Publish and verify matching policy/support pages and final screenshots.
- [ ] Validate signing and a distribution archive; upload a unique build for TestFlight.
- [ ] Complete physical TestFlight testing and enter final App Store metadata/privacy/age-rating answers.
- [ ] Obtain final App Store submission/public-release authorization.
