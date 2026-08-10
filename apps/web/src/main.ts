import * as alphaTab from "@coderline/alphatab";
import type { FingeringProfileName, FingeringResult } from "@stringmap/fingering-engine";
import { runStructuredScorePipeline } from "@stringmap/score-pipeline";
import { SAMPLE_MUSIC_XML } from "./sample";
import "./styles.css";

const PLAYER_STATE_PLAYING = 1;

const canvas = requireElement<HTMLElement>("alpha-tab");
const fileInput = requireElement<HTMLInputElement>("musicxml-file");
const profileSelect = requireElement<HTMLSelectElement>("profile");
const runButton = requireElement<HTMLButtonElement>("run");
const playButton = requireElement<HTMLButtonElement>("play");
const stopButton = requireElement<HTMLButtonElement>("stop");
const status = requireElement<HTMLElement>("status");

const api = new alphaTab.AlphaTabApi(canvas, {
  core: {
    fontDirectory: new URL("/font/", window.location.href).href,
  },
  display: {
    staveProfile: alphaTab.StaveProfile.ScoreTab,
  },
  player: {
    enablePlayer: true,
    soundFont: new URL("/soundfont/sonivox.sf2", window.location.href).href,
    scrollElement: document.querySelector(".notation-viewport") as HTMLElement,
  },
});

let sourceXml = SAMPLE_MUSIC_XML;

api.playerReady.on(() => {
  playButton.disabled = false;
  stopButton.disabled = false;
  status.textContent = "Playback ready";
});
api.playerStateChanged.on(({ state, stopped }) => {
  status.textContent = state === PLAYER_STATE_PLAYING
    ? "Playing synchronized score"
    : stopped ? "Playback ready" : "Playback paused";
});
api.error.on((error) => {
  status.textContent = `alphaTab: ${String(error)}`;
});

fileInput.addEventListener("change", async () => {
  const file = fileInput.files?.[0];
  if (!file) return;
  sourceXml = await file.text();
  status.textContent = `${file.name} loaded`;
  runPipeline();
});
runButton.addEventListener("click", runPipeline);
profileSelect.addEventListener("change", runPipeline);
playButton.addEventListener("click", () => api.playPause());
stopButton.addEventListener("click", () => api.stop());

runPipeline();

function runPipeline(): void {
  try {
    status.textContent = "Optimizing…";
    const profile = profileSelect.value as FingeringProfileName;
    const result = runStructuredScorePipeline(sourceXml, { profile });
    api.tex(result.alphaTex);
    renderTrace(result.fingering);
    requireElement<HTMLElement>("alphatex").textContent = result.alphaTex;
    requireElement<HTMLElement>("total-cost").textContent =
      `${labelProfile(profile)} · total ergonomic cost ${formatCost(result.fingering.totalCost)}`;
    const noteCount = result.fingering.steps.length;
    requireElement<HTMLElement>("score-summary").textContent =
      `${result.score.title} · ${noteCount} note${noteCount === 1 ? "" : "s"} · ${result.score.tempo} BPM`;
    status.textContent = result.score.warnings[0] ?? "Pipeline complete";
  } catch (error) {
    status.textContent = error instanceof Error ? error.message : String(error);
  }
}

function renderTrace(fingering: FingeringResult): void {
  const body = requireElement<HTMLTableSectionElement>("trace");
  body.replaceChildren(...fingering.steps.map((step, index) => {
    const row = document.createElement("tr");
    const transition = step.transition;
    const values = [
      `${index + 1}. MIDI ${step.note.midi}`,
      String(step.candidateCount),
      `S${step.position.string} / F${step.position.fret}`,
      formatCost(transition?.fretMovement ?? 0),
      formatCost(transition?.positionShift ?? 0),
      formatCost(transition?.stringChange ?? 0),
      formatCost(transition?.largeStretch ?? 0),
      formatCost(step.unary.fretHeight),
      formatCost(step.unary.openStringPreference),
      formatCost(step.cumulativeCost),
    ];
    row.append(...values.map((value) => {
      const cell = document.createElement("td");
      cell.textContent = value;
      return cell;
    }));
    return row;
  }));
}

function requireElement<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) throw new Error(`Missing required element #${id}.`);
  return element as T;
}

function formatCost(value: number): string {
  return value.toFixed(2);
}

function labelProfile(profile: FingeringProfileName): string {
  return profile === "stayInPosition" ? "Stay in Position" : `${profile[0]!.toUpperCase()}${profile.slice(1)}`;
}
