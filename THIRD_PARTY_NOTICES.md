# Third-party notices and research references

## Runtime dependencies

### alphaTab

- Project: <https://github.com/CoderLine/alphaTab>
- Inspected revision: `2a460d7`
- Runtime version: `1.8.4`
- Package: `@coderline/alphatab` and `@coderline/alphatab-vite`
- License: Mozilla Public License 2.0
- Use: notation and tablature engraving, SoundFont playback, playback cursor, workers, and Vite integration.

The iOS application bundles alphaTab's published JavaScript distribution, Bravura font, Sonivox SoundFont, and MPL license. The web and iOS implementations are pinned to the same release. The requested `1.9.0` stable package was not published to npm at implementation time, so the latest stable release, `1.8.4`, is pinned reproducibly instead of using a prerelease build.

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

## OMR projects evaluated but not included

### homr

- Project: <https://github.com/liebharc/homr>
- License: GNU Affero General Public License 3.0
- Use: architecture/licensing evaluation only; not a runtime or build dependency.

### Audiveris

- Project: <https://github.com/Audiveris/audiveris>
- License: GNU Affero General Public License 3.0
- Use: architecture/licensing evaluation only; not a runtime or build dependency.

No homr or Audiveris code is copied into StringMap. A future network service using either project requires a separately reviewed AGPL compliance and corresponding-source distribution plan.
