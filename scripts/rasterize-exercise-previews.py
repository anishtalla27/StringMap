"""Resolve alphaTab's external Bravura glyphs for standalone review previews."""
from pathlib import Path
import sys
import xml.etree.ElementTree as E
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
import cairosvg
r=Path(__file__).resolve().parents[1]
font=TTFont(r/'apps/ios/StringMap/Resources/AlphaTab/font/Bravura.woff2')
glyphs=font.getGlyphSet();cmap=font.getBestCmap();scale=36/font['head'].unitsPerEm
ns='{http://www.w3.org/2000/svg}'
folder = r / (sys.argv[1] if len(sys.argv) > 1 else 'artifacts/offline-exercise-verification')
previews = [p for p in folder.glob('*.svg') if not p.name.endswith('.paths.svg')]
for p in previews:
 root=E.fromstring(p.read_text())
 for group in list(root.iter(ns+'g')):
  if group.get('class')!='at':continue
  for text in list(group):
   if text.tag!=ns+'text':continue
   chars=text.text or ''; widths=[glyphs[cmap[ord(c)]].width for c in chars]
   x=-sum(widths)*scale/2 if text.get('text-anchor')=='middle' else 0
   for char,width in zip(chars,widths):
    pen=SVGPathPen(glyphs);glyphs[cmap[ord(char)]].draw(pen)
    E.SubElement(group,ns+'path',{'d':pen.getCommands(),'transform':f'translate({x} 0) scale({scale} {-scale})','fill':'#17140f'})
    x+=width*scale
   group.remove(text)
 resolved=p.with_suffix('.paths.svg');resolved.write_bytes(E.tostring(root))
 cairosvg.svg2png(bytestring=E.tostring(root),write_to=str(p.with_suffix('.png')))
print(f'Rasterized {len(previews)} alphaTab scores with exact bundled Bravura outlines')
