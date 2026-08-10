import { DOMParser } from "@xmldom/xmldom";
import { midiToPitch, musicXmlPitchToMidi } from "./pitch";
import type {
  NormalizedEvent,
  NormalizedMeasure,
  NormalizedNote,
  NormalizedScore,
  TimeSignature,
} from "./types";

/**
 * Parses the first part of a score-partwise MusicXML document into the small,
 * renderer-neutral score model used by the fingering pipeline.
 *
 * Milestone constraint: chord notes, backups/multiple voices, grace notes, and
 * tuplets are rejected explicitly instead of being silently flattened.
 */
export function parseMusicXml(xml: string): NormalizedScore {
  if (!xml.trim()) throw new Error("MusicXML input is empty.");

  const parserErrors: string[] = [];
  const document = new DOMParser({
    errorHandler: {
      warning: () => undefined,
      error: (message) => parserErrors.push(message),
      fatalError: (message) => parserErrors.push(message),
    },
  }).parseFromString(xml, "application/xml");

  if (parserErrors.length > 0) throw new Error(`Invalid MusicXML: ${parserErrors.join(" ")}`);
  const root = document.documentElement;
  if (!root || nameOf(root) !== "score-partwise") {
    throw new Error("Only score-partwise MusicXML is supported in this milestone.");
  }

  const parts = descendants(root, "part");
  if (parts.length === 0) throw new Error("MusicXML does not contain a part.");
  const part = parts[0]!;
  const warnings = parts.length > 1 ? ["Only the first MusicXML part was imported."] : [];
  const partId = part.getAttribute("id") ?? "";

  let divisions = 1;
  let timeSignature: TimeSignature = { beats: 4, beatType: 4 };
  let tempo: number | null = null;
  let eventCounter = 0;
  const measures: NormalizedMeasure[] = [];

  directChildren(part, "measure").forEach((measureElement, measureIndex) => {
    let cursorDivisions = 0;
    const events: NormalizedEvent[] = [];

    for (const child of directChildren(measureElement)) {
      const childName = nameOf(child);
      if (childName === "attributes") {
        divisions = optionalPositiveNumber(child, "divisions") ?? divisions;
        const time = firstDescendant(child, "time");
        if (time) {
          timeSignature = {
            beats: requiredPositiveNumber(time, "beats"),
            beatType: requiredPositiveNumber(time, "beat-type"),
          };
        }
        continue;
      }

      if (childName === "direction") {
        tempo ??= parseTempo(child);
        continue;
      }

      if (childName === "backup") {
        throw new Error(`Measure ${measureIndex + 1} contains multiple voices; only monophonic MusicXML is supported.`);
      }

      if (childName === "forward") {
        const duration = requiredPositiveNumber(child, "duration");
        events.push({
          id: `rest-${eventCounter++}`,
          kind: "rest",
          measureIndex,
          onsetQuarters: cursorDivisions / divisions,
          durationQuarters: duration / divisions,
        });
        cursorDivisions += duration;
        continue;
      }

      if (childName !== "note") continue;
      if (firstDirectChild(child, "chord")) {
        throw new Error(`Measure ${measureIndex + 1} contains a chord; only monophonic MusicXML is supported.`);
      }
      if (firstDirectChild(child, "grace")) {
        throw new Error(`Measure ${measureIndex + 1} contains a grace note, which is not supported yet.`);
      }
      if (firstDirectChild(child, "time-modification")) {
        throw new Error(`Measure ${measureIndex + 1} contains a tuplet, which is not supported yet.`);
      }

      const duration = requiredPositiveNumber(child, "duration");
      const base = {
        id: `event-${eventCounter++}`,
        measureIndex,
        onsetQuarters: cursorDivisions / divisions,
        durationQuarters: duration / divisions,
      };

      if (firstDirectChild(child, "rest")) {
        events.push({ ...base, kind: "rest" });
      } else {
        const pitchElement = firstDirectChild(child, "pitch");
        if (!pitchElement) throw new Error(`Measure ${measureIndex + 1} contains an unpitched note.`);
        const step = requiredText(pitchElement, "step");
        const alter = optionalFiniteNumber(pitchElement, "alter") ?? 0;
        const octave = requiredFiniteNumber(pitchElement, "octave");
        const midi = musicXmlPitchToMidi(step, alter, octave);
        const ties = descendants(child, "tie").map((tie) => tie.getAttribute("type"));
        const note: NormalizedNote = {
          ...base,
          kind: "note",
          midi,
          pitch: midiToPitch(midi),
          tieStart: ties.includes("start"),
          tieStop: ties.includes("stop"),
        };
        events.push(note);
      }
      cursorDivisions += duration;
    }

    measures.push({
      index: measureIndex,
      number: measureElement.getAttribute("number") ?? String(measureIndex + 1),
      timeSignature: { ...timeSignature },
      events,
    });
  });

  const title = textOf(firstDescendant(root, "work-title"))
    || textOf(firstDescendant(root, "movement-title"))
    || "Untitled score";

  return {
    source: "musicxml",
    title,
    partName: findPartName(root, partId) || "Guitar",
    tempo: tempo ?? 120,
    measures,
    warnings,
  };
}

