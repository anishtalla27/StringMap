"""Run directly in the isolated Zeus environment, outside service discovery."""
import unittest
from zeus_timing_search import prefix_has_nonnegative_timing


class PrefixTimingTests(unittest.TestCase):
    def test_backup_cannot_cross_start(self):
        self.assertFalse(prefix_has_nonnegative_timing('measure clef:G2 C4 quarter backup half'))
        self.assertTrue(prefix_has_nonnegative_timing('measure clef:G2 C4 quarter backup quarter'))

    def test_dots_and_triplets_use_exact_durations(self):
        self.assertTrue(prefix_has_nonnegative_timing('measure clef:G2 C4 quarter dot backup quarter backup eighth'))
        self.assertFalse(prefix_has_nonnegative_timing('measure clef:G2 C4 eighth 3in2 backup eighth'))
        self.assertTrue(prefix_has_nonnegative_timing('measure clef:G2 C4 eighth 3in2 backup eighth 3in2'))

    def test_chords_do_not_advance_twice(self):
        self.assertFalse(prefix_has_nonnegative_timing('measure clef:G2 C4 quarter chord E4 quarter backup half'))

    def test_measure_boundary_resets_cursor(self):
        self.assertFalse(prefix_has_nonnegative_timing('measure clef:G2 C4 whole measure backup quarter'))

    def test_incomplete_prefix_is_not_repaired_or_rejected(self):
        self.assertTrue(prefix_has_nonnegative_timing('measure clef:G2 C4'))
        self.assertTrue(prefix_has_nonnegative_timing('measure clef:G2 C4 quarter backup'))


if __name__ == '__main__':
    unittest.main()
