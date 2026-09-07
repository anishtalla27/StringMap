"""Research-only guitar staff images for evaluating separate recognition models.

Only the supplied image enters this process. No MusicXML reference is loaded.
Rejects unsupported staff layouts rather than trimming or merging staves.
"""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
from unittest.mock import patch

import cv2
import numpy as np
from homr.main import ProcessingConfig, detect_staffs_in_image
from homr.staff_parsing import prepare_staff_image
from homr.staff_regions import StaffRegions
from homr import staff_parsing
from column_staff_crop import crop_staff


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--full-height', action='store_true', help='Keep canonical HOMR crop bounds for its encoder')
    parser.add_argument('--horizontal-margin-units', type=float, default=2,
                        help='Research crop margin in staff spaces; upstream default is 2')
    parser.add_argument('--column-dewarp', action='store_true', help='Research column-wise staff resampling')
    parser.add_argument('--common-span', action='store_true', help='Extend short detected ranges only when a majority of staffs agree on page width')
    args = parser.parse_args()
    if not 2 <= args.horizontal_margin_units <= 20:
        parser.error('Horizontal margin must be between 2 and 20 staff spaces')
    args.output.mkdir(exist_ok=False, parents=True)
    image = args.output / ('page' + args.image.suffix)
    image.write_bytes(args.image.read_bytes())
    report = {'referenceUsed':False, 'shipping':False, 'horizontalMarginUnits':args.horizontal_margin_units,
              'columnDewarp':args.column_dewarp,
              'sourceSHA256':hashlib.sha256(image.read_bytes()).hexdigest(), 'staffs':[]}
    debug = None
    try:
        with open(os.devnull, 'w') as quiet, contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
            groups, pixels, debug, _, count = detect_staffs_in_image(str(image), ProcessingConfig(False,False,False,False,-1,False,False,False,False))
            if len(groups) != count or any(len(g.staffs) != 1 or g.staffs[0].is_grandstaff for g in groups):
                raise ValueError('Unsupported or unresolved staff layout; no staffs were discarded')
            regions = StaffRegions(groups)
            spans = np.array([g.staffs[0].max_x-g.staffs[0].min_x for g in groups], dtype=float)
            median = float(np.median(spans)); common_span = None
            if args.common_span and len(spans) >= 3 and sum(abs(spans-median) <= median*0.05) >= len(spans)*0.6:
                common_span = median
            report['commonSpan'] = common_span
            original_region = staff_parsing._calculate_region
            def expanded_region(staff, regions):
                region = original_region(staff, regions).copy()
                extra = int(round((args.horizontal_margin_units-2)*staff.average_unit_size))
                region[0] -= extra; region[2] += extra
                if common_span is not None:
                    region[2] = max(region[2], int(np.ceil(staff.min_x+common_span+args.horizontal_margin_units*staff.average_unit_size)))
                return region
            for i, group in enumerate(groups, 1):
                if args.column_dewarp:
                    crop = crop_staff(pixels, group.staffs[0], args.horizontal_margin_units, common_span)
                else:
                    with patch.object(staff_parsing, '_calculate_region', side_effect=expanded_region):
                        crop, _ = prepare_staff_image(debug, i-1, group.staffs[0], pixels, regions=regions)
                gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY) if crop.ndim == 3 else crop
                rows = np.flatnonzero((gray < 128).sum(axis=1) >= max(4, gray.shape[1]//1000))
                if not rows.size:
                    raise ValueError('An entire staff crop is empty')
                top, bottom = max(0,int(rows[0])-8), min(gray.shape[0],int(rows[-1])+9)
                if args.full_height:
                    top, bottom = 0, gray.shape[0]
                target = args.output / f'staff-{i}.png'
                if not cv2.imwrite(str(target), gray[top:bottom]):
                    raise OSError('Failed to write staff crop')
                report['staffs'].append({'staff':i,'detectedNotes':group.staffs[0].get_number_of_notes(),'cropBounds':[0,top,gray.shape[1],bottom],'cropSHA256':hashlib.sha256(target.read_bytes()).hexdigest()})
        report['status'] = 'completed'
    except Exception as error:
        report.update(status='failed', error=str(error))
        raise
    finally:
        if debug is not None:
            debug.clean_debug_files_from_previous_runs()
        (args.output/'extraction.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Extracted',len(report['staffs']),'staffs',flush=True)


if __name__ == '__main__':
    main()
