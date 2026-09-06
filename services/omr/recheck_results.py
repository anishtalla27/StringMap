"""Revalidate preserved real recognizer outputs after native pipeline changes."""
import hashlib
import json
from pathlib import Path
import subprocess
from benchmark import ROOT,SWIFT,compare,events


def recheck(corpus,results,output):
    output.mkdir(parents=True,exist_ok=True)
    manifest=json.loads((corpus/'manifest.json').read_text());summary=[]
    for case in manifest:
        original=json.loads((results/(case['id']+'.json')).read_text())
        row={'id':case['id'],'recognizedResult':str(results/(case['id']+'.json')),'capture':case['capture'],'swiftSHA256':hashlib.sha256(SWIFT.read_bytes()).hexdigest()}
        if original.get('recognitionStatus')=='completed':
            xml=results/(case['id']+'.musicxml')
            pipeline=json.loads(subprocess.check_output([str(SWIFT),str(xml)],timeout=30))
            assert pipeline['parsed'] and pipeline['tabPlayable'],case['id']
            metrics=compare(case['expected'],events(pipeline['score']))
            checks=json.loads(subprocess.check_output(['node','scripts/verify-score-playback.mjs'],input=json.dumps(pipeline).encode(),cwd=ROOT,timeout=30))
            assert metrics['noteEvent']['f1']==1,case['id']
            for key in ['tabPitchExact','allNotesAssigned','distinctStrings']: assert checks.get(key), (case['id'],checks)
            renderers=[v for v in checks.values() if isinstance(v,dict)]
            assert renderers and all(v.get('exactPlayback') and v.get('sourceIdentitiesPreserved') for v in renderers),(case['id'],checks)
            row.update({'xmlSHA256':hashlib.sha256(xml.read_bytes()).hexdigest(),'metrics':metrics,'checks':checks,'pass':True})
        else:
            assert case['category']=='unsupported',case['id']
            row['expectedRejection']=True
        (output/(case['id']+'.json')).write_text(json.dumps(row,indent=2));summary.append(row)
    return {'images':len(summary),'exactRecognizedImages':sum(r.get('pass',False) for r in summary),'expectedRejections':sum(r.get('expectedRejection',False) for r in summary),'notes':sum(r.get('metrics',{}).get('noteEvent',{}).get('truePositive',0) for r in summary),'chords':sum(r.get('metrics',{}).get('chords',{}).get('complete',0) for r in summary)}


if __name__=='__main__':
    output=ROOT/'artifacts/engine-evaluation/final-pipeline-recheck';results=[]
    for corpus,source in [('omr-corpus','linux-http-ready-v2'),('rhythm-corpus-v2','linux-rhythm-v2')]:
        results.append(recheck(ROOT/'artifacts'/corpus,ROOT/'artifacts/engine-evaluation'/source,output))
    (output/'summary.json').write_text(json.dumps(results,indent=2));print(json.dumps(results))
