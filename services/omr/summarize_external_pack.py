"""Summarize observed external-pack results without treating missing runs as passes."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('results',type=Path);a=p.parse_args()
rows=[json.loads(f.read_text()) for f in a.results.glob('*.json') if f.name not in ('comparison.json','summary.json')]
rows=[r for r in rows if 'case' in r]
groups={}
for r in rows:
 g=groups.setdefault(r['case']['kind'],dict(images=0,recognized=0,imported=0,tabPlayable=0,exactNotationPlayback=0,failures=[]))
 g['images']+=1;g['recognized']+=r.get('status')=='completed';g['imported']+=r.get('pipeline',{}).get('parsed',False);g['tabPlayable']+=r.get('pipeline',{}).get('tabPlayable',False)
 g['exactNotationPlayback']+=r.get('playback',{}).get('notationAlphaTex',{}).get('exactPlayback',False)
 if r.get('error'):g['failures'].append({'image':r['case']['image'],'error':r['error']})
summary={'plannedImages':22,'observedImages':len(rows),'pendingImages':22-len(rows),'groups':groups,'realCameraImages':0,'handwrittenGuitarImages':0,'referenceComparisons':'provisional; see comparison.json','readyForRelease':False}
(a.results/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))
