#!/usr/bin/env python3
"""Original continuation course. Called after the preserved foundation generator."""
import json
from pathlib import Path
from xml.sax.saxutils import escape
root=Path('apps/ios/StringMap/Resources/Tutorial')
course=json.loads((root/'course.json').read_text());course['lessons']=course['lessons'][:12]
opens=[64,59,55,50,45,40]
E=(1,0,0);F=(1,1,1);G=(1,3,3);B=(2,0,0);C=(2,1,1);D=(2,3,3)
g=(3,0,0);a=(3,2,2);e=(4,2,2);f=(4,3,3);d=(4,0,0);c=(5,3,3)
# Explicit event positions and timing; sustained notes use independent voices.
def ev(p,q=1,**kw):return dict(p=p,q=q,**kw)
def bar(*items):return list(items)
def seq(*ps,q=1):return [ev(p,q) for p in ps]
def ph(name,bars,beats=4,beatType=4,**kw):return dict(name=name,bars=bars,beats=beats,beatType=beatType,**kw)
def quiz(question,correct,wrong,hint):return dict(question=question,answers=[correct,*wrong],correctIndex=0,hint=hint)
def row(title,summary,see,detail,practice,recap,target,phrases,question,**kw):return dict(title=title,summary=summary,see=see,detail=detail,practice=practice,recap=recap,quizString=target[0],quizFret=target[1],phrases=phrases,question=question,**kw)
def picking(ps):return [ev(p,.5,cue='Pick down' if i%2==0 else 'Pick up') for i,p in enumerate(ps)]
pent=[(6,5,1),(6,8,4),(5,5,1),(5,7,3),(4,5,1),(4,7,3),(3,5,1),(3,7,3),(2,5,1),(2,8,4),(1,5,1),(1,8,4)]
Dtri=[(3,2,1),(2,3,3),(1,2,2)];Dmtri=[(3,2,2),(2,3,3),(1,1,1)]
Atri=[(3,2,1),(2,2,2),(1,0,0)];Amtri=[(3,2,2),(2,1,1),(1,0,0)]
Ftri=[(3,2,2),(2,1,1),(1,1,1)]
def fingerbar(bass,upper):
 # Four voices; each upper note sustains to the barline, with repeated
 # strokes ending the preceding note on that same string.
 ps=[bass,*upper,bass,*upper]
 return [ev(p,.5,duration=(2 if i in [0,4] else (2 if i<4 else (8-i)*.5)),voice=str(p[0]),cue=['p · thumb','i · index','m · middle','a · ring'][i%4]) for i,p in enumerate(ps)]
def slurbar(p1,p2,kind):
 return [ev(p1,1,slurStart=kind,cue='Pick once'),ev(p2,1,slurStop=kind,cue='H · Hammer on' if kind=='hammer-on' else 'P · Pull off'),ev(None,1),ev(p1,1,cue='Reset and pick')]
