# Structured-score architecture

## Boundaries

```text
Input adapter               Stable core                  Output adapter
─────────────               ───────────                  ──────────────
MusicXML parser ───────▶ NormalizedScore ───────▶ alphaTex generator
future OMR adapter          │        ▲                  │
future MIDI adapter         ▼        │                  ▼
                     FingeringNote[] │               alphaTab
                            │        │          render + synth + cursor
                            ▼        │
                    candidate layers │
                            │        │
                            ▼        │
                      DP optimizer ──┘
```

`NormalizedScore` is the seam for future image/PDF OMR. OMR should be a new input adapter with confidence/provenance metadata; it should not reach into candidate generation or alphaTab.

## Major decisions

### TypeScript throughout the first slice

The optimizer is small, deterministic, and useful in both browser and server contexts. Keeping it in a framework-free TypeScript workspace package avoids a service boundary for interactive profile changes. Partitura remains a reasonable future backend dependency for richer symbolic analysis, but adding Python now would create operational complexity without improving the monophonic milestone.

### A narrow normalized score

The internal model stores only semantic data this slice uses: measures, time signatures, events, quarter-note durations, MIDI pitch, display pitch, rests, and ties. It deliberately does not mirror all of MusicXML. Unsupported polyphony and rhythm are rejected at the adapter boundary, which prevents plausible-looking but incorrect tablature.

### Exact layered-graph optimization

Greedy choices are locally attractive and globally poor when an upcoming run favors another string. With at most six candidates per note, exact dynamic programming is simpler and fast enough. Each table cell stores total cost and a predecessor; backtracking yields the minimum path and its explanation.

### Separate node and edge costs

Fret height and open-string preference describe a position itself. Movement, position shift, string change, and stretch describe a transition. The split makes weight changes legible and allows every chosen step to expose a reconciled cost breakdown.

### alphaTex as the alphaTab handoff

The optimizer must control the chosen string and fret. Generating alphaTex expresses those exact positions while delegating engraving, MIDI synthesis, playback cursor synchronization, and transport to alphaTab. StringMap does not implement notation rendering or audio synthesis.

## Next structured-score steps

Before OMR work, the pipeline should expand in this order:

1. Tuplet and arbitrary-duration representation.
2. Key signatures, tempo changes, articulations, repeats, and more tie cases.
3. Multi-voice normalization with a clear melody-selection policy.
4. Chord candidate generation and multi-note hand-state optimization.
5. Corpus tests against exported MusicXML from MuseScore, Finale, and Dorico.

OMR can then target the mature normalized-score contract and report uncertainty separately from fingering cost.
