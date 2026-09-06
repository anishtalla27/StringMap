# External notation pack results

## Latest outcome

The retained JPEG service now produces **11/15 printed XML results, 10 strict notation/playback results and seven standard-tuning tab results**. All seven general-handwriting samples still fail. Actual external Fancy Photos/review/edit/undo/audition/save/relaunch workflows pass on iPhone and iPad simulators, but these are app-flow checks, not reference-accurate transcription. A lossless preparation experiment regressed the corpus's provisional event accuracy and was not adopted. Final code/test evidence and remaining release gates are in [the release report](../evidence.md); machine-readable results are in `preserved-unison-results.json`. Historical runs below are retained rather than overwritten.

## Initial outcome

All **22 supplied images** were sent through the actual local HTTP recognition service. **10/15 printed pages produced MusicXML; 5 failed. All 7 general handwritten pages failed recognition or layout validation.** This is not release-ready recognition and does not meet the requested “works well” outcome.

The initial run was exploratory and spanned code changes. It is not a frozen accuracy qualification. Final Swift/alphaTab checks were rerun against the preserved recognition outputs: **8/10 import and produce exact notation MIDI with source identities preserved; 3/10 additionally produce playable tab in the unchanged default instrument configuration.** Two outputs are rejected for unsupported fermata/repeat-ending notation. Exact MIDI here means faithful to the recognized score, not faithful to the source image.

The supplied README explicitly says these images are photo simulations, not physical camera captures. Handwriting is genuine but general notation, with no matching symbolic ground truth. No real-camera or handwritten-guitar release gate was passed.

## Confirmed changes

- Chord notes with omitted voice fields inherit their anchor's voice. Explicit conflicting voices still fail validation; pitches and source identities are preserved.
- Composite durations such as 2.5 quarter notes render as exact tied segments, including notation playback when guitar fingering is unavailable. Unsupported nonrepresentable rhythms still fail instead of rounding.
- The command-line verifier now expands repeats for notation-only fallback, matching the app; it also supports the actual review-mode importer.
- Ambiguous predicted staff positions are reported as unreadable rather than falsely asserting that a single-staff guitar page contains multiple staves.
- Added reusable corpus, reference and result-comparison runners; local evaluation assets and checksum manifest are retained separately from app/container resources.

## Validation

- 48 Swift core tests pass.
- 25 iOS unit tests pass on the iPhone simulator (`artifacts/ios-external-pack-unit.xcresult`).
- 36 symbolic end-to-end MIDI tests pass, including new composite-duration and inherited-chord-voice cases.
- 19 Python service/adapter tests pass.
- All supplied file checksums still match after testing; `git diff --check` passes.

No full manual UI or physical-device run was performed for this pack. Subsequent focused simulator Files-import checks are recorded below.

## Experiments and unresolved defects

Additional full-page rotation retries did not recover the Fantasy page; that experiment was removed to avoid adding failure latency without demonstrated benefit. Audiveris 5.11.0 was also tested on Solus cum Sola and did not provide a reliable replacement. A local exploratory timing reconstruction was not adopted: note durations alone do not reliably disambiguate independent voices.

HOMR's chord-duration scheduling produces wrong onsets for interleaved voices. Some pages also have missed/incorrect symbols or unresolved staff predictions. Guitar written and sounding octaves must be explicitly distinguished: the reference MXL declares octave transpose -1 while these scans preserve visible written pitch. Provisional comparisons report both views, without selecting an octave to maximize score.

Complete reference-MXL import was separately exercised: 6/15 strict imports succeed, 5 give default-tuning tab. Remaining failures include cross-voice ties, repeat endings and fermatas. Galliard P27 contains low D outside standard tuning; the app must retain that music for review, not transpose it to force fingering. Supporting cross-voice ties needs consistent changes to validation, rendering, source mapping and playback, not simply removing the validator check.

First-page comparison boundaries are inferred from MXL print metadata and require independent PDF verification. References never enter the recognizer. See `artifacts/external-pack-baseline/comparison.json` for provisional pitch/onset/duration/note-event/chord metrics; do not treat them as certified accuracy percentages.

## Per-image recognition