rows=[
row('Control the eighth notes','Keep a steady pick through string crossings.',
 'Count 1 and 2 and 3 and 4 and. A downstroke starts each numbered beat; an upstroke answers on “and”. Keep the motion small.',
 'The picking cue is separate from the fretting finger inside the marker. Start with open strings, then keep the same alternating motion while crossing between strings 2 and 1.',
 'Say the count before playing. Loop the first example until each pair is even, then play the crossing phrase. Choose a slower BPM whenever the upstroke catches.',
 'You can divide a beat evenly and carry alternate picking across a string change.',E,
 [ph('Even pairs',[picking([E]*8),picking([B,E,B,E,B,E,B,E])]),ph('Crossing current',[picking([B,C,D,E,G,F,E,D]),picking([C,B,E,F,G,E,D,B])])],
 quiz('Which stroke follows a downstroke in this exercise?','An upstroke',['Another downstroke','No stroke'],'Keep alternating down and up, including across strings.')),
row('Play across the beat','Hear the difference between a tie and a new attack.',
 'A dotted quarter lasts one and a half beats. A tie joins two notes of the same pitch: hold through the second note instead of picking again.',
 'Keep counting during rests. In Across the barline, the open E crosses from beat 4 into the next measure. The sound continues, even though the notation needs two noteheads.',
 'Clap the dotted rhythm. Then count the rests and hold the tied E without another pick. Compare it with the repeated E near the end.',
 'You can separate silence, a held note, and a repeated attack.',E,
 [ph('Offbeat doorway',[[ev(None,.5),ev(E,1.5),ev(F,.5),ev(G,.5),ev(E,1)], [ev(G,1.5),ev(F,.5),ev(E,1),ev(None,1)]]),ph('Across the barline',[[ev(E,1),ev(F,1),ev(G,1),ev(E,1,tieStart=True)],[ev(E,1,tieStop=True),ev(None,1),ev(E,1),ev(E,1)]])],
 quiz('What do you do at the second note of a tie?','Keep the first note sounding',['Pick the note again','Change to another string'],'A tie holds the same pitch; it is not a new attack.')),
row('Feel six-eight','Count two groups of three.',
 'Say ONE two three FOUR five six. Each syllable is an eighth note; each group of three makes one dotted-quarter pulse.',
 'The BPM control still counts quarter notes. At 60 quarter-note BPM, the dotted-quarter pulse is 40 per minute. The six-eight grouping comes from your count, not a change to the slider’s unit.',
 'Clap two larger pulses while saying six subdivisions. Play the broken pattern with the same grouping, then let the dotted notes fill a complete group.',
 'You can read six-eight without treating it as six heavy beats.',g,
 [ph('Two groups',[seq(c,e,g,a,g,e,q=.5),[ev(f,1.5),ev(g,1.5)]],6,8),ph('Drifting answer',[seq(a,g,e,d,e,g,q=.5),[ev(c,3)]],6,8)],
 quiz('How many eighth notes fill one dotted-quarter pulse?','Three',['Two','Four'],'Count ONE two three as one larger pulse.')),
row('Move beyond first position','Release, travel, and land with a guide finger.',
 'Your index finger names the position. Let it guide you from fret 1 to fret 3 and then fret 5. Release pressing force before travelling; do not squeeze while moving.',
 'The position caption marks the intended hand location. Look at the landing fret before moving. A guide finger may lightly touch the string; this is a position shift, not a sounded slide.',
 'Step through each landing before using Play. Keep the thumb mobile and the wrist comfortable. Stop and reset if the hand feels forced.',
 'You can prepare a new position and land before picking.',(1,5,1),
 [ph('Three landing places',[seq((1,1,1),(1,3,1),(1,5,1),(1,7,3)),seq((1,5,1),(1,3,1),(1,1,1),E)]),ph('Across the landing',[seq((2,3,1),(2,5,3),(1,3,1),(1,5,3)),seq((2,5,1),(2,7,3),(1,5,1),(1,7,3))])],
 quiz('What should happen before a position shift?','Release excess fretting pressure',['Squeeze harder','Lock the thumb in place'],'Lighten the grip so the hand can move freely.'),maxFret=8),
row('A minor pentatonic','Map five notes across six strings.',
 'The A-minor pentatonic scale contains A, C, D, E, and G. Start with index finger 1 at fret 5; use finger 3 at fret 7 and finger 4 at fret 8.',
 'Root rings mark A. Frets 5–8 form this position, even though the board also shows the nut for orientation. Say the note names instead of memorizing only a shape.',
 'Play the lower three strings first and then the upper three. Pause on every A. Use the second example to come back down without speeding up.',
 'You can find A roots and follow a fifth-position pentatonic route.',(1,5,1),
 [ph('Five-note staircase',[seq(*pent[:4]),seq(*pent[4:8]),seq(*pent[8:])]),ph('Return to the root',[seq(*pent[::-1][:4]),seq(*pent[::-1][4:8]),seq(*pent[::-1][8:])])],
 quiz('Which notes belong to A minor pentatonic?','A C D E G',['A B C D E','A C-sharp E F-sharp G'],'Use the five-note collection, with A as the home note.'),maxFret=8,rootPitchClass=9),
row('Make a musical phrase','Turn a scale into a question and answer.',
 'A phrase has shape and space. Play a short idea, leave silence, then answer it. You do not have to use every note in the pattern.',
 'Listen for the A root as a resting place. The examples use the same pentatonic collection with different rhythms. Keep silences intentional and stop the string for each rest.',
 'Loop the call, then answer with the written response. Finally invent a two-note answer on the shown positions; the app is a reference, not a judge of your improvisation.',
 'You can use rhythm and silence to give a small group of notes a musical shape.',(2,5,1),
 [ph('A short question',[[ev((1,5,1),.5),ev((1,8,4),.5),ev((2,8,4),1),ev((2,5,1),1),ev(None,1)],[ev((3,7,3),1),ev((3,5,1),1),ev((4,7,3),1),ev(None,1)]]),ph('Leave an answer',[[ev(None,1),ev((2,5,1),.5),ev((2,8,4),.5),ev((1,5,1),2)],[ev((1,8,4),1.5),ev((1,5,1),.5),ev((2,5,1),1),ev((1,5,1),1)]])],
 quiz('What can make a short phrase clearer?','Leaving intentional space',['Playing every note as fast as possible','Ignoring the pulse'],'A counted rest gives an idea room to breathe.'),maxFret=8,rootPitchClass=9),
row('Fingerpicking foundations','Let the thumb and fingers share the work.',
 'Picking-hand letters are p for thumb, i for index, m for middle, and a for ring. They are not the fretting-hand numbers. Assign p to the bass and i–m–a to strings 3–2–1.',
 'Hold the Em or Am shape while the picking hand moves. Notes on different strings overlap and keep glowing until their written durations end. The blue marker shows the next attack, not a command to stop the others.',
 'Read each picking cue aloud. Keep the hand relaxed and pluck toward the palm with a small motion. First play one four-note cycle, then join two cycles.',
 'You can separate the roles of both hands and let a broken chord ring.',(2,1,1),
 [ph('Em ringing pattern',[fingerbar((6,0,0),[g,B,E])]*2),ph('Am ringing pattern',[fingerbar((5,0,0),[(3,2,3),C,E])]*2)],
 quiz('What does p mean in a picking cue?','Picking-hand thumb',['Fretting finger 1','Pull off'],'Letters describe the picking hand; numbers describe the fretting hand.')),
row('Small chords, clear voices','Compare major and minor triads.',
 'A triad contains a root, a third, and a fifth. These small shapes use only strings 3, 2, and 1. Leave the other strings out.',
 'Compare D major with D minor: only the highest note moves from F-sharp to F. Compare A major with A minor: the C-sharp on string 2 lowers to C. One semitone changes the chord quality.',
 'Check each shape one string at a time, then hear its three notes together. Keep the same pulse while changing and let your hand reset between attempts.',
 'You can hear and locate the note that changes a major triad into minor.',(1,1,1),
 [ph('D to D minor',[[ev(Dtri,4)],[ev(Dmtri,4)]],muted=[4,5,6]),ph('A to A minor',[[ev(Atri,4)],[ev(Amtri,4)]],muted=[4,5,6])],
 quiz('Which chord tone lowers to change major into minor?','The third',['The root','The fifth'],'D major has F-sharp; D minor has F. This is its third.')),
row('Your first small barre','One finger, two strings, without excess pressure.',
 'Lay the side of index finger 1 across strings 1 and 2 at fret 1. Add finger 2 on string 3 fret 2. This small F shape uses only the top three strings.',
 'The bar on the diagram is one finger covering two strings. Bring it close behind the fret and use only enough pressure for clarity. Release between attempts; stop if anything hurts.',
 'Check strings 3, 2, and 1 individually. If one is muted, adjust the index angle instead of squeezing harder. Then alternate the shape with open E minor on the top strings.',
 'You can recognize a small barre and check both strings it covers.',F,
 [ph('Check the barre',[seq((3,2,2),(2,1,1),(1,1,1),None),[ev(Ftri,2),ev(None,2)]],muted=[4,5,6],barre=True),ph('Grip and release',[[ev(Ftri,2),ev(None,2)],[ev([g,B,E],2),ev(None,2)]],muted=[4,5,6],barre=True)],
 quiz('What does the short barre represent?','One finger holding two strings',['Two fingers on one string','A capo across all six strings'],'Index finger 1 covers strings 1 and 2 at fret 1.')),
row('Hammer-ons and ascending slurs','Pick once, then sound the higher note.',
 'Pick the lower note once, then bring the next fretting finger down clearly just behind its fret. The second note comes from the fretting hand. H and a curved slur connect the pair.',
 'A hammer-on changes pitch; a tie holds the same pitch. Keep the lower fretting finger placed for the fretted pair. Use a small controlled movement, not a large swing.',
 'Step through each pair to place the fingers. Use Play to hear the connected rhythm, then play it yourself with one initial pick. Keep both notes clear before increasing BPM.',
 'You can distinguish a hammer-on from a picked pair or a tie.',(1,3,3),
 [ph('Open to fretted',[slurbar(E,G,'hammer-on'),slurbar(B,D,'hammer-on')]),ph('Two fretted notes',[slurbar(F,G,'hammer-on'),slurbar(C,D,'hammer-on')])],
 quiz('How many pick strokes begin a two-note hammer-on pair?','One',['Two','None'],'Pick the first note; the fretting hand sounds the second.')),
row('Pull-offs and connected phrases','Prepare the lower note before releasing the higher one.',
 'Place the lower finger first. Pick the higher note, then make a small controlled plucking release with that fretting finger so the lower note sounds. P and a slur identify the pull-off.',
 'Simply lifting away may make the second note too quiet. Keep the prepared finger firm without excess force and avoid catching an unintended string. H rises in pitch; P falls.',
 'Practice descending pairs, then the three-note connected group. Pick only at the start of each group. Compare clarity at a slow tempo and take breaks.',
 'You can connect notes in both directions with prepared fingers.',F,
 [ph('Descending pairs',[slurbar(G,F,'pull-off'),slurbar(D,C,'pull-off')]),ph('Up and back',[[ev(F,1,slurStart='hammer-on',cue='Pick once'),ev(G,1,slurStop='hammer-on',slurStart='pull-off',cue='H · Hammer on'),ev(F,1,slurStop='pull-off',cue='P · Pull off'),ev(None,1)],[ev(C,1,slurStart='hammer-on',cue='Pick once'),ev(D,1,slurStop='hammer-on',slurStart='pull-off',cue='H · Hammer on'),ev(C,1,slurStop='pull-off',cue='P · Pull off'),ev(None,1)]])],
 quiz('What should be ready before a fretted pull-off?','The lower finger is already placed',['The lower finger stays in the air','Both fingers leave the string'],'Prepare the destination before sounding the higher note.')),
]
lead=[seq((1,3,1),(1,5,3),(1,5,1),(1,8,4)),slurbar((1,5,1),(1,8,4),'hammer-on'),slurbar((2,8,4),(2,5,1),'pull-off'),[ev((3,7,3),1.5),ev((3,5,1),.5),ev((4,7,3),1),ev(None,1)]]
lead += [seq((2,5,1),(2,8,4),(1,5,1),(1,8,4)),slurbar((1,8,4),(1,5,1),'pull-off'),seq((3,7,3),(3,5,1),(4,7,3),(4,5,1)),[ev((4,7,3),2),ev(None,2)]]
accomp=[fingerbar((4,0,0),Dtri),fingerbar((4,0,0),Dmtri),fingerbar((5,0,0),Atri),fingerbar((5,0,0),Amtri)]*2
rows.append(row('Put the new skills together','Two original studies, one step at a time.',
 'Choose Lead study for position shifts, pentatonic phrases, and H/P connections. Choose Ringing triads for a separate fingerpicking study. You do not need to play both parts together.',
 'Practice two bars at a time. Before a shift, locate the landing fret; before a slur, prepare its destination. In fingerpicking, follow p–i–m–a while the fretting hand holds the shape.',
 'Play each study slowly, then revisit the bar that needed the most attention. Finish with one relaxed complete pass. Accuracy and comfort matter more than finishing at a particular speed.',
 'You have connected rhythm, fretboard movement, lead technique, and small chord textures. Choose your next practice focus and return whenever you like.',(1,5,1),
 [ph('Lead study',lead),ph('Ringing triads',accomp)],quiz('What is a useful response to a difficult bar?','Slow down and isolate the transition',['Always restart the entire piece','Push through discomfort'],'Work on the small transition, then reconnect it to the phrase.'),maxFret=8,rootPitchClass=9))
