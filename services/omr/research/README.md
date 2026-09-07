# Isolated recognition experiments

These tools are excluded from the service container and do not change the hosted HOMR adapter. Zeus tools require the separately installed Zeus Python 3.10 environment; HOMR tools use the existing pinned HOMR environment. Do not install research dependencies into the production worker.

`extract_guitar_staffs.py` takes an image, detects single guitar staffs with the pinned HOMR detector, dewarps each staff and removes surrounding vertical whitespace. It rejects unresolved connected-staff layouts. Its inputs contain no reference notation.

`evaluate_zeus_beam.py` loads the pinned Zeus AYCE snapshot and compares model-ranked alternatives. Before searching, a width-one implementation must exactly reproduce the upstream greedy prediction for every input. The optional `--timing-guard` rejects a completed prefix that moves the MusicXML cursor before the start of a measure. It never pads a measure, changes a duration or chooses pitches using a reference. Every candidate is retained, and final export requires terminated output, no decoder diagnostics and exact predicted pitch-token preservation.

Example using the existing local environments, from the repository root:

```sh
services/omr/.venv-homr/bin/python services/omr/research/extract_guitar_staffs.py --image /absolute/path/page.jpg --output artifacts/new-page-crops
artifacts/engine-evaluation/tools/zeus-venv/bin/python services/omr/research/evaluate_zeus_beam.py --crops artifacts/new-page-crops --model artifacts/engine-evaluation/tools/ayce-2026-08-03.model --output artifacts/new-page-beam --width 8 --timing-guard
artifacts/engine-evaluation/tools/zeus-venv/bin/python services/omr/research/check_zeus_timing_search.py
```

References enter only the separate `services/omr/compare_staff_crops.py` evaluation. Its scores align the beginnings of individual staffs, so they do not establish correct whole-page timing. Extra predicted staffs and missing reference staffs count against accuracy. A successful XML export also does not establish faithful recognition, valid ties across crops, native support for every symbol, or playable guitar tab.

The tested model and code are pinned in `docs/release/external-notation-pack/alternative-model-pins.json`. Zeus code is MIT-licensed and the evaluated weights carry CC BY-SA 4.0 terms. The local reference/photo corpus remains research evidence outside this folder. Neither this model nor these experiments are a qualified shipping dependency. See `docs/release/external-notation-pack/recognition-search-results.json` for outcomes and limitations.


## HOMR joint-head search

`evaluate_homr_beam.py` tests width-four joint-head search against the pinned decoder's greedy output. It enumerates the highest joint probabilities across the model's six independent output heads, keeps bounded hypotheses, and requires width one to reproduce all upstream symbol fields before proceeding. Three checks compare the joint enumerator with exhaustive Cartesian scoring, deterministic ties and nonfinite-input rejection. The fixed length penalty is 0.6. Model likelihood and export validity determine selection; references do not enter inference. `searchSeconds` includes width-one verification plus the wider search, excluding the earlier upstream baseline and encoder run.

HOMR requires its canonical staff dimensions: use `extract_guitar_staffs.py --full-height` rather than the tight Zeus crop. `assemble_homr_beam.py` assembles a complete page with notation state preserved across staff breaks. A missing or unexportable staff fails the page; predicted notes are never dropped to make it valid.

```sh
services/omr/.venv-homr/bin/python services/omr/research/extract_guitar_staffs.py --image /absolute/path/page.jpg --output artifacts/new-homr-crops --full-height
artifacts/engine-evaluation/tools/homr-venv/bin/python services/omr/research/evaluate_homr_beam.py --crops artifacts/new-homr-crops --output artifacts/new-homr-beam --beam 4
artifacts/engine-evaluation/tools/homr-venv/bin/python services/omr/research/assemble_homr_beam.py --results artifacts/new-homr-beam
artifacts/engine-evaluation/tools/homr-venv/bin/python services/omr/research/check_homr_beam.py
```

The four-page trial regressed on every staff-aligned comparison and was not adopted. Full-page/native results, model hashes and limits are retained in `docs/release/external-notation-pack/homr-beam-results.json`.

## Staff crop geometry

`extract_guitar_staffs.py --full-height --column-dewarp --common-span` runs the geometry experiment; `--horizontal-margin-units` controls image margins. `evaluate_homr_beam.py --beam 1` then preserves the verified upstream greedy reading without a wider search. The research common-span trial applies a majority width even when no staff is a clear outlier; the production adapter has the additional short-span gate documented in the service README.