| Image | Result | Seconds |
|---|---|---:|
| printed_guitar-01_fantasy_p5__flat | failed | 12.1 |
| printed_guitar-02_fancy_p6__tilt_left | failed | 12.1 |
| printed_guitar-03_solus_cum_sola__soft_shadow | completed | 56.8 |
| printed_guitar-04_solus_sine_sola__perspective | completed | 58.8 |
| printed_guitar-05_dr_cases_pavan__tilt_right | failed | 28.3 |
| printed_guitar-06_lachrimae_pavan__hard_shadow | completed | 83.2 |
| printed_guitar-07_digorie_pipers_galliard__flat | failed | 28.5 |
| printed_guitar-08_dowlands_first_galliard__tilt_left | completed | 67.0 |
| printed_guitar-09_frog_galliard__soft_shadow | completed | 107.9 |
| printed_guitar-10_galliard_p24__perspective | completed | 49.1 |
| printed_guitar-11_melancholy_galliard__tilt_right | completed | 101.7 |
| printed_guitar-12_galliard_p27__hard_shadow | completed | 70.9 |
| printed_guitar-13_galliard_p28__flat | completed | 79.0 |
| printed_guitar-14_giles_hobies_galliard__tilt_left | failed | 104.9 |
| printed_guitar-15_galliard_p30__soft_shadow | completed | 85.7 |
| handwritten_general_notation-01_CVC-MUSCIMA_W-07_N-05_D-ideal__soft_shadow | failed | 22.2 |
| handwritten_general_notation-02_CVC-MUSCIMA_W-29_N-10_D-ideal__perspective | failed | 30.5 |
| handwritten_general_notation-03_CVC-MUSCIMA_W-37_N-17_D-ideal__tilt_right | failed | 55.0 |
| handwritten_general_notation-04_CVC-MUSCIMA_W-27_N-16_D-ideal__hard_shadow | failed | 53.2 |
| handwritten_general_notation-05_CVC-MUSCIMA_W-09_N-13_D-ideal__flat | failed | 14.1 |
| handwritten_general_notation-06_CVC-MUSCIMA_W-50_N-08_D-ideal__tilt_left | failed | 18.1 |
| handwritten_general_notation-07_CVC-MUSCIMA_W-16_N-17_D-ideal__soft_shadow | failed | 8.1 |

## Evidence locations

- `artifacts/external-pack-baseline/`: original HTTP results and emitted XML.
- `artifacts/external-pack-render-recheck/`: final import and exact MIDI checks of all ten emitted printed scores.
- `artifacts/external-pack-references/` and `artifacts/external-pack-full-references.log`: complete supplied MXL import tests.
- `artifacts/external-pack-audiveris/`: independent-engine trial.
- `artifacts/external-pack-recovery-direct/`: failed rotation-recovery experiment.
- `artifacts/external-pack-playback-final.log`, `external-pack-swift.log`, `external-pack-service-tests-final.log`: regression results.

Recognition reliability, additional supported notation, actual camera testing and handwritten-guitar qualification remain open release blockers.

## September 6 follow-up: cross-voice ties

The validator now matches a tie across voice changes only when exactly one same-pitch, same-staff note ends at that onset, preferring a matching original voice. Ambiguous unisons remain review errors. Source voices and note IDs remain unchanged. Rendering and the native source map use the tie anchor's render voice, so the continuation sustains instead of re-attacking.

Current complete-reference results: **11/15 strict imports, all 11 exact notation MIDI/source mapping; 9/15 default-tuning tab results are exact.** Evidence is preserved in `artifacts/cross-voice-references/` and `artifacts/cross-voice-external-references.log`. This does not improve the photo recognizer's note/onset accuracy by itself.

The remaining Solus cum Sola tie has an actual quarter-beat gap in the supplied MXL (event-458 ends at measure-local 2.75; event-460 starts at 3.0). Review retains its notes and flags the unresolved tie rather than inventing a duration. Repeat endings and fermatas remain unsupported. The two low-D scores can be retained on import and then configured with the appropriate tuning; file import no longer requires successful standard-tuning fingering.

Regression coverage: **50 core tests and 38 exact symbolic playback tests pass**, including cross-voice ties within and across bars, ambiguous tie rejection, and source-voice/identity preservation through MusicXML save/reopen. Simulator UI verification is recorded separately.

