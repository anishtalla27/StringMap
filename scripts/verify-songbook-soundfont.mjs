// Qualify the bundled instrument's pitch mapping separately from MIDI checks.
// This does not replace listening on a physical iPhone/iPad.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { importer, midi, synth, Settings } from '@coderline/alphatab';
const catalog = JSON.parse(fs.readFileSync('apps/ios/StringMap/Resources/Songbook/catalog.json'));
const pitches = [...new Set(catalog.songs.flatMap(s => s.arrangements.flatMap(a => a.events.flatMap(e => e.midi == null ? [] : [e.midi]))))].sort((a,b)=>a-b);
const sf = fs.readFileSync('apps/ios/StringMap/Resources/AlphaTab/soundfont/stringmap-guitar.sf2');
const results = [];
for (const key of pitches) {
  // One sustained note on a synthetic low-E string, no effects or articulation.
  const score = importer.ScoreLoader.loadAlphaTex(`\\track "Guitar" \\tuning E2 \\instrument acousticguitarnylon \\tempo 60 . ${key-40}.1.1`, new Settings());
  const file = new midi.MidiFile();
  new midi.MidiFileGenerator(score, new Settings(), new midi.AlphaSynthMidiFileHandler(file)).generate();
  const options = new synth.AudioExportOptions(); options.soundFonts = [new Uint8Array(sf)];
  const exporter = synth.AlphaSynth.prototype.exportAudio.call({}, options, file, [], new Map());
  const mono = [];
  for (let chunk; (chunk = exporter.render(500));) {
    // Downsample interleaved 44.1 kHz stereo to mono 11.025 kHz.
    for (let i=0; i<chunk.samples.length; i+=8) mono.push((chunk.samples[i]+chunk.samples[i+1])/2);
  }
  const rate = 11025, frames = [];
  for (const startSeconds of [.15,.3,.5]) {
    const x = mono.slice(Math.round(startSeconds*rate), Math.round(startSeconds*rate)+4096);
    const n = 2048, maxLag = 300, difference = new Float64Array(maxLag+1);
    for (let lag=1;lag<=maxLag;lag++) for(let i=0;i<n;i++) difference[lag]+=(x[i]-x[i+lag])**2;
    let sum=0;
    for(let lag=1;lag<=maxLag;lag++){sum+=difference[lag];difference[lag]=sum ? difference[lag]*lag/sum : 1;}
    let lag=2;
    for(;lag<maxLag;lag++) if(difference[lag]<.15){while(lag+1<maxLag && difference[lag+1]<difference[lag])lag++;break;}
    assert.ok(lag<maxLag, `No stable fundamental for MIDI ${key}`);
    const [a,b,c]=[difference[lag-1],difference[lag],difference[lag+1]];
    const corrected=lag+(a-c)/(2*(a-2*b+c));
    const hz=rate/corrected, expected=440*2**((key-69)/12), cents=1200*Math.log2(hz/expected);
    assert.ok(Math.abs(cents)<35, `MIDI ${key}: ${hz} Hz (${cents} cents)`);
    frames.push({startSeconds,hz,cents});
  }
  results.push({midi:key,expectedHz:440*2**((key-69)/12),frames});
}
const report = {scope:'Synthetic isolated SoundFont pitch mapping; physical listening remains pending', soundFontSHA256:crypto.createHash('sha256').update(sf).digest('hex'), toleranceCents:35, results};
fs.writeFileSync('docs/release/songbook/soundfont-pitch-verification.json',JSON.stringify(report,null,2)+'\n');
console.log(`PASS ${results.length} distinct Songbook pitches, three independent fundamental estimates per pitch`);
