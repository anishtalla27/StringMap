"""Image-only research cohort; compare references only after inference finishes.

SPDX-License-Identifier: AGPL-3.0-or-later
Uses canonical full-height staff crops and HTTP-equivalent image normalization.
This is not the production retry pipeline or a release qualification.
"""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from production import prepare_page


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pack', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    research = Path(__file__).resolve().parent
    report = {'shipping': False, 'referencesUsed': False, 'cases': []}
    environment = {**os.environ, 'OPENBLAS_NUM_THREADS': '1', 'OMP_NUM_THREADS': '1'}
    for case in csv.DictReader((args.pack / 'manifest.csv').open()):
        if case['kind'] != 'printed_guitar':
            continue
        name = Path(case['image']).stem
        folder = args.output / name
        folder.mkdir()
        started = time.monotonic()
        data = (args.pack / case['image']).read_bytes()
        row = {'id': name, 'sourceSHA256': hashlib.sha256(data).hexdigest()}
        try:
            normalized = folder / 'normalized.jpg'
            prepare_page(data).save(normalized, 'JPEG', quality=95)
            row['normalizedSHA256'] = hashlib.sha256(normalized.read_bytes()).hexdigest()
            with (folder / 'extraction.log').open('w') as log:
                subprocess.run([sys.executable, str(research / 'extract_guitar_staffs.py'),
                                '--image', str(normalized), '--output', str(folder / 'crops'),
                                '--full-height'], stdout=log, stderr=subprocess.STDOUT,
                               check=True, timeout=180, env=environment)
            with (folder / 'inference.log').open('w') as log:
                subprocess.run([sys.executable, str(research / 'evaluate_pitch_consistency.py'),
                                '--crops', str(folder / 'crops'), '--output', str(folder / 'results')],
                               stdout=log, stderr=subprocess.STDOUT, check=True,
                               timeout=180, env=environment)
            row['inference'] = json.loads((folder / 'results/inference.json').read_text())
            row['status'] = 'completed'
        except Exception as error:
            row.update(status='failed', error=str(error))
        row['seconds'] = time.monotonic() - started
        report['cases'].append(row)
        (args.output / 'cohort.json').write_text(json.dumps(report, indent=2) + '\n')
        print(name, row['status'], row.get('inference', {}).get('pageExports'), flush=True)


if __name__ == '__main__':
    main()
