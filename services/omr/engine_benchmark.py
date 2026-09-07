"""Compare real local recognizers against the same immutable image references.

References are used only after recognition, never as recognizer input. This
runner deliberately keeps each engine/version in a separate result directory.
It exercises the production Swift importer, optimizer and alphaTab MIDI path.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
import zipfile
import xml.etree.ElementTree as ET

from benchmark import ROOT, SWIFT, compare, events


def unpack_musicxml(path):
    with zipfile.ZipFile(path) as archive:
        container = archive.getinfo("META-INF/container.xml")
        if container.file_size > 100_000:
            raise ValueError("Invalid MusicXML container")
        root = ET.fromstring(archive.read(container))
        entry = next(x for x in root.iter() if x.tag.split('}')[-1] == 'rootfile')
        name = entry.attrib['full-path']
        info = archive.getinfo(name)
        if not 0 < info.file_size <= 10 * 1024 * 1024:
            raise ValueError("Invalid MusicXML size")
        return archive.read(info)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--engine', choices=['audiveris', 'homr'], required=True)
    parser.add_argument('--executable', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--corpus', type=Path, default=ROOT/'artifacts/omr-corpus')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--match', default='')
    parser.add_argument('--limit', type=int, default=1000)
    args = parser.parse_args()
    executable = args.executable.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((args.corpus/'manifest.json').read_text())
    cases = [x for x in manifest if args.match in x['id']][:args.limit]
    fingerprints = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in {
        'swiftBinarySHA256': SWIFT,
        'playbackVerifierSHA256': ROOT/'scripts/verify-score-playback.mjs',
        'sourceMapSHA256': ROOT/'apps/ios/StringMap/Resources/AlphaTab/source-note-map.js',
    }.items()}
    for case in cases:
        target = args.output/(case['id']+'.json')
        if target.exists():
            continue
        work = args.output/case['id']; work.mkdir(exist_ok=True)
        image = work/'page.jpg'; shutil.copyfile(args.corpus/case['image'], image)
        started = time.monotonic()
        result = {k: case[k] for k in ['id', 'category', 'capture', 'provenance']}
        result.update(engine=args.engine, version=args.version, **fingerprints,
                      imageSHA256=hashlib.sha256(image.read_bytes()).hexdigest(),
                      metrics=compare(case['expected'], []))
        (args.output/'progress.json').write_text(json.dumps({'case': case['id'], 'started': time.time()}))
        command = ([str(executable), '-batch', '-transcribe', '-export', '-output', str(work.resolve()), '--', str(image.resolve())]
                   if args.engine == 'audiveris' else [str(executable), '--gpu', 'no', '--no-title', str(image.resolve())])
        try:
            with (work/'recognizer.log').open('wb') as log:
                process = subprocess.run(command, stdout=log, stderr=log, timeout=300)
            result['exitCode'] = process.returncode
            if args.engine == 'audiveris':
                xml_data = unpack_musicxml(work/'page.mxl')
            else:
                xml_data = (work/'page.musicxml').read_bytes()
            xml = work/'result.musicxml'; xml.write_bytes(xml_data)
            result['recognitionStatus'] = 'completed'
            pipeline = json.loads(subprocess.check_output([str(SWIFT), str(xml)], timeout=120))
            result['pipeline'] = pipeline
            if pipeline['parsed']:
                result['metrics'] = compare(case['expected'], events(pipeline['score']))
                result['renderPlayback'] = json.loads(subprocess.check_output(
                    ['node', 'scripts/verify-score-playback.mjs'], input=json.dumps(pipeline).encode(), cwd=ROOT, timeout=30))
        except Exception as error:
            result['error'] = str(error)
            result.setdefault('recognitionStatus', 'failed')
        result['seconds'] = round(time.monotonic()-started, 3)
        target.write_text(json.dumps(result, indent=2)+'\n')
        print(json.dumps({'id': case['id'], 'seconds': result['seconds'], 'status': result['recognitionStatus'],
                          'noteEventF1': result['metrics']['noteEvent']['f1'], 'tabPlayable': result.get('pipeline', {}).get('tabPlayable')}), flush=True)
    rows = [json.loads((args.output/(c['id']+'.json')).read_text()) for c in cases if (args.output/(c['id']+'.json')).exists()]
    groups = {}
    for row in rows:
        group = groups.setdefault(row['capture'], {'images': 0, 'failures': 0, 'truePositive': 0, 'missing': 0, 'extra': 0})
        group['images'] += 1; group['failures'] += row['recognitionStatus'] != 'completed'
        for key in ['truePositive', 'missing', 'extra']:
            group[key] += row['metrics']['noteEvent'][key]
    for group in groups.values():
        d = 2*group['truePositive']+group['missing']+group['extra']
        group['noteEventF1'] = 2*group['truePositive']/d if d else None
    (args.output/'summary.json').write_text(json.dumps({'engine': args.engine, 'version': args.version, 'groups': groups}, indent=2)+'\n')
    print(json.dumps(groups))


if __name__ == '__main__':
    main()
