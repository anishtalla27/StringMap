// Synthesize real PCM using alphaTab's shipping AlphaSynth and the bundled bank.
import fs from 'node:fs';
import path from 'node:path';
import {midi, synth} from '@coderline/alphatab';
const destination=process.argv[2] ?? 'artifacts/soundfont-evaluation';
fs.mkdirSync(destination,{recursive:true});
const bank=new Uint8Array(fs.readFileSync('apps/ios/StringMap/Resources/AlphaTab/soundfont/stringmap-guitar.sf2'));
function render(program, keys, metronome=0, velocity=90) {
  const file=new midi.MidiFile(), handler=new midi.AlphaSynthMidiFileHandler(file);
  handler.addTimeSignature(0,4,4);handler.addTempo(0,120);handler.addProgramChange(0,0,0,program);
  keys.forEach((keys,i)=>(Array.isArray(keys)?keys:[keys]).forEach(key=>handler.addNote(0,i*1920,1440,key,velocity,0)));
  handler.finishTrack(0,Math.max(3840,keys.length*1920));
  const options=new synth.AudioExportOptions();options.soundFonts=[bank];options.metronomeVolume=metronome;
  const exporter=synth.AlphaSynth.prototype.exportAudio.call({},options,file,[],new Map());
  const buffers=[];let count=0;
  for(let chunk;(chunk=exporter.render(1000));) {buffers.push(chunk.samples);count+=chunk.samples.length;if(count>44100*2*180)throw Error('Export did not terminate');}
  const pcm=new Float32Array(count);let offset=0;for(const buffer of buffers){pcm.set(buffer,offset);offset+=buffer.length;}
  if(!pcm.every(Number.isFinite))throw Error('Non-finite audio');
  const peak=pcm.reduce((a,b)=>Math.max(a,Math.abs(b)),0);
  const rms=Math.sqrt(pcm.reduce((a,b)=>a+b*b,0)/pcm.length);
  if(peak<.001 || peak>1 || rms<.0001)throw Error(`Invalid audio: peak ${peak}, rms ${rms}`);
  for(let i=0;i<keys.length;i++) {
    const samples=pcm.subarray(i*44100*2,(i+1)*44100*2);
    if(Math.max(...samples.subarray(0,50000).map(Math.abs))<.001)throw Error(`Silent MIDI ${keys[i]}`);
  }
  return {pcm,peak,rms,seconds:count/88200};
}
function wav(filename, pcm) {
  const data=Buffer.alloc(44+pcm.length*2);data.write('RIFF',0);data.writeUInt32LE(data.length-8,4);data.write('WAVEfmt ',8);data.writeUInt32LE(16,16);data.writeUInt16LE(1,20);data.writeUInt16LE(2,22);data.writeUInt32LE(44100,24);data.writeUInt32LE(176400,28);data.writeUInt16LE(4,32);data.writeUInt16LE(16,34);data.write('data',36);data.writeUInt32LE(pcm.length*2,40);
  pcm.forEach((v,i)=>data.writeInt16LE(Math.round(Math.max(-1,Math.min(1,v))*32767),44+i*2));fs.writeFileSync(filename,data);
}
const cases=[{id:'guitar-range',program:24,keys:Array.from({length:53},(_,i)=>36+i)},
 {id:'saved-score-compatibility',program:25,keys:[40,45,50,55,59,64,76,88]},
 {id:'six-string-chords',program:24,velocity:127,keys:[[40,47,52,56,59,64],[40,48,52,55,60,64],[43,47,50,55,59,67]]},
 {id:'metronome',program:24,keys:[],metronome:0.75}];
const results=[];
for(const c of cases){const result=render(c.program,c.keys,c.metronome,c.velocity);wav(path.join(destination,c.id+'.wav'),result.pcm);results.push({...c,peak:result.peak,rms:result.rms,seconds:result.seconds,finiteNonSilent:true});}
fs.writeFileSync(path.join(destination,'synthesis-results.json'),JSON.stringify(results,null,2));console.log(JSON.stringify(results));
