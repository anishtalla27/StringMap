"""End-to-end symbolic tests: shipping Swift -> bundled alphaTab -> MIDI events."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
SWIFT=ROOT/'apps/ios/Packages/StringMapCore/.build/debug/stringmap-check'

def note(id,step,octave,duration,extra='',voice='1'):
    return f'<note id="{id}">{extra}<pitch><step>{step}</step><octave>{octave}</octave></pitch><duration>{duration}</duration><voice>{voice}</voice></note>'

def measure(content,number=1):
    return f'<measure number="{number}"><attributes><divisions>12</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>{content}</measure>'

def xml(content):
    return f'<score-partwise><part-list><score-part id="P1"><part-name>Guitar</part-name></score-part></part-list><part id="P1">{content}</part></score-partwise>'

cases={
 'trailing-forward':measure(note('a','E',4,12)+'<forward><duration>36</duration></forward>')+measure(note('b','G',4,12),2),
 'forward-before-backup':measure('<forward><duration>48</duration></forward><backup><duration>48</duration></backup>'+note('a','E',4,12))+measure(note('b','G',4,12),2),
 'partial-silent-measure':measure('<forward><duration>24</duration></forward>')+measure(note('b','G',4,12),2),
 'fractional-trailing-forward':measure(note('a','E',4,4)+'<forward><duration>8</duration></forward>')+measure(note('b','G',4,12),2),
 'sixty-fourth-triplets':measure(''.join(note(str(i),step,4,0.5) for i,step in enumerate(['C','D','E']))),
 'triplet-composite-gap':measure(note('held','E',3,3.5,voice='2')+'<backup><duration>3.5</duration></backup>'+note('melody','G',4,1,voice='1')),
 'guitar-photo':measure(note('low','E',4,48)+note('high','B',4,48,'<chord/>')),
 'guitar-photo-explicit-transpose':measure('<attributes><transpose><chromatic>0</chromatic><octave-change>-1</octave-change></transpose></attributes>'+note('low','E',4,48)+note('high','B',4,48,'<chord/>')),
 'cross-voice-tie':measure(note('a','E',4,12,"<tie type='start'/>",'2')+note('b','E',4,12,"<tie type='stop'/>",'1')),
 'cross-voice-bar-tie':measure(note('a','E',4,48,"<tie type='start'/>",'2'))+measure(note('b','E',4,48,"<tie type='stop'/>",'1'),2),

 'composite-duration':measure(note('held','E',4,30)+'<note id="gap"><rest/><duration>18</duration></note>'),
 'chord-inherited-voice':measure(note('bass','E',3,48,voice='4')+note('high','B',3,48,'<chord/>',voice='4').replace('<voice>4</voice>','')),

 'six-independent-voices':measure('<backup><duration>48</duration></backup>'.join(note('v'+str(i), step, octave,48,voice=str(i+1)) for i,(step,octave) in enumerate([('E',4),('B',3),('G',3),('D',3),('A',2),('E',2)]))),
 'voices':measure(note('bass','E',2,48,voice='2')+'<backup><duration>48</duration></backup>'+note('a','G',3,12)+note('b','A',3,12)+note('c','B',3,24)),
 'ties':measure(note('a','E',3,12,"<tie type='start'/>",'2')+note('b','E',3,12,"<tie type='stop'/>",'2')+'<backup><duration>24</duration></backup>'+note('melody','G',4,24)),
 'partial-chord-sustain':measure(note('bass','E',3,24)+note('high','E',4,12,'<chord/>')+note('next','G',4,12)),
 'leading-gap':measure('<forward><duration>12</duration></forward>'+note('a','E',4,12))+measure(note('b','G',4,12),2),
 'cross-measure-tie':measure(note('a','E',4,12,"<tie type='start'/>"))+measure(note('b','E',4,12,"<tie type='stop'/>"),2),
 'triplet-pickup':measure(''.join(note(str(i),step,4,4,'<time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>') for i,step in enumerate(['C','D','E'])))+measure(note('next','G',4,12),2),
 'silent-first-voice':measure('<note id="rest"><rest/><duration>48</duration><voice>1</voice></note><backup><duration>48</duration></backup>'+note('melody','G',4,48,voice='2')),
 'empty-measure':measure('')+measure(note('b','G',4,12),2),
}
with tempfile.TemporaryDirectory() as directory:
 paths=[]
 for name,content in cases.items():
    p=Path(directory)/(name+'.musicxml');p.write_text(xml(content));paths.append(p)
 paths+=sorted((ROOT/'apps/ios/StringMap/Resources/Samples').glob('*.musicxml'))
 paths+=sorted((ROOT/'artifacts/omr-corpus').glob('*.musicxml'))
 for path in paths:
    raw=subprocess.check_output([str(SWIFT),str(path)]+(['--drop-d'] if path.stem=='drop-d-study' else [])+(['--guitar-photo'] if path.stem.startswith('guitar-photo') else []));result=json.loads(raw)
    assert result['parsed'],(path.name,result)
    explicit_lengths={'trailing-forward':4,'forward-before-backup':4,'partial-silent-measure':2,'fractional-trailing-forward':1}
    if path.stem in explicit_lengths:
        assert result['score']['measures'][0]['minimumDurationQuarters']==explicit_lengths[path.stem],(path.name,result)
    if path.stem.startswith('guitar-photo'):
        assert sorted(p['midi'] for p in result['positions'])==[52,59],(path.name,result)
    checks=json.loads(subprocess.check_output(['node','scripts/verify-score-playback.mjs'],input=raw,cwd=ROOT))
    assert result['tabPlayable'],(path.name,result.get('tabError'))
    assert all(v is True if isinstance(v,bool) else v.get('parsed') and v.get('exactPlayback') and v.get('sourceIdentitiesPreserved') for v in checks.values()),(path.name,checks)
    print(path.name+' PASS')
 print(f'{len(paths)} symbolic scores passed exact MIDI pitch, onset, sustain duration, assignment and string uniqueness checks.')
