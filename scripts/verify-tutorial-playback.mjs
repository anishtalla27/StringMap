import fs from 'node:fs';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {importer,midi,synth,rendering,Settings,StaveProfile,NotationElement,LayoutMode} from '@coderline/alphatab';
const folder='artifacts/tutorial-verification';
const course=JSON.parse(fs.readFileSync('apps/ios/StringMap/Resources/Tutorial/course.json'));
const bank=new Uint8Array(fs.readFileSync('apps/ios/StringMap/Resources/AlphaTab/soundfont/stringmap-guitar.sf2'));
const report=[];
for(const lesson of course.lessons) for(const phrase of lesson.phrases) {
 const input=JSON.parse(fs.readFileSync(`${folder}/${phrase.id}-native.json`));
 const check=spawnSync(process.execPath,['scripts/verify-score-playback.mjs'],{input:JSON.stringify(input),encoding:'utf8'});
 assert.equal(check.status,0,check.stderr);
 const result=JSON.parse(check.stdout);assert.ok(result.alphaTex.exactPlayback&&result.alphaTex.sourceIdentitiesPreserved,phrase.id);
 fs.writeFileSync(`${folder}/${phrase.id}-playback.json`,JSON.stringify(result));
 const settings=new Settings(),score=importer.ScoreLoader.loadAlphaTex(input.alphaTex,settings);
 const file=new midi.MidiFile(),handler=new midi.AlphaSynthMidiFileHandler(file);
 new midi.MidiFileGenerator(score,settings,handler).generate();
 const options=new synth.AudioExportOptions();options.soundFonts=[bank];
 const exporter=synth.AlphaSynth.prototype.exportAudio.call({},options,file,[],new Map());
 let count=0,peak=0,energy=0;
 for(let chunk;(chunk=exporter.render(500));) {
  for(const v of chunk.samples){assert.ok(Number.isFinite(v));peak=Math.max(peak,Math.abs(v));energy+=v*v;}
  count+=chunk.samples.length;assert.ok(count<88200*120);
 }
 const expectedSeconds=input.score.measures.reduce((sum,m)=>sum+Math.max(m.timeSignature.beats*4/m.timeSignature.beatType,...m.events.map(e=>{const n=(e.note??e.rest)._0;return n.onsetQuarters+n.durationQuarters})),0);
 assert.ok(peak>.001&&peak<=1&&energy>0,`${phrase.id} PCM`);
 assert.ok(count/88200>=expectedSeconds-.1&&count/88200<=expectedSeconds+5);
 for(const [mode,profile] of [['notation',StaveProfile.Score],['tab',StaveProfile.ScoreTab]]) {
  const settings=new Settings();settings.core.engine='svg';settings.core.enableLazyLoading=false;settings.display.staveProfile=profile;settings.display.layoutMode=LayoutMode.Horizontal;settings.display.scale=1.1;for(const e of [NotationElement.EffectDynamics,NotationElement.GuitarTuning,NotationElement.TrackNames])settings.notation.elements.set(e,false);settings.notation.elements.set(NotationElement.ScoreTitle,false);settings.notation.elements.set(NotationElement.ScoreSubTitle,false);
  const renderer=new rendering.ScoreRenderer(settings);renderer.width=900;const parts=[];
  renderer.partialRenderFinished.on(e=>{if(e.renderResult)parts.push({svg:e.renderResult,height:e.height,width:e.width,x:e.x,y:e.y})});
  renderer.error.on(e=>{throw e});renderer.renderScore(score,[0]);assert.ok(parts.length);
  const height=Math.max(...parts.map(p=>p.y+p.height)),width=Math.max(...parts.map(p=>p.x+p.width));
  assert.ok(height + 44 <= (mode === "tab" ? 380 : 280),`${phrase.id}: tutorial staff exceeds its panel (${height})`);
  const body=parts.map(p=>p.svg.replace('<svg ',`<svg x="${p.x}" y="${p.y}" `)).join('\n');
  fs.writeFileSync(`${folder}/${phrase.id}-${mode}.svg`,`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><rect width="100%" height="100%" fill="white"/>${body}</svg>`);
  renderer.destroy();
 }
 // Check that slurs are actual alphaTab connections with distinct articulation,
 // rather than labels attached to ordinary picked notes.
 const slurNotes=input.score.measures.flatMap(m=>m.events.filter(e=>e.note).map(e=>e.note._0)).filter(n=>n.slurFromID);
 let articulationVerified=false;
 if(slurNotes.length) {
  const midiNotes=[];const actualHandler=new midi.AlphaSynthMidiFileHandler(new midi.MidiFile());
  actualHandler.addNote=(track,start,length,key,velocity)=>midiNotes.push({start,key,velocity});
  new midi.MidiFileGenerator(score,settings,actualHandler).generate();
  const plainNotes=[];const plainHandler=new midi.AlphaSynthMidiFileHandler(new midi.MidiFile());
  plainHandler.addNote=(track,start,length,key,velocity)=>plainNotes.push({start,key,velocity});
  const plain=importer.ScoreLoader.loadAlphaTex(input.alphaTex.replaceAll("{h}",""),settings);
  new midi.MidiFileGenerator(plain,settings,plainHandler).generate();
  let offsets=0;const byID=new Map();
  for(const m of input.score.measures){for(const e of m.events)if(e.note){const n=e.note._0;byID.set(n.id,{...n,start:Math.round((offsets+n.onsetQuarters)*960)});}offsets+=m.timeSignature.beats*4/m.timeSignature.beatType;}
  for(const n of slurNotes){const dest=byID.get(n.id),origin=byID.get(n.slurFromID);const a=midiNotes.find(x=>x.start===origin.start&&x.key===origin.midi),b=midiNotes.find(x=>x.start===dest.start&&x.key===dest.midi);assert.ok(a&&b);const picked=plainNotes.find(x=>x.start===dest.start&&x.key===dest.midi);assert.ok(picked);assert.ok(b.velocity<picked.velocity,`${phrase.id}: slur destination articulation`);}
  articulationVerified=true;
 }
 const speeds=[]; let tempoInvariantNotes;

 for(const bpm of [30,60,90,120]) {
  const scaledSettings=new Settings();
  const scaled=importer.ScoreLoader.loadAlphaTex(input.alphaTex.replace(/\\tempo 60\b/,`\\tempo ${bpm}`),scaledSettings);
  const scaledFile=new midi.MidiFile(),scaledHandler=new midi.AlphaSynthMidiFileHandler(scaledFile),actual=[];
  const add=scaledHandler.addNote;
  scaledHandler.addNote=function(track,start,length,key,velocity,channel){actual.push([start,length,key,velocity]);add.call(this,track,start,length,key,velocity,channel)};
  new midi.MidiFileGenerator(scaled,scaledSettings,scaledHandler).generate();
  assert.ok(actual.length>0);
  if(tempoInvariantNotes)assert.deepEqual(actual,tempoInvariantNotes,`${phrase.id}: tempo altered MIDI notes`);
  else tempoInvariantNotes=actual;
  const exp=synth.AlphaSynth.prototype.exportAudio.call({},options,scaledFile,[],new Map());
  let samples=0,power=0;
  for(let chunk;(chunk=exp.render(500));){samples+=chunk.samples.length;for(const v of chunk.samples){assert.ok(Number.isFinite(v));power+=v*v;}assert.ok(samples<88200*180);}
  assert.ok(power>0);assert.ok(samples/88200>=expectedSeconds*60/bpm-.1&&samples/88200<=expectedSeconds*60/bpm+5,`${phrase.id} ${bpm} BPM duration`);
  speeds.push({bpm,seconds:samples/88200,notes:actual.length});
 }
 report.push({articulationVerified,speeds,id:phrase.id,notes:phrase.events.filter(e=>e.midi!==null).length,exactMIDI:true,sourceIDs:true,peak,seconds:count/88200,expectedSeconds});
}
fs.writeFileSync(`${folder}/summary.json`,JSON.stringify(report,null,2));
console.log(`PASS: ${report.length} tutorial phrases; exact MIDI, source IDs, both notation modes and finite non-silent PCM`);
