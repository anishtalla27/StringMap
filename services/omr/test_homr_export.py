"""Exercise the actual pinned XML writer, without model inference."""
from fractions import Fraction
from pathlib import Path
import tempfile
import unittest

from homr.music_xml_generator import generate_xml, XmlGeneratorArguments
from homr.transformer.vocabulary import EncodedSymbol, remove_duplicated_symbols
from recognizer import clean_preserving_notes
from patch_homr import (apply, verify, installed_path, ORIGINAL, REPLACEMENT,
                       REST_ORIGINAL, REST_REPLACEMENT, TIMING_IMPORT_ORIGINAL,
                       TIMING_IMPORT_REPLACEMENT, TIMING_ORIGINAL, TIMING_REPLACEMENT)


def symbol(rhythm, pitch='_'):
    return EncodedSymbol(rhythm, pitch=pitch, lift='_', articulation='_', slur='_', position='upper')


def export(short, long, reverse=False):
    members = [symbol(short, 'C5'), symbol(long, 'E4')]
    if reverse:
        members.reverse()
    tokens = [symbol('clef_G2'), EncodedSymbol('timeSignature/4'), members[0],
              EncodedSymbol('chord'), members[1], symbol('note_4', 'G4'), EncodedSymbol('barline')]
    root = generate_xml(XmlGeneratorArguments(), [tokens], '')
    divisions = Fraction(root.findtext('.//divisions'))
    cursor = Fraction(0); last = Fraction(0); events = {}
    for item in root.findall('./part/measure')[0]:
        if item.tag == 'backup':
            cursor -= Fraction(item.findtext('duration')) / divisions
        elif item.tag == 'note':
            duration = Fraction(item.findtext('duration')) / divisions
            onset = last if item.find('chord') is not None else cursor
            events[item.findtext('pitch/step')] = (onset, duration)
            if item.find('chord') is None:
                last = onset; cursor += duration
    return events, root


