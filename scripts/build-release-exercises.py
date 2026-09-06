"""Encode original StringMap exercises; no external score or arrangement is used.

Pitch tokens are sounding scientific pitches. Each bar is explicitly composed
below; duration values are quarter-note units. The manifest is the authored
specification, retained separately from MusicXML for downstream verification.
"""
from pathlib import Path
import json
import xml.etree.ElementTree as E

ROOT = Path(__file__).resolve().parents[1]
# title, learning focus, BPM, time signature, key fifths, four-bar phrase.
STUDIES = [
('Open String Walk', 'Meet all six open strings, one note at a time.', 72, (4,4), 0, 'E2:1 A2:1 D3:1 G3:1 | B3:1 E4:1 B3:1 G3:1 | D3:2 A2:1 E2:1 | G3:1 B3:1 E4:2'),
('First Steps in C', 'Read a first-position C-major melody.', 80, (4,4), 0, 'C3:1 D3:1 E3:1 G3:1 | A3:1 G3:1 E3:2 | F3:1 E3:1 D3:1 G3:1 | E3:1 D3:1 C3:2'),
('Two String Conversation', 'Cross between the top two strings.', 76, (4,4), 0, 'B3:1 D4:1 E4:1 F4:1 | G4:2 E4:1 D4:1 | C4:1 E4:1 F4:1 D4:1 | E4:2 B3:2'),
('Quiet Quarter Notes', 'Keep a steady pulse through repeated notes.', 84, (4,4), 0, 'E3:1 E3:1 G3:1 A3:1 | G3:1 E3:1 D3:1 E3:1 | C3:1 C3:1 D3:1 F3:1 | E3:1 G3:1 C3:2'),
('Room to Breathe', 'Count the rests without losing the beat.', 72, (4,4), 0, 'C3:1 R:1 E3:1 G3:1 | A3:2 R:1 G3:1 | F3:1 E3:1 R:1 D3:1 | C3:2 R:2'),
('Half Note Horizon', 'Hold longer notes for their full value.', 88, (4,4), 0, 'G3:2 E3:2 | A3:2 G3:2 | F3:2 D3:2 | E3:1 D3:1 C3:2'),
('Three Beat Stroll', 'Feel three quarter-note beats in each bar.', 90, (3,4), 0, 'C3:1 E3:1 G3:1 | A3:2 G3:1 | F3:1 D3:1 E3:1 | C3:3'),
('Eighth Note River', 'Play even pairs of eighth notes.', 72, (4,4), 0, 'C3:0.5 D3:0.5 E3:0.5 G3:0.5 A3:1 G3:1 | E3:0.5 F3:0.5 G3:0.5 A3:0.5 G3:2 | F3:0.5 E3:0.5 D3:0.5 C3:0.5 D3:1 G3:1 | E3:1 D3:1 C3:2'),
('Dotted Footsteps', 'Count a dotted quarter followed by an eighth.', 76, (4,4), 0, 'E3:1.5 G3:0.5 A3:1 G3:1 | C4:1.5 B3:0.5 G3:2 | F3:1.5 A3:0.5 G3:1 E3:1 | D3:1.5 E3:0.5 C3:2'),
('G Major Path', 'Find F-sharp in a one-sharp key signature.', 84, (4,4), 1, 'G3:1 A3:1 B3:1 D4:1 | E4:1 D4:1 C4:1 B3:1 | A3:1 F#3:1 G3:1 B3:1 | A3:1 F#3:1 G3:2'),
('D Major Turn', 'Follow F-sharp and C-sharp in D major.', 80, (4,4), 2, 'D3:1 F#3:1 A3:1 B3:1 | A3:2 F#3:1 E3:1 | D3:1 E3:1 F#3:1 C#4:1 | B3:1 A3:1 D3:2'),
('A Minor Lantern', 'Shape a short melody in natural minor.', 78, (4,4), 0, 'A2:1 C3:1 E3:1 G3:1 | A3:2 E3:1 D3:1 | F3:1 E3:1 C3:1 B2:1 | C3:1 B2:1 A2:2'),
('Chromatic Neighbors', 'Read adjacent semitones and accidentals.', 68, (4,4), 0, 'E3:1 F3:1 F#3:1 G3:1 | G#3:1 A3:1 G#3:1 G3:1 | F#3:1 F3:1 E3:1 D#3:1 | E3:2 R:2'),
('Six Eight Drift', 'Group six eighth notes into two dotted-quarter pulses.', 72, (6,8), 0, 'C3:0.5 E3:0.5 G3:0.5 A3:0.5 G3:0.5 E3:0.5 | F3:1.5 G3:1.5 | A3:0.5 G3:0.5 E3:0.5 D3:0.5 E3:0.5 G3:0.5 | C3:3'),
('Bass String Trail', 'Read low notes on the bass strings.', 76, (4,4), 0, 'E2:1 G2:1 A2:1 B2:1 | C3:1 B2:1 A2:2 | D3:1 C3:1 B2:1 G2:1 | A2:1 G2:1 E2:2'),
('Upper String Answer', 'Practice a melody in the upper register.', 82, (4,4), 0, 'E4:1 G4:1 A4:1 G4:1 | F4:1 E4:1 D4:2 | G4:1 F4:1 E4:1 C4:1 | D4:1 F4:1 E4:2'),
('Offbeat Echo', 'Enter after a rest and keep eighth-note timing.', 76, (4,4), 0, 'R:0.5 E3:0.5 G3:1 A3:0.5 G3:0.5 E3:1 | R:0.5 D3:0.5 F3:1 G3:0.5 F3:0.5 D3:1 | E3:0.5 G3:0.5 C4:1 B3:0.5 G3:0.5 E3:1 | D3:1 R:1 C3:2'),
('Small Journey', 'Combine rests, dotted rhythms, and string crossings.', 84, (4,4), 0, 'C3:1 E3:0.5 G3:0.5 A3:1 G3:1 | E3:1.5 F3:0.5 G3:1 R:1 | A3:0.5 G3:0.5 E3:1 D3:1 F3:1 | E3:1 D3:1 C3:2'),
]

