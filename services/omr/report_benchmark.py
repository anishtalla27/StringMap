"""Summarize only observed results; missing cases are never counted as passes."""
import json
from pathlib import Path
import statistics
from datetime import datetime, timezone

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'artifacts/omr-results'


def report(corpus=ROOT/'artifacts/omr-corpus', out=OUT, destination=ROOT/'docs/release/recognition-benchmark.json'):
    manifest=json.loads((corpus/'manifest.json').read_text())
    ids={x['id'] for x in manifest}
    rows=[json.loads(p.read_text()) for p in sorted(out.glob('*.json')) if p.stem in ids]
    groups={}
    for row in rows:
        group=groups.setdefault(row['capture'],{'images':0,'recognitionFailures':0,'importFailures':0,'tabFailures':0,'playbackFailures':0,'seconds':[], 'metrics':{}})
        group['images']+=1;group['seconds'].append(row['seconds'])
        group['recognitionFailures']+=row.get('recognitionStatus')!='completed'
        pipeline=row.get('pipeline',{})
        if row.get('recognitionStatus')=='completed':
            group['importFailures']+=not pipeline.get('parsed',False)
            group['tabFailures']+=not pipeline.get('tabPlayable',False)
            checks=row.get('renderPlayback',{})
            group['playbackFailures']+=not checks or not any(isinstance(v,dict) and v.get('exactPlayback') for v in checks.values())
        for name,metric in row['metrics'].items():
            if name=='chords':
                total=group.setdefault('chords',{'total':0,'complete':0});total['total']+=metric['total'];total['complete']+=metric['complete']
            else:
                total=group['metrics'].setdefault(name,{'truePositive':0,'missing':0,'extra':0})
                for key in total:total[key]+=metric[key]
    for group in groups.values():
        times=group.pop('seconds');group['medianSeconds']=statistics.median(times);group['maxSeconds']=max(times)
        for metric in group['metrics'].values():
            denominator=2*metric['truePositive']+metric['missing']+metric['extra'];metric['f1']=2*metric['truePositive']/denominator if denominator else None
    snapshot={'recordedAt':datetime.now(timezone.utc).isoformat(),'plannedImages':len(manifest),'completedCases':len(rows),'pendingCases':len(manifest)-len(rows),'groups':groups,
        'realCameraImages':sum(x['capture']=='camera' for x in rows),'genuineHandwritingImages':sum(x['category']=='handwriting' for x in rows),'independentlyReviewedReferences':0,
        'correctedInAppAndMatchedReference':0,'releaseTargetsMet':False,
        'buildFingerprints':sorted({x['swiftBinarySHA256'] for x in rows if 'swiftBinarySHA256' in x}),
        'scope':f'{len(manifest)} manifest images; capture categories and recognition failures are reported separately. Generated variants do not count as camera or handwriting coverage.'}
    snapshot['engines']=sorted({x.get('engine','unknown') for x in rows})
    (out/'summary.json').write_text(json.dumps(snapshot,indent=2)+'\n')
    if destination: destination.write_text(json.dumps(snapshot,indent=2)+'\n')
    return snapshot

if __name__=='__main__':
    value=report();print(json.dumps({k:value[k] for k in ['completedCases','plannedImages','pendingCases','releaseTargetsMet']}))