### Real Files import on iPhone simulator

The updated build passes **25 iOS unit tests** (`artifacts/cross-voice-ios-unit.xcresult`). The opt-in `testExternalCrossVoiceScoreThroughFiles` also passes using the supplied complete Fantasy MusicXML through the system Files picker, without an injected import. It verifies ready playback, starts playback, and pauses. Evidence: `artifacts/cross-voice-files-locations.xcresult` (one passed, no failures or skips), with [imported notation and tab](../screenshots/external-fantasy-iphone-import.png) and [moving playback](../screenshots/external-fantasy-iphone-playing.png). Screenshots were visually inspected.

This checks the app's file, rendering and playback-control path; it does not establish audible physical-device playback or image recognition accuracy. Code hashes for this follow-up are in `cross-voice-code-checksums.json`; the earlier `final-code-checksums.json` remains the earlier recognition-run snapshot.

The supplied Galliard P27 also passes an actual Files-picker test: standard tuning reports the low D while retaining notation and playback; changing to Drop D produces playable tab and clears the warning. `artifacts/low-d-files-identified.xcresult` records one passing test. [Retained notation](../screenshots/external-low-d-notation.png) and [Drop D tab](../screenshots/external-low-d-tab.png) were visually inspected. The separate exact MIDI check reports 466 sounding attacks, preserved source identities, all notes assigned, and distinct simultaneous strings (`artifacts/cross-voice-drop-d.json`). The app's 470 note entries include tied continuations, so these counts have different meanings.

All **10 iPad simulator UI regression tests pass** without skips (`artifacts/cross-voice-ipad-ui.xcresult`), covering practice, landscape, score workflow, recovery/edit/undo/audition/save, transport across tabs and unplayable notation fallback. These ten exclude the opt-in real-service Photos and externally seeded Files tests.

A paired iPhone 14 Pro briefly appeared available, but disconnected before the physical build could start; Xcode timed out waiting for its destination. No physical test is claimed. The user requested skipping steps requiring manual input, so no unlock or reconnection was requested. Evidence: `artifacts/physical-iphone-qa-build.log`.

A subsequent generic-device build reached Apple's provisioning service, which reported no registered devices for the team and no development profile for this bundle ID (`artifacts/generic-device-qa-build.log`). No signed device build or archive was produced.

### Recognition alternatives and correction warnings

Pinned Jazzmus and Clarity models were evaluated locally. Their outputs are not reliable enough to replace the shipping recognizer; [the separate report](alternative-recognizers.md) records raw inference, conversion limitations, and the failed hybrid guitar trial.

Review edits now recompute unresolved-tie warnings so a corrected tie does not leave an obsolete warning behind. Revalidation also avoids accumulating duplicate tie warnings, while preserving recognition warnings about the source image. **51 core tests and 38 exact symbolic MIDI checks pass** after this fix (`artifacts/tie-warning-core-tests.log`, `tie-warning-playback.log`). The **25 iOS unit tests also pass** inside `artifacts/tie-warning-ios.xcresult`; that initial combined bundle includes a separate failed UI test caused by querying an offscreen control and is not an all-green bundle. Current source hashes are in `tie-warning-code-checksums.json`.

The corrected UI test and the existing recovery workflow then both pass on the iPhone simulator: **two passed, no failures or skips** in `artifacts/tie-warning-editor-ui.xcresult`. One verifies a malformed tie initially prevents audition, then removing that mark restores audition; the other verifies pitch editing, undo, audition, confirmation, saving, and reopening from the persisted library. Screenshots are retained in `artifacts/tie-warning-editor-attachments/`.

### Compressed MusicXML import

All 15 original `.mxl` archives now enter the shipping Swift importer directly. Each result is identical to parsing its extracted original XML; 11 strict notation/playback and nine standard-tuning tab results remain exact. `mxl-results.json` records per-file outcomes. The app saves extracted XML locally, never ancillary archive content. Native Files import, playback, relaunch and exact-library-record reopening pass on both iPhone and iPad simulators (`artifacts/mxl-iphone-files-v3.xcresult`, `artifacts/mxl-ipad-files.xcresult`). The core suite is now 59 tests; 38 symbolic MIDI cases and 25 iOS unit tests pass. Source hashes: `mxl-code-checksums.json`. Earlier failed UI selectors are retained in the initial MXL test bundles; final focused runs pass without skips.

