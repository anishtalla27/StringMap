# Third-party notices and research references

## Runtime dependencies

### alphaTab

- Project: <https://github.com/CoderLine/alphaTab>
- Package: `@coderline/alphatab` and `@coderline/alphatab-vite`
- License: Mozilla Public License 2.0
- Use: notation and tablature engraving, SoundFont playback, playback cursor, and Vite worker/asset integration.

alphaTab remains an external dependency. Its source was not merged into StringMap.

## Design references

### MoChord

- Project: <https://github.com/Mocha-Yuan/MoChord>
- License: MIT
- Use: research reference only.

MoChord's `practiceVoicingPath.ts` demonstrated a useful architectural idea: score individual guitar shapes separately from transitions and use dynamic programming to select a smooth sequence. StringMap applies that general idea to a different problem—single-note candidate layers—with an original data model, cost function, three profiles, tie constraints, explanation trace, and implementation. No MoChord source file was copied.

### Partitura

- Project: <https://github.com/CPJKU/partitura>
- License: Apache License 2.0
- Use: evaluated as a possible future server-side symbolic-music layer; not currently included as a dependency.

### Tably

- Project: <https://github.com/e-erdag/Tably>
- License: none found in the inspected repository.
- Use: inspection only. No code, assets, or text were copied, and Tably is not a dependency.
