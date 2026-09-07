"""Assemble complete image-derived HOMR staff predictions, without references.

SPDX-License-Identifier: AGPL-3.0-or-later
Full-page assembly retains key/time state across staff breaks and all predicted
notes. No missing staff is silently skipped, no durations or pitches repaired.
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
from homr.music_xml_generator import XmlGeneratorArguments, generate_xml
from homr.transformer.vocabulary import EncodedSymbol
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from recognizer import resolve_single_staff_positions, validate_note_preservation, validate_score


def main():
    p=argparse.ArgumentParser();p.add_argument('--results',type=Path,required=True);a=p.parse_args()
    report=json.loads((a.results/'inference.json').read_text());summary={}
    for mode in ['greedy','beam']:
        output=a.results/(mode+'-page.musicxml');output.unlink(missing_ok=True)
        try:
            tokens=[];count=0
            for row in report['inputs']:
                if mode=='greedy':path=a.results/'greedy'/(row['staff']+'.json')
                else:
                    if row['selected'] is None:raise ValueError('A staff has no valid selected prediction')
                    path=a.results/(row['staff']+f"-candidate-{row['selected']}.json")
                raw=json.loads(path.read_text())
                if len(raw)>=608:raise ValueError('Staff reached decoder sequence limit')
                symbols=[EncodedSymbol(**s) for s in raw]
                symbols,_=resolve_single_staff_positions(symbols)
                count+=sum(s.rhythm.startswith('note') for s in symbols)
                tokens.extend(symbols);tokens.append(EncodedSymbol('newline'))
            with open(os.devnull,'w') as quiet,contextlib.redirect_stdout(quiet),contextlib.redirect_stderr(quiet):
                root=generate_xml(XmlGeneratorArguments(),[tokens],'')
                validate_note_preservation(root,count)
                data=ET.tostring(root,encoding='utf-8',xml_declaration=True);validate_score(data)
            output.write_bytes(data);summary[mode]={'exported':True,'predictedNotes':count,'exportedNotes':len(root.findall('.//note/pitch'))}
        except Exception as error:summary[mode]={'exported':False,'error':str(error)}
    (a.results/'page-assembly.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(a.results,summary,flush=True)


if __name__=='__main__':main()
