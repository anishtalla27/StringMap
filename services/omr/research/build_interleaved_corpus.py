"""Original voice-interleaving studies with pre-inference symbolic references.

SPDX-License-Identifier: AGPL-3.0-or-later
These are engraved controls, not real photos or an accuracy qualification set.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import cairosvg
import verovio
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_rhythm_corpus import note


def main():
    p = argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True); a = p.parse_args()
    a.output.mkdir(parents=True, exist_ok=False)
    studies = {
        'interleaved-dotted': [([72, 74, 76, 77], [1.5, .5, 1, 1]), ([60, 64, 62], [2, 1.5, .5])],
        'interleaved-middle': [([76, 74, 72, 77], [.5, .5, 1, 2]), ([60, 62, 64], [1.5, .5, 2])],
        'monophonic-control': [([72, 74, 76, 77], [1.5, .5, 1, 1])],
    }
    rows = []; report = {'capture': 'original engraved controls', 'referencesBeforeInference': True, 'cases': []}
    for name, voices in studies.items():
        root = ET.Element('score-partwise', version='4.0')
        sp = ET.SubElement(ET.SubElement(root, 'part-list'), 'score-part', id='P1')
        ET.SubElement(sp, 'part-name').text = 'Guitar'
        part = ET.SubElement(root, 'part', id='P1'); expected = []
        for index in range(4):
            measure = ET.SubElement(part, 'measure', number=str(index + 1))
            if index == 0:
                attributes = ET.SubElement(measure, 'attributes')
                ET.SubElement(attributes, 'divisions').text = '12'
                ET.SubElement(ET.SubElement(attributes, 'key'), 'fifths').text = '0'
                meter = ET.SubElement(attributes, 'time')
                ET.SubElement(meter, 'beats').text = '4'; ET.SubElement(meter, 'beat-type').text = '4'
                clef = ET.SubElement(attributes, 'clef')
                ET.SubElement(clef, 'sign').text = 'G'; ET.SubElement(clef, 'line').text = '2'
            for voice, (pitches, durations) in enumerate(voices, 1):
                if voice > 1: ET.SubElement(ET.SubElement(measure, 'backup'), 'duration').text = '48'
                onset = 0
                for pitch, duration in zip(pitches, durations, strict=True):
                    note(measure, [pitch], duration, voice=voice)
                    ET.SubElement(measure.findall('note')[-1], 'stem').text = 'up' if voice == 1 else 'down'
                    expected.append({'midi': pitch, 'onset': index * 4 + onset, 'duration': duration})
                    onset += duration
                assert onset == 4
        xml = ET.tostring(root, encoding='unicode'); (a.output / (name + '.musicxml')).write_text(xml)
        renderer = verovio.toolkit(); renderer.setOptions({'pageWidth': 2100, 'pageHeight': 1200,
            'scale': 60, 'adjustPageHeight': True, 'breaks': 'none', 'header': 'none', 'footer': 'none'})
        if not renderer.loadData(xml) or renderer.getPageCount() != 1: raise ValueError('Expected one engraved page')
        svg = renderer.renderToSVG(1); (a.output / (name + '.svg')).write_text(svg)
        png = a.output / (name + '.png')
        cairosvg.svg2png(bytestring=svg.encode(), write_to=str(png), output_width=2600, background_color='white')
        image = a.output / (name + '.jpg'); Image.open(png).convert('RGB').save(image, quality=95)
        rows.append({'image': image.name, 'kind': 'printed_guitar', 'matching_musicxml': name + '.musicxml'})
        report['cases'].append({'id': name, 'voices': voices, 'expected': expected,
                                'imageSHA256': hashlib.sha256(image.read_bytes()).hexdigest()})
    with (a.output / 'manifest.csv').open('w', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    (a.output / 'specification.json').write_text(json.dumps(report, indent=2) + '\n')
    manifest = [{'id': c['id'], 'image': c['id'] + '.jpg', 'reference': c['id'] + '.musicxml',
                 'expected': c['expected'], 'capture': 'engraved',
                 'category': 'printed-chords' if c['id'].startswith('interleaved') else 'printed-melody',
                 'provenance': 'Original interleaved study specified before recognition',
                 'license': 'Repository-owned test material'} for c in report['cases']]
    (a.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__': main()
