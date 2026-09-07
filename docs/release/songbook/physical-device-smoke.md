# Physical Release smoke test — September 7, 2026

Device: iPhone 14 Pro, iOS 26.6.1. Version 1.0.0 (5), Release configuration, development signed for the connected phone. No library reset or uninstall was performed.

Three UI tests passed with zero failures in 77.272 seconds using the ReleaseValidation scheme:

- ReleaseHomeUITests/testHomeTransportLoadsPlayerAndUpdatesStatus: Home transport opens the player and updates playback state.
- ReleaseTutorialUITests/testPlaybackClockAdvancesAndResumes: tutorial clock and fretboard advance, pause/resume works, then Free Practice clock and fretboard advance.
- SongbookUITests/testSongbookArrangementSwitchingAndPlayback: Amazing Grace melody clock/fretboard advance, pause and seek work, chord tones appear, and switching back restores the melody position.

Visually reviewed retained captures: physical-tutorial.png shows sounding G3 on open string 3 with corresponding written G4; physical-free-practice.png shows B3 on open string 2 with written B4 and tab 0; physical-songbook-chord.png shows G accompaniment at frets 3–2–0–0–0–3 (strings 6 through 1), matching notation/tab. The tutorial capture is scrolled to its transport; the upper fretboard is outside the scroll viewport, not missing content.

Strict code-signature verification and offline bundle audit passed: 20 songs, 40 arrangements, 24 lessons, 40 tutorial examples, 18 exercises; scanner/listening code and permissions absent. Standalone launch succeeded after testing. This is a targeted physical regression check, not another exhaustive run of every arrangement. Prior full simulator/content evidence remains in this directory. Audible output, accessories, interruptions and spoken VoiceOver remain the separate user-reported qualification already recorded.

Setup fix: project.yml contained duplicate app settings.base keys that discarded DEVELOPMENT_TEAM during generation. Moved the team to global base settings so app and tests inherit it. Xcode registered the new phone and refreshed provisioning. No application source or musical content changed. An initial attempt using the general StringMap scheme could not compile Debug-oriented unit tests in Release; the dedicated ReleaseValidation scheme passed unchanged.

Raw evidence: artifacts/new-iphone-release-tests.xcresult, artifacts/new-iphone-release-tests.log and artifacts/new-iphone-final-captures. App Store distribution validation remains recorded separately; this device-signed build is not the distribution IPA. TestFlight and App Store submission remain pending.
