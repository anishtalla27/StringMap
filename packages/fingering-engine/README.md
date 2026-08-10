# `@stringmap/fingering-engine`

An independent, renderer-neutral module for mapping a monophonic MIDI-note sequence onto a six-string guitar.

## Model

Each note receives every exact `(string, fret)` candidate in the configured tuning and fret range. The optimizer treats successive candidate groups as a layered graph and chooses the globally cheapest path with dynamic programming.

The total path cost is the sum of two unary components and four transition components:

```text
unary(position) =
    fret × fretHeight
  - isOpenString × openStringPreference

transition(previous, current) =
    absoluteFretDistance × fretMovement
  + absoluteHandPositionDistance × positionShift
  + absoluteStringDistance × stringChange
  + max(0, frettedDistance - comfortableStretch)² × largeStretch
```

Open strings are treated as first position for travel, but never incur a stretch penalty because the fretting hand does not hold fret zero. A tied destination is constrained to the source string/fret.

## Profiles

Profiles do not change algorithm behavior or add hidden rules; they supply different weights to the same cost function.

| Weight | Beginner | Balanced | Stay in Position |
| --- | ---: | ---: | ---: |
| Fret movement | 1.10 | 1.40 | 2.40 |
| Position shift | 2.20 | 2.80 | 6.50 |
| String change | 0.80 | 1.35 | 1.80 |
| Large stretch | 4.50 | 3.20 | 5.00 |
| Fret height | 0.45 | 0.20 | 0.05 |
| Open-string reward | 3.50 | 1.20 | 0.25 |
| Comfortable stretch | 3 frets | 4 frets | 4 frets |

- **Beginner** strongly rewards open strings and low frets, and penalizes stretches beyond three frets.
- **Balanced** trades open-string convenience against smooth movement and consistent tone.
- **Stay in Position** makes hand-position shifts expensive while largely ignoring absolute fret height.

Callers can also provide a complete custom `CostWeights` object. The returned `FingeringResult.steps` is the inspection trace used by the demo and tests.
