"""Import complete supplied MusicXML scores, avoiding cut ties at page boundaries."""
import sys,json,subprocess,hashlib
from pathlib import Path
sys.path.insert(0,'services/omr')
from engine_benchmark import unpack_musicxml
from benchmark import SWIFT
import argparse
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=Path('artifacts/external-pack-references'));args=parser.parse_args()
out=args.output;out.mkdir(parents=True,exist_ok=True)
for f in sorted(Path('artifacts/external-notation-pack/StringMap_notation_test_pack/printed_ground_truth').glob('*.mxl')):
 p=out/(f.stem+'.musicxml');p.write_bytes(unpack_musicxml(f))
 r=json.loads(subprocess.check_output([str(SWIFT),str(f)],timeout=120))
 plain=json.loads(subprocess.check_output([str(SWIFT),str(p)],timeout=120))
 assert r == plain, f'Compressed/plain pipeline mismatch: {f.name}'
 r['compressedInput']={'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'plainPipelineIdentical':True}
 if r.get('parsed'):r['playback']=json.loads(subprocess.check_output(['node','scripts/verify-score-playback.mjs'],input=json.dumps(r).encode(),timeout=60))
 (out/(f.stem+'.json')).write_text(json.dumps(r,indent=2));print(f.stem,r.get('parsed'),r.get('error'),r.get('tabPlayable'),r.get('tabError'),flush=True)
