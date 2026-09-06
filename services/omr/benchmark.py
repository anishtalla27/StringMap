"""Actual service -> Swift importer/fingering -> bundled alphaTab MIDI benchmark.

No inferred octave alignment or automatic ground-truth corrections are applied.
Reports synthetic variants separately from real camera/handwriting provenance.
"""
import argparse
import base64
import hashlib
from collections import Counter
import json
from pathlib import Path
import subprocess
import time
import urllib.request
import uuid
from report_benchmark import report

ROOT = Path(__file__).resolve().parents[2]
SWIFT = ROOT / 'apps/ios/Packages/StringMapCore/.build/debug/stringmap-check'


def events(score):
    result=[]; offset=0
    for measure in score['measures']:
        end=0
        for item in measure['events']:
            event=next(iter(item.values()))['_0']
            end=max(end,event['onsetQuarters']+event['durationQuarters'])
            if 'note' in item: result.append({'midi':event['midi'],'onset':offset+event['onsetQuarters'],'duration':event['durationQuarters']})
        offset+=max(end,measure.get('minimumDurationQuarters') or 0) or measure['timeSignature']['beats']*4/measure['timeSignature']['beatType']
    return result


def counts(values, fields):
    return Counter(tuple(round(v[f],6) for f in fields) for v in values)


def compare(expected, actual):
    result={}
    for name,fields in [('pitch',['midi']),('onset',['onset']),('duration',['duration']),('noteEvent',['midi','onset','duration'])]:
        a,b=counts(expected,fields),counts(actual,fields); tp=sum((a&b).values());missing=sum((a-b).values());extra=sum((b-a).values())
        result[name]={'truePositive':tp,'missing':missing,'extra':extra,'f1':2*tp/(2*tp+missing+extra) if 2*tp+missing+extra else 1}
    chords={v['onset'] for v in expected if sum(n['onset']==v['onset'] for n in expected)>1}
    result['chords']={'total':len(chords),'complete':sum(counts([v for v in expected if v['onset']==t],['midi','duration'])==counts([v for v in actual if abs(v['onset']-t)<1e-6],['midi','duration']) for t in chords)}
    return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--url',default='http://127.0.0.1:8765');parser.add_argument('--clean-only',action='store_true');parser.add_argument('--limit',type=int,default=1000)
    parser.add_argument('--corpus',type=Path,default=ROOT/'artifacts/omr-corpus')
    parser.add_argument('--output',type=Path,default=ROOT/'artifacts/omr-results')
    parser.add_argument('--engine',default='homr-457e7c6-stringmap-guitar-v2-cpu')
    parser.add_argument('--loopback-proxy',action='store_true',help='Local-only Docker development forwarding; URL must be loopback.')
    args=parser.parse_args(); corpus=args.corpus;out=args.output;out.mkdir(parents=True,exist_ok=True)
    if args.loopback_proxy:
        from urllib.parse import urlparse
        if urlparse(args.url).hostname not in {'127.0.0.1','localhost','::1'}: parser.error('Proxy testing is loopback-only')
    fingerprints={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__).with_name(n) for n in ['production.py','recognizer.py','staff_image.py','score_quality.py','requirements-lock.txt','homr-model-checksums.json']]}
    manifest=json.loads((corpus/'manifest.json').read_text()); cases=[x for x in manifest if not args.clean_only or x['capture']=='engraved'][:args.limit]
    def request(path, data=None, headers=None, method=None):
        with urllib.request.urlopen(urllib.request.Request(args.url+path,data,{**({'X-Forwarded-For':'127.0.0.1'} if args.loopback_proxy else {}),**(headers or {})},method=method),timeout=40) as response:
            raw=response.read();return json.loads(raw) if raw else None
    # Fail the run before assigning image failures if startup is not complete.
    request('/health')
    for case in cases:
        target=out/(case['id']+'.json')
        if target.exists():continue
        started=time.monotonic();result={'id':case['id'],'category':case['category'],'capture':case['capture'],'engine':args.engine,'metrics':compare(case['expected'],[])}
        result['recognizerFilesSHA256']=fingerprints
        result['imageSHA256']=hashlib.sha256((corpus/case['image']).read_bytes()).hexdigest()
        result['provenance']=case.get('provenance',{})
        pending=out/(case['id']+'.pending')
        job_id=pending.read_text() if pending.exists() else str(uuid.uuid4())
        pending.write_text(job_id)
        (out/'progress.json').write_text(json.dumps({'current':case['id'],'jobID':job_id,'started':time.time()}))
        try:
            job=request('/v1/recognitions',(corpus/case['image']).read_bytes(),{'Content-Type':'image/jpeg','Idempotency-Key':job_id},'POST')
            while job['status'] in {'queued','processing'}:
                time.sleep(3);job=request('/v1/recognitions/'+job_id)
                if time.monotonic()-started>720:raise TimeoutError('Benchmark deadline')
            result['recognitionStatus']=job['status']
            if job['status']=='completed':
                xml=out/(case['id']+'.musicxml');xml.write_bytes(base64.b64decode(job['musicXMLBase64'],validate=True))
                result['swiftBinarySHA256']=hashlib.sha256(SWIFT.read_bytes()).hexdigest()
                result['playbackVerifierSHA256']=hashlib.sha256((ROOT/'scripts/verify-score-playback.mjs').read_bytes()).hexdigest()
                result['sourceMapSHA256']=hashlib.sha256((ROOT/'apps/ios/StringMap/Resources/AlphaTab/source-note-map.js').read_bytes()).hexdigest()
                pipeline=json.loads(subprocess.check_output([str(SWIFT),str(xml)],timeout=120));result['pipeline']=pipeline
                if pipeline['parsed']:
                    result['metrics']=compare(case['expected'],events(pipeline['score']))
                    result['renderPlayback']=json.loads(subprocess.check_output(['node','scripts/verify-score-playback.mjs'],input=json.dumps(pipeline).encode(),cwd=ROOT,timeout=30))
            else:result['error']=job.get('error','Cancelled')
        except Exception as error:result['error']=str(error)
        finally:
            try:request('/v1/recognitions/'+job_id,method='DELETE')
            except Exception:result['deleteFailed']=True
        result['seconds']=round(time.monotonic()-started,2);target.write_text(json.dumps(result,indent=2));pending.unlink(missing_ok=True)
        report(corpus,out,None)
        print(json.dumps({k:result.get(k) for k in ['id','recognitionStatus','error','seconds']}),flush=True)
    print(json.dumps(report(corpus,out,None)),flush=True)


if __name__=='__main__':main()
