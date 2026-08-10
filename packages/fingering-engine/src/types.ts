/** MIDI pitches for conventional guitar strings, ordered high E (1) to low E (6). */
export type GuitarTuning = readonly [number, number, number, number, number, number];

export interface FingeringNote {
  id: string;
  midi: number;
  /** A tie destination must remain on the same string and fret as its source. */
  tieStop?: boolean;
}

export interface GuitarPosition {
  /** Conventional guitar string number: 1 is the highest-pitched string. */
  string: number;
  fret: number;
  midi: number;
}

export interface CostWeights {
  fretMovement: number;
  positionShift: number;
  stringChange: number;
  largeStretch: number;
  fretHeight: number;
  openStringPreference: number;
  comfortableStretch: number;
}

export type FingeringProfileName = "beginner" | "balanced" | "stayInPosition";

export interface UnaryCostBreakdown {
  fretHeight: number;
  openStringPreference: number;
}

export interface TransitionCostBreakdown {
  fretMovement: number;
  positionShift: number;
  stringChange: number;
  largeStretch: number;
}

export interface FingeringStep {
  note: FingeringNote;
  position: GuitarPosition;
  candidateCount: number;
  unary: UnaryCostBreakdown;
  transition: TransitionCostBreakdown | null;
  incrementalCost: number;
  cumulativeCost: number;
}

export interface FingeringResult {
  profile: FingeringProfileName | "custom";
  weights: CostWeights;
  totalCost: number;
  steps: FingeringStep[];
}

export interface OptimizeOptions {
  tuning?: GuitarTuning;
  maxFret?: number;
  profile?: FingeringProfileName;
  weights?: CostWeights;
}