class ExactExportTests(unittest.TestCase):
    def test_earlier_sustained_voice_resumes_inside_newest_note(self):
        tokens = [symbol('clef_G2'), EncodedSymbol('timeSignature/4'),
                  symbol('note_4.', 'C5'), EncodedSymbol('chord'), symbol('note_2', 'C4'),
                  symbol('note_8', 'D5'), symbol('note_4', 'E5'), EncodedSymbol('chord'),
                  symbol('note_4.', 'E4'), symbol('note_4', 'F5'), symbol('note_8', 'D4'),
                  EncodedSymbol('barline')]
        root = generate_xml(XmlGeneratorArguments(), [tokens], '')
        divisions = Fraction(root.findtext('.//divisions'))
        cursor = Fraction(0); last = Fraction(0); events = {}
        for item in root.findall('./part/measure')[0]:
            if item.tag == 'backup': cursor -= Fraction(item.findtext('duration')) / divisions
            elif item.tag == 'note':
                duration = Fraction(item.findtext('duration')) / divisions
                onset = last if item.find('chord') is not None else cursor
                events[item.findtext('pitch/step') + item.findtext('pitch/octave')] = (onset, duration)
                if item.find('chord') is None: last = onset; cursor += duration
        self.assertEqual(events, {'C5': (0, Fraction(3, 2)), 'C4': (0, 2),
            'D5': (Fraction(3, 2), Fraction(1, 2)), 'E5': (2, 1), 'E4': (2, Fraction(3, 2)),
            'F5': (3, 1), 'D4': (Fraction(7, 2), Fraction(1, 2))})
        self.assertEqual(root.findtext('.//time/beats'), '4')

    def test_real_cleanup_cannot_rewrite_a_short_triplet_measure(self):
        tokens = [symbol('clef_G2'), EncodedSymbol('timeSignature/4'),
                  symbol('note_6', 'C5'), symbol('note_6', 'D5'), symbol('note_6', 'E5'),
                  EncodedSymbol('barline'), symbol('note_1', 'G5'), EncodedSymbol('barline')]
        protected, reason = clean_preserving_notes(tokens, remove_duplicated_symbols)
        self.assertIs(protected, tokens)
        self.assertEqual(reason, 'music')
        self.assertEqual([s.rhythm for s in tokens if s.rhythm.startswith('note')],
                         ['note_6', 'note_6', 'note_6', 'note_1'])
        cleaned, reason = clean_preserving_notes(
            tokens, lambda items: remove_duplicated_symbols(items, cleanup_tuplets=False))
        self.assertIsNone(reason)
        self.assertEqual([s.rhythm for s in cleaned if s.rhythm.startswith('note')],
                         ['note_6', 'note_6', 'note_6', 'note_1'])

    def test_simultaneous_triplet_duration_is_not_rounded(self):
        for reverse in [False, True]:
            events, _ = export('note_8', 'note_3', reverse)
            self.assertEqual(events, {'C': (0, Fraction(1, 2)), 'E': (0, Fraction(4, 3)),
                                      'G': (Fraction(1, 2), 1)})

    def test_dotted_quintuplet_and_following_onset_are_exact(self):
        events, _ = export('note_16', 'note_5.')
        self.assertEqual(events, {'C': (0, Fraction(1, 4)), 'E': (0, Fraction(6, 5)),
                                  'G': (Fraction(1, 4), 1)})

    def test_ordinary_mixed_duration_chord_stays_exact(self):
        events, _ = export('note_8', 'note_2')
        self.assertEqual(events, {'C': (0, Fraction(1, 2)), 'E': (0, 2),
                                  'G': (Fraction(1, 2), 1)})

    def test_patch_is_pinned_idempotent_and_refuses_unknown_source(self):
        original = (installed_path().read_bytes().replace(REPLACEMENT, ORIGINAL)
                    .replace(REST_REPLACEMENT, REST_ORIGINAL)
                    .replace(TIMING_IMPORT_REPLACEMENT, TIMING_IMPORT_ORIGINAL)
                    .replace(TIMING_REPLACEMENT, TIMING_ORIGINAL))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'music_xml_generator.py'; path.write_bytes(original)
            with self.assertRaises(RuntimeError): verify(path)
            self.assertTrue(apply(path)); verify(path)
            once = path.read_bytes(); self.assertFalse(apply(path)); self.assertEqual(path.read_bytes(), once)
            path.write_bytes(original.replace(ORIGINAL, REPLACEMENT))
            self.assertTrue(apply(path)); verify(path); self.assertEqual(path.read_bytes(), once)
            path.write_bytes(original.replace(ORIGINAL, REPLACEMENT).replace(REST_ORIGINAL, REST_REPLACEMENT))
            self.assertTrue(apply(path)); verify(path); self.assertEqual(path.read_bytes(), once)
            path.write_bytes(once + b'\n# unknown modification\n')
            before = path.read_bytes()
            with self.assertRaises(RuntimeError): apply(path)
            self.assertEqual(path.read_bytes(), before)

    def test_each_simultaneous_rest_keeps_its_own_voice_and_onset(self):
        tokens = [symbol('clef_G2'), EncodedSymbol('timeSignature/4'), symbol('rest_4'),
                  EncodedSymbol('chord'), symbol('rest_4'), EncodedSymbol('chord'),
                  symbol('note_4', 'C5'), symbol('note_2.', 'D5'), EncodedSymbol('barline')]
        root = generate_xml(XmlGeneratorArguments(), [tokens], '')
        rests = [n for n in root.findall('.//note') if n.find('rest') is not None]
        self.assertEqual(len(rests), 2)
        self.assertEqual(len({n.findtext('voice') for n in rests}), 2)
        divisions = Fraction(root.findtext('.//divisions'))
        self.assertTrue(all(Fraction(n.findtext('duration')) / divisions == 1 for n in rests))
        cursor = Fraction(0); onsets = []
        for item in root.findall('./part/measure')[0]:
            if item.tag == 'backup': cursor -= Fraction(item.findtext('duration')) / divisions
            elif item.tag == 'note':
                onsets.append((item.findtext('pitch/step', 'rest'), cursor))
                cursor += Fraction(item.findtext('duration')) / divisions
        self.assertEqual(onsets, [('C', 0), ('rest', 0), ('rest', 0), ('D', 1)])


if __name__ == '__main__':
    unittest.main()
