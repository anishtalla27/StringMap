# Tutorial expansion: 24-lesson candidate

This expansion supersedes the 12-lesson catalog in the earlier release reports. Build 4 is a new local candidate; the earlier App Store Connect upload is not evidence for this binary. No replacement upload, submission, or public release is implied.

## Implemented scope

- Foundations retain lesson IDs 1–12 and their original 16 MusicXML examples. Building Skills adds 13–18; Connected Playing adds 19–24. The catalog now contains 24 lessons and 40 examples, alongside the original 18 Free Practice exercises.
- Every new lesson has two original examples, original instruction and a nonblocking technique/rhythm question. Lessons 13–23 use two or three bars per example; lesson 24 has two separate eight-bar studies. All new material starts at 60 quarter-note BPM.
- Normalized measure durations drive tutorial timing, including six-eight. Prescribed positions survive optimization. Fingerpicking uses independent voices and retains simultaneous sounding notes on the fretboard.
- Teaching presentation includes frets through 8, actual fret numbers, A-root rings where authored, position captions, separate picking-hand cues and a data-defined two-string barre. Existing Free Practice fretboard presentation is retained.
- Bundled guitar slurs explicitly opt into import; general external technique import stays disabled. Hammer-on/pull-off source links survive import, JSON, transposition, MusicXML writing, repeat copying, fingering and alphaTex. Invalid direction, string changes and disconnected pairs are rejected. Ties remain separate.
- Tutorial engraving uses a compact horizontal staff, follows seeks and omits redundant tuning/track/dynamic labels. The complete staff and optional tab fit the measured panel height. Free Practice keeps its existing layout.
- Step audition includes the initial picked note of a complete connected group or tie. A sustained bass does not hide the picking cue for the next upper-string attack.
- Build-3 WebKit audio-session ownership is preserved. No microphone grading, scanner, account or network dependency was added.

## Verification record

The tests use the actual Swift importer and optimizer, actual alphaTab renderer and MIDI generator, and the bundled SoundFont synthesizer. Hand-reviewed pitch arrays and separately specified rhythmic cells live in `TutorialTests.swift`; expected references are not emitted by either course generator.

Completed September 7, 2026:

- 77 Swift core tests, 43 iOS unit tests, 13 TypeScript tests and TypeScript typechecking pass.
- All 40 tutorial examples pass native import/optimization, engraving, MIDI and actual SoundFont PCM checks at 30, 60, 90 and 120 BPM (160 tempo trials). Checks cover exact pitch/onset/duration, ties without extra attacks, H/P source identity and articulation, simultaneous-string separation and unclipped audio. All 18 existing exercises (518 events) pass regression checks; 3,108 bridge clock/seek checks pass.
- Both simulator sizes exercised all 24 new examples and their controls, stepping, questions, completion and restored progress. iPhone re-ran the original 12-lesson public flow and actual tutorial/Free Practice clock advancement. Final targeted iPhone/iPad runs pass active notation/barre and actual six-eight loop wrapping; large text, mirroring and rotation pass. Reduce Motion behavior has bridge coverage; spoken VoiceOver usability still needs physical review.
- Visually inspected beginning/middle/end of every new example (72 captures), plus 69 explicit shift/chord/barre/slur transitions and final correction screenshots. See [comparison notes](screenshots/tutorial-expansion/review-notes.md). These are visually reviewed XCTest UI captures, not a claim of physical listening.
- The final signed archive is `artifacts/StringMap-1.0.0-build4-release.xcarchive`; exported IPA is `artifacts/tutorial-expansion-distribution/StringMap.ipa`. Archive, export, strict signature verification and binary audit pass. Build 4 was installed on the connected iPhone. It was not uploaded to Apple.
- Refreshed seven native iPhone Store images and the iPad Learn image are in `docs/store/screenshots/tutorial-expansion`, with passing-test provenance and dimensions. Listing, support and course provenance copy are updated.

Detailed local evidence paths are in [tutorial-expansion-tests.json](tutorial-expansion-tests.json). Historical failed UI bundles remain available: final targeted reruns resolve the test-helper failures rather than disguising the earlier bundle as wholly passing.

## Findings corrected during testing

1. A newly added normalized-note initializer initially omitted its slur fields, losing source links. A core round-trip test exposed it; the fields are now preserved.
2. Sustained bass events could take precedence over newly attacked notes in the p–i–m–a cue. The cue and short audition now follow the latest attack; all ringing notes remain highlighted.
3. The initial teaching-fret change affected inlays rather than fret-number labels. The intended numeric labels now cover every visible fret; ordinary inlays remain unchanged.
4. Dense independent voices overflowed the old vertically paged notation panel. Tutorial engraving is horizontal, unnecessary effect labels are hidden, and every rendered example is checked against the panel height.
5. The initial slur-articulation assertion incorrectly compared a pull-off with its already softened hammer-on predecessor. It now compares each destination with that same note in an otherwise identical plain-picked score.
6. The barre line overlaid its finger numbers; drawing it behind the markers restores contrast. Compact phone teaching layouts now separate open-string and first-fret touch targets.
7. A mirroring UI test used a launch argument that overrode persisted settings, preventing the switch from changing the value. The test now establishes orientation through the actual switch. A separate accessibility helper now reveals the parent fretboard before tapping its child, and the loop assertion parses UIKit milliseconds instead of assuming percentages. Both corrected checks pass.

## Technique audio and remaining release boundaries

The real alphaTab synthesizer generates both pitches, their exact durations and distinct softer destination velocities for H/P links. A tie has one attack across its full held duration. This establishes a synthesized reference, not acoustic authenticity or physical audibility. Lesson copy identifies technique sound as synthesized.

A person must still listen on physical iPhone and iPad, including with the silent switch enabled, and distinguish picked notes, held ties, hammer-ons and pull-offs. Headphones/Bluetooth, interruptions and the project's TestFlight exercise also need physical evidence. App Store upload, account-holder declarations, review submission and public release are separate steps.

## Teaching references and rights

All exercises, prose and authored fingering data are original. No external sheet music, lesson scripts, recordings or arrangements were copied. Background references:

- [Bradford Werner: shifting and guide fingers](https://www.thisisclassicalguitar.com/lesson-shifts-string-squeak-guitar/)
- [JustinGuitar: triad chord grips](https://www.justinguitar.com/guitar-lessons/triad-chord-grips-im-151) — supplied planning reference; the accessible page did not expose a lesson transcript.
- [Bradford Werner: guitar slurs](https://www.thisisclassicalguitar.com/lesson-slurs-for-classical-guitar/)
- [alphaTab note properties](https://alphatab.net/docs/alphatex/note-properties)
