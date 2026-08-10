import type { CostWeights, FingeringProfileName } from "./types";

/**
 * Profiles share the same transparent cost model and vary only its weights.
 * A larger weight makes the corresponding behavior more expensive.
 */
export const FINGERING_PROFILES: Readonly<Record<FingeringProfileName, CostWeights>> = {
  beginner: {
    fretMovement: 1.1,
    positionShift: 2.2,
    stringChange: 0.8,
    largeStretch: 4.5,
    fretHeight: 0.45,
    openStringPreference: 3.5,
    comfortableStretch: 3,
  },
  balanced: {
    fretMovement: 1.4,
    positionShift: 2.8,
    stringChange: 1.35,
    largeStretch: 3.2,
    fretHeight: 0.2,
    openStringPreference: 1.2,
    comfortableStretch: 4,
  },
  stayInPosition: {
    fretMovement: 2.4,
    positionShift: 6.5,
    stringChange: 1.8,
    largeStretch: 5,
    fretHeight: 0.05,
    openStringPreference: 0.25,
    comfortableStretch: 4,
  },
};
