"""Render the video soundtrack: StringMap's Minuet in G Songbook arrangements (melody + chords)
through the app's bundled CC0 guitar SoundFont. Plain sample playback, no extra instruments."""
import json, os, wave, numpy as np
from pathlib import Path
from sf2 import SF2
HERE=Path(__file__).parent
IOS=Path(os.environ.get('STRINGMAP_IOS','../../../stringmap-ios'))/'apps/ios'
SR=44100; BPM=90; Q=60/BPM; T0=1.0; LENGTH=68.0
sf=SF2(IOS/'StringMap/Resources/AlphaTab/soundfont/stringmap-guitar.sf2')
zones=sf.instrument_zones(0)[1:]
def zone_for(m):
    for z in zones:
        kr=z[43]; lo,hi=kr&255,kr>>8
        if lo<=m<=hi: return z
cache={}
def voice(midi):
    if midi in cache: return cache[midi]
    z=zone_for(midi); s=sf.shdr[z[53]]
    start,end,root,corr=s[1],s[2],s[6],s[7]
    root=z.get(58,root)
    x=sf.smpl[start:end].copy()
    cents=(midi-root)*100+corr
    if cents:
        ratio=2**(cents/1200); idx=np.arange(0,len(x)-1,ratio)
        x=np.interp(idx,np.arange(len(x)),x).astype(np.float32)
    cache[midi]=x; return x
d=json.load(open(HERE/'data.json'))
N=int(SR*LENGTH); L=np.zeros(N,np.float32); R=np.zeros(N,np.float32)
rng=np.random.default_rng(7)
def add(midi,t,dur,gain,pan=0.0,release=0.45):
    x=voice(midi); i0=int(t*SR); held=int(dur*SR); rel=int(release*SR)
    n=min(len(x),held+rel,N-i0)
    if n<=0: return
    seg=x[:n]*gain
    if n>held:
        k=n-held; seg[held:]*=np.exp(-np.linspace(0,6,k)).astype(np.float32)
    lg=np.cos((pan+1)*np.pi/4); rg=np.sin((pan+1)*np.pi/4)
    L[i0:i0+n]+=seg*lg; R[i0:i0+n]+=seg*rg
end=max(n['on']+n['dur'] for n in d['melody'])
for n in d['melody']:
    beat=n['on']%3
    accent=1.0 if beat==0 else (0.86 if beat in (1,2) else 0.78)
    last=n['on']+n['dur']>=end
    add(n['midi'],T0+n['on']*Q,n['dur']*Q+(2.2 if last else 0.02),0.95*accent*rng.uniform(0.94,1.04),pan=0.12,release=0.5 if not last else 1.2)
from collections import defaultdict
bars=defaultdict(list)
for c in d['chords']: bars[c['on']].append(c)
for on,notes in bars.items():
    notes=sorted(notes,key=lambda c:c['midi'])
    last=on+notes[0]['dur']>=end
    for k,c in enumerate(notes):
        t=T0+on*Q+k*0.014
        add(c['midi'],t,c['dur']*Q-0.05+(2.2 if last else 0),0.42*(0.9+0.1*k/len(notes)),pan=-0.18+0.06*k,release=0.35 if not last else 1.2)
# Light room reverb: exponentially decaying noise IR, applied via FFT.
ir_len=int(1.6*SR); t=np.arange(ir_len)/SR
irL=(rng.standard_normal(ir_len)*np.exp(-t/0.38)).astype(np.float32); irR=(rng.standard_normal(ir_len)*np.exp(-t/0.38)).astype(np.float32)
irL[:int(0.012*SR)]=0; irR[:int(0.017*SR)]=0
irL/=np.sqrt((irL**2).sum()); irR/=np.sqrt((irR**2).sum())
def conv(x,h):
    n=1<<int(np.ceil(np.log2(len(x)+len(h))))
    return np.fft.irfft(np.fft.rfft(x,n)*np.fft.rfft(h,n),n)[:len(x)].astype(np.float32)
wet=0.16
Lo=L+wet*conv(L,irL); Ro=R+wet*conv(R,irR)
# Fade out tail
fo=int(2.0*SR); Lo[-fo:]*=np.linspace(1,0,fo); Ro[-fo:]*=np.linspace(1,0,fo)
peak=max(np.abs(Lo).max(),np.abs(Ro).max()); g=0.89/peak
out=np.stack([Lo*g,Ro*g],1)
print('peak before norm',peak,'gain',g,'melody end s',T0+end*Q)
pcm=(np.clip(out,-1,1)*32767).astype('<i2')
with wave.open(str(HERE/'soundtrack.wav'),'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print('wrote soundtrack.wav', LENGTH,'s')