def sub(parent, tag, value=None, **attributes):
    node=E.SubElement(parent,tag,attributes)
    if value is not None:node.text=str(value)
    return node

def main():
    folder=ROOT/'apps/ios/StringMap/Resources/Exercises';folder.mkdir(exist_ok=True)
    catalog=[]
    for index,(title,detail,bpm,signature,key,phrase) in enumerate(STUDIES,1):
        resource=f'exercise-{index:02}'
        root=E.Element('score-partwise',version='4.0')
        sub(sub(root,'work'),'work-title',title)
        sub(sub(root,'identification'),'creator','StringMap original exercise',type='composer')
        partlist=sub(root,'part-list');sub(sub(partlist,'score-part',id='P1'),'part-name','Guitar')
        part=sub(root,'part',id='P1'); expected=[]
        # Two explicitly notated passes give beginners time to practice, without repeat-navigation ambiguity.
        bars=phrase.split('|')*2
        for mi,bar in enumerate(bars):
            m=sub(part,'measure',number=str(mi+1)); attrs=sub(m,'attributes')
            sub(attrs,'divisions',4);sub(sub(attrs,'key'),'fifths',key)
            ts=sub(attrs,'time');sub(ts,'beats',signature[0]);sub(ts,'beat-type',signature[1])
            clef=sub(attrs,'clef');sub(clef,'sign','G');sub(clef,'line',2)
            transpose=sub(attrs,'transpose');sub(transpose,'diatonic',0);sub(transpose,'chromatic',0);sub(transpose,'octave-change',-1)
            if mi==0:sub(sub(m,'direction'),'sound',tempo=str(bpm))
            onset=0
            for ni,token in enumerate(bar.split()):
                pitch,duration=token.split(':');duration=float(duration)
                identity=f'{resource}-m{mi+1}-e{ni+1}';n=sub(m,'note',id=identity)
                midi=None
                if pitch=='R':sub(n,'rest')
                else:
                    step=pitch[0];alter=1 if '#' in pitch else 0;octave=int(pitch[-1])
                    midi=12*(octave+1)+{'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}[step]+alter
                    p=sub(n,'pitch');sub(p,'step',step)
                    if alter:sub(p,'alter',alter)
                    sub(p,'octave',octave+1) # conventional guitar notation sounds one octave below written
                sub(n,'duration',int(duration*4));sub(n,'voice',1)
                typ={0.5:'eighth',1:'quarter',1.5:'quarter',2:'half',3:'half',4:'whole'}[duration]
                sub(n,'type',typ)
                if duration in (1.5,3):sub(n,'dot')
                expected.append(dict(id=identity,measureIndex=mi,onsetQuarters=onset,durationQuarters=duration,midi=midi))
                onset+=duration
            assert onset==signature[0]*4/signature[1],(title,mi,onset)
        E.indent(root)
        (folder/f'{resource}.musicxml').write_bytes(E.tostring(root,encoding='utf-8',xml_declaration=True))
        catalog.append(dict(resource=resource,title=title,detail=detail,tempo=bpm,beats=signature[0],beatType=signature[1],keyFifths=key,events=expected))
    (folder/'catalog.json').write_text(json.dumps(catalog,indent=2)+'\n')
    print(f'Encoded {len(catalog)} original exercises, {sum(len(s["events"]) for s in catalog)} events')

if __name__=='__main__':main()