The resampling helper is shared through `../staff_image.py`; `column_staff_crop.py` is only a research import wrapper. Four checks in `check_column_staff_crop.py` cover slope extrapolation, white grayscale/RGB borders, straightening of synthetic staff lines and invalid geometry. Production retry-selection and majority/outlier guards have separate service unit tests. All 15 printed trial outputs are retained under `artifacts/column-staff-external-pages/`; only the guarded alternative was adopted. See `docs/release/crop-retry-verification.json` for actual HTTP, native, Linux and simulator evidence.

## Inline text and handwriting probes

`inspect_music_text.swift` runs the local Apple Vision text recognizer on an image and records observed boxes/candidates without editing pixels or reading music references. Compile with `swiftc`; it is a macOS research tool excluded from the service container. The initial Fancy staff/page probe did not reliably find fingering digits, so no masking was adopted.

The six manually cropped handwritten treble-staff checks, source hashes and native import failures are recorded in `docs/release/external-notation-pack/handwriting-staff-results.json`. Crop bounds were chosen from visible page geometry before inference. Four XML exports are insufficient. After the explicit unsupported-mark review change, three open as unresolved reviews and one still fails on grace-note timing. A small independent pitch check also fails; see `docs/release/review-issues-verification.json`.


## Audiveris page comparison and deskewing

`evaluate_audiveris_pages.py` runs the installed pinned Audiveris 5.11.0 app on selected external-pack images. It opens references only after XML export. `--deskew --scale 2` applies image-only line-angle consensus and bounds the result to 18 million pixels. Each original image, prepared image, raw log, MusicXML, native result and comparison is retained. Audiveris remains research-only.

`compare_measure_timing.py` diagnoses cumulative drift by comparing events within matching measure indices. Its deliberately aligned results are not whole-page accuracy and do not correct any music. The `implicit` attribute describes measure numbering, so these experiments do not infer or pad missing time from that flag (MusicXML 4.0 measure reference: https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/measure-partwise/).

The 15-page raw and prepared comparisons are recorded in `docs/release/external-notation-pack/audiveris-page-trial.json`. The prepared engine exports every page but remains far below the recognition target. Only the separately tested, bounded HOMR recovery path was adopted: see `page_image.py` and `docs/release/page-deskew-verification.json`. It has no upscaling and never changes an already successful reading.

## Pitch consistency and overlapping voices

`evaluate_pitch_consistency.py` reproduces all six original decoder fields before testing a pitch mask. A predicted note may choose any pitched class from C0 through B9; a predicted rest uses the empty-pitch class. This experiment preserves the predicted rhythm and records every changed decision and its uncalibrated model probability. It uses no guitar range, fingering or reference. **Constrained pitch selection is not a production feature.**

`run_pitch_consistency_pack.py` normalizes each image like an HTTP upload, extracts canonical full-height staffs, and runs that comparison. `assess_pitch_timing_pack.py` loads reference music only after all inference completes. It assesses whole-page events, separate measure-index diagnostics, strict/review imports, tab invariants and exact MIDI. Export success is separate from all these checks. The retained 15-page experiment in `artifacts/pitch-consistency-printed/` predates the production overlap-timing patch: its writer SHA-256 was `6779fcdde4190ddd3508552f66ac28948740c2ff2464a63e4b6d5808df8089aa`. Repeating it against the new writer does not reproduce that old timing baseline.

`sustained_timing.py` and `evaluate_sustained_timing.py` isolated cursor advancement without modifying installed files: an earlier voice can end before the newest note does. That timing change was then implemented separately in production `../symbol_timing.py` and the pinned install-time writer patch. The pitch experiment remains excluded. References never choose between alternatives.

`build_interleaved_corpus.py` creates two original two-voice studies and one melody control, with 72 expected written note events specified before recognition. It emits MusicXML, engraved images, a specification, and both benchmark manifest formats. These are controlled engravings, not camera photos. Run the builder with the rendering environment (`services/omr/.venv/bin/python`) and a new `--output` directory. The three actual Linux HTTP uploads passed all 72 pitch/onset/duration events, all 16 simultaneous groups, and exact native/tab/MIDI checks. Complete production verification and limitations are recorded in `docs/release/interleaved-timing-verification.json`.
