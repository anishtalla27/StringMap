"""Research-only Clarity export of independently detected guitar staves.

Consumes retained predictions, not references. Keeps raw token order, predicted
key/time changes and every staff. Bypasses upstream piano grouping, majority
key/time replacement, measure normalization and token post-processing. The
upstream serializer is still experimental; record preservation checks and keep
both raw predictions and XML rather than treating a valid file as accuracy.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("predictions", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--repository", type=Path, default=Path("artifacts/clarity-omr-evaluation"))
args = parser.parse_args()
sys.path.insert(0, str(args.repository.resolve()))

from src.pipeline.assemble_score import AssembledScore, AssembledStaff, AssembledSystem, StaffLocation
from src.pipeline.export_musicxml import write_musicxml, _parse_pitch_token
from music21.pitch import Pitch

rows = [json.loads(line) for line in args.predictions.read_text().splitlines() if line.strip()]
systems = []
expected_pitches = Counter()
for index, row in enumerate(rows):
    tokens = row["tokens"]
    if "<eos>" not in tokens:
        raise ValueError(f"Unfinished prediction for {row['sample_id']}; do not export truncated music")
    for token in tokens:
        if token.startswith("note-"):
            expected_pitches[int(Pitch(_parse_pitch_token(token)).midi)] += 1
    def first(prefix):
        return next((token for token in tokens if token.startswith(prefix)), None)
    measures = tokens.count("<measure_start>")
    staff = AssembledStaff(row["sample_id"], tokens, "guitar", measures,
                           first("clef-"), first("keySignature-"), first("timeSignature-"),
                           StaffLocation(0, index * 100, index * 100 + 90, 0, 1000))
    systems.append(AssembledSystem(0, index, [staff], measures, staff.key_signature, staff.time_signature))

result = write_musicxml(AssembledScore(systems, ["guitar"]), args.output)
root = ET.parse(args.output).getroot()
actual_pitches = Counter()
for pitch in root.findall("./part/measure/note/pitch"):
    midi = 12 * (int(pitch.findtext("octave")) + 1)
    midi += {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}[pitch.findtext("step")]
    midi += int(pitch.findtext("alter", "0"))
    actual_pitches[midi] += 1
result.update({"inputStaves": len(rows), "inputNoteTokens": sum(expected_pitches.values()),
               "outputNoteEntries": sum(actual_pitches.values()),
               "pitchMultisetPreserved": actual_pitches == expected_pitches,
               "releaseQualified": False})
args.output.with_suffix(".export.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
