"""Original, independently specified rhythms beyond the initial quarter-note set.

The expected events are written from the composition specification, before any
recognizer runs. References and all image variants stay outside the engine.
"""
import json
from pathlib import Path
import random
import xml.etree.ElementTree as ET

import cairosvg
import verovio
from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'artifacts/rhythm-corpus-v2'
TYPES = {4: ('whole', 0), 3: ('half', 1), 2: ('half', 0), 1.5: ('quarter', 1),
         1: ('quarter', 0), .75: ('eighth', 1), .5: ('eighth', 0), .25: ('16th', 0), 1/3: ('eighth', 0)}


def note(parent, pitches, duration, voice=1, tied=None, tuplet_boundary=None):
    for index, midi in enumerate(pitches or [None]):
        n = ET.SubElement(parent, 'note')
        if index: ET.SubElement(n, 'chord')
        if midi is None: ET.SubElement(n, 'rest')
        else:
            p = ET.SubElement(n, 'pitch')
            name, alter = [('C',0),('C',1),('D',0),('E',-1),('E',0),('F',0),('F',1),('G',0),('A',-1),('A',0),('B',-1),('B',0)][midi%12]
            ET.SubElement(p, 'step').text = name
            if alter: ET.SubElement(p, 'alter').text = str(alter)
            ET.SubElement(p, 'octave').text = str(midi//12-1)
        ET.SubElement(n, 'duration').text = str(round(duration*12))
        if tied: ET.SubElement(n, 'tie', type=tied)
        ET.SubElement(n, 'voice').text = str(voice)
        kind, dots = TYPES[duration]
        ET.SubElement(n, 'type').text = kind
        for _ in range(dots): ET.SubElement(n, 'dot')
        if duration == 1/3:
            t = ET.SubElement(n, 'time-modification')
            ET.SubElement(t, 'actual-notes').text = '3'; ET.SubElement(t, 'normal-notes').text = '2'
        if tied: ET.SubElement(ET.SubElement(n, 'notations'), 'tied', type=tied)
        if tuplet_boundary:
            ET.SubElement(ET.SubElement(n, 'notations'), 'tuplet', type=tuplet_boundary, number='1', bracket='yes')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    for study in range(12):
        rng = random.Random(7019+study)
        name = f'rhythm-{study+1:02d}'
        feature = ['mixed-durations', 'dotted-rests', 'sixteenths', 'key-signature',
                   'chord-rhythms', 'independent-voices', 'barline-ties', 'triplets',
                   'repeats', 'flat-key', 'rests', 'multiple-systems'][study]
        root = ET.Element('score-partwise', version='4.0')
        ET.SubElement(ET.SubElement(root, 'work'), 'work-title').text = name
        sp = ET.SubElement(ET.SubElement(root, 'part-list'), 'score-part', id='P1')
        ET.SubElement(sp, 'part-name').text = 'Guitar'
        part = ET.SubElement(root, 'part', id='P1')
        expected = []
        for m in range(8):
            measure = ET.SubElement(part, 'measure', number=str(m+1))
            if m == 0:
                a = ET.SubElement(measure, 'attributes'); ET.SubElement(a, 'divisions').text = '12'
                ET.SubElement(ET.SubElement(a, 'key'), 'fifths').text = '1' if study==3 else '-2' if study==9 else '0'
                t = ET.SubElement(a, 'time'); ET.SubElement(t, 'beats').text = '4'; ET.SubElement(t, 'beat-type').text = '4'
                c = ET.SubElement(a, 'clef'); ET.SubElement(c, 'sign').text = 'G'; ET.SubElement(c, 'line').text = '2'
            if m == 4: ET.SubElement(measure, 'print', **{'new-system': 'yes'})
            if study == 8 and m == 0: ET.SubElement(ET.SubElement(measure, 'barline', location='left'), 'repeat', direction='forward')
            patterns = [[.5,.5,1,2], [1.5,.5,1,1], [.25,.25,.25,.25,.5,.5,2]]
            durations = patterns[study%3]
            if study == 7: durations = [1/3,1/3,1/3,1,2]
            if study == 6: durations = [2,2]
            if study == 5: durations = [1,1,1,1]
            onset = 0
            for index, duration in enumerate(durations):
                scale = [60,62,64,65,67,69,71,72]
                if study==3: scale=[62,64,66,67,69,71,72,74]
                if study==9: scale=[60,62,63,65,67,69,70,72]
                pitches = [rng.choice(scale)]
                if study == 4: pitches = rng.choice([[60,64,67],[62,65,69],[59,62,67]])
                if study in [1,10] and index == m%len(durations): pitches = []
                tied = None
                if study == 6:
                    pitches=[67]
                    if index==1 and m<7: tied='start'
                    if index==0 and m>0: tied='stop'
                note(measure, pitches, duration, tied=tied, tuplet_boundary=('start' if index==0 else 'stop' if index==2 else None) if study==7 else None)
                for midi in pitches: expected.append({'midi':midi,'onset':m*4+onset,'duration':duration})
                onset += duration
            if study == 5:
                ET.SubElement(ET.SubElement(measure,'backup'),'duration').text='48'
                note(measure,[52],4,voice=2)
                expected.append({'midi':52,'onset':m*4,'duration':4})
            if study == 8 and m==7: ET.SubElement(ET.SubElement(measure,'barline',location='right'),'repeat',direction='backward')
        if study == 8: expected += [{**x,'onset':x['onset']+32} for x in list(expected)]
        xml=ET.tostring(root,encoding='unicode'); (OUT/(name+'.musicxml')).write_text(xml)
        tk=verovio.toolkit();tk.setOptions({'pageWidth':2100,'pageHeight':1800,'scale':60,'adjustPageHeight':True,'breaks':'encoded','header':'none','footer':'none'})
        if not tk.loadData(xml):raise RuntimeError('Engraving failed')
        svg=tk.renderToSVG(1)
        if study==7 and 'tupletNum' not in svg: raise RuntimeError('Triplet number was not engraved')
        cairosvg.svg2png(bytestring=svg.encode(),write_to=str(OUT/(name+'.png')),output_width=2600,background_color='white')
        image=Image.open(OUT/(name+'.png')).convert('RGB')
        variants={'clean':image,'rotate':image.rotate(-3,resample=Image.Resampling.BICUBIC,expand=True,fillcolor='white'),
                  'dim':ImageEnhance.Brightness(image).enhance(.55),'blur':image.filter(ImageFilter.GaussianBlur(.7))}
        for variant, page in variants.items():
            image_name=name+'-'+variant+'.jpg';page.save(OUT/image_name,quality=85)
            manifest.append({'id':name+'-'+variant,'image':image_name,'reference':name+'.musicxml','feature':feature,
                'category':'printed-chords' if study in [4,5] else 'printed-melody','capture':'engraved' if variant=='clean' else 'synthetic-'+variant,
                'expected':expected,'provenance':'Original StringMap rhythmic study; concert pitches; two systems; reference specified before recognition.','license':'Repository-owned test material'})
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'images':len(manifest),'distinctScores':12,'features':[x['feature'] for x in manifest if x['capture']=='engraved']}))


if __name__=='__main__':main()
