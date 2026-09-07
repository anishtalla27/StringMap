from fractions import Fraction as F
import unittest
from homr.music_xml_generator import SymbolChord
from homr.transformer.vocabulary import EncodedSymbol
from symbol_timing import advances_for_measure, schedule_interleaved_groups


def group(*rhythms):
    return SymbolChord([EncodedSymbol(rhythm, pitch='C5', position='upper') for rhythm in rhythms])


class SymbolTimingTests(unittest.TestCase):
    def test_monophonic_durations_and_trailing_sustain(self):
        self.assertEqual(advances_for_measure([[F(1, 4)], [F(1, 8)], [F(3, 8)]]),
                         [F(1, 4), F(1, 8), F(3, 8)])
        self.assertEqual(advances_for_measure([[F(1, 3), F(1, 8)], [F(1, 8)]]),
                         [F(1, 8), F(5, 24)])

    def test_earlier_voice_resumes_before_newest_note_ends(self):
        self.assertEqual(advances_for_measure([[F(3, 8), F(1, 2)], [F(1, 8)],
                         [F(1, 4), F(3, 8), F(1, 2)], [F(1, 4)], [F(1, 8)]]),
                         [F(3, 8), F(1, 8), F(1, 4), F(1, 8), F(1, 8)])

    def test_boundaries_rests_and_original_symbols_are_preserved(self):
        groups = [group('note_4', 'rest_4.'), group('note_4'), group('rest_8'),
                  group('barline'), group('note_4')]
        originals = [(g.symbols, [s.get_duration().fraction for s in g.symbols]) for g in groups]
        self.assertIs(schedule_interleaved_groups(groups), groups)
        self.assertEqual([g.get_duration() for g in groups], [F(1, 4), F(1, 8), F(1, 8), F(0), F(1, 4)])
        for current, (symbols, durations) in zip(groups, originals, strict=True):
            self.assertIs(current.symbols, symbols)
            self.assertEqual([s.get_duration().fraction for s in current.symbols], durations)
        self.assertEqual([g.get_duration() for g in schedule_interleaved_groups(groups)],
                         [F(1, 4), F(1, 8), F(1, 8), F(0), F(1, 4)])

    def test_unsupported_timing_is_not_inferred(self):
        groups = [group('note_4', 'note_4.'), group('note_8G'), group('note_4')]
        expected = [g.get_duration() for g in groups]
        self.assertEqual([g.get_duration() for g in schedule_interleaved_groups(groups)], expected)
        for invalid in [[[]], [[F(0)]], [[F(-1)]]]:
            with self.assertRaises(ValueError): advances_for_measure(invalid)


if __name__ == '__main__': unittest.main()
