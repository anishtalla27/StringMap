import type {
  CostWeights,
  GuitarPosition,
  TransitionCostBreakdown,
  UnaryCostBreakdown,
} from "./types";

export function unaryCost(position: GuitarPosition, weights: CostWeights): UnaryCostBreakdown {
  return {
    fretHeight: position.fret * weights.fretHeight,
    openStringPreference: position.fret === 0 ? -weights.openStringPreference : 0,
  };
}

export function transitionCost(
  previous: GuitarPosition,
  current: GuitarPosition,
  weights: CostWeights,
): TransitionCostBreakdown {
  const fretDistance = Math.abs(current.fret - previous.fret);
  const positionDistance = Math.abs(handPosition(current.fret) - handPosition(previous.fret));
  // Open strings still require travel to/from first position, but do not create
  // a left-hand stretch because no finger holds fret zero.
  const excessStretch = previous.fret > 0 && current.fret > 0
    ? Math.max(0, fretDistance - weights.comfortableStretch)
    : 0;

  return {
    fretMovement: fretDistance * weights.fretMovement,
    positionShift: positionDistance * weights.positionShift,
    stringChange: Math.abs(current.string - previous.string) * weights.stringChange,
    largeStretch: excessStretch * excessStretch * weights.largeStretch,
  };
}

export function sumCosts(cost: UnaryCostBreakdown | TransitionCostBreakdown): number {
  return Object.values(cost).reduce((total, component) => total + component, 0);
}

/** First-finger home position for a fretted note. */
function handPosition(fret: number): number {
  return fret === 0 ? 1 : Math.max(1, fret - 1);
}
