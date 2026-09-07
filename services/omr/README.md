# StringMap recognition service

`production.py` hosts a pinned, CPU-only [HOMR](https://github.com/liebharc/homr) guitar adapter. The iOS client receives MusicXML through an owned asynchronous API; no recognition engine is embedded in the app. oemer and Audiveris evaluation results are retained, but neither is the production dependency. Handwriting remains an unmet release gate.

The service returns the visible written pitches. At the photo-input boundary, iOS defaults to standard guitar notation (written E4 sounds E3), with a concert-pitch option. Explicit MusicXML transposition is applied once; ordinary structured-file import continues to follow its encoded transposition. `stringmap-check --guitar-photo` verifies the same default photo interpretation. The original controlled benchmark was specified at concert pitch, so its historical totals must not be relabeled as verification of this new guitar-photo boundary.

On independently detected single-staff systems, stray lower-staff note/rest labels can be assigned to the sole treble staff when there is no predicted second clef. Pitches, durations, order and all other predicted note fields remain unchanged, and an uncertain-placement warning reaches review. Connected/multiple staves and a predicted second clef remain rejected. This recovers usable review output, not recognition accuracy qualification.

## Local development

Use Python 3.12. `./services/omr/bootstrap.sh` creates `.venv-homr`, installs `requirements-lock.txt`, and downloads checksum-verified models. Requests never download models or executable code.

Installation also runs `patch_homr.py` against the pinned XML writer. Upstream chooses its integer timing grid from only the shortest note in each chord, which can truncate a longer triplet or quintuplet member. The patch includes every member's duration denominator and preserves predicted durations, pitches and order. Both the original and patched source hashes are checked, and unexpected source is rejected without modification. Existing local environments must run `.venv-homr/bin/python patch_homr.py` from this directory once. Service startup and direct recognition verify the patched writer. The patch and reproducible build instructions are included in the corresponding-source offer.

The writer patch also emits every predicted simultaneous rest as a separate rhythmic voice. Installation can upgrade the earlier exact-duration patch without modifying unknown source. Recognition disables upstream's measure-length heuristic for removing tuplets; lossless cleanup is accepted only if notes, rests, durations, accidentals, articulations, ties, grouping and measure boundaries remain identical. Any proposed musical change retains the original prediction for review. Export checks both pitched-note and rest counts before returning a result.

`symbol_timing.py` advances serialized onset groups to the earliest outstanding note or rest ending, including voices that started in an earlier chord. This lets an earlier voice resume while the newest note still sustains. It preserves exact fractional durations, pitches, rests and simultaneous membership, resets at barlines, and retains the final sustained tail when estimating measure length. Grace and multi-measure-rest timing stays with upstream's separate handling and remains subject to native unsupported-notation checks. Incorrect recognized rhythms can still give incorrect onsets; review and accuracy qualification remain required. Experimental constrained pitch selection is not used by the service.

```sh
OMR_ENV=development OMR_DATA_DIR=/tmp/stringmap-omr \
  services/omr/.venv-homr/bin/python -m uvicorn --app-dir services/omr \
  production:configured_app --factory --host 127.0.0.1 --port 8765 --no-access-log
```

Development mode accepts loopback clients only and omits App Attest for Simulator. Never expose it publicly. Physical development builds require a separate HTTPS staging service with `OMR_ENV=staging`, `APP_ATTEST_ENVIRONMENT=development`, the real App ID and an explicit allowed build. Production accepts only production attestation and TestFlight/App Store launch categories.

## Container and Railway

Build from repository root:

```sh
docker build -f services/omr/Dockerfile -t stringmap-omr .
```

The Python 3.12.13 Linux ARM64 image was built locally. See `docs/release/evidence.md` for executed checks and outstanding hosting validation. Select `services/omr/railway.toml` in Railway. No paid service has been provisioned.

Use one replica, one Uvicorn process, one recognition worker and a private persistent volume at `/data`. A process lock prevents a second worker from wiping live files. The entrypoint sets volume ownership, then drops to UID 10001; app code and models are read-only to that account. Plan volume-backed deployment downtime instead of overlapping replicas. Trust forwarded headers only behind Railway's edge; never expose the container port directly to the internet.

Required production variables:

- `APPLE_APP_ID`: verified Apple App ID prefix, followed by `.com.anishtalla.StringMap`.
- `ALLOWED_APP_BUILDS`: comma-separated distributed build numbers.
- `OMR_ENV=production`, `APP_ATTEST_ENVIRONMENT=production`, `OMR_DATA_DIR=/data`.
- `MAX_HOURLY_SCANS_PER_DEVICE=20`, `MAX_DAILY_SCANS=100` by default.

After hosting authorization, generate a real Railway HTTPS domain and set it and `DEVELOPMENT_TEAM` in Xcode's Release configuration. The Release check rejects missing or placeholder values. No Apple private signing key is needed for basic attestation/assertion verification. Real Apple receipts, launch metadata and App Attest on physical distributed builds still require validation. Fraud-metric receipt refresh is not implemented.

## Recognition and lifecycle

The adapter requires one staff per system, retains multiple systems and rejects connected/grand staves instead of dropping them. Stray lower-staff note/rest labels are resolved only with independently detected single staves, a predicted upper treble clef and no predicted lower clef; a warning identifies the uncertain staff. If upstream duplicate-pitch cleanup would lose a note, the original prediction is retained with an explicit unison/duplicate review warning. Export must contain one pitched note per predicted note; a missing predicted pitch must not be silently converted into a rest.

When the model emits no opening clef, time signature or key signature before the first note/rest, a specific review warning identifies that missing context. The app can correct time and key signatures without transposing existing notes. Emitted context may itself be wrong; these checks do not establish visual correctness.

Measure timing is checked without changing any note. An unreadable first prediction or structurally inconsistent output is reread from image rotations of +2 and -2 degrees, If those readings remain rhythmically inconsistent or unreadable, one column-resampling attempt can recover a prematurely shortened staff crop. It requires at least three staffs, 60% agreement on page width within 5%, and a staff shorter than 90% of that width. It extends the crop using image geometry only, retains every predicted note, and replaces a prior reading only if the alternative has no measure-length warnings. If all four readings fail, one final attempt may straighten a tilted page using agreement among long image segments. It requires at least ten segments, 65% agreement within 0.3 degrees and a measured tilt from 0.5 to 12 degrees, expands the canvas without clipping, and limits the prepared image to 18 megapixels. It never replaces a successful reading. There are at most five attempts total. Explicitly unsupported original page layouts fail immediately. Rotation candidate selection uses timing consistency and detector agreement, never reference scores, pitch-range assumptions or octave shifting. Unresolved timing problems are sent to the app as review warnings. Unsupported symbols or unresolved pitches may still require a clearer crop or a supported MusicXML import; recognition is not a completeness guarantee.

- `GET /health`: startup/model readiness, not accuracy certification.
- `GET /recognizer-source.tar.gz`: unauthenticated exact corresponding-source offer for the deployed AGPL recognizer, adapter and build scripts.
- `POST /v1/attest/challenge`: short-lived, one-time challenge.
- `POST /v1/attest/session`: proof to one-hour bearer session.
- `POST /v1/recognitions`: JPEG/PNG, bearer authorization and UUID `Idempotency-Key`; returns 202.
- `GET /v1/recognitions/{id}`: owned status and result.
- `DELETE /v1/recognitions/{id}`: idempotent cancellation; terminates running/queued work and removes results.

Four uploads are bounded to 20 MB each; images must decode as JPEG/PNG and be at most 20 megapixels. At most four jobs are active/queued, with one per device and one recognizer subprocess. Queue age is bounded to two minutes; total processing including retries is bounded to 180 seconds. Cancellation kills the process group. Terminal cleanup removes images/intermediates; startup removes crash leftovers. Results expire after 55 minutes with a 30-second cleanup cadence. Reads/resubmissions enforce expiry too. SQLite secure-delete is enabled. Image/score contents never enter operational logs; disable provider volume snapshots/backups of temporary data. `lifetimeChildPeakRSSBytes` is the service's lifetime child high-water mark, not per-job memory usage.

Image preparation applies EXIF orientation, bounds dimensions to 3000 pixels, strips metadata, and writes JPEG at quality 95 for the pinned recognizer. A lossless-PNG experiment preserved more image detail but worsened provisional note-event accuracy on the external corpus, so it is not the default; the release evidence retains both comparisons. Upload digests/idempotency still use the original request bytes. Prepared images are removed by the same lifecycle cleanup.

## Licenses and reproducibility

HOMR revision `457e7c6518a10ba755db2e60883419e56c4d7369` and the adapter use AGPL-3.0-or-later; see `RECOGNIZER-LICENSE.md` and `COPYING.homr`. The container includes all three CPU model weights pinned in `homr-model-checksums.json`, exact Python dependency versions, full pinned upstream source, service sources, public Apple verification certificates and build instructions. Production refuses to start without the source archive. The iOS app exposes the hosted source offer in Settings.

To reproduce a downloaded source bundle, install its locked requirements with Python 3.12, run `python patch_homr.py` and `python models.py --download`, then the development command above with the extracted directory as `--app-dir`. For the included Dockerfile, place the extracted files in `services/omr/` under a fresh build directory and run the Docker build command from that directory.

## Verification

```sh
services/omr/.venv-homr/bin/python -m pip install -r services/omr/requirements-test.txt
services/omr/.venv-homr/bin/python -m unittest discover -s services/omr
swift build --package-path apps/ios/Packages/StringMapCore
python3 scripts/test-score-playback.py
services/omr/.venv-homr/bin/python services/omr/benchmark.py --output artifacts/homr-results
```

Security tests use a test CA and fake subprocesses; they are not recognition accuracy or real Apple validation. The image benchmark uses actual HTTP recognition, the shipping Swift importer/fingering engine, bundled alphaTab parser and MIDI generator. Original generated engravings and controlled variants are reported separately from real camera photos and genuine handwriting. Independently checked guitar references and successful in-app correction remain required for release.
