import vm from 'node:vm';import fs from 'node:fs';import assert from 'node:assert/strict';import {StaveProfile,Settings,NotationElement,LayoutMode,ScrollMode} from '@coderline/alphatab';
let api;class Event {on(fn){this.fn=fn}}
class API {constructor(host,initialSettings){this.initialSettings=initialSettings;api=this;for(const k of ['scoreLoaded','renderFinished','playerReady','soundFontLoad','playerStateChanged','playerPositionChanged','error'])this[k]=new Event();this.settings=new Settings();this.settings.fillFromJson(initialSettings);this.score={};this.playbackSpeed=.75;this.timePosition=4000;this.isLooping=true;this.renderCount=0}updateSettings(){}render(){this.renderCount++}}
const context={URL,setTimeout,clearTimeout,alphaTab:{AlphaTabApi:API,StaveProfile,LayoutMode,ScrollMode,NotationElement,PlayerMode:{EnabledSynthesizer:1},PlayerOutputMode:{WebAudioScriptProcessor:1}},document:{getElementById:()=>({}),scrollingElement:{}},window:{location:{href:'http://127.0.0.1/index.html'},addEventListener(){}}};
vm.runInNewContext(fs.readFileSync('apps/ios/StringMap/Resources/AlphaTab/bridge.js','utf8'),context);
for(const show of [false,true,false,true]){context.window.stringMap.setShowTab(show);assert.equal(api.settings.display.staveProfile,show?StaveProfile.ScoreTab:StaveProfile.Score);assert.equal(api.playbackSpeed,.75);assert.equal(api.timePosition,4000);assert.ok(api.isLooping)}
assert.equal(api.renderCount,4);context.window.stringMap.setShowTab(true);assert.equal(api.renderCount,4);
console.log('PASS: notation/tab switching preserves transport state and avoids unnecessary renders');

const settings = new Settings(); settings.fillFromJson(api.initialSettings);
assert.equal(settings.notation.isNotationElementVisible(NotationElement.ScoreTitle),false);
assert.equal(settings.notation.isNotationElementVisible(NotationElement.ScoreSubTitle),false);
console.log("PASS: actual alphaTab settings suppress duplicate native score titles");

// WebKit owns a separate session: configure it before synth creation and restore
// it on resume (for example after an internal microphone session).
const audioSession = {type: 'auto'};
const AudioAPI = class extends API {
  constructor(...args) { assert.equal(audioSession.type, 'playback'); super(...args); }
  playPause() { assert.equal(audioSession.type, 'playback'); return true; }
};
const audioContext = {...context, navigator: {audioSession}, alphaTab: {...context.alphaTab, AlphaTabApi: AudioAPI}, window: {...context.window}};
vm.runInNewContext(fs.readFileSync('apps/ios/StringMap/Resources/AlphaTab/bridge.js','utf8'), audioContext);
audioSession.type = 'auto';
assert.equal(audioContext.window.stringMap.playPause(), true);
console.log('PASS: Web Audio requests media playback before synth creation and on resume; missing API remains supported');

audioContext.window.stringMap.setTutorialPresentation(true);
assert.equal(api.settings.display.layoutMode,LayoutMode.Horizontal);
assert.equal(api.settings.player.scrollMode,ScrollMode.OffScreen);
assert.equal(api.settings.notation.isNotationElementVisible(NotationElement.EffectDynamics),false);
assert.equal(api.timePosition,4000);
assert.equal(api.playbackSpeed,.75);
console.log('PASS: tutorial engraving uses a compact horizontal staff without changing playback');

const motion = {matches: true, addEventListener(_, callback) {this.changed = callback;}};
const motionContext = {...context,matchMedia:()=>motion,window:{...context.window}};
vm.runInNewContext(fs.readFileSync('apps/ios/StringMap/Resources/AlphaTab/bridge.js','utf8'),motionContext);
assert.equal(api.settings.player.enableAnimatedBeatCursor,false);
assert.equal(api.settings.player.scrollSpeed,0);
motion.matches=false;motion.changed();
assert.equal(api.settings.player.enableAnimatedBeatCursor,true);
console.log('PASS: Reduce Motion uses a static cursor and immediate scrolling');

// alphaTab's position event schedules its bound update in two animation frames.
// The bridge must scroll behind that update, not a zero-delay timer using stale bounds.
const frames = [];
const scrollContext = {...context, window: {...context.window, requestAnimationFrame: fn => frames.push(fn)}};
vm.runInNewContext(fs.readFileSync('apps/ios/StringMap/Resources/AlphaTab/bridge.js','utf8'), scrollContext);
scrollContext.window.stringMap.setTutorialPresentation(true);
let beatBounds = 'ending';
let scrolledTo;
api.scrollToCursor = () => { scrolledTo = beatBounds; };
frames.push(() => frames.push(() => { beatBounds = 'beginning'; }));
api.playerPositionChanged.fn({currentTime:0,endTime:30000,originalTempo:84,modifiedTempo:84,isSeek:true});
assert.equal(scrolledTo,undefined);
for (const callback of frames.splice(0)) callback();
assert.equal(scrolledTo,undefined);
for (const callback of frames.splice(0)) callback();
assert.equal(scrolledTo,'beginning');
console.log('PASS: horizontal restart/seek scroll follows the updated beat bounds');
