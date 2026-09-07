// Structural pipeline qualification only. Historical melody review is independent.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { importer, midi, synth, rendering, Settings, StaveProfile, LayoutMode, NotationElement } from '@coderline/alphatab';
const folder = process.argv[2] ?? 'artifacts/songbook-verification';
const catalog = JSON.parse(fs.readFileSync('apps/ios/StringMap/Resources/Songbook/catalog.json'));
const soundFonts = [new Uint8Array(fs.readFileSync('apps/ios/StringMap/Resources/AlphaTab/soundfont/stringmap-guitar.sf2'))];
const reports = [];
for (const song of catalog.songs) for (const arrangement of song.arrangements) {
  const input = JSON.parse(fs.readFileSync(`${folder}/${arrangement.id}-native.json`));
  const check = spawnSync(process.execPath, ['scripts/verify-score-playback.mjs'], { input: JSON.stringify(input), encoding: 'utf8' });
  assert.equal(check.status, 0, check.stderr);
  const checked = JSON.parse(check.stdout).alphaTex;
  assert.ok(checked.exactPlayback && checked.sourceIdentitiesPreserved, arrangement.id);
  const quarters = input.score.measures.reduce((sum, m) => sum + (Math.max(m.minimumDurationQuarters ?? 0, ...m.events.map(e => { const n = (e.note ?? e.rest)._0; return n.onsetQuarters + n.durationQuarters; })) || m.timeSignature.beats * 4 / m.timeSignature.beatType), 0);
  const tempos = [...new Set([30, 60, 90, 120, input.score.tempo])];
  const speeds = [];
  let baseline;
  for (const bpm of tempos) {
    const settings = new Settings();
    const score = importer.ScoreLoader.loadAlphaTex(input.alphaTex.replace(/\\tempo\s+[\d.]+/g, `\\tempo ${bpm}`), settings);
    const file = new midi.MidiFile(), handler = new midi.AlphaSynthMidiFileHandler(file), notes = [];
    const add = handler.addNote;
    handler.addNote = function (...args) { notes.push(args.slice(1, 5)); return add.apply(this, args); };
    new midi.MidiFileGenerator(score, settings, handler).generate();
    if (baseline) assert.deepEqual(notes, baseline, `${arrangement.id}: tempo changed pitch or ticks`); else baseline = notes;
    const options = new synth.AudioExportOptions(); options.soundFonts = soundFonts;
    const exporter = synth.AlphaSynth.prototype.exportAudio.call({}, options, file, [], new Map());
    let samples = 0, energy = 0, peak = 0;
    const expectedSeconds = quarters * 60 / bpm;
    for (let chunk; (chunk = exporter.render(500));) {
      samples += chunk.samples.length;
      for (const value of chunk.samples) { assert.ok(Number.isFinite(value)); energy += value * value; peak = Math.max(peak, Math.abs(value)); }
      assert.ok(samples / 88200 < expectedSeconds + 10, `${arrangement.id}: export did not end`);
    }
    assert.ok(energy > 0 && peak > 0.001 && peak <= 1, `${arrangement.id}: invalid PCM`);
    const seconds = samples / 88200;
    assert.ok(seconds >= expectedSeconds - .1 && seconds <= expectedSeconds + 5, `${arrangement.id}: ${bpm} BPM duration ${seconds} vs ${expectedSeconds}`);
    speeds.push({ bpm, seconds, expectedSeconds, notes: notes.length, peak });
  }
  for (const [mode, profile] of [['notation', StaveProfile.Score], ['tab', StaveProfile.ScoreTab]]) {
    const settings = new Settings(); settings.core.engine = 'svg'; settings.core.enableLazyLoading = false;
    settings.display.staveProfile = profile; settings.display.layoutMode = LayoutMode.Horizontal;
    for (const element of [NotationElement.EffectDynamics, NotationElement.GuitarTuning, NotationElement.TrackNames]) settings.notation.elements.set(element, false);
    const score = importer.ScoreLoader.loadAlphaTex(input.alphaTex, settings);
    const renderer = new rendering.ScoreRenderer(settings); renderer.width = 1000;
    const parts = []; renderer.partialRenderFinished.on(e => { if (e.renderResult) parts.push(e); });
    renderer.error.on(e => { throw e; }); renderer.renderScore(score, [0]); assert.ok(parts.length);
    const height = Math.max(...parts.map(p => p.y + p.height));
    const width = Math.max(...parts.map(p => p.x + p.width));
    const body = parts.map(p => p.renderResult.replace('<svg ', `<svg x="${p.x}" y="${p.y}" `)).join('\n');
    fs.writeFileSync(`${folder}/${arrangement.id}-${mode}.svg`, `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><rect width="100%" height="100%" fill="white"/>${body}</svg>`);
    renderer.destroy();
  }
  reports.push({ id: arrangement.id, exactMIDI: true, sourceIdentities: true, speeds });
  console.log(`PASS ${arrangement.id}: ${tempos.length} tempos, MIDI, PCM, notation/tab`);
  fs.writeFileSync(`${folder}/structural-summary.json`, JSON.stringify({ scope: 'Structural checks; not historical-source, listening, or UI qualification', arrangements: reports }, null, 2));
}
assert.equal(reports.length, 40);
