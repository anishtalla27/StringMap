// Listening references rendered by the actual bundled synthesizer and SoundFont.
import fs from 'node:fs';
import {importer,midi,synth,Settings} from '@coderline/alphatab';
const directory='artifacts/tutorial-audio';fs.mkdirSync(directory,{recursive:true});
const options=new synth.AudioExportOptions();options.soundFonts=[new Uint8Array(fs.readFileSync('apps/ios/StringMap/Resources/AlphaTab/soundfont/stringmap-guitar.sf2'))];
for(const [name,id,plain] of [['picked-comparison','lesson-22-phrase-1',true],['hammer-ons','lesson-22-phrase-1',false],['pull-offs','lesson-23-phrase-1',false],['connected-group','lesson-23-phrase-2',false],['tie-and-repeated-notes','lesson-14-phrase-2',false]]) {
 const input=JSON.parse(fs.readFileSync(`artifacts/tutorial-verification/${id}-native.json`));
 const settings=new Settings(),score=importer.ScoreLoader.loadAlphaTex(plain?input.alphaTex.replaceAll('{h}',''):input.alphaTex,settings);
 const file=new midi.MidiFile();new midi.MidiFileGenerator(score,settings,new midi.AlphaSynthMidiFileHandler(file)).generate();
 const exp=synth.AlphaSynth.prototype.exportAudio.call({},options,file,[],new Map());const buffers=[];let length=0;
 for(let chunk;(chunk=exp.render(500));){buffers.push(chunk.samples);length+=chunk.samples.length;}
 const data=Buffer.alloc(44+length*2);data.write('RIFF',0);data.writeUInt32LE(data.length-8,4);data.write('WAVEfmt ',8);data.writeUInt32LE(16,16);data.writeUInt16LE(1,20);data.writeUInt16LE(2,22);data.writeUInt32LE(44100,24);data.writeUInt32LE(176400,28);data.writeUInt16LE(4,32);data.writeUInt16LE(16,34);data.write('data',36);data.writeUInt32LE(length*2,40);
 let offset=44;for(const samples of buffers)for(const value of samples){if(!Number.isFinite(value)||Math.abs(value)>1)throw Error('Invalid PCM');data.writeInt16LE(Math.round(value*32767),offset);offset+=2;}
 fs.writeFileSync(`${directory}/${name}.wav`,data);
}
console.log('Exported five synthesized listening references; physical listening remains required.');