export function scoreNotes(score: NormalizedScore): NormalizedNote[] {
  return score.measures.flatMap((measure) =>
    measure.events.filter((event): event is NormalizedNote => event.kind === "note"),
  );
}

function parseTempo(direction: Element): number | null {
  const sound = firstDescendant(direction, "sound");
  const soundTempo = sound?.getAttribute("tempo");
  if (soundTempo) return parsePositiveNumber(soundTempo, "tempo");
  const perMinute = firstDescendant(direction, "per-minute");
  return perMinute ? parsePositiveNumber(textOf(perMinute), "tempo") : null;
}

function findPartName(root: Element, partId: string): string {
  const scorePart = descendants(root, "score-part").find((part) => part.getAttribute("id") === partId);
  return scorePart ? textOf(firstDescendant(scorePart, "part-name")) : "";
}

function requiredText(parent: Element, name: string): string {
  const element = firstDescendant(parent, name);
  const value = textOf(element);
  if (!value) throw new Error(`MusicXML element <${name}> is missing or empty.`);
  return value;
}

function requiredPositiveNumber(parent: Element, name: string): number {
  return parsePositiveNumber(requiredText(parent, name), name);
}

function optionalPositiveNumber(parent: Element, name: string): number | null {
  const element = firstDescendant(parent, name);
  return element ? parsePositiveNumber(textOf(element), name) : null;
}

function requiredFiniteNumber(parent: Element, name: string): number {
  return parseFiniteNumber(requiredText(parent, name), name);
}

function optionalFiniteNumber(parent: Element, name: string): number | null {
  const element = firstDescendant(parent, name);
  return element ? parseFiniteNumber(textOf(element), name) : null;
}

function parsePositiveNumber(value: string, label: string): number {
  const parsed = parseFiniteNumber(value, label);
  if (parsed <= 0) throw new Error(`Invalid MusicXML ${label}: ${value}`);
  return parsed;
}

function parseFiniteNumber(value: string, label: string): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) throw new Error(`Invalid MusicXML ${label}: ${value}`);
  return parsed;
}

function textOf(element: Element | null): string {
  return element?.textContent?.trim() ?? "";
}

function nameOf(element: Element): string {
  return element.localName || element.tagName.replace(/^.*:/, "");
}

function directChildren(parent: Element, name?: string): Element[] {
  const result: Element[] = [];
  for (let index = 0; index < parent.childNodes.length; index += 1) {
    const node = parent.childNodes.item(index);
    if (node?.nodeType === 1) {
      const element = node as Element;
      if (!name || nameOf(element) === name) result.push(element);
    }
  }
  return result;
}

function firstDirectChild(parent: Element, name: string): Element | null {
  return directChildren(parent, name)[0] ?? null;
}

function descendants(parent: Element, name: string): Element[] {
  const result: Element[] = [];
  const nodes = parent.getElementsByTagName("*");
  for (let index = 0; index < nodes.length; index += 1) {
    const element = nodes.item(index);
    if (element && nameOf(element) === name) result.push(element);
  }
  return result;
}

function firstDescendant(parent: Element, name: string): Element | null {
  return descendants(parent, name)[0] ?? null;
}