for number,r in enumerate(rows,13):
 lid=f'lesson-{number:02d}';phrases=r.pop('phrases');out=[]
 for pi,p in enumerate(phrases,1):
  rid=f'{lid}-phrase-{pi}';events=[];bars=[];measureLength=p['beats']*4/p['beatType'];absolute=0
  for mi,items in enumerate(p['bars']):
   assert sum(i['q'] for i in items)==measureLength,(rid,mi)
   onset=0;xml=[]
   for ei,item in enumerate(items):
    pos=item['p'];positions=pos if isinstance(pos,list) else [pos];q=item.get('duration',item['q']);duration=int(q*4)
    typ={.5:'eighth',1:'quarter',1.5:'quarter',2:'half',2.5:'half',3:'half',4:'whole'}[q]
    assert q!=2.5
    for ni,position in enumerate(positions):
     nid=f'{rid}-m{mi+1}-e{ei+1}-n{ni+1}';voice=item.get('voice','1');st,fr,fi=position or (0,0,0);midi=opens[st-1]+fr if position else None
     evt=dict(id=nid,measure=mi,onset=onset,duration=q,string=st,fret=fr,finger=fi,midi=midi,startQuarter=absolute+onset)
     if 'cue' in item:evt['cue']=item['cue']
     if number in [16,24] and position:evt['positionLabel']=('Fifth position' if fr-fi+1>=5 else 'Third position' if fr-fi+1>=3 else 'First position')
     events.append(evt)
     pitch='<rest/>' if not position else '<pitch><step>'+['C','C','D','D','E','F','F','G','G','A','A','B'][(midi+12)%12]+'</step>'+('<alter>1</alter>' if (midi+12)%12 in [1,3,6,8,10] else '')+f'<octave>{(midi+12)//12-1}</octave></pitch>'
     ties=''.join(f'<tie type="{t}"/>' for k,t in [('tieStop','stop'),('tieStart','start')] if item.get(k))
     tech=''.join(f'<{item[k]} type="{t}" number="1">{ "H" if item[k]=="hammer-on" else "P" }</{item[k]}>' for k,t in [('slurStop','stop'),('slurStart','start')] if k in item)
     xml.append(f'<note id="{nid}">'+('<chord/>' if ni else '')+pitch+f'<duration>{duration}</duration>'+ties+f'<voice>{voice}</voice><type>{typ}</type>'+('<dot/>' if q in [1.5,3] else '')+('<notations><technical>'+tech+'</technical></notations>' if tech else '')+'</note>')
    # Sustain in another voice while advancing to the next picking attack.
    if q>item['q']:xml.append(f'<backup><duration>{int((q-item["q"])*4)}</duration></backup>')
    onset+=item['q']
   attrs=f'<attributes><divisions>4</divisions><key><fifths>0</fifths></key><time><beats>{p["beats"]}</beats><beat-type>{p["beatType"]}</beat-type></time><clef><sign>G</sign><line>2</line></clef><transpose><octave-change>-1</octave-change></transpose></attributes><direction><sound tempo="60"/></direction>' if mi==0 else ''
   bars.append(f'<measure number="{mi+1}">{attrs}'+''.join(xml)+'</measure>');absolute+=measureLength
  title=escape(r['title']+' — '+p['name'])
  (root/f'{rid}.musicxml').write_text(f'<?xml version="1.0"?><score-partwise version="4.0"><work><work-title>{title}</work-title></work><identification><creator type="composer">StringMap original exercise</creator></identification><part-list><score-part id="P1"><part-name>Guitar</part-name></score-part></part-list><part id="P1">'+''.join(bars)+'</part></score-partwise>')
  out.append(dict(id=rid,name=p['name'],events=events,mutedStrings=p.get('muted',[]),barre=dict(fret=1,firstString=1,lastString=2,finger=1) if p.get('barre') else None))
 r.update(id=lid,number=number,phrases=out);course['lessons'].append(r)
(root/'course.json').write_text(json.dumps(course,indent=2)+'\n')
print('Extended course:',len(course['lessons']),'lessons')
