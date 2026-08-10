import { enumeratePositions } from "./candidates";
import { sumCosts, transitionCost, unaryCost } from "./cost";
import { FINGERING_PROFILES } from "./profiles";
import { DEFAULT_MAX_FRET, STANDARD_TUNING } from "./tuning";
import type {
  CostWeights,
  FingeringNote,
  FingeringResult,
  FingeringStep,
  GuitarPosition,
  OptimizeOptions,
  TransitionCostBreakdown,
  UnaryCostBreakdown,
} from "./types";

interface PathCell {
  cost: number;
  previousIndex: number | null;
  unary: UnaryCostBreakdown;
  transition: TransitionCostBreakdown | null;
}

/**
 * Finds the globally cheapest path through the layered candidate graph.
 * Complexity is O(notes × candidates²); a six-string guitar has at most six
 * candidates per note, so exhaustive dynamic programming stays small and exact.
 */
export function optimizeFingering(
  notes: readonly FingeringNote[],
  options: OptimizeOptions = {},
): FingeringResult {
  const profile = options.profile ?? "balanced";
  const weights: CostWeights = options.weights ?? FINGERING_PROFILES[profile];
  const tuning = options.tuning ?? STANDARD_TUNING;
  const maxFret = options.maxFret ?? DEFAULT_MAX_FRET;

  if (notes.length === 0) {
    return { profile: options.weights ? "custom" : profile, weights: { ...weights }, totalCost: 0, steps: [] };
  }

  const layers = notes.map((note) => {
    const candidates = enumeratePositions(note.midi, tuning, maxFret);
    if (candidates.length === 0) {
      throw new RangeError(`Note ${note.id} (MIDI ${note.midi}) is outside this guitar's playable range.`);
    }
    return candidates;
  });

  const table: PathCell[][] = [];
  for (let noteIndex = 0; noteIndex < notes.length; noteIndex += 1) {
    const note = notes[noteIndex]!;
    const candidates = layers[noteIndex]!;
    table[noteIndex] = candidates.map((candidate) => {
      const unary = unaryCost(candidate, weights);
      const unaryTotal = sumCosts(unary);
      if (noteIndex === 0) {
        return { cost: unaryTotal, previousIndex: null, unary, transition: null };
      }

      const previousCandidates = layers[noteIndex - 1]!;
      const previousRow = table[noteIndex - 1]!;
      let best: PathCell = {
        cost: Number.POSITIVE_INFINITY,
        previousIndex: null,
        unary,
        transition: null,
      };

      previousCandidates.forEach((previous, previousIndex) => {
        if (note.tieStop && !samePosition(previous, candidate)) return;
        const transition = transitionCost(previous, candidate, weights);
        const cost = previousRow[previousIndex]!.cost + sumCosts(transition) + unaryTotal;
        if (cost < best.cost) {
          best = { cost, previousIndex, unary, transition };
        }
      });
      return best;
    });
  }

  const lastRow = table.at(-1)!;
  let selectedIndex = indexOfMinimum(lastRow.map((cell) => cell.cost));
  if (!Number.isFinite(lastRow[selectedIndex]!.cost)) {
    throw new Error("No valid fingering path exists; a tie may cross incompatible pitches.");
  }

  const steps: FingeringStep[] = [];
  for (let noteIndex = notes.length - 1; noteIndex >= 0; noteIndex -= 1) {
    const cell = table[noteIndex]![selectedIndex]!;
    const transitionTotal = cell.transition ? sumCosts(cell.transition) : 0;
    steps.unshift({
      note: notes[noteIndex]!,
      position: layers[noteIndex]![selectedIndex]!,
      candidateCount: layers[noteIndex]!.length,
      unary: cell.unary,
      transition: cell.transition,
      incrementalCost: sumCosts(cell.unary) + transitionTotal,
      cumulativeCost: cell.cost,
    });
    selectedIndex = cell.previousIndex ?? 0;
  }

  return {
    profile: options.weights ? "custom" : profile,
    weights: { ...weights },
    totalCost: lastRow[indexOfMinimum(lastRow.map((cell) => cell.cost))]!.cost,
    steps,
  };
}

function samePosition(a: GuitarPosition, b: GuitarPosition): boolean {
  return a.string === b.string && a.fret === b.fret;
}

function indexOfMinimum(values: readonly number[]): number {
  return values.reduce((best, value, index) => (value < values[best]! ? index : best), 0);
}
