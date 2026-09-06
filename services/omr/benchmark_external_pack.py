"""Local external-pack robustness run. References never enter recognition.

Pack image conditions are simulated, not actual camera captures. General
handwriting lacks symbolic references; recognition success is not accuracy.
Run from repository root. Assets remain in ignored artifacts, outside the app.
"""
import sys,csv,json,time,uuid,base64,hashlib,subprocess,urllib.request
from pathlib import Path
sys.path.insert(0,str(Path('services/omr').resolve()))
from benchmark import SWIFT,ROOT
import argparse
parser=argparse.ArgumentParser()
parser.add_argument('--pack',type=Path,default=Path('artifacts/external-notation-pack/StringMap_notation_test_pack'))
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--match',default='')
parser.add_argument('--url',default='http://127.0.0.1:8765',help='Recognition service under test')
parser.add_argument('--concert-pitch',action='store_true',help='Use only for a page explicitly written at sounding pitch; guitar notation is the app default.')
args=parser.parse_args();p=args.pack;out=args.output;out.mkdir(parents=True,exist_ok=True)
def request(path,data=None,headers=None,method=None):
 with urllib.request.urlopen(urllib.request.Request(args.url.rstrip('/')+path,data,headers or {},method=method),timeout=40) as r:
  b=r.read();return json.loads(b) if b else None
for c in csv.DictReader((p/'manifest.csv').open()):
 name=c['kind']+'-'+Path(c['image']).stem
 if args.match not in name:continue
 target=out/(name+'.json')
 if target.exists():continue
 started=time.monotonic();jid=str(uuid.uuid4());r={'photoPitchConvention':'asEncoded' if args.concert_pitch else 'guitarWritten','recognizerSHA256':hashlib.sha256(Path('services/omr/recognizer.py').read_bytes()).hexdigest(),'serviceFilesSHA256':{n:hashlib.sha256(Path('services/omr',n).read_bytes()).hexdigest() for n in ['production.py','recognizer.py','staff_image.py','page_image.py','score_quality.py','patch_homr.py','symbol_timing.py']},'case':c,'imageSHA256':hashlib.sha256((p/c['image']).read_bytes()).hexdigest()}
 try:
  j=request('/v1/recognitions',(p/c['image']).read_bytes(),{'Content-Type':'image/jpeg','Idempotency-Key':jid},'POST')
  while j['status'] in ('queued','processing'):
   time.sleep(2);j=request('/v1/recognitions/'+jid)
  r['status']=j['status'];r['error']=j.get('error')
  if j['status']=='completed':
   xml=out/(name+'.musicxml');xml.write_bytes(base64.b64decode(j['musicXMLBase64']))
   r['swiftSHA256']=hashlib.sha256(SWIFT.read_bytes()).hexdigest()
   convention=[] if args.concert_pitch else ['--guitar-photo']
   r['pipeline']=json.loads(subprocess.check_output([str(SWIFT),str(xml)]+convention,timeout=120))
   if not r['pipeline'].get('parsed'):
    r['reviewPipeline']=json.loads(subprocess.check_output([str(SWIFT),str(xml),'--for-review']+convention,timeout=120))
   if r['pipeline'].get('parsed'):
    r['playback']=json.loads(subprocess.check_output(['node','scripts/verify-score-playback.mjs'],input=json.dumps(r['pipeline']).encode(),timeout=60))
 except Exception as e:r['error']=str(e)
 finally:
  try:request('/v1/recognitions/'+jid,method='DELETE')
  except Exception as e:r['cleanupError']=str(e)
 r['seconds']=time.monotonic()-started;target.write_text(json.dumps(r,indent=2));print(name,r.get('status'),r.get('error'),round(r['seconds']),flush=True)
