"""Post-inference, provisional comparison using MusicXML system boundaries.

Never passed to recognition. Page/system boundaries and reference events need
independent visual verification before these metrics can qualify a release.
"""
import argparse
import copy
import json
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

from benchmark import SWIFT, compare
from compare_external_pack import read_events
from engine_benchmark import unpack_musicxml


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--results", type=Path, required=True)
    args = parser.parse_args()
    root = ET.fromstring(unpack_musicxml(args.reference))
    if len(root.findall("part")) != 1:
        raise ValueError("Evaluation requires a single-part reference")
    groups = []
    state = {}
    for index, measure in enumerate(root.findall("./part/measure")):
        page = measure.find("print")
        if index and page is not None and page.get("new-page") == "yes":
            break
        if not groups or page is not None and page.get("new-system") == "yes":
            groups.append([])
        for attributes in measure.findall("attributes"):
            for child in attributes:
                state[child.tag] = copy.deepcopy(child)
        clone = copy.deepcopy(measure)
        if not groups[-1]:
            attributes = clone.find("attributes")
            if attributes is None:
                attributes = ET.Element("attributes")
                clone.insert(0, attributes)
            for tag, child in state.items():
                if attributes.find(tag) is None:
                    attributes.append(copy.deepcopy(child))
        groups[-1].append(clone)
    rows = []
    actual_staffs = {int(match.group(1)) for path in args.results.glob('staff-*.musicxml')
                     if (match := re.fullmatch(r'staff-(\d+)', path.stem))}
    # Extra detected/predicted staffs must count as extra music, rather than
    # disappearing when we enumerate only the reference's staff boundaries.
    for staff in sorted(set(range(1, len(groups) + 1)) | actual_staffs):
        measures = groups[staff - 1] if 1 <= staff <= len(groups) else []
        reference = ET.Element("score-partwise")
        part = ET.SubElement(reference, "part", id="P1")
        part.extend(measures)
        sounding = read_events(reference)
        for attributes in reference.findall(".//attributes"):
            for transpose in attributes.findall("transpose"):
                attributes.remove(transpose)
        written = read_events(reference)
        path = args.results / f"staff-{staff}.musicxml"
        actual = read_events(ET.parse(path).getroot()) if path.exists() else []
        row = {"staff": staff, "referenceMeasures": [m.get("number") for m in measures],
               "musicXMLProduced": path.exists(), "writtenMetrics": compare(written, actual),
               "soundingMetrics": compare(sounding, actual)}
        if path.exists():
            row["swiftReview"] = json.loads(subprocess.check_output([str(SWIFT), str(path), "--for-review"], timeout=120))
        rows.append(row)
    totals = {key: sum(row["writtenMetrics"]["noteEvent"][key] for row in rows)
              for key in ["truePositive", "missing", "extra"]}
    denominator = 2 * totals["truePositive"] + totals["missing"] + totals["extra"]
    totals["f1"] = 2 * totals["truePositive"] / denominator if denominator else None
    output = {"releaseQualified": False, "boundaryStatus": "MusicXML first-page/system breaks; independent audit required",
              "reference": str(args.reference), "writtenNoteEventTotals": totals, "cases": rows}
    (args.results / "comparison.json").write_text(json.dumps(output, indent=2) + "\n")
    print(args.results, totals, flush=True)


if __name__ == "__main__":
    main()
