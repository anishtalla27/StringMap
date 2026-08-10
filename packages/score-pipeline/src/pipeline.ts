import {
  enumeratePositions,
  optimizeFingering,
  type GuitarPosition,
  type OptimizeOptions,
} from "@stringmap/fingering-engine";
import { generateAlphaTex } from "./alphatex";
import { parseMusicXml, scoreNotes } from "./musicxml";

export function runStructuredScorePipeline(xml: string, options: OptimizeOptions = {}) {
  const score = parseMusicXml(xml);
  const notes = scoreNotes(score);
  const tuning = options.tuning;
  const maxFret = options.maxFret;
  const candidates: Record<string, GuitarPosition[]> = {};
  notes.forEach((note) => {
    candidates[note.id] = enumeratePositions(note.midi, tuning, maxFret);
  });
  const fingering = optimizeFingering(notes, options);
  const alphaTex = generateAlphaTex(score, fingering);
  return { score, candidates, fingering, alphaTex };
}
