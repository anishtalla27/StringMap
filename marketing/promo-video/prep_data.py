"""Parse StringMap's Minuet in G Songbook resources and run a faithful Python port of
the Swift FingeringEngine (monophonic DP + backward suffix pass) for the video."""
import json, math, os, xml.etree.ElementTree as ET
from pathlib import Path
# Point STRINGMAP_IOS at a checkout of the codex/native-ios-app branch.
IOS=Path(os.environ.get('STRINGMAP_IOS','../../../stringmap-ios'))/'apps/ios'
SB=IOS/'StringMap/Resources/Songbook'
PC={'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}
def parse(path):
    root=ET.parse(path).getroot(); notes=[]; onset=0.0; div=8; octave_change=0
    for m in root.iter('measure'):
        mnum=int(m.get('number')); start=onset; last_onset=onset
        a=m.find('attributes')
        if a is not None:
            if a.findtext('divisions'): div=int(a.findtext('divisions'))
            if a.find('transpose') is not None: octave_change=int(a.findtext('transpose/octave-change') or 0)
        for n in m.findall('note'):
            dur=int(n.findtext('duration'))/div
            is_chord=n.find('chord') is not None
            t=last_onset if is_chord else onset
            if n.find('rest') is None:
                p=n.find('pitch'); midi=12*(int(p.findtext('octave'))+1)+PC[p.findtext('step')]+int(p.findtext('alter') or 0)+12*octave_change
                notes.append(dict(id=n.get('id'),midi=midi,onset=t,dur=dur,measure=mnum))
            if not is_chord: last_onset=onset; onset+=dur
    return notes
melody=parse(SB/'minuet-g-melody.musicxml'); chords=parse(SB/'minuet-g-chords.musicxml')
cat=json.load(open(SB/'catalog.json')); song=[s for s in cat['songs'] if s['id']=='minuet-g'][0]
arr={a['kind']:a for a in song['arrangements']}
for n in chords: n['pos']=arr['chords']['positions'][n['id']]
for n in melody: n['authored']=arr['melody']['positions'][n['id']]
print(len(melody),'melody notes',len(chords),'chord notes', 'end', max(n['onset']+n['dur'] for n in melody))
print('chord labels', arr['chords'].get('chords')[:3])

STD=[40,45,50,55,59,64]  # string 6..1 low to high; Swift openMIDIPitches index -> string index+1
PROFILES={
 'beginner':dict(fretMovement=1.1,positionShift=2.4,stringChange=0.9,largeStretch=4.8,fretHeight=0.5,openStringPreference=3.5,comfortableStretch=3,stringSkipping=1.5,repeatedNoteConsistency=2.0,initialHandPosition=1.5,awkwardTransition=2.5),
 'balanced':dict(fretMovement=1.4,positionShift=2.8,stringChange=1.35,largeStretch=3.2,fretHeight=0.2,openStringPreference=1.2,comfortableStretch=4,stringSkipping=1.1,repeatedNoteConsistency=2.4,initialHandPosition=0.7,awkwardTransition=1.8),
 'stayInPosition':dict(fretMovement=2.4,positionShift=7.0,stringChange=1.6,largeStretch=5.0,fretHeight=0.05,openStringPreference=0.25,comfortableStretch=4,stringSkipping=1.2,repeatedNoteConsistency=3.0,initialHandPosition=3.0,awkwardTransition=2.0),
 'minimumMovement':dict(fretMovement=3.2,positionShift=4.0,stringChange=0.45,largeStretch=2.0,fretHeight=0.08,openStringPreference=0.1,comfortableStretch=5,stringSkipping=0.35,repeatedNoteConsistency=3.5,initialHandPosition=1.0,awkwardTransition=1.0),
 'performance':dict(fretMovement=1.2,positionShift=2.0,stringChange=1.8,largeStretch=2.3,fretHeight=0.03,openStringPreference=-0.25,comfortableStretch=5,stringSkipping=1.6,repeatedNoteConsistency=1.8,initialHandPosition=0.2,awkwardTransition=0.8),
}
def positions(midi,opens,maxFret=20):
    out=[]
    for i,o in enumerate(opens):
        f=midi-o
        if 0<=f<=maxFret: out.append(dict(string=i+1,fret=f,midi=midi))
    return sorted(out,key=lambda p:(p['fret'],p['string']))
def hand(f): return 1 if f==0 else max(1,f-1)
def unary(p,w,pref=None):
    h=abs(hand(p['fret'])-pref)*w['initialHandPosition'] if pref is not None else 0
    return p['fret']*w['fretHeight']+(-w['openStringPreference'] if p['fret']==0 else 0)+h
def trans(a,b,na,nb,w):
    fd=abs(b['fret']-a['fret']); pd=abs(hand(b['fret'])-hand(a['fret'])); sd=abs(b['string']-a['string'])
    ex=max(0,fd-w['comfortableStretch']) if a['fret']>0 and b['fret']>0 else 0
    aw=max(0,fd-7)
    return (fd*w['fretMovement']+pd*w['positionShift']+(0 if sd==0 else w['stringChange'])+max(0,sd-1)*w['stringSkipping']
            +ex*ex*w['largeStretch']+(w['repeatedNoteConsistency'] if na['midi']==nb['midi'] and a!=b else 0)+aw*aw*w['awkwardTransition'])
def optimize(notes,w,opens):
    layers=[positions(n['midi'],opens) for n in notes]
    INF=float('inf'); cost=[]; par=[]
    for i,L in enumerate(layers):
        row=[];pr=[]
        for c in L:
            u=unary(c,w)
            if i==0: row.append(u); pr.append(None); continue
            best=INF;bp=None
            for j,p in enumerate(layers[i-1]):
                v=cost[i-1][j]+trans(p,c,notes[i-1],notes[i],w)+u
                if v<best: best=v;bp=j
            row.append(best);pr.append(bp)
        cost.append(row);par.append(pr)
    last=len(layers)-1; fi=min(range(len(layers[last])),key=lambda k:cost[last][k])
    sel=[0]*len(layers); sel[last]=fi
    for i in range(last,0,-1): sel[i-1]=par[i][sel[i]]
    suf=[[INF]*len(L) for L in layers]; suf[last]=[0]*len(layers[last])
    for i in range(last-1,-1,-1):
        for a,p in enumerate(layers[i]):
            for b,c in enumerate(layers[i+1]):
                suf[i][a]=min(suf[i][a],trans(p,c,notes[i],notes[i+1],w)+unary(c,w)+suf[i+1][b])
    total=cost[last][fi]
    return dict(total=total,layers=layers,selected=sel,parents=par,
                delta=[[round(cost[i][k]+suf[i][k]-total,2) for k in range(len(L))] for i,L in enumerate(layers)])

OPENS=[64,59,55,50,45,40]
res={k:optimize(melody,w,OPENS) for k,w in PROFILES.items()}
counts=[len(L) for L in res['balanced']['layers']]
routes=math.prod(counts)
print('candidate counts',counts[:20],'routes 10^%.2f'%math.log10(routes), 'exact digits',len(str(routes)))
for k,r in res.items():
    ch=[r['layers'][i][s] for i,s in enumerate(r['selected'])]
    same=sum(1 for c,n in zip(ch,melody) if c['string']==n['authored']['string'] and c['fret']==n['authored']['fret'])
    print(k,'total %.2f'%r['total'],'agrees with authored',same,'/',len(melody), 'frets',[c['fret'] for c in ch[:16]], 'strings',[c['string'] for c in ch[:16]])
# E4 / B3 positions for the "one note, many places" scene
for m in (59,62,64,67): print(m,[(p['string'],p['fret']) for p in positions(m,OPENS)])
def pos_list(r): return [dict(s=r['layers'][i][k]['string'],f=r['layers'][i][k]['fret']) for i,k in enumerate(r['selected'])]
data=dict(
  tempoBase=96,
  melody=[dict(id=n['id'],midi=n['midi'],on=n['onset'],dur=n['dur'],m=n['measure']) for n in melody],
  chords=[dict(midi=n['midi'],on=n['onset'],dur=n['dur'],m=n['measure'],s=n['pos']['string'],f=n['pos']['fret']) for n in chords],
  chordLabels=arr['chords']['chords'],
  routes=str(routes), routesLog10=math.log10(routes),
  profiles={k:dict(total=round(r['total'],2),route=pos_list(r)) for k,r in res.items()},
  balanced=dict(layers=[[dict(s=p['string'],f=p['fret']) for p in L] for L in res['balanced']['layers']],
                selected=res['balanced']['selected'],parents=res['balanced']['parents'],delta=res['balanced']['delta']),
)
json.dump(data,open(Path(__file__).parent/'data.json','w'))
print('wrote data.json')
