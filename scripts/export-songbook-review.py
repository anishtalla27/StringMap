"""Build review-only contact sheets from xcresulttool-exported attachments.

Usage: python3 scripts/export-songbook-review.py ATTACHMENTS_DIR iphone|ipad
Requires Pillow. These cropped sheets are never App Store upload images.
"""
from PIL import Image,ImageDraw
from pathlib import Path
import json,re,sys,hashlib
folder=Path(sys.argv[1]);device=sys.argv[2]
if device not in {"iphone", "ipad"}: raise SystemExit("device must be iphone or ipad")
out=Path('docs/release/songbook/visual')/device;out.mkdir(parents=True,exist_ok=True)
manifest=json.loads((folder/'manifest.json').read_text());catalog=json.load(open('apps/ios/StringMap/Resources/Songbook/catalog.json'))
shots={}
for t in manifest:
 if 'EverySongbookArrangementClockSeekingAndFretboard' not in t['testIdentifier']:continue
 for a in t['attachments']:
  if a['exportedFileName'].endswith('.png'):
   name=a['suggestedHumanReadableName'].split('_0_')[0]
   shots[name]=a
records=[]
for song in catalog['songs']:
 for arr in song['arrangements']:
  names=[arr['id']+'-'+x for x in ['beginning','middle','ending']]
  names += sorted([n for n in shots if n.startswith(arr['id']+'-change-')],key=lambda n:int(n.rsplit('-',1)[1]))
  assert all(n in shots for n in names)
  for page in range(0,len(names),3):
   images=[]
   for n in names[page:page+3]:
    src=folder/shots[n]['exportedFileName'];im=Image.open(src).convert('RGB')
    # Contact sheet only: full original retained in xcresult; trim OS chrome.
    w,h=im.size;im=im.crop((0,int(h*.105),w,int(h*.88)))
    im=im.resize((600,round(im.height*600/im.width)))
    tile=Image.new('RGB',(600,im.height+35),'white');tile.paste(im,(0,35));ImageDraw.Draw(tile).text((10,8),n,fill='black')
    images.append(tile)
    records.append({'name':n,'sourceAttachment':shots[n]['exportedFileName'],'sha256':hashlib.sha256(src.read_bytes()).hexdigest()})
   contact=Image.new('RGB',(1800,max(i.height for i in images)),'#ddd')
   for i,im in enumerate(images):contact.paste(im,(i*600,0))
   contact.save(out/f'{arr["id"]}-{page//3+1:02d}.jpg',quality=88)
(out/'manifest.json').write_text(json.dumps({'device':device,'purpose':'Review contact sheets, not App Store upload images. Full original XCTest screenshots remain in the result bundle.','captures':records},indent=2)+'\n')
print(device,len(records),'captures',len(list(out.glob('*.jpg'))),'contact sheets')
