import fs from 'node:fs';
import {importer,midi,synth,Settings} from '@coderline/alphatab';
const folder='artifacts/offline-exercise-verification';
const bank=new Uint8Array(fs.readFileSync('apps/ios/StringMap/Resources/AlphaTab/soundfont/stringmap-guitar.sf2'));
const results=[];
for(const entry of JSON.parse(fs.readFileSync('apps/ios/StringMap/Resources/Exercises/catalog.json'))) {
 const input=JSON.parse(fs.readFileSync(`${folder}/${entry.resource}-native.json`));
 const settings=new Settings(),score=importer.ScoreLoader.loadAlphaTex(input.alphaTex,settings);
 const file=new midi.MidiFile(),handler=new midi.AlphaSynthMidiFileHandler(file);
 new midi.MidiFileGenerator(score,settings,handler).generate();
 const options=new synth.AudioExportOptions();options.soundFonts=[bank];
 const exporter=synth.AlphaSynth.prototype.exportAudio.call({},options,file,[],new Map());
 let samples=0,peak=0,energy=0;const chunks=[];
 for(let chunk;(chunk=exporter.render(500));) {
  for(const value of chunk.samples){if(!Number.isFinite(value))throw Error('Non-finite PCM');peak=Math.max(peak,Math.abs(value));energy+=value*value;}
  samples+=chunk.samples.length;chunks.push(chunk.samples);
  if(samples>44100*2*180)throw Error('Synthesis did not finish');
 }
 if(peak<.001||peak>1||energy<=0)throw Error(`${entry.resource}: invalid audio ${peak}`);
 const expectedSeconds=8*entry.beats*4/entry.beatType*60/entry.tempo;
 if(samples/88200<expectedSeconds-0.1||samples/88200>expectedSeconds+5)throw Error('Incorrect audio length');
 const wav=Buffer.alloc(44+samples*2);wav.write('RIFF');wav.writeUInt32LE(wav.length-8,4);wav.write('WAVEfmt ',8);wav.writeUInt32LE(16,16);wav.writeUInt16LE(1,20);wav.writeUInt16LE(2,22);wav.writeUInt32LE(44100,24);wav.writeUInt32LE(176400,28);wav.writeUInt16LE(4,32);wav.writeUInt16LE(16,34);wav.write('data',36);wav.writeUInt32LE(samples*2,40);
 let offset=44;for(const chunk of chunks)for(const value of chunk){wav.writeInt16LE(Math.round(value*32767),offset);offset+=2;}
 fs.writeFileSync(`${folder}/${entry.resource}.wav`,wav);
 results.push({resource:entry.resource,peak,rms:Math.sqrt(energy/samples),seconds:samples/88200,expectedSeconds});
}
fs.writeFileSync(`${folder}/synthesis.json`,JSON.stringify(results,null,2));console.log('PASS: all 18 pieces synthesize finite, non-silent, unclipped PCM of expected duration');
