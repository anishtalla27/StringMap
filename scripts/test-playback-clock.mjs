// Exercise the shipping bridge's clock conversion against alphaTab's actual
// PositionChangedEventArgs contract, without requiring speakers or a browser.
import vm from 'node:vm';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {synth} from '@coderline/alphatab';
let api;const posted=[];
class Event { on(fn){this.fn=fn} }
class API {
 constructor(){ api=this;for(const k of ['scoreLoaded','renderFinished','playerReady','soundFontLoad','playerStateChanged','playerPositionChanged','error'])this[k]=new Event();this.playbackSpeed=1; }
}
const context={URL,clearTimeout,setTimeout,alphaTab:{AlphaTabApi:API,StaveProfile:{ScoreTab:1},PlayerMode:{EnabledSynthesizer:1},PlayerOutputMode:{WebAudioScriptProcessor:1}},document:{getElementById:()=>({}),scrollingElement:{}},window:{location:{href:'http://127.0.0.1/index.html'},webkit:{messageHandlers:{stringMap:{postMessage:p=>posted.push(p)}}},addEventListener(){}}};
vm.runInNewContext(fs.readFileSync('apps/ios/StringMap/Resources/AlphaTab/bridge.js','utf8'),context);
let checks=0;
for(const entry of JSON.parse(fs.readFileSync('apps/ios/StringMap/Resources/Exercises/catalog.json'))) {
 for(const speed of [.25,.5,.75,1,1.5,2]) {
  context.window.stringMap.setSpeed(speed);
  for(const e of entry.events) {
   const beat=e.measureIndex*entry.beats*4/entry.beatType+e.onsetQuarters+e.durationQuarters/2;
   const scoreTime=beat*60000/entry.tempo;
   const args=new synth.PositionChangedEventArgs(scoreTime/speed,32000/speed,beat*960,32000,true,entry.tempo,entry.tempo*speed);
   api.playerPositionChanged.fn(args);
   assert.ok(Math.abs(posted.at(-1).currentTime-scoreTime)<1e-7);
   assert.ok(Math.abs(posted.at(-1).endTime-32000)<1e-7);
   context.window.stringMap.seek(scoreTime);
   assert.ok(Math.abs(api.timePosition-scoreTime/speed)<1e-7);
   checks++;
  }
 }
}
console.log(`PASS: ${checks} bridge position/seek checks across 18 exercises and six speeds`);
