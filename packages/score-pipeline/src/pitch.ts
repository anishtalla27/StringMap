const STEP_TO_SEMITONE: Readonly<Record<string, number>> = {
  C: 0,
  D: 2,
  E: 4,
  F: 5,
  G: 7,
  A: 9,
  B: 11,
};

const PITCH_CLASS_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];

export function musicXmlPitchToMidi(step: string, alter: number, octave: number): number {
  const semitone = STEP_TO_SEMITONE[step.toUpperCase()];
  if (semitone === undefined) throw new Error(`Invalid MusicXML pitch step: ${step}`);
  const midi = (octave + 1) * 12 + semitone + alter;
  if (!Number.isInteger(midi) || midi < 0 || midi > 127) {
    throw new RangeError(`MusicXML pitch ${step}${alter === 0 ? "" : alter}/${octave} is outside MIDI range.`);
  }
  return midi;
}

export function midiToPitch(midi: number): string {
  return `${PITCH_CLASS_NAMES[midi % 12]}${Math.floor(midi / 12) - 1}`;
}
