# StringMap

StringMap is an umbrella repository for turning structured music scores into playable, explainable guitar tablature. The current milestone implements one complete vertical slice:

```text
MusicXML → normalized score → all string/fret candidates
         → explainable fingering optimization → alphaTex
         → alphaTab notation, tablature, and synchronized playback
```

The implemented scope is deliberately narrow: monophonic melodies, standard six-string tuning (`E2 A2 D3 G3 B3 E4`), and frets 0–20. OCR/OMR, microphone recognition, tutoring, accounts, payments, and mobile apps are not present.

## Workspace

- `packages/fingering-engine` — standalone candidate generation and original dynamic-programming optimizer.
- `packages/score-pipeline` — MusicXML normalization, score orchestration, and alphaTex generation.
- `apps/web` — a thin Vite proof app for importing MusicXML, choosing a profile, inspecting the cost trace, and using alphaTab.

The score model sits between ingestion and fingering. A later OMR adapter should produce the same `NormalizedScore`; it does not need to change the optimizer or renderer.

## Run it

Requires Node.js 20 or newer.

```bash
npm install
npm test
npm run typecheck
npm run dev
```

Open the Vite URL, choose a `.musicxml` or `.xml` file, and select Beginner, Balanced, or Stay in Position. The included known melody loads by default.

Production verification:

```bash
npm run build
```

## Current MusicXML contract

The parser reads the first part of a `score-partwise` document and normalizes pitch, accidentals, measure-local onset, duration, rests, time signatures, tempo, and ties. Multiple parts generate a visible warning.

Unsupported constructs fail explicitly instead of being flattened incorrectly:

- chords and multiple voices (`backup`)
- grace notes
- tuplets
- `score-timewise` documents
- rhythmic values that cannot yet be represented as binary or dotted alphaTex durations

This contract is intentionally honest for the first monophonic milestone. See [ARCHITECTURE.md](./docs/ARCHITECTURE.md) for the extension points and decisions.

## Fingering optimization

For every MIDI note, the engine enumerates every string whose open pitch can reach the note within the fret limit. These candidate sets become layers in a directed acyclic graph. Dynamic programming finds the exact minimum-cost path across the layers in `O(notes × candidates²)` time; a six-string instrument has at most six candidates per layer.

Every result includes:

- chosen string and fret
- number of valid candidates
- each weighted unary and transition cost
- incremental and cumulative costs
- the exact profile weights

This makes a recommendation reproducible and easy to tune. The cost model and profile values are documented in [the engine README](./packages/fingering-engine/README.md).

## References and licensing

alphaTab is used as the notation/tab renderer and synchronized player. MoChord informed the high-level separation between per-shape and transition scoring; StringMap's monophonic graph, cost components, profiles, types, and implementation were written for this repository. Partitura was evaluated but is not currently needed in the browser-first slice. Tably was inspected only; no Tably code was copied because its repository has no license.

See [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md) for details.
