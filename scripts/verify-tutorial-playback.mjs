import fs from 'node:fs';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {importer,midi,synth,rendering,Settings,StaveProfile} from '@coderline/alphatab';
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
 const expectedSeconds=Math.max(...phrase.events.map(e=>e.measure*4+e.onset+e.duration));
 assert.ok(peak>.001&&peak<=1&&energy>0,`${phrase.id} PCM`);
 assert.ok(count/88200>=expectedSeconds-.1&&count/88200<=expectedSeconds+5);
 for(const [mode,profile] of [['notation',StaveProfile.Score],['tab',StaveProfile.ScoreTab]]) {
  const settings=new Settings();settings.core.engine='svg';settings.core.enableLazyLoading=false;settings.display.staveProfile=profile;
  const renderer=new rendering.ScoreRenderer(settings);renderer.width=900;const parts=[];
  renderer.partialRenderFinished.on(e=>{if(e.renderResult)parts.push({svg:e.renderResult,height:e.height})});
  renderer.error.on(e=>{throw e});renderer.renderScore(score,[0]);assert.ok(parts.length);
  let y=0;const body=parts.map(p=>{const svg=p.svg.replace('<svg ',`<svg y="${y}" `);y+=p.height;return svg}).join('\n');
  fs.writeFileSync(`${folder}/${phrase.id}-${mode}.svg`,`<svg xmlns="http://www.w3.org/2000/svg" width="900" height="${y}"><rect width="100%" height="100%" fill="white"/>${body}</svg>`);
  renderer.destroy();
 }
 report.push({id:phrase.id,notes:phrase.events.filter(e=>e.midi!==null).length,exactMIDI:true,sourceIDs:true,peak,seconds:count/88200,expectedSeconds});
}
fs.writeFileSync(`${folder}/summary.json`,JSON.stringify(report,null,2));
console.log(`PASS: ${report.length} tutorial phrases; exact MIDI, source IDs, both notation modes and finite non-silent PCM`);
