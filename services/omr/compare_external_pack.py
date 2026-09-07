"""Provisional page-one reference comparison, independent rational XML timing.

MusicXML page breaks can differ from PDF layout: review boundaries visually
before using these metrics as a release qualification. No octave alignment.
"""
import argparse,csv,json,xml.etree.ElementTree as ET
from fractions import Fraction
from pathlib import Path
from engine_benchmark import unpack_musicxml
from benchmark import compare

def read_events(root,first_page=False):
    result=[]; divisions=Fraction(1);meter=Fraction(4);offset=Fraction(0);transpose=0
    for index,m in enumerate(root.findall('./part/measure')):
        if first_page and index and m.find("print[@new-page='yes']") is not None:break
        cursor=Fraction(0);last=Fraction(0);end=Fraction(0)
        for e in m:
            if e.tag=='attributes':
                if e.find('divisions') is not None:divisions=Fraction(e.findtext('divisions'))
                if e.find('time/beats') is not None:meter=Fraction(e.findtext('time/beats'))*4/Fraction(e.findtext('time/beat-type'))
                if e.find('transpose') is not None:transpose=int(e.findtext('transpose/chromatic','0'))+12*int(e.findtext('transpose/octave-change','0'))
            elif e.tag=='backup':cursor-=Fraction(e.findtext('duration'))/divisions
            elif e.tag=='forward':cursor+=Fraction(e.findtext('duration'))/divisions;end=max(end,cursor)
            elif e.tag=='note':
                if e.find('grace') is not None:continue
                d=Fraction(e.findtext('duration','0'))/divisions
                t=last if e.find('chord') is not None else cursor
                if e.find('pitch') is not None:
                    pitch=e.find('pitch');midi=12*(int(pitch.findtext('octave'))+1)+{'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}[pitch.findtext('step')]+int(pitch.findtext('alter','0'))+transpose
                    result.append(dict(midi=midi,onset=float(offset+t),duration=float(d)))
                end=max(end,t+d)
                if e.find('chord') is None:last=t;cursor+=d
        offset+=end or meter
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--pack',type=Path,default=Path('artifacts/external-notation-pack/StringMap_notation_test_pack'));p.add_argument('--results',type=Path,required=True);a=p.parse_args();rows=[]
    for c in csv.DictReader((a.pack/'manifest.csv').open()):
        name=c['kind']+'-'+Path(c['image']).stem; path=a.results/(name+'.json')
        if not path.exists():continue
        r=json.loads(path.read_text());entry={'id':name,'status':r.get('status'),'error':r.get('error'),'seconds':r['seconds'],'tabPlayable':r.get('pipeline',{}).get('tabPlayable')}
        if c['matching_musicxml']:
            ref=ET.fromstring(unpack_musicxml(a.pack/c['matching_musicxml']));expected=read_events(ref,True)
            xml=a.results/(name+'.musicxml');actual=read_events(ET.parse(xml).getroot()) if xml.exists() else []
            entry['provisionalMetrics']=compare(expected,actual)
            # Report visible written pitches separately from sounding guitar pitches.
            # The reference's explicit transpose is removed, never selected to maximize accuracy.
            for parent in ref.iter():
                for child in list(parent):
                    if child.tag=='transpose':parent.remove(child)
            entry['provisionalWrittenNotationMetrics']=compare(read_events(ref,True),actual)
            entry['referenceStatus']='XML first-page boundary; PDF boundary and reference pitches need independent checking'
        else:entry['referenceStatus']='No symbolic ground truth; accuracy unmeasured'
        rows.append(entry)
    (a.results/'comparison.json').write_text(json.dumps({'cases':rows,'realCameraImages':0,'releaseQualified':False},indent=2)+'\n')
    for r in rows:print(r['id'],r['status'],r.get('provisionalMetrics',{}).get('noteEvent',{}).get('f1'))
