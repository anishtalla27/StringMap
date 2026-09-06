// Inspect the actual bundled alphaTab parser and MIDI generator, not a substitute.
import { importer, midi, Settings } from '@coderline/alphatab';
import fs from 'node:fs';
import '../apps/ios/StringMap/Resources/AlphaTab/source-note-map.js';
const input=JSON.parse(fs.readFileSync(0,'utf8'));
const voiceNames=[...new Set((input.score?.measures ?? []).flatMap(m=>m.events.map(e=>(e.note??e.rest)._0.voice)))].sort();
const expected=[], identities=[], byID=new Map(); let offset=0;
for(const measure of input.score?.measures ?? []) {
  let end=0;
  for(const wrapped of measure.events) {
    const event=(wrapped.note ?? wrapped.rest)._0;
    end=Math.max(end,event.onsetQuarters+event.durationQuarters);
    if(!wrapped.note) continue;
    identities.push({id:event.id,midi:event.midi,voice:event.voice,voiceIndex:input.renderedVoiceIndices?.[event.id] ?? voiceNames.indexOf(event.voice),startTick:Math.round((offset+event.onsetQuarters)*960),endTick:Math.round((offset+event.onsetQuarters+event.durationQuarters)*960)});
    const note={id:event.id,midi:event.midi,onset:offset+event.onsetQuarters,duration:event.durationQuarters};
    if(event.tieFromID && byID.has(event.tieFromID)) {
      const prior=byID.get(event.tieFromID); prior.duration+=note.duration; byID.set(event.id,prior);
    } else {expected.push(note);byID.set(event.id,note)}
  }
  offset+=Math.max(end,measure.minimumDurationQuarters ?? 0) || measure.timeSignature.beats*4/measure.timeSignature.beatType;
}
function comparable(values){return values.map(n=>[n.midi,Math.round(n.onset*960),Math.round(n.duration*960)]).sort((a,b)=>a[1]-b[1]||a[0]-b[0]||a[2]-b[2])}
const checks={};
if(!input.alphaTex && !input.notationAlphaTex) checks.unrenderable={parsed:false,error:input.notationError ?? input.tabError ?? input.error ?? "No renderable notation"};
for(const kind of ['alphaTex','notationAlphaTex']) if(input[kind]) {
  try {
    const settings=new Settings(),score=importer.ScoreLoader.loadAlphaTex(input[kind],settings);
    const mapping=globalThis.StringMapSourceMap.assign(score,identities);
    const identityPreserved=mapping.unmappedRenderedNotes===0 && mapping.coveredIDs.length===identities.length;
    const file=new midi.MidiFile(),handler=new midi.AlphaSynthMidiFileHandler(file),events=[];
    const add=handler.addNote;
    handler.addNote=function(track,start,length,key,velocity,channel){events.push({midi:key,onset:start/960,duration:length/960});add.call(this,track,start,length,key,velocity,channel)};
    new midi.MidiFileGenerator(score,settings,handler).generate();
    const want=comparable(expected),got=comparable(events);
    checks[kind]={parsed:true,notes:events.length,sourceIdentitiesPreserved:identityPreserved,exactPlayback:JSON.stringify(want)===JSON.stringify(got)};
    if(!checks[kind].exactPlayback) Object.assign(checks[kind],{expected:want,actual:got});
  }catch(error){checks[kind]={parsed:false,error:error.message}}
}
if(input.positions){
  const positions=new Map(input.positions.map(p=>[p.id,p])),tuning=input.tuning ?? [64,59,55,50,45,40];
  checks.tabPitchExact=input.positions.every(p=>p.midi===tuning[p.string-1]+p.physicalFret);
  checks.allNotesAssigned=input.positions.length===(input.score?.measures.flatMap(m=>m.events.filter(e=>e.note))??[]).length;
  checks.distinctStrings=expected.every(n=>{
    const active=expected.filter(m=>m.onset<=n.onset+1e-7 && m.onset+m.duration>n.onset+1e-7);
    const strings=active.map(m=>positions.get(m.id)?.string);return strings.every(Boolean)&&new Set(strings).size===strings.length;
  });
}
console.log(JSON.stringify(checks));
