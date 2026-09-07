"""Isolated image-only Audiveris trial; reference comparison runs after inference.

No result is selected or edited using a reference. Output metrics retain the
provisional MusicXML page-boundary limitation of the supplied external pack.
"""
import argparse
import copy
import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from benchmark import ROOT, SWIFT, compare
from compare_external_pack import read_events
from engine_benchmark import unpack_musicxml


def written_events(root, first_page=False):
    root = copy.deepcopy(root)
    for parent in root.iter():
        for child in list(parent):
            if child.tag == 'transpose':
                parent.remove(child)
    return read_events(root, first_page)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--pack', type=Path, default=ROOT/'artifacts/external-notation-pack/StringMap_notation_test_pack')
    p.add_argument('--app', type=Path, default=ROOT/'artifacts/engine-evaluation/tools/Audiveris.app')
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--ids', type=int, nargs='+', required=True)
    p.add_argument('--deskew', action='store_true')
    p.add_argument('--scale', type=int, choices=[1,2], default=1)
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    rows = list(csv.DictReader((args.pack/'manifest.csv').open()))
    rows = [r for r in rows if r['kind'] == 'printed_guitar' and int(Path(r['image']).stem.split('_')[0]) in args.ids]
    assert len(rows) == len(set(args.ids)), 'Every requested image must exist'
    executable = (args.app/'Contents/MacOS/Audiveris').resolve()
    report = {'engine':'Audiveris 5.11.0', 'jarSHA256':hashlib.sha256((args.app/'Contents/app/audiveris.jar').read_bytes()).hexdigest(),
              'referencesUsedByInference':False, 'releaseQualified':False, 'shippingChanged':False, 'realCameraImages':0,
              'referenceBoundaryStatus':'Provisional first MusicXML page; independent PDF audit required', 'cases':[]}
    report['preparation'] = {'deskew':args.deskew,'scale':args.scale}
    for row in rows:
        ident = Path(row['image']).stem
        folder = args.output/ident; folder.mkdir()
        image = folder/'page.jpg'; shutil.copy2(args.pack/row['image'], image)
        case = {'id':ident, 'imageSHA256':hashlib.sha256(image.read_bytes()).hexdigest()}
        start = time.monotonic()
        try:
            if args.deskew or args.scale != 1:
                from deskew_page import prepare
                target = folder/'prepared.png'
                case['imagePreparation'] = prepare(image,target,deskew=args.deskew,scale=args.scale)
                image = target

            with (folder/'recognizer.log').open('wb') as log:
                run = subprocess.run([str(executable), '-batch','-transcribe','-export','-output',str(folder.resolve()),'--',str(image.resolve())],
                                     stdout=log,stderr=log,timeout=300)
            case['exitCode'] = run.returncode
            data = unpack_musicxml(folder/(image.stem+'.mxl'))
            target = folder/'recognized.musicxml'; target.write_bytes(data)
            case.update(status='completed', recognitionSeconds=round(time.monotonic()-start,3), xmlSHA256=hashlib.sha256(data).hexdigest())
            actual_root = ET.fromstring(data)
            # References are first opened here, after the immutable XML export.
            reference = ET.fromstring(unpack_musicxml(args.pack/row['matching_musicxml']))
            case['writtenWholePageMetrics'] = compare(written_events(reference,True),written_events(actual_root))
            case['soundingWholePageMetrics'] = compare(read_events(reference,True),read_events(actual_root))
            for mode, flags in [('strict',[]),('review',['--for-review'])]:
                native = json.loads(subprocess.check_output([str(SWIFT),str(target),'--guitar-photo']+flags,timeout=120))
                (folder/(mode+'-native.json')).write_text(json.dumps(native,indent=2)+'\n')
                entry={'parsed':native['parsed'],'error':native.get('error'),'tabPlayable':native.get('tabPlayable'),
                       'notationError':native.get('notationError'),'unresolvedMarks':len(native.get('score',{}).get('reviewIssues') or [])}
                if native.get('notationAlphaTex'):
                    playback=json.loads(subprocess.check_output(['node',str(ROOT/'scripts/verify-score-playback.mjs')],input=json.dumps(native).encode(),cwd=ROOT,timeout=60))
                    (folder/(mode+'-playback.json')).write_text(json.dumps(playback,indent=2)+'\n')
                    entry['playback']=playback
                case[mode]=entry
        except Exception as error:
            case.setdefault('status','failed');case['error']=str(error)
        case['totalSeconds']=round(time.monotonic()-start,3)
        report['cases'].append(case)
        (args.output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(case),flush=True)


if __name__ == '__main__':
    main()