### Guitar photo octave and single-staff labels

The current iOS photo boundary defaults to standard written guitar notation, sounding one octave below the page. Concert pitch remains selectable; explicit XML transposition, prior drafts and saved corrected files are handled without double transposition. A fresh supplied perspective-image HTTP run passes all recognized-score tab/MIDI checks (`artifacts/guitar-photo-live-external/`). The actual controlled Photos/review/edit/undo/audition/save/reopen workflow passes on both simulator families. See the latest [release evidence](../evidence.md) section for exact bundles and limits.

A source-preserving staff-label fix recovers Fantasy. Current full printed-pack HTTP rerun: **11/15 produce XML, nine strict notation/playback, seven standard-tuning tab**. Detailed records: `guitar-photo-results.json`; current hashes: `guitar-photo-code-checksums.json`. All playback checks are exact to the recognized output, not the image. The untouched earlier all-22 baseline remains evidence of the seven handwriting failures; handwriting was not rerun or qualified by this change. Timing accuracy and the four ambiguous duplicate-note failures remain open. A separate unshipped preservation experiment on Fancy produces tab but only 23.5% provisional written note-event F1 (`artifacts/preserved-unison-trial/`).

## Preserved-unison and strict-export rerun

The adapter now retains ambiguous unison predictions with a review warning, retries unreadable first readings from bounded image rotations, and refuses XML that converts a predicted note into a rest. The full supplied **22-image** HTTP run yields **11/15 printed XML results, 10 strict native notation/playback results, seven standard-tuning tab results, and no successful handwriting results**. Two former failures are recovered (02 and 07); two previous apparent successes expose missing-pitch loss (01 and 12). Printed 05 and 14 still fail. The overall release target remains unmet. `preserved-unison-results.json` records each outcome, code/image fingerprints and playback checks; `artifacts/preserved-unison-retry-external/` retains raw results and provisional comparisons.

The real iPhone Photos preparation path produces a different input from uploading the supplied JPEG directly. A retained cropped Fancy result exposed an unsupported 64th-note triplet. That exact rhythm and composite gaps are now renderable; all recognized source identities, tab pitches and MIDI events pass on the retained scan. This fixes audition/save availability, not transcription accuracy. The original UI failure and subsequent count/label assertion failures remain preserved. Final flow evidence is recorded in the main release evidence report.

Thirty-two clean generated controls still match all 1,136 events and 168 chords on the changed recognizer. Twenty-eight service tests, 64 core tests and 42 symbolic MIDI cases pass. Neither control-image success nor MusicXML production establishes useful handwriting or real-camera recognition.

## Lossless preparation experiment and retained default

A lossless-PNG preparation trial did not improve this corpus: aggregate provisional written note-event F1 fell from 8.61% to 8.28%; cases 03, 07 and 13 regressed, and none improved on that metric. The experiment is retained under `artifacts/lossless-external-pack-v2/` and was not adopted as the default. A prepared Fancy scan illustrated the tradeoff: its pitch multiset improved, but event F1 fell from 42.1% to 23.5%. Pixel preservation and note counts alone are insufficient evidence of accurate transcription.

The final runtime retains JPEG quality 95 and adds tested EXIF orientation/metadata stripping. For every supplied image and all 32 clean controls, final prepared bytes match the previously tested JPEG path exactly (`artifacts/final-image-preparation-equivalence.json`). Final service coverage is 31 passing tests. Current source fingerprints are in `review-preservation-final-code-checksums.json`; the main release report distinguishes final flows from experimental ones. Real-camera, independent-reference and handwriting gates remain open.

The final service also passed a fresh complete controlled regression: 148 musical images, 5,120 exact note events, 800 complete chord onsets, plus five rejected unsupported/blank inputs. See [current regression](../review-preservation-benchmark.json). These generated controls establish regression safety; the supplied external images remain inaccurate and the app is not release-qualified.
