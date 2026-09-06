# Third-party notices and research references

## Runtime dependencies

### alphaTab

- Project: <https://github.com/CoderLine/alphaTab>
- Inspected revision: `2a460d7`
- Runtime version: `1.8.4`
- Package: `@coderline/alphatab` and `@coderline/alphatab-vite`
- License: Mozilla Public License 2.0
- Use: notation and tablature engraving, SoundFont playback, playback cursor, workers, and Vite integration.

The iOS application bundles alphaTab's published JavaScript distribution, Bravura font, a separate CC0 FreePats guitar SoundFont, and MPL license. The web and iOS implementations are pinned to the same release. The published 1.8.4 distribution is pinned reproducibly.

### ZIPFoundation

- Project: <https://github.com/weichsel/ZIPFoundation>
- Runtime version: `0.9.20`, exact revision `22787ffb59de99e5dc1fbfe80b19c97a904ad48d`
- License: MIT (complete text below)
- Use: on-device compressed MusicXML reading. Its bundled privacy manifest declares file timestamp access under reason `0A2A.1`; no tracking or collected data.

MIT License

Copyright (c) 2017-2025 Thomas Zoechling (https://www.peakstep.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Design references

### MoChord

- Project: <https://github.com/Mocha-Yuan/MoChord>
- Inspected revision: `ce9d524`
- License: MIT
- Use: research reference only.

MoChord's `practiceVoicingPath.ts` demonstrated a useful architectural idea: score individual guitar shapes separately from transitions and use dynamic programming to select a smooth sequence. StringMap applies that general idea to a different problem—single-note candidate layers—with an original data model, explicit cost function, five profiles, locks, capo/tuning support, metrics, tie constraints, explanation trace, and implementation. No MoChord source file was copied.

### Partitura

- Project: <https://github.com/CPJKU/partitura>
- Inspected revision: `427ff87`
- License: Apache License 2.0
- Use: evaluated as a possible future server-side symbolic-music layer; not currently included as a dependency.

### Tably

- Project: <https://github.com/e-erdag/Tably>
- Inspected revision: `39ed68c`
- License: none found in the inspected repository.
- Use: inspection only. No code, assets, or text were copied, and Tably is not a dependency.

## OMR dependency and evaluations

### HOMR — hosted recognition

- Project: <https://github.com/liebharc/homr>
- Pinned revision: `457e7c6518a10ba755db2e60883419e56c4d7369`
- License: GNU Affero General Public License 3.0; complete notice in `services/omr/COPYING.homr`.
- Use: CPU inference in the separate Python recognition service. No engine code or model is embedded in the native iOS app.

The original StringMap guitar adapter and timing audit are available under AGPL-3.0-or-later. Every container includes a downloadable `/recognizer-source.tar.gz` with the complete pinned HOMR source, adapter, service code, public verification certificates, dependency lock and model/build instructions. Production requires the bundle. The native Settings screen links to the deployed source offer. Model weights are SHA-256 pinned and installed at build time.

### Earlier engines and research

- [oemer](https://github.com/BreezeWhite/oemer), MIT, revision `dbe2a933d630d0f74805d717960eb259473f5978`: previous unsuccessful benchmark only. Its adapter/patches remain to preserve evidence; production does not install or execute it.
- [Audiveris](https://github.com/Audiveris/audiveris), AGPL-3.0, version 5.11.0: standalone evaluation only. Not included in the app or production container.
- [Zeus](https://github.com/OmniOMR/zeus), MIT code, with the AYCE 2026-08-03 model under CC BY-SA 4.0: handwriting research only. Not included in the app or production container.

Public MusiCorpus/OmniOMR handwriting samples were accessed solely for local research, under their CC BY-NC-SA 4.0 dataset terms. They are retained in ignored research artifacts, never shipped, redistributed with the app, or used to train a production model. A treble-staff piano manuscript pilot is not guitar/handwriting release qualification.

## Bundled font and SoundFont notices

Bravura is copyright 2015 Steinberg Media Technologies GmbH, with Reserved Font Name Bravura, under SIL Open Font License 1.1. The exact license and font log shipped by alphaTab 1.8.4 are bundled with the app and reproduced in Settings.

StringMap classical guitar SoundFont is based on FreePats **Spanish classical guitar, 2019-06-18**, recorded by Roberto <roberto@zenvoid.org> and dedicated by its creator to the public domain under CC0 1.0. Source: https://freepats.zenvoid.org/Guitar/acoustic-guitar.html . The complete CC0 dedication, provenance and exact source/output checksums are bundled with the app.

StringMap's original metronome click and bank mapping adaptation are also dedicated to CC0 1.0. Guitar samples remain unchanged. The source-pinned reproduction script is `scripts/build-guitar-soundfont.py`. The previous SONiVOX/Creative-derived bank is no longer bundled in iOS. The web development reference still uses alphaTab's upstream bank and is not the distributed iOS product.

The unmodified alphaTab source is available at https://github.com/CoderLine/alphaTab/tree/v1.8.4. The app bundles the MPL-2.0 license. StringMap's separate bridge is original application code.

## Recognition build and benchmark tools

HOMR uses NumPy (BSD-3-Clause), ONNX Runtime (MIT), OpenCV (Apache-2.0), Pillow (HPND), RapidOCR (Apache-2.0) and their pinned transitive packages. The recognition API uses FastAPI (MIT), Starlette (BSD-3-Clause), Uvicorn (BSD-3-Clause), cryptography (Apache-2.0 OR BSD-3-Clause), cbor2 (MIT), and asn1crypto (MIT). Transitive package metadata and exact versions are captured in the release evidence. Apple App Attest root certificates are distributed by Apple for signature verification.

Verovio (LGPL-3.0), CairoSVG (LGPL-3.0), and their dependencies are development-only benchmark tools, not iOS or recognition-container dependencies. The generated studies are original StringMap test compositions. Their synthetic variants must never be reported as real camera photographs or genuine handwriting.
