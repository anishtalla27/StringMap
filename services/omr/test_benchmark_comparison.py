"""Independent accounting checks for missing and extra predicted staffs."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from compare_staff_crops import main


class StaffComparisonTests(unittest.TestCase):
    def test_missing_and_extra_staffs_count_and_beam_candidates_do_not(self):
        note = '<note><pitch><step>E</step><octave>4</octave></pitch><duration>4</duration></note>'
        attributes = '<attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>'
        first = f'<measure number="1">{attributes}{note}</measure>'
        second = f'<measure number="2"><print new-system="yes"/>{note}</measure>'
        reference = f'<score-partwise><part id="P1">{first}{second}</part></score-partwise>'.encode()
        predicted = f'<score-partwise><part id="P1">{first}</part></score-partwise>'
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)
            (out/'staff-1.musicxml').write_text(predicted)
            (out/'staff-3.musicxml').write_text(predicted)
            (out/'staff-1-candidate-0.musicxml').write_text(predicted)
            with patch('sys.argv', ['compare_staff_crops', '--reference', 'test.mxl', '--results', folder]), \
                 patch('compare_staff_crops.unpack_musicxml', return_value=reference), \
                 patch('compare_staff_crops.subprocess.check_output', return_value=b'{"parsed":true}'), \
                 contextlib.redirect_stdout(io.StringIO()):
                main()
            result = json.loads((out/'comparison.json').read_text())
            self.assertEqual(result['writtenNoteEventTotals'], {'truePositive':1,'missing':1,'extra':1,'f1':0.5})
            self.assertEqual([r['staff'] for r in result['cases']], [1,2,3])
            self.assertEqual(result['cases'][2]['referenceMeasures'], [])


if __name__ == '__main__':
    unittest.main()
