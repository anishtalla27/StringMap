#!/usr/bin/env python3
"""Export passing Release UI screenshots in native App Store dimensions."""
import argparse, hashlib, json, re, shutil, struct, subprocess, tempfile
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('result',type=Path)
parser.add_argument('device',choices=['iphone-6.9','ipad-13'])
parser.add_argument('--out',type=Path,default=Path('docs/store/screenshots/final'))
parser.add_argument('--test-id',help='Export only this independently passing test case')
parser.add_argument('--expected-count',type=int,default=7,help='Expected number of named screenshots in the selected test')
args=parser.parse_args()
assert args.expected_count>0
summary=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(args.result)]))
if args.test_id:
 details=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','test-details','--path',str(args.result),'--test-id',args.test_id]))
 assert details['testResult']=='Passed','The selected screenshot test must pass'
else:
 assert summary['failedTests']==0 and summary['passedTests']>0,'Screenshots require a passing test run'
allowed={'iphone-6.9':{(1260,2736),(1290,2796),(1320,2868)},'ipad-13':{(2064,2752),(2048,2732)}}
with tempfile.TemporaryDirectory(prefix='stringmap-screenshots-') as temporary:
 folder=Path(temporary)
 subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(args.result),'--output-path',str(folder)],check=True,stdout=subprocess.DEVNULL)
 files=[]
 for test in json.loads((folder/'manifest.json').read_text()):
  if args.test_id and test['testIdentifier']!=args.test_id:continue
  for attachment in test['attachments']:
   name=attachment['suggestedHumanReadableName']
   match=re.search(r'store-(\d\d-[a-z-]+)',name)
   if not match:continue
   assert not attachment['isAssociatedWithFailure']
   source=folder/attachment['exportedFileName'];data=source.read_bytes()
   assert data[:8]==b'\x89PNG\r\n\x1a\n','Expected unedited PNG screenshot'
   width,height=struct.unpack('>II',data[16:24]);color_type=data[25]
   assert (width,height) in allowed[args.device],(width,height)
   assert color_type in (0,2,6),'Unexpected screenshot encoding'
   # XCTest PNGs can include an opaque alpha channel. Encode as JPEG for
   # App Store upload; never crop, resize, retouch, or synthesize screen content.
   dest=args.out/args.device/(match.group(1)+('.jpg' if color_type==6 else '.png'));dest.parent.mkdir(parents=True,exist_ok=True)
   if color_type==6:
    subprocess.run(['sips','-s','format','jpeg','-s','formatOptions','95',str(source),'--out',str(dest)],check=True,stdout=subprocess.DEVNULL)
    assert dest.read_bytes().startswith(b'\xff\xd8')
   else: shutil.copy2(source,dest)
   files.append(dict(file=str(dest.relative_to(args.out)),width=width,height=height,sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),sourceSHA256=hashlib.sha256(data).hexdigest(),sourceAttachment=name))
 assert len(files)==args.expected_count,f'Expected {args.expected_count} final screens, found {len(files)}'
 manifest_path=args.out/'manifest.json'
 manifest=json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
 manifest[args.device]=dict(configuration='Release',resultBundle=str(args.result),selectedTest=args.test_id,screenshots=sorted(files,key=lambda x:x['file']))
 manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
 print(f'Exported {len(files)} native {args.device} screenshots with validated dimensions and no alpha.')
