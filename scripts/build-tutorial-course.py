#!/usr/bin/env python3
"""Original StringMap teaching content; no external arrangements or recordings."""
import json
from pathlib import Path
from xml.sax.saxutils import escape
root=Path('apps/ios/StringMap/Resources/Tutorial');root.mkdir(parents=True,exist_ok=True)
# (string, fret, finger); pitches below are independently checked by course tests.
E=(1,0,0);F=(1,1,1);G=(1,3,3);B=(2,0,0);C=(2,1,1);D=(2,3,3)
g=(3,0,0);a=(3,2,2);d=(4,0,0);e=(4,2,2);f=(4,3,3)
A=(5,0,0);b=(5,2,2);c=(5,3,3);lowE=(6,0,0);lowF=(6,1,1);lowG=(6,3,3)
Em=[(6,0,0),(5,2,2),(4,2,3),(3,0,0),(2,0,0),(1,0,0)]
Am=[(5,0,0),(4,2,2),(3,2,3),(2,1,1),(1,0,0)]
Dm=[(4,0,0),(3,2,1),(2,3,3),(1,2,2)]
def n(p,q=1):return ([p] if isinstance(p,tuple) else p,q)
def line(*ps):return [n(p) for p in ps]
def phrase(name,bars,muted=[]):return dict(name=name,bars=bars,mutedStrings=muted)
rows=[
('Meet your guitar','Find your way around the instrument.',
 'Rest the guitar securely and let your shoulders relax. The thinnest string is 1; the thickest is 6. A fret number names the space just before that metal fret. Touch a string on the diagram to explore it.',
 'Your fretting fingers are index 1, middle 2, ring 3, and little finger 4. Press just behind the fret, not on its wire, using only enough pressure for a clear note. Pick one string gently. Pause if anything hurts.',
 'Play each reference tone and match your open string by ear, or use your own tuner. These are reference pitches, not automatic tuning measurements. Spend a minute finding strings 1 and 6 without rushing.',
 'You can name the strings, find a fret, and identify your fretting fingers.',lowE,
 [phrase('Reference tones',[line(lowE,A,d,g),[n(B,2),n(E,2)]])]),
('Six open strings','Hear the low-to-high string order.',
 'An open string rings without a fretting finger. Read the board from string 6 to string 1: E, A, D, G, B, E. The two E strings share a letter but sound two octaves apart.',
 'The hollow circle means open: no fretting finger. The staff uses guitar treble notation, written one octave above what you hear. A sounding high-string E4 is written as E5; the tab and fretboard still mean the open first string.',
 'Play each open string slowly. Say its name before picking. Then try returning from high E to low E. Repeat twice, leaving time to move your picking hand.',
 'You have connected six open-string sounds to names and locations.',E,
 [phrase('Open-string return',[line(lowE,A,d,g),line(B,E,B,g),line(d,A,lowE,lowE)])]),
('Your first three notes','E, F, and G on string 1.',
 'Keep your hand near the nut. Play E open, F with finger 1 at fret 1, and G with finger 3 at fret 3. This is first position: your fingers work near frets 1–4.',
 'The number inside a lit marker is your finger, not the fret number. Read the fret along the bottom edge. Keep unused fingers relaxed and close to the string.',
 'Step through E, F, G, F. Say each name and place your finger before picking. Repeat the phrase three times, then try finding F with the labels as your guide.',
 'You can play E–F–G without moving your hand out of first position.',F,
 [phrase('First three notes',[line(E,F,G,F),[n(E,2),n(G),n(E)]])]),
('A second string','B, C, and D; then cross to string 1.',
 'String 2 gives you B open, C at fret 1 with finger 1, and D at fret 3 with finger 3. Check the string number before placing the finger.',
 'When crossing strings, move the picking hand only as far as needed. The next-note marker shows where to prepare. Listen for one clear note at a time.',
 'Play B–C–D, then cross to the open E on string 1. Try the return journey slowly. If a string buzzes, reset your fingertip just behind the fret.',
 'You can connect two strings into a short musical phrase.',C,
 [phrase('Across two strings',[line(B,C,D,E),line(G,F,D,C),[n(B,2),n(E,2)]])]),
('Into the middle','G–A and D–E–F on strings 3 and 4.',
 'On string 3, play G open and A at fret 2 with finger 2. On string 4, play D open, E at fret 2 with finger 2, and F at fret 3 with finger 3.',
 'Some note letters appear in several octaves. Use the staff height and string number together. These middle-string notes sound lower than the notes from your first two strings.',
 'Explore each string separately, then join the phrase. Keep the wrist comfortable and let your elbow move naturally as you reach another string.',
 'You have extended your first-position map to the middle strings.',a,
 [phrase('Middle-string answer',[line(d,e,f,g),[n(a,2),n(g),n(e)],[n(d,2),n(g,2)]])]),
('The bass strings','A–B–C and low E–F–G.',
 'String 5: A open, B at fret 2 with finger 2, C at fret 3 with finger 3. String 6: E open, F at fret 1 with finger 1, G at fret 3 with finger 3.',
 'Bass notes use ledger lines below the staff. Follow one line or space at a time rather than guessing from the distance. The board labels always show the sounding octave.',
 'Play the bass phrase at an easy tempo. Compare the low open E with the high open E from lesson 2. Keep the string order clear as you move between strings 6 and 5.',
 'You can locate natural notes across all six strings in first position.',b,
 [phrase('Bass-string path',[line(lowE,lowF,lowG,A),line(b,c,b,A),[n(lowG,2),n(lowE,2)]])]),
('Keep the pulse','Count notes and silence.',
 'In 4/4, count 1–2–3–4 evenly. A quarter note lasts one beat, a half note two beats, and two eighth notes divide one beat: say “1 and”. A rest is counted silence.',
 'The cursor keeps moving during a rest while the sounding marker disappears. Stop the string gently for a rest. BPM here counts quarter-note beats.',
 'Clap the rhythm first. Then play it on open E. Start slowly and count aloud. Try three loops, keeping the rests as steady as the notes.',
 'You can keep counting through long notes, short notes, and rests.',E,
 [phrase('Count and breathe',[[n(E,2),n([],1),n(E,1)],[n(E,.5),n(E,.5),n(E,1),n([],1),n(E,1)]])]),
('Your first melody','Make a small musical sentence.',
 'Use the notes you already know to play this original melody. Read a few notes ahead and prepare the next finger while the current note sounds.',
 'Practice the two bars separately, then join them. Long notes are a chance to breathe and prepare, not a reason to lose the beat.',
 'Choose a tempo where you can stay relaxed. Play one phrase, pause to reset, and play it again. Aim for a steady pulse rather than speed.',
 'You can combine note reading, string changes, and rhythm into a melody.',D,
 [phrase('A small beginning',[line(E,G,F,E),line(D,C,B,C),[n(D,2),n(E),n(F)],[n(E,2),n([],2)]])]),
('E minor','Build your first open chord.',
 'Place finger 2 on string 5 at fret 2 and finger 3 on string 4 at fret 2. Leave strings 6, 3, 2, and 1 open. Together these notes form E minor, written Em.',
 'A chord sounds several notes together. The board shows the whole shape. First check each string separately so you can hear whether every intended note rings.',
 'Choose String check and pick from string 6 to 1. Adjust any muffled note, then choose Chord to hear all six together. Strum gently downward and let it ring for four beats.',
 'You can build Em and check each of its six strings.',(5,2,2),
 [phrase('String check',[[n(p,.5) for p in Em]+[n([],1)]]),phrase('Chord',[[n(Em,4)],[n(Em,4)]])]),
('A minor','Build Am and make a slow chord change.',
 'For Am, place finger 1 on string 2 fret 1, finger 2 on string 4 fret 2, and finger 3 on string 3 fret 2. Play strings 5 through 1; leave string 6 out.',
 'An X means do not play that string. Check the five intended strings individually. Move slowly between Em and Am, letting the shape settle before the next strum.',
 'Practice the Am string check, then the Changes phrase. Strum on beat 1 and use the remaining beats to prepare. Pause between changes whenever you need to.',
 'You can form Am and move between two open chord shapes.',(2,1,1),
 [phrase('String check',[[n(p,.5) for p in Am]+[n([],1.5)]],[6]),phrase('Changes',[[n(Em,4)],[n(Am,4)]])]),
('D major','A smaller chord with a sharp.',
 'Place finger 1 on string 3 fret 2, finger 3 on string 2 fret 3, and finger 2 on string 1 fret 2. Play from open string 4 down toward string 1. Omit strings 5 and 6.',
 'String 1 fret 2 is F-sharp: one fret above F. The sharp sign raises a note by one semitone. This F-sharp helps give D major its sound.',
 'Check the four strings separately. Keep fingertips curved enough for adjacent strings to ring, without forcing your hand. Then try one gentle four-string strum every four beats.',
 'You can read a sharp and form the open D-major shape.',(1,2,2),
 [phrase('String check',[[n(p,1) for p in Dm]],[5,6]),phrase('Chord',[[n(Dm,4)],[n(Dm,4)]],[5,6])]),
('Put it together','Finish with melody and chord changes.',
 'First play the melody using single notes. Then choose Chord changes for a separate Em–Am–D exercise. These are two activities: you do not need to play melody and chords at once.',
 'Review the notes or chord shapes whenever you need to. Progress means taking part and noticing what to practice next, not passing a speed test.',
 'Spend a minute on the melody and a minute changing chords slowly. Finish by choosing one earlier lesson to revisit. A few relaxed minutes repeated regularly are enough for a useful practice session.',
 'You have explored open strings, first-position notes, rhythm, a melody, and three chord shapes. Keep revisiting them at your own pace.',G,
 [phrase('Melody',[line(B,C,D,E),[n(G,2),n(F),n(E)],[n(D,2),n(C),n(B)],[n(E,2),n([],2)]]),phrase('Chord changes',[[n(Em,4)],[n(Am,4)],[n(Dm,4)],[n(Em,4)]])])]
