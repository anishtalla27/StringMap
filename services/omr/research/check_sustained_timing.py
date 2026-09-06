import unittest
from fractions import Fraction as F
from sustained_timing import advances_for_measure


class SustainedTimingTests(unittest.TestCase):
    def test_monophonic_timing_is_unchanged(self):
        durations = [F(1, 4), F(1, 8), F(3, 8)]
        self.assertEqual(advances_for_measure([[d] for d in durations]), durations)

    def test_earlier_chord_voice_can_resume_inside_later_note(self):
        # Quarter-note units: [1.5, 2], .5, [1, 1.5, 2], 1, .5.
        # The final eighth starts at 3.5, while the preceding quarter sustains.
        groups = [[F(3, 8), F(1, 2)], [F(1, 8)],
                  [F(1, 4), F(3, 8), F(1, 2)], [F(1, 4)], [F(1, 8)]]
        advances = advances_for_measure(groups)
        self.assertEqual(advances, [F(3, 8), F(1, 8), F(1, 4), F(1, 8), F(1, 8)])
        self.assertEqual(sum(advances), F(1))

    def test_final_sustained_tail_and_tuplets_are_exact(self):
        self.assertEqual(advances_for_measure([[F(1, 3), F(1, 8)], [F(1, 8)]]),
                         [F(1, 8), F(5, 24)])

    def test_grace_or_missing_duration_is_not_guessed(self):
        for groups in [[[]], [[F(0)]], [[F(-1)]]]:
            with self.assertRaises(ValueError): advances_for_measure(groups)


if __name__ == '__main__': unittest.main()
