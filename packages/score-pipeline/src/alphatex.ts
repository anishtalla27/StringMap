import type { FingeringResult } from "@stringmap/fingering-engine";
import type { NormalizedEvent, NormalizedScore, TimeSignature } from "./types";

/** Converts the normalized score plus chosen fingerings to alphaTab's alphaTex. */
export function generateAlphaTex(score: NormalizedScore, fingering: FingeringResult): string {
  const byNoteId = new Map(fingering.steps.map((step) => [step.note.id, step]));
  const lines = [
    `\\title "${escapeAlphaTex(score.title)}"`,
    `\\track "${escapeAlphaTex(score.partName)}"`,
    "\\staff{score tabs}",
    "\\tuning E4 B3 G3 D3 A2 E2",
    "\\instrument acousticguitarsteel",
    `\\tempo ${score.tempo}`,
    ".",
  ];

  let previousTime: TimeSignature | null = null;
  for (const measure of score.measures) {
    const tokens: string[] = [];
    if (!sameTime(previousTime, measure.timeSignature)) {
      tokens.push(`\\ts ${measure.timeSignature.beats} ${measure.timeSignature.beatType}`);
      previousTime = measure.timeSignature;
    }
    tokens.push(...measure.events.map((event) => eventToAlphaTex(event, byNoteId)));
    tokens.push("|");
    lines.push(tokens.join(" "));
  }

  return lines.join("\n");
}

function eventToAlphaTex(
  event: NormalizedEvent,
  byNoteId: Map<string, FingeringResult["steps"][number]>,
): string {
  const duration = alphaTexDuration(event.durationQuarters);
  if (event.kind === "rest") return `r.${duration.value}${duration.effect}`;
  const step = byNoteId.get(event.id);
  if (!step) throw new Error(`No optimized fingering exists for note ${event.id}.`);
  const tie = event.tieStop ? "{t}" : "";
  return `${step.position.fret}.${step.position.string}.${duration.value}${duration.effect}${tie}`;
}

function alphaTexDuration(quarters: number): { value: number; effect: string } {
  const candidates = [
    { quarters: 4, value: 1, effect: "" },
    { quarters: 3, value: 2, effect: "{d}" },
    { quarters: 2, value: 2, effect: "" },
    { quarters: 1.5, value: 4, effect: "{d}" },
    { quarters: 1, value: 4, effect: "" },
    { quarters: 0.75, value: 8, effect: "{d}" },
    { quarters: 0.5, value: 8, effect: "" },
    { quarters: 0.375, value: 16, effect: "{d}" },
    { quarters: 0.25, value: 16, effect: "" },
    { quarters: 0.125, value: 32, effect: "" },
  ];
  const match = candidates.find((candidate) => Math.abs(candidate.quarters - quarters) < 1e-7);
  if (!match) {
    throw new Error(`Duration ${quarters} quarter notes cannot yet be represented by this alphaTex generator.`);
  }
  return { value: match.value, effect: match.effect };
}

function sameTime(a: TimeSignature | null, b: TimeSignature): boolean {
  return a?.beats === b.beats && a.beatType === b.beatType;
}

function escapeAlphaTex(value: string): string {
  return value.replaceAll("\\", "\\\\").replaceAll('"', '\\"');
}
