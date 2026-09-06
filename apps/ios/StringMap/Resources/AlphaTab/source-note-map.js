// Keep source identities on the rendered model, including tied sustain segments.
// This is also loaded by the release playback verifier using the same code.
globalThis.StringMapSourceMap = {
  assign(score, sourceNotes) {
    const voices = [...new Set(sourceNotes.map(n => n.voice))].sort();
    const offsets = []; let tick = 0;
    for (const bar of score.masterBars) { offsets.push(tick); tick += bar.calculateDuration(); }
    const covered = new Set(); let unmapped = 0;
    for (const track of score.tracks) for (const staff of track.staves) for (const bar of staff.bars) {
      for (const voice of bar.voices) for (const beat of voice.beats) for (const note of beat.notes) {
        const onset = offsets[bar.index] + beat.playbackStart;
        const candidates = sourceNotes.filter(n => n.midi === note.realValue &&
          (n.voiceIndex ?? voices.indexOf(n.voice)) === voice.index && n.startTick <= onset + 1 && n.endTick > onset + 1);
        note.stringMapSourceIDs = candidates.map(n => n.id);
        for (const n of candidates) covered.add(n.id);
        if (!candidates.length) unmapped++;
      }
    }
    return { coveredIDs: [...covered], unmappedRenderedNotes: unmapped };
  }
};
