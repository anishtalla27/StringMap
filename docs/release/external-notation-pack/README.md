# Supplied notation pack

Local assets: `artifacts/external-notation-pack/StringMap_notation_test_pack/`, extracted from the user-supplied `StringMap_notation_test_pack.zip`. Every supplied checksum was verified. The manifest and original checksums are retained here; binary evaluation assets stay outside the shipping app and Docker build.

The pack's README explicitly identifies the 22 images as **controlled photo simulations**, not camera captures. Fifteen are printed guitar arrangements from Eric Crouch's Guitar Loot, with complete PDF/MXL sources but only the first PDF page depicted. Seven are genuine handwritten general notation from CVC-MUSCIMA/MUSCIMA++, without symbolic references. Do not count them as handwritten guitar qualification or claim measured handwriting accuracy from successful recognition alone.

Sources: https://guitarloot.org.uk/ and https://ufal.mff.cuni.cz/muscima . Guitar Loot requests acknowledgement. MUSCIMA++ is CC BY-NC-SA 4.0; retained for local noncommercial evaluation, not bundled or used for training. Requested citations: Hajič and Pecina, ICDAR 2017, pp. 39–46; Fornés et al., IJDAR 15(3), 2012, pp. 243–251.

Run actual HTTP recognition, Swift import/fingering and alphaTab playback from repository root with the local development service on port 8765:

```
services/omr/.venv-homr/bin/python services/omr/benchmark_external_pack.py --output artifacts/external-pack-final
services/omr/.venv-homr/bin/python services/omr/compare_external_pack.py --results artifacts/external-pack-final
services/omr/.venv-homr/bin/python services/omr/check_external_references.py
```

Run only one HTTP corpus runner at a time: loopback development jobs share an owner. Each run deletes its server jobs and preserves output locally. Comparison uses independent rational MusicXML cursors, with page-one boundaries inferred from reference XML print metadata. These are provisional until PDF page boundaries are independently checked. Raw sounding-pitch metrics and visible-written-pitch metrics are separate; no automatic octave alignment is used. References never enter the recognizer.

The initial exploratory run spans adapter/Swift fixes and is not a frozen release benchmark. Retain it as failure evidence. Final validation must use a fresh output folder, fixed binaries, and source fingerprints.