lessons=[];opens=[64,59,55,50,45,40]
for ix,(title,summary,see,detail,practice,recap,target,phrases) in enumerate(rows,1):
 lid=f'lesson-{ix:02d}';resources=[]
 for pi,ph in enumerate(phrases):
  rid=f'{lid}-phrase-{pi+1}';events=[];xml=[]
  for mi,bar in enumerate(ph['bars']):
   assert sum(q for _,q in bar)==4
   onset=0;nodes=[]
   for ei,(positions,q) in enumerate(bar):
    eid=f'{rid}-m{mi+1}-e{ei+1}'
    typ={.5:'eighth',1:'quarter',1.5:'quarter',2:'half',4:'whole'}[q]
    common=f'<duration>{int(q*2)}</duration><voice>1</voice><type>{typ}</type>'+('<dot/>' if q==1.5 else '')
    if not positions:
     nodes.append(f'<note id="{eid}"><rest/>{common}</note>')
     events.append(dict(id=eid,measure=mi,onset=onset,duration=q,string=0,fret=0,finger=0,midi=None))
    for ni,(st,fr,fi) in enumerate(positions):
     nid=f'{eid}-n{ni+1}';midi=opens[st-1]+fr;written=midi+12
     names=['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];name=names[written%12]
     pitch=f'<pitch><step>{name[0]}</step>'+('<alter>1</alter>' if '#' in name else '')+f'<octave>{written//12-1}</octave></pitch>'
     nodes.append(f'<note id="{nid}">'+('<chord/>' if ni else '')+pitch+common+'</note>')
     events.append(dict(id=nid,measure=mi,onset=onset,duration=q,string=st,fret=fr,finger=fi,midi=midi))
    onset+=q
   attrs='<attributes><divisions>2</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef><transpose><octave-change>-1</octave-change></transpose></attributes><direction><sound tempo="60"/></direction>' if mi==0 else ''
   xml.append(f'<measure number="{mi+1}">{attrs}'+''.join(nodes)+'</measure>')
  out='<?xml version="1.0" encoding="utf-8"?><score-partwise version="4.0"><work><work-title>'+escape(title+' — '+ph['name'])+'</work-title></work><identification><creator type="composer">StringMap original exercise</creator></identification><part-list><score-part id="P1"><part-name>Guitar</part-name></score-part></part-list><part id="P1">'+''.join(xml)+'</part></score-partwise>'
  (root/f'{rid}.musicxml').write_text(out)
  resources.append(dict(id=rid,name=ph['name'],events=events,mutedStrings=ph['mutedStrings']))
 lessons.append(dict(id=lid,number=ix,title=title,summary=summary,see=see,detail=detail,practice=practice,recap=recap,quizString=target[0],quizFret=target[1],phrases=resources))
(root/'course.json').write_text(json.dumps(dict(version=1,lessons=lessons),indent=2)+'\n')
(root/'PROVENANCE.md').write_text('# Tutorial content provenance\n\nAll lesson text and musical phrases were authored for StringMap. No third-party arrangements, recordings, illustrations, or lesson scripts are included. Conventional note names, chord shapes, and technique terminology describe musical facts. See scripts/build-tutorial-course.py for editable source. Reference tones use the existing bundled SoundFont.\n')
print(f'Wrote {len(lessons)} lessons and {sum(len(x["phrases"]) for x in lessons)} phrases')
