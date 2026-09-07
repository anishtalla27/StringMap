"""Musical consistency checks for choosing image-derived candidates.

SPDX-License-Identifier: AGPL-3.0-or-later

Never changes notes or timing. No benchmark references, guitar fingering costs,
pitch-range assumptions or octave adjustments enter candidate selection.
"""
from fractions import Fraction
import xml.etree.ElementTree as ET


def audit(data: bytes) -> dict:
    root = ET.fromstring(data)
    divisions = Fraction(1); meter = Fraction(4)
    issues = []; overflow = Fraction(0); underflow = Fraction(0)
    measures = root.findall('./part/measure')
    for index, measure in enumerate(measures):
        cursor = Fraction(0); end = Fraction(0); last_onset = Fraction(0)
        for item in measure:
            if item.tag == 'attributes':
                if item.find('divisions') is not None: divisions = Fraction(item.findtext('divisions'))
                time = item.find('time')
                if time is not None and time.find('beats') is not None:
                    meter = Fraction(time.findtext('beats')) * 4 / Fraction(time.findtext('beat-type'))
            elif item.tag == 'backup': cursor -= Fraction(item.findtext('duration')) / divisions
            elif item.tag == 'forward':
                cursor += Fraction(item.findtext('duration')) / divisions; end = max(end, cursor)
            elif item.tag == 'note':
                duration = Fraction(item.findtext('duration', '0')) / divisions
                onset = last_onset if item.find('chord') is not None else cursor
                end = max(end, onset + duration)
                if item.find('chord') is None: cursor += duration; last_onset = onset
        if end > meter:
            overflow += end-meter
            issues.append(f'Measure {measure.get("number",str(index+1))} has more beats than its time signature. Check for extra rests and incorrect durations.')
        elif end < meter and index not in [0, len(measures)-1] and measure.get('implicit') != 'yes':
            underflow += meter-end
            issues.append(f'Measure {measure.get("number",str(index+1))} has fewer beats than its time signature. Check for missing notes or rests.')
    return {'overflowQuarters': float(overflow), 'underflowQuarters': float(underflow), 'warnings': issues}


def rank(quality: dict, counts: list[dict]) -> tuple:
    return (quality['overflowQuarters'], quality['underflowQuarters'],
            sum(abs(c['detected']-c['recognized']) for c in counts))
