"""Post-inference reference and native-pipeline checks for research outputs.

SPDX-License-Identifier: AGPL-3.0-or-later
Whole-page metrics retain actual timing errors. Measure-index diagnostics are
separate and do not qualify accuracy. References never enter inference/export.
"""
import argparse
import csv
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from benchmark import compare, SWIFT
from compare_external_pack import read_events
from engine_benchmark import unpack_musicxml
from compare_measure_timing import diagnostic


def main():
    p = argparse.ArgumentParser(); p.add_argument('--pack', type=Path, required=True)
    p.add_argument('--results', type=Path, required=True); a = p.parse_args()
    source_cases = [c for c in csv.DictReader((a.pack / 'manifest.csv').open()) if c['kind'] == 'printed_guitar']
    cohort = json.loads((a.results / 'cohort.json').read_text())
    if len(cohort['cases']) != len(source_cases): raise ValueError('Inference cohort is incomplete')
    report = {'shipping': False, 'releaseQualified': False, 'realCameraImages': 0,
              'referenceStatus': 'Provisional first-page MusicXML boundaries and notation; not independently audited.',
              'cases': []}
    modes = ['greedy-page', 'constrained-page', 'greedy-sustained', 'constrained-sustained']
    for case in source_cases:
        name = Path(case['image']).stem; folder = a.results / name / 'results'
        if (folder / 'inference.json').exists():
            subprocess.run([sys.executable, str(Path(__file__).with_name('evaluate_sustained_timing.py')),
                            '--results', str(folder)], check=True, timeout=30, capture_output=True)
        reference_path = a.pack / case['matching_musicxml']
        reference = ET.fromstring(unpack_musicxml(reference_path) if reference_path.suffix.lower() == '.mxl'
                                  else reference_path.read_bytes())
        # Explicit written-pitch comparison; never choose an octave for better fit.
        for element in reference.iter():
            for child in list(element):
                if child.tag == 'transpose': element.remove(child)
        expected = read_events(reference, True)
        row = {'id': name, 'modes': {}}
        for mode in modes:
            xml = folder / (mode + '.musicxml')
            actual = ET.parse(xml).getroot() if xml.exists() else None
            result = {'exported': actual is not None,
                      'metrics': compare(expected, read_events(actual) if actual is not None else [])}
            if actual is not None:
                result['measureAlignedDiagnostic'] = diagnostic(reference, actual)
                native = json.loads(subprocess.check_output([str(SWIFT), str(xml), '--guitar-photo'], timeout=120))
                (folder / (mode + '-native.json')).write_text(json.dumps(native, indent=2) + '\n')
                result.update(parsed=native.get('parsed'), tabPlayable=native.get('tabPlayable'),
                              error=native.get('error'), tabError=native.get('tabError'))
                if native.get('parsed'):
                    playback = json.loads(subprocess.check_output(['node', 'scripts/verify-score-playback.mjs'],
                        input=json.dumps(native).encode(), timeout=60))
                    (folder / (mode + '-playback.json')).write_text(json.dumps(playback, indent=2) + '\n')
                    for kind, check in playback.items():
                        if isinstance(check, bool):
                            if not check: raise AssertionError(f'{name}/{mode}/{kind}: tab invariant failed')
                        elif not check.get('parsed') or not check.get('exactPlayback') or not check.get('sourceIdentitiesPreserved'):
                            raise AssertionError(f'{name}/{mode}/{kind}: native playback mismatch')
                    if 'notationAlphaTex' not in playback: raise AssertionError('Missing notation playback')
                    if native.get('tabPlayable') and 'alphaTex' not in playback: raise AssertionError('Missing tab playback')
                    result['playback'] = playback
                else:
                    review = json.loads(subprocess.check_output([str(SWIFT), str(xml), '--guitar-photo', '--for-review'], timeout=120))
                    (folder / (mode + '-review.json')).write_text(json.dumps(review, indent=2) + '\n')
                    result['reviewParsed'] = review.get('parsed')
            row['modes'][mode] = result
        report['cases'].append(row)
        (a.results / 'assessment.json').write_text(json.dumps(report, indent=2) + '\n')
        print(name, {m: round(r['metrics']['noteEvent']['f1'], 4) for m, r in row['modes'].items()}, flush=True)
    report['totals'] = {}
    for mode in modes:
        rows = [c['modes'][mode] for c in report['cases']]
        totals = {k: sum(r['metrics']['noteEvent'][k] for r in rows) for k in ['truePositive', 'missing', 'extra']}
        totals['f1'] = 2 * totals['truePositive'] / (2 * totals['truePositive'] + totals['missing'] + totals['extra'])
        report['totals'][mode] = {'noteEvent': totals, 'exported': sum(r['exported'] for r in rows),
                                 'parsed': sum(bool(r.get('parsed')) for r in rows),
                                 'tabPlayable': sum(bool(r.get('tabPlayable')) for r in rows)}
    (a.results / 'assessment.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['totals'], indent=2))


if __name__ == '__main__': main()
