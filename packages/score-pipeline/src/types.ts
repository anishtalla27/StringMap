export interface TimeSignature {
  beats: number;
  beatType: number;
}

interface BaseEvent {
  id: string;
  measureIndex: number;
  onsetQuarters: number;
  durationQuarters: number;
}

export interface NormalizedNote extends BaseEvent {
  kind: "note";
  midi: number;
  pitch: string;
  tieStart: boolean;
  tieStop: boolean;
}

export interface NormalizedRest extends BaseEvent {
  kind: "rest";
}

export type NormalizedEvent = NormalizedNote | NormalizedRest;

export interface NormalizedMeasure {
  index: number;
  number: string;
  timeSignature: TimeSignature;
  events: NormalizedEvent[];
}

export interface NormalizedScore {
  source: "musicxml";
  title: string;
  partName: string;
  tempo: number;
  measures: NormalizedMeasure[];
  warnings: string[];
}
