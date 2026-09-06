"""Original out-of-scope image fixtures; no borrowed scores or photographs."""
import json
from pathlib import Path
import cairosvg
import verovio
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'artifacts/unsupported-corpus'
OUT.mkdir(parents=True,exist_ok=True);manifest=[]
def notes(staff,step,octave):
    return ''.join(f'<note><pitch><step>{step}</step><octave>{octave}</octave></pitch><duration>1</duration><type>quarter</type><staff>{staff}</staff></note>' for _ in range(4))
for variant in ['piano','ensemble']:
    ids=['P1'] if variant=='piano' else ['P1','P2']
    xml='<score-partwise><part-list>'+''.join(f'<score-part id="{i}"><part-name>{"Piano" if variant=="piano" else "Instrument"}</part-name></score-part>' for i in ids)+'</part-list>'
    for identifier in ids:
        xml+=f'<part id="{identifier}">'
        for m in range(4):
            xml+=f'<measure number="{m+1}">'
            if m==0:
                xml+='<attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time>'
                xml+=('<staves>2</staves><clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef>' if variant=='piano' else '<clef><sign>G</sign><line>2</line></clef>')+'</attributes>'
            xml+=notes(1,'E',4)
            if variant=='piano':xml+='<backup><duration>4</duration></backup>'+notes(2,'C',3)
            xml+='</measure>'
        xml+='</part>'
    xml+='</score-partwise>';tk=verovio.toolkit();tk.setOptions({'pageWidth':2100,'scale':60,'adjustPageHeight':True,'breaks':'none','header':'none','footer':'none'})
    assert tk.loadData(xml);svg=tk.renderToSVG(1);png=OUT/(variant+'.png');cairosvg.svg2png(bytestring=svg.encode(),write_to=str(png),output_width=2600,background_color='white');Image.open(png).convert('RGB').save(OUT/(variant+'.jpg'),quality=92)
    (OUT/(variant+'.musicxml')).write_text(xml)
    manifest.append({'id':'unsupported-'+variant,'image':variant+'.jpg','category':'unsupported','capture':'generated-unsupported','expected':[],'provenance':'Original generated '+variant+' score; outside single-part guitar scope'})
page=Image.new('RGB',(1600,1200),'white');draw=ImageDraw.Draw(page);draw.text((150,300),'G minor     C major     D7',fill='black',font_size=90);page.save(OUT/'chord-names.jpg')
manifest.append({'id':'unsupported-chord-names','image':'chord-names.jpg','category':'unsupported','capture':'generated-unsupported','expected':[],'provenance':'Generated chord-name text without written notes'})
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
