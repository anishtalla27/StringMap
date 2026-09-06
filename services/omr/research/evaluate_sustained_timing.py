"""Re-export retained image-derived symbols with experimental sustain timing.

SPDX-License-Identifier: AGPL-3.0-or-later
Patches only this process's in-memory export call; no installed files change.
References are evaluated separately. Never silently skip a failed staff.
"""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import sys
from types import MethodType
from unittest.mock import patch
import xml.etree.ElementTree as ET

import homr.music_xml_generator as writer
from homr.transformer.vocabulary import EncodedSymbol
from sustained_timing import advances_for_measure
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from recognizer import resolve_single_staff_positions, validate_note_preservation, validate_score


def schedule(groups):
    pending = []
    def finish():
        durations = [[s.get_duration().fraction for s in group.symbols
                      if s.rhythm.startswith(('note', 'rest'))] for group in pending]
        if any('G' in s.rhythm or s.rhythm.endswith('m') for group in pending for s in group.symbols):
            raise ValueError('Grace and multi-measure rests require separate timing')
        for group, advance in zip(pending, advances_for_measure(durations), strict=True):
            group.get_duration = MethodType(lambda self, value=advance: value, group)
        pending.clear()
    for group in groups:
        if group.is_barline(): finish()
        elif group.symbols[0].rhythm.startswith(('note', 'rest')): pending.append(group)
    finish()
    return groups


def export(folder, mode):
    report = json.loads((folder / 'inference.json').read_text())
    tokens = []
    inputs = []
    for row in report['inputs']:
        if not row['baselineTerminated' if mode == 'greedy' else 'constrainedTerminated']:
            raise ValueError('Incomplete staff sequence')
        path = folder / mode / (row['staff'] + '.json')
        inputs.append({'staff': row['staff'], 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
        symbols = [EncodedSymbol(**s) for s in json.loads(path.read_text())]
        resolved, _ = resolve_single_staff_positions(symbols)
        tokens.extend(resolved); tokens.append(EncodedSymbol('newline'))
    original = writer.add_tuplet_start_stop
    with patch.object(writer, 'add_tuplet_start_stop', side_effect=lambda groups: schedule(original(groups))):
        root = writer.generate_xml(writer.XmlGeneratorArguments(), [tokens], '')
    validate_note_preservation(root, sum(s.rhythm.startswith('note') for s in tokens),
                               sum(s.rhythm.startswith('rest') for s in tokens))
    data = ET.tostring(root, encoding='utf-8', xml_declaration=True)
    validate_score(data)
    (folder / (mode + '-sustained.musicxml')).write_bytes(data)
    return inputs


if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('--results', type=Path, required=True); a = p.parse_args()
    report = {'shipping': False, 'referencesUsed': False, 'modes': {}}
    for mode in ['greedy', 'constrained']:
        try:
            with open(os.devnull, 'w') as quiet, contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
                inputs = export(a.results, mode)
            report['modes'][mode] = {'exported': True, 'inputs': inputs}
        except Exception as error: report['modes'][mode] = {'exported': False, 'error': str(error)}
    (a.results / 'sustained-inference.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v['exported'] for k, v in report['modes'].items()}))
