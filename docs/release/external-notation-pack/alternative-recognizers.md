# Alternative recognizer evaluation — September 6

These are isolated, local research experiments. Neither candidate replaces the shipping HOMR adapter. Images and raw results remain in ignored `artifacts/`. No reference XML was provided to model inference. Model and code revisions/hashes are in `alternative-model-pins.json`; the isolated environment is recorded in `artifacts/omr-model-evaluation-requirements.txt`.

## Jazzmus

The [authors' repository](https://github.com/JuanCarlosMartinezSevilla/ISMIR-Jazzmus) and [model card](https://huggingface.co/JuanCarlosMartinezSevilla/jazzmus-model) describe a model trained on handwritten jazz lead sheets. Code/model cards declare MIT licensing; the separate Ultralytics dependency and all training-data terms would still need a deployment audit. The research [paper](https://arxiv.org/abs/2509.05329) concerns melody and chord names, not qualification for handwritten polyphonic guitar.

All seven supplied general-handwriting photo simulations ran on CPU. The model detected 57 staff regions and emitted predictions for all 57, taking approximately 11.6–21.8 seconds per page after model loading. This is inference completion, not successful score recognition. Inspection found wrong pitches, invented chord names, malformed syntax and unresolved ties. Detector over/under-segmentation also remains unmeasured.

An exploratory conversion of only the melodic `**kern` column yielded 53 MusicXML files; 15 passed the Swift strict importer and 14 produced default-tuning tab. These are not preservation or accuracy results: music21 warned about malformed tokens and may normalize predictions. Four conversions failed. Raw chord-name columns were retained in original files and never turned into guitar notes. No symbolic references exist in the supplied handwriting pack, so no accuracy percentage is reported.

Evidence: `artifacts/jazzmus-external-results/`, `jazzmus-external.log`, and `jazzmus-melody-conversion/summary.json`. Reproduce inference with `services/omr/evaluate_jazzmus.py`, the pinned repository/model, and the isolated environment. The initial upstream CLI attempt failed because it treated a local model path as a Hub repository; the evaluator loads local weights directly and ran with Hub networking disabled.

## Clarity-OMR and a hybrid trial

[Clarity-OMR](https://github.com/clquwu/Clarity-OMR) provides CPU inference and explicit voice tokens. Its repository declares GPL-3.0; its [model card](https://huggingface.co/clquwu/Clarity-OMR) declares CC-BY-SA-4.0. This is an evaluation, not a completed deployment license review.

Input was the supplied Fantasy photo simulation, wrapped unchanged as the sole raster image in a one-page PDF. The original pipeline detected eight regions, including a false region near the page title, and assembled two piano parts. Its exporter reported 21 measure mismatches despite producing schema-valid XML. The first export needed the missing lxml dependency; it was rerun against retained predictions without repeating recognition.

A second experiment used HOMR's seven detected/dewarped guitar staff images with Clarity's pinned recognizer (CPU, beam width five). Inference took approximately 66 seconds. A research exporter preserved each staff's raw tokens, bypassing upstream piano grouping, key/time majority replacement, measure normalization and token post-processing. It emitted 435 note entries from 435 note tokens, with the same pitch multiset. Nevertheless, there were 20 measure mismatches and poor transcription accuracy. The supplied photo visibly contains measures 1–20, matching the MXL page break at measure 21. The provisional comparison has 343 reference entries and 435 recognized entries, with written-pitch/onset/duration note-event F1 about 7.2%. Reference events have not received a complete independent note-by-note audit.

Swift can retain the hybrid output as notation, and alphaTab reconstructs its 430 sounding attacks with exact timing and source identities; tied continuations explain the difference from 435 note entries. Standard-tuning tab correctly rejects an unplayable passage. Faithful playback of incorrect recognition does not make that recognition accurate.

Evidence: `artifacts/clarity-external-results/`, especially `hybrid-comparison.json`, `hybrid-playback.json`, `01-fantasy-hybrid.export.json`, and both raw prediction manifests. The research exporter is `services/omr/export_clarity_guitar_evaluation.py`. This candidate is not adopted; no release gate is closed by these experiments.

## Zeus on the supplied Fantasy photo simulation

[Zeus](https://github.com/OmniOMR/zeus), source `3cbcb56fbb4c24de3f63557be14a66f6c578125a`, used the already pinned AYCE 2026-08-03 snapshot (MIT code, CC BY-SA 4.0 weights) in its isolated Python 3.10 environment. The seven existing HOMR image-derived staff crops were the only recognizer input. Ground-truth XML was read afterward, exclusively by the comparison script. No production service dependency was changed.

| Fixed preprocessing variant | MusicXML produced | Provisional written note-event F1 |
| --- | ---: | ---: |
| Original HOMR staff crops | 5 / 7 staffs | 51.3% |
| Remove excess vertical whitespace | 7 / 7 staffs | 47.7% |
| Same crop plus fixed threshold smoothing | 6 / 7 staffs | 39.3% |

The original trial failed LMX decoding on staffs 1 and 7 because the predicted backups implied negative onsets. Tighter image bounds recovered syntactically decodable output for all staffs, but note/onset/duration errors remained extensive: 163 matches, 180 missing and 178 extra events against 343 reference entries. This is not a viable replacement and no variant was adopted. Decodable XML alone does not establish recognition correctness.

These are provisional comparisons using the reference's first-page/system breaks (measures 1–20), with written and sounding pitches reported separately. Every reference event and staff boundary still needs independent visual auditing; no real camera or handwriting gate passes. The comparison counts absent staff outputs as missing notes. Per-staff Swift review results include unresolved ties at cropped boundaries and other limitations; they are not full-page playback evidence.

Reproduction: `services/omr/evaluate_zeus_crops.py` consumes image crops/model only and retains all raw LMX, XML, bounds, hashes and inference timing. `services/omr/compare_staff_crops.py` performs the separate post-inference reference comparison. Evidence: `artifacts/zeus-external-fantasy/`, `artifacts/zeus-external-fantasy-tight/`, associated logs, and `alternative-model-pins.json`. The first preprocessing-script attempt lacked Pillow in the isolated environment; it was changed to use already-installed TensorFlow image decoding, leaving production dependencies untouched.
# Further external-page diagnostics — September 6

Audiveris 5.11.0 was run in batch mode on the supplied flat Fantasy, Digorie Piper's Galliard and Galliard P28 images. References were read only after export. Fantasy produced valid native tab/MIDI but provisional written note-event F1 was **6.2%** (21 matched, 322 missing, 309 extra). Digorie produced XML with **6.1%** event F1 and failed strict native import; Galliard P28 produced no MXL. Raw outputs, private diagnostic logs, hashes and comparisons are retained in `artifacts/audiveris-external-flat/`, driven by `artifacts/evaluate-audiveris-external.py`. This external trial does not qualify Audiveris as a replacement.

An isolated HOMR timing hypothesis advanced to the earliest outstanding note end rather than considering only newly started notes. On the stored Fantasy image-derived tokens, it changed 27 advances and improved provisional event F1 from **5.0% to 12.0%**, with timing warnings falling from 14 to six. That remains far below qualification; this scheduling change was **not adopted**. Both candidate XML files, changes and comparisons are in `artifacts/active-duration-timing-trial/`. Page boundaries still require independent checking; pitch/duration multiset scores are not event-aligned accuracy.

## Model search and measure-crop trials

The new isolated tools in `services/omr/research/` implement fixed-width Zeus beam search and optional pruning of prefixes with impossible negative measure cursors. Width one exactly reproduces upstream greedy inference on every evaluated staff. Final export rejects decoder diagnostics, nonterminated output and any mismatch between predicted pitch tokens and exported notes. Five prefix timing checks pass. Neither pitches nor durations are repaired using a reference.

| Supplied printed page | Unconstrained width four | Width eight with timing guard |
| --- | ---: | ---: |
| Fantasy, fixed tight staff crops | 59.3% | 59.5% |
| Fancy, tilted photo simulation | 37.2% | 39.5% |
| Solus Sine Sola, perspective simulation | 13.8% | 10.6% |
| Galliard P28, flat image | 32.1% | 32.3% |

Values are provisional **staff-aligned note-event F1**, including absent outputs as missing notes. Extra predicted staffs are now included in scoring, with a regression test. This is not whole-page timing qualification. The Fantasy greedy baseline on identical tight inputs was 47.7%; unconstrained width eight fell to 54.7% because one staff had negative decoded onsets. The guard recovered that staff, but recognition still falls far short of release targets and does not generalize reliably.

Image-only segmentation also tested recognition one measure at a time. A pixel rule confused a stem with a barline, and the trained detector alone had extra stem detections. Their agreement found the 20 visible Fantasy measures. Zeus exported 19/20 with 42.7% within-measure F1, or 49.7% with the original staff's visible clef/key prefix included in each later crop. Missing context was one problem, but providing it did not solve transcription. No crop variant was adopted.

Evidence: `artifacts/zeus-beam4-fantasy/`, `zeus-beam8-fantasy/`, `zeus-beam4-timing-fantasy/`, `zeus-beam8-timing-fantasy/`, `zeus-cross-scores/`, `zeus-consensus-bar-crops/`, and `zeus-context-bar-crops/`. [Machine-readable comparison and hashes](recognition-search-results.json). The three additional printed cases all completed; a later accidental handwritten filename match failed layout checks and is retained in the first orchestrator log. The runner's printed-category filter was corrected and all six printed comparisons recomputed.
