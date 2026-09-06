"""Post-inference timing diagnostic, never a recognizer input or correction.

Aligning measure indices deliberately removes accumulated timing drift. These
numbers are not whole-page accuracy and cannot qualify a release.
"""
import argparse
import copy
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from benchmark import compare
from compare_external_pack import read_events
from engine_benchmark import unpack_musicxml


def measure_events(root, first_page=False):
    if len(root.findall('part'))!=1:raise ValueError('Diagnostic requires one part')
    state={};result=[]
    for index,measure in enumerate(root.findall('./part/measure')):
        if first_page and index and measure.find("print[@new-page='yes']") is not None:break
        clone=copy.deepcopy(measure)
        inherited=ET.Element('attributes')
        inherited.extend(copy.deepcopy(child) for tag,child in state.items() if tag!='transpose')
        clone.insert(0,inherited)
        for attributes in measure.findall('attributes'):
            for child in attributes:state[child.tag]=copy.deepcopy(child)
        # Compare written pitch explicitly for both files, never search octaves.
        for attributes in clone.findall('attributes'):
            for transpose in attributes.findall('transpose'):attributes.remove(transpose)
        wrapper=ET.Element('score-partwise');ET.SubElement(wrapper,'part').append(clone)
        events=read_events(wrapper)
        result.append({'events':events,'end':max((e['onset']+e['duration'] for e in events),default=0)})
    return result


def diagnostic(reference, actual):
    refs=measure_events(reference,True);predictions=measure_events(actual)
    rows=[]
    for index in range(max(len(refs),len(predictions))):
        ref=refs[index] if index<len(refs) else {'events':[],'end':0}
        pred=predictions[index] if index<len(predictions) else {'events':[],'end':0}
        rows.append({'index':index+1,'actualEnd':pred['end'],'referenceEnd':ref['end'],'metrics':compare(ref['events'],pred['events'])})
    totals={key:sum(r['metrics']['noteEvent'][key] for r in rows) for key in ['truePositive','missing','extra']}
    denominator=2*totals['truePositive']+totals['missing']+totals['extra']
    totals['f1']=2*totals['truePositive']/denominator if denominator else None
    return {'limits':'Diagnostic only: aligns measure indices; barlines and boundaries are provisional; not whole-page timing accuracy.',
            'referenceMeasures':len(refs),'actualMeasures':len(predictions),'totals':totals,'measures':rows}


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--reference',type=Path,required=True);p.add_argument('--recognized',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    result=diagnostic(ET.fromstring(unpack_musicxml(a.reference)),ET.parse(a.recognized).getroot())
    a.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result['totals']))
