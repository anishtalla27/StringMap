"""Check chord XML and catalog against a separately reviewed guitar harmony plan."""
from pathlib import Path
import json, xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
folder=ROOT/'apps/ios/StringMap/Resources/Songbook'
catalog=json.loads((folder/'catalog.json').read_text())
review=json.loads((ROOT/'docs/release/songbook/harmony-review.json').read_text())
assert len(catalog['songs'])==20
assert set(review['measureChords'])=={s['id'] for s in catalog['songs']}
assert len(list(folder.glob('*.musicxml')))==40
PC={'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}
for song in catalog['songs']:
 arrangement=next(a for a in song['arrangements'] if a['kind']=='chords')
 melody=ET.parse(folder/(song['id']+'-melody.musicxml')).findall('.//part/measure')
 measures=ET.parse(folder/(arrangement['resource']+'.musicxml')).findall('.//part/measure')
 expected=review['measureChords'][song['id']].split()
 assert len(measures)==len(melody)==len(expected)==len(arrangement['chords']),song['id']
 start=0
 for index,(name,measure,melodyMeasure) in enumerate(zip(expected,measures,melody)):
  grip=review['grips'][name]
  length=sum(float(n.findtext('duration')) for n in melodyMeasure.findall('note'))/float(melodyMeasure.findtext('attributes/divisions'))
  notes=measure.findall('note');assert len(notes)==len(grip['midi'])
  division=float(measure.findtext('attributes/divisions'))
  label=arrangement['chords'][index]
  assert label==dict(onset=start,duration=length,root=PC[name[0]],quality='m' if name.endswith('m') else ''),(song['id'],index,label)
  for i,n in enumerate(notes):
   p=n.find('pitch');midi=12*int(p.findtext('octave'))+PC[p.findtext('step')]+int(p.findtext('alter','0'))
   assert midi==grip['midi'][i],(song['id'],index,i)
   assert float(n.findtext('duration'))/division==length
   assert (n.find('chord') is not None)==(i>0)
   assert arrangement['positions'][n.attrib['id']]==dict(string=grip['strings'][i],fret=grip['frets'][i],physicalFret=grip['frets'][i],midi=midi)
   assert arrangement['fingers'][n.attrib['id']]==grip['fingers'][i]
  root=PC[name[0]]
  assert {(n-root)%12 for n in grip['midi']}==({0,3,7} if name.endswith('m') else {0,4,7})
  assert len(set(grip['strings']))==len(grip['strings'])
  start+=length
 assert start==arrangement['durationQuarters']
 print(f'PASS {song["id"]}: complete accompaniment, harmony, rhythm, voiced pitches, string/fret/finger labels')
print('20 accompaniments checked against the independent harmony plan')
