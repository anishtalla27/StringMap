"""Compare emitted MusicXML with separately read historical source references.
This script never imports the content generator or derives reference melodies.
"""
from pathlib import Path
import json
import xml.etree.ElementTree as E
ROOT=Path(__file__).resolve().parents[1]
review=json.loads((ROOT/'docs/release/songbook/source-review.json').read_text())
catalog=json.loads((ROOT/'apps/ios/StringMap/Resources/Songbook/catalog.json').read_text())
assert review['reviewStatus']=='melody-reference-review-complete'
assert len(review['sources'])==20
assert set(review['sources'])=={song['id'] for song in catalog['songs']}

def pitch(token):
 if token=='R': return None
 return (int(token[-1])+1)*12 + {'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}[token[0]] + (1 if '#' in token else -1 if 'b' in token else 0)

for slug,reference in review['sources'].items():
 root=E.parse(ROOT/f'apps/ios/StringMap/Resources/Songbook/{slug}-melody.musicxml')
 expected=[]
 for bar in reference['sourceTokens'].split('|'):
  notes=[]
  for token in bar.split():
   name,duration=token.split('/');midi=pitch(name)
   notes.append((None if midi is None else midi+reference['transposeSemitones'],float(duration)*reference.get('durationScale',1)))
  expected.append(notes)
 actual=[]
 for measure in root.findall('.//part/measure'):
  division=float(measure.findtext('attributes/divisions'))
  notes=[]
  for note in measure.findall('note'):
   p=note.find('pitch')
   midi=None if p is None else (int(p.findtext('octave'))+1)*12 + {'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}[p.findtext('step')] + int(p.findtext('alter','0')) - 12
   notes.append((midi,float(note.findtext('duration'))/division))
  actual.append(notes)
 assert len(actual)==len(expected),(slug,'measure count',len(actual),len(expected))
 for i,(got,want) in enumerate(zip(actual,expected),1):assert got==want,(slug,i,got,want)
 print(f'PASS {slug}: historical melody pitches, rests, rhythm and complete declared form')
print(f'{len(review["sources"])} melody references checked. Harmony, runtime, UI and physical audio remain separate checks.')
