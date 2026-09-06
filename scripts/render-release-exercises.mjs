import fs from 'node:fs';
import {importer, rendering, Settings} from '@coderline/alphatab';
const folder='artifacts/offline-exercise-verification';
for(const entry of JSON.parse(fs.readFileSync('apps/ios/StringMap/Resources/Exercises/catalog.json'))) {
 const input=JSON.parse(fs.readFileSync(`${folder}/${entry.resource}-native.json`));
 const settings=new Settings();settings.core.engine='svg';settings.core.enableLazyLoading=false;
 const score=importer.ScoreLoader.loadAlphaTex(input.alphaTex,settings);
 const renderer=new rendering.ScoreRenderer(settings);renderer.width=1100;
 let parts=[];renderer.partialRenderFinished.on(e=>{if(e.renderResult)parts.push({svg:e.renderResult,width:e.width,height:e.height})});
 renderer.error.on(e=>{throw e});renderer.renderScore(score,[0]);
 if(!parts.length)throw Error('No rendered output');
 const totalHeight=parts.reduce((sum,p)=>sum+p.height,0);let y=0;
 const body=parts.map(p=>{const svg=p.svg.replace('<svg ',`<svg y="${y}" `);y+=p.height;return svg}).join('\n');
 fs.writeFileSync(`${folder}/${entry.resource}.svg`,`<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="${totalHeight}"><rect width="100%" height="100%" fill="white"/>${body}</svg>`);
 renderer.destroy();
}
console.log('Rendered all 18 exercises using the shipping alphaTab engine');
