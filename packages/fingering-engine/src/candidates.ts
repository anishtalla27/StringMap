import { DEFAULT_MAX_FRET, STANDARD_TUNING } from "./tuning";
import type { GuitarPosition, GuitarTuning } from "./types";

/** Enumerates every exact string/fret realization of a MIDI pitch. */
export function enumeratePositions(
  midi: number,
  tuning: GuitarTuning = STANDARD_TUNING,
  maxFret = DEFAULT_MAX_FRET,
): GuitarPosition[] {
  if (!Number.isInteger(midi) || midi < 0 || midi > 127) {
    throw new RangeError(`MIDI pitch must be an integer from 0 to 127; received ${midi}.`);
  }
  if (!Number.isInteger(maxFret) || maxFret < 0) {
    throw new RangeError(`maxFret must be a non-negative integer; received ${maxFret}.`);
  }

  return tuning
    .map((openMidi, index) => ({ string: index + 1, fret: midi - openMidi, midi }))
    .filter((position) => position.fret >= 0 && position.fret <= maxFret)
    .sort((a, b) => a.fret - b.fret || a.string - b.string);
}
