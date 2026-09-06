import unittest
from constrained_pitch import select_pitch


class PitchSelectionTests(unittest.TestCase):
    vocab = {0: '.', 1: '_', 2: 'B9', 3: 'C0', 4: 'E4'}

    def test_note_uses_highest_scored_pitched_class_without_octave_limits(self):
        selected, change = select_pitch('note_8', [0, 8, 4, 2, 3], self.vocab)
        self.assertEqual(selected, 2); self.assertEqual(change['rawPitch'], '_')
        self.assertEqual(change['selectedPitch'], 'B9')
        self.assertLess(change['selectedProbability'], change['rawProbability'])

    def test_valid_note_and_nonmusical_control_are_unchanged(self):
        self.assertEqual(select_pitch('note_4', [0, 0, 1, 5, 2], self.vocab), (3, None))
        self.assertEqual(select_pitch('barline', [4, 3, 2, 1, 0], self.vocab), (0, None))

    def test_rest_keeps_its_predicted_rhythm_and_uses_empty_pitch(self):
        selected, change = select_pitch('rest_2.', [0, 1, 2, 3, 4], self.vocab)
        self.assertEqual(selected, 1); self.assertEqual(change['rhythm'], 'rest_2.')

    def test_invalid_inputs_fail_and_ties_are_deterministic(self):
        with self.assertRaises(ValueError): select_pitch('note_4', [float('nan')], {0: 'C4'})
        with self.assertRaises(ValueError): select_pitch('note_4', [1], {0: '_'})
        with self.assertRaises(ValueError): select_pitch('note_4', [1, 2], {1: 'C4'})
        self.assertEqual(select_pitch('note_4', [0, 5, 1, 1, 1], self.vocab)[0], 2)


if __name__ == '__main__': unittest.main()
