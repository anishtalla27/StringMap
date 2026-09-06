import vm from 'node:vm';import fs from 'node:fs';import assert from 'node:assert/strict';import {StaveProfile,Settings,NotationElement} from '@coderline/alphatab';
let api;class Event {on(fn){this.fn=fn}}
class API {constructor(host,initialSettings){this.initialSettings=initialSettings;api=this;for(const k of ['scoreLoaded','renderFinished','playerReady','soundFontLoad','playerStateChanged','playerPositionChanged','error'])this[k]=new Event();this.settings={display:{staveProfile:StaveProfile.ScoreTab}};this.score={};this.playbackSpeed=.75;this.timePosition=4000;this.isLooping=true;this.renderCount=0}updateSettings(){}render(){this.renderCount++}}
const context={URL,setTimeout,clearTimeout,alphaTab:{AlphaTabApi:API,StaveProfile,PlayerMode:{EnabledSynthesizer:1},PlayerOutputMode:{WebAudioScriptProcessor:1}},document:{getElementById:()=>({}),scrollingElement:{}},window:{location:{href:'http://127.0.0.1/index.html'},addEventListener(){}}};
vm.runInNewContext(fs.readFileSync('apps/ios/StringMap/Resources/AlphaTab/bridge.js','utf8'),context);
for(const show of [false,true,false,true]){context.window.stringMap.setShowTab(show);assert.equal(api.settings.display.staveProfile,show?StaveProfile.ScoreTab:StaveProfile.Score);assert.equal(api.playbackSpeed,.75);assert.equal(api.timePosition,4000);assert.ok(api.isLooping)}
assert.equal(api.renderCount,4);context.window.stringMap.setShowTab(true);assert.equal(api.renderCount,4);
console.log('PASS: notation/tab switching preserves transport state and avoids unnecessary renders');

const settings = new Settings(); settings.fillFromJson(api.initialSettings);
assert.equal(settings.notation.isNotationElementVisible(NotationElement.ScoreTitle),false);
assert.equal(settings.notation.isNotationElementVisible(NotationElement.ScoreSubTitle),false);
console.log("PASS: actual alphaTab settings suppress duplicate native score titles");
