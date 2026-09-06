"""Regression tests for recognition validation and image-derived retry selection."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace
from PIL import Image
from recognizer import (recognize, validate_score, UnsupportedPage,
                        resolve_single_staff_positions, clean_preserving_notes,
                        validate_note_preservation, validate_prediction_length,
                        opening_notation_warnings)
from score_quality import audit


def score(measures, divisions=12):
    attributes = f'<attributes><divisions>{divisions}</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>'
    return ('<score-partwise><identification><miscellaneous/></identification><part id="P1">' + ''.join(
        f'<measure number="{i+1}">{attributes if i == 0 else ""}{content}</measure>'
        for i, content in enumerate(measures)) + '</part></score-partwise>').encode()


def note(duration=12, pitch='C', extra=''):
    return f'<note>{extra}<pitch><step>{pitch}</step><octave>4</octave></pitch><duration>{duration}</duration></note>'


class RecognitionTests(unittest.TestCase):
    def test_missing_opening_context_is_reported_without_rewriting_symbols(self):
        symbols = [SimpleNamespace(rhythm='note_4', pitch='E4'),
                   SimpleNamespace(rhythm='clef_G2'), SimpleNamespace(rhythm='keySignature_1')]
        warnings = opening_notation_warnings(symbols)
        self.assertEqual(len(warnings), 3)
        self.assertTrue(any('4/4 default' in w for w in warnings))
        self.assertEqual(symbols[0].pitch, 'E4')
        self.assertEqual(len(symbols), 3)

    def test_explicit_opening_context_including_zero_accidentals_is_not_missing(self):
        symbols = [SimpleNamespace(rhythm=r) for r in
                   ['clef_G2', 'keySignature_0', 'timeSignature/4', 'rest_4', 'note_4']]
        self.assertEqual(opening_notation_warnings(symbols), [])
        self.assertEqual(len(opening_notation_warnings(symbols[1:])), 1)

    def test_sequence_limit_cannot_be_exported_as_a_completed_staff(self):
        # EOS is not included in the upstream symbol list. A sequence one
        # shorter than the cap can finish on the final decoder iteration.
        symbols = [SimpleNamespace(rhythm='note_4', pitch='E4')] * 608
        validate_prediction_length(symbols[:-1], 608)
        with self.assertRaisesRegex(ValueError, 'No truncated score'):
            validate_prediction_length(symbols, 608)
        with self.assertRaises(ValueError): validate_prediction_length(symbols, 607)

    def test_cleanup_cannot_drop_unison_voice_or_mutate_its_fallback(self):
        symbols = [SimpleNamespace(rhythm='note_4', pitch='E4', position='upper'),
                   SimpleNamespace(rhythm='chord', position='upper'),
                   SimpleNamespace(rhythm='note_2', pitch='E4', position='upper')]
        def lossy_cleanup(copied):
            copied[0].rhythm = 'note_8'
            return copied[:1]
        result, warning = clean_preserving_notes(symbols, lossy_cleanup)
        self.assertTrue(warning)
        self.assertIs(result, symbols)
        self.assertEqual([s.rhythm for s in result], ['note_4', 'chord', 'note_2'])
        self.assertEqual([s.pitch for s in result if s.rhythm.startswith('note')], ['E4', 'E4'])

    def test_lossless_cleanup_still_removes_redundant_layout_symbols(self):
        symbols = [SimpleNamespace(rhythm='clef_G2'), SimpleNamespace(rhythm='clef_G2'),
                   SimpleNamespace(rhythm='note_4')]
        result, warning = clean_preserving_notes(symbols, lambda copied: copied[1:])
        self.assertFalse(warning)
        self.assertEqual([s.rhythm for s in result], ['clef_G2', 'note_4'])

    def test_cleanup_cannot_change_rhythm_pitch_tie_or_drop_rests(self):
        original = [SimpleNamespace(rhythm='note_12', pitch='E4', slur='start'),
                    SimpleNamespace(rhythm='chord'), SimpleNamespace(rhythm='rest_4')]
        for field, value in [('rhythm', 'note_8'), ('pitch', 'F4'), ('slur', 'stop')]:
            def change(items):
                setattr(items[0], field, value)
                return items
            result, reason = clean_preserving_notes(original, change)
            self.assertIs(result, original); self.assertEqual(reason, 'music')
        for cleanup in [lambda items: items[:-1], lambda items: [items[0], items[-1]]]:
            result, reason = clean_preserving_notes(original, cleanup)
            self.assertIs(result, original); self.assertEqual(reason, 'music')
        self.assertEqual(vars(original[0]), {'rhythm': 'note_12', 'pitch': 'E4', 'slur': 'start'})

    def test_xml_export_must_also_preserve_every_recognized_rest(self):
        root = validate_score(score([note() + '<note><rest/><duration>12</duration></note>']))
        validate_note_preservation(root, 1, 1)
        for expected in [0, 2]:
            with self.assertRaisesRegex(ValueError, 'recognized rests'):
                validate_note_preservation(root, 1, expected)

    def test_xml_export_must_preserve_every_predicted_note_including_unisons(self):
        root = validate_score(score([note() + note(24, extra='<chord/>')]))
        validate_note_preservation(root, 2)
        for expected in [1, 3]:
            with self.assertRaises(ValueError): validate_note_preservation(root, expected)
        coerced = validate_score(score([note() + '<note><rest/><duration>12</duration></note>']))
        with self.assertRaises(ValueError): validate_note_preservation(coerced, 2)

    def test_single_treble_staff_recovers_stray_labels_without_changing_or_dropping_music(self):
        clef = SimpleNamespace(rhythm='clef_G2', position='upper')
        low = SimpleNamespace(rhythm='note_16', position='lower', pitch='B3', lift='#', slur='start')
        rest = SimpleNamespace(rhythm='rest_8', position='lower')
        original = [clef, low, rest]
        resolved, count = resolve_single_staff_positions(original)
        self.assertEqual(count, 2)
        self.assertEqual(len(resolved), len(original))
        for before, after in zip(original, resolved):
            self.assertEqual({k:v for k,v in vars(before).items() if k!='position'},
                             {k:v for k,v in vars(after).items() if k!='position'})
            self.assertEqual(after.position, 'upper')
        self.assertEqual(low.position, 'lower')
        self.assertEqual(rest.position, 'lower')

    def test_second_clef_or_missing_treble_anchor_is_not_silently_merged(self):
        upper = SimpleNamespace(rhythm='clef_G2', position='upper')
        lower = SimpleNamespace(rhythm='clef_F4', position='lower')
        note = SimpleNamespace(rhythm='note_4', position='lower')
        for symbols in [[upper, lower, note], [note]]:
            with self.assertRaises(ValueError): resolve_single_staff_positions(symbols)

    def test_validation_rejects_empty_multiple_or_grand_staff_scores_and_entities(self):
        for data in [b'<score-partwise/>', b'<score-partwise><part/><part/></score-partwise>',
                     score(['<attributes><staves>2</staves></attributes>'+note()]),
                     score([note(extra='<staff>2</staff>')])]:
            with self.assertRaises(UnsupportedPage): validate_score(data)
        for data in [score(['<note><rest/><duration>48</duration></note>']), b'<!ENTITY x "bad">', b'']:
            with self.assertRaises(ValueError): validate_score(data)
        self.assertEqual(len(validate_score(score([note()+note(extra='<chord/>')])).findall('.//note')), 2)

    def test_polyphony_chords_and_triplets_do_not_overcount_measure_duration(self):
        voices = note(48, 'E') + '<backup><duration>48</duration></backup>' + note(12)*4
        chords = (note(12)+note(12,'E','<chord/>'))*4
        triplets = note(4)*3 + note(36)
        self.assertEqual(audit(score([voices, chords, triplets]))['warnings'], [])

    def test_pickup_and_closing_partial_bars_are_allowed_but_internal_gap_is_reported(self):
        quality = audit(score([note(), note(24), note(36)]))
        self.assertEqual(quality['underflowQuarters'], 2)
        self.assertEqual(len(quality['warnings']), 1)
        self.assertIn('Measure 2', quality['warnings'][0])

    def test_extra_rest_is_reported_without_rewriting_notes(self):
        data = score([note(48), '<note><rest/><duration>12</duration></note>'+note(48)])
        self.assertEqual(audit(data)['overflowQuarters'], 1)
        self.assertIn('Measure 2', audit(data)['warnings'][0])
        self.assertEqual(data, score([note(48), '<note><rest/><duration>12</duration></note>'+note(48)]))

    def test_retry_selects_complete_image_reading_preserving_its_pitches(self):
        original = score([note(60, 'C')]); alternative = score([note(48, 'F')])
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); image=root/'input.jpg'; output=root/'result.musicxml'
            Image.new('RGB',(100,100),'white').save(image)
            paths=[]
            def reader(source, target):
                paths.append(source)
                target.write_bytes(original if len(paths)==1 else alternative)
                return {'staffCount':1,'noteCounts':[{'detected':1,'recognized':1}]}
            with patch('recognizer.recognize_once', side_effect=reader): result=recognize(image,output)
            self.assertEqual(result['attempts'],2)
            self.assertEqual(output.read_bytes(),alternative)
            self.assertNotEqual(paths[0],paths[1])
            self.assertFalse(list(root.glob('candidate-*'))+list(root.glob('variant-*')))

    def test_failed_retries_keep_original_notes_and_surface_timing_warning(self):
        original=score([note(60,'G')])
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);image=root/'input.jpg';output=root/'result.musicxml'
            Image.new('RGB',(100,100),'white').save(image)
            calls=0
            def reader(source,target,preparation="standard"):
                nonlocal calls
                calls+=1
                if calls>1: raise ValueError('Unreadable alternative')
                target.write_bytes(original)
                return {'staffCount':1,'noteCounts':[{'detected':1,'recognized':1}]}
            with patch('recognizer.recognize_once',side_effect=reader): result=recognize(image,output)
            self.assertEqual(result['attempts'],4)
            self.assertEqual(result['timingWarnings'],1)
            xml=validate_score(output.read_bytes())
            self.assertEqual(xml.findtext('.//pitch/step'),'G')
            self.assertEqual(xml.findtext('.//note/duration'),'60')
            self.assertIn('more beats',xml.findtext('.//miscellaneous-field'))
            self.assertFalse(list(root.glob('candidate-*'))+list(root.glob('variant-*')))

    def test_unreadable_first_pass_is_reread_without_inventing_missing_pitches(self):
        valid = score([note(48, 'F')])
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); image=root/'input.jpg'; output=root/'result.musicxml'
            Image.new('RGB',(100,100),'white').save(image)
            calls=[]
            def reader(source,target,preparation="standard"):
                calls.append(source)
                if len(calls)==1:
                    target.write_bytes(b'incomplete output')
                    raise ValueError('A note has no pitch')
                target.write_bytes(valid)
                return {'staffCount':1,'noteCounts':[{'detected':1,'recognized':1}]}
            with patch('recognizer.recognize_once',side_effect=reader): result=recognize(image,output)
            self.assertEqual(result['attempts'],2)
            self.assertEqual(output.read_bytes(),valid)
            self.assertNotEqual(calls[0],calls[1])
            self.assertFalse(list(root.glob('candidate-*'))+list(root.glob('variant-*')))

    def test_unreadable_page_exhausts_bounded_retries_and_leaves_no_partial_score(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); image=root/'input.jpg'; output=root/'result.musicxml'
            Image.new('RGB',(100,100),'white').save(image)
            def reader(source,target,preparation="standard"):
                target.write_bytes(b'partial')
                raise ValueError('Missing pitch')
            with patch('recognizer.recognize_once',side_effect=reader) as mock:
                with self.assertRaisesRegex(ValueError,'Missing pitch'): recognize(image,output)
            self.assertEqual(mock.call_count,4)
            self.assertEqual(list(root.iterdir()),[image])

    def test_clean_original_does_not_trigger_image_retries(self):
        clean = score([note(48, 'E')])
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); image=root/'input.jpg'; output=root/'result.musicxml'
            Image.new('RGB',(100,100),'white').save(image)
            def reader(source,target):
                target.write_bytes(clean)
                return {'staffCount':1,'noteCounts':[{'detected':1,'recognized':1}]}
            with patch('recognizer.recognize_once',side_effect=reader) as mock:
                result=recognize(image,output)
            self.assertEqual(mock.call_count,1)
            self.assertEqual(result['attempts'],1)
            self.assertEqual(output.read_bytes(),clean)

    def test_column_retry_accepts_only_a_reading_without_timing_warnings(self):
        original=score([note(72,'G')])
        for candidate, accepted in [(score([note(24,'E')+note(24,'F')]),True),
                                     (score([note(60,'E')]),False)]:
            with self.subTest(accepted=accepted), tempfile.TemporaryDirectory() as temp:
                root=Path(temp); image=root/'input.jpg'; output=root/'result.musicxml'
                Image.new('RGB',(100,100),'white').save(image)
                preparations=[]
                def reader(source,target,preparation='standard'):
                    preparations.append(preparation)
                    if preparation=='standard' and len(preparations)>1:
                        raise ValueError('Unreadable rotation')
                    target.write_bytes(candidate if preparation=='column' else original)
                    count=2 if preparation=='column' and accepted else 1
                    return {'staffCount':1,'preparation':preparation,
                            'noteCounts':[{'detected':count,'recognized':count}]}
                with patch('recognizer.recognize_once',side_effect=reader):
                    result=recognize(image,output)
                self.assertEqual(preparations,['standard']*3+['column'])
                self.assertEqual(result['attempts'],4)
                self.assertEqual(result['preparation'],'column' if accepted else 'standard')
                pitches=[n.findtext('pitch/step') for n in validate_score(output.read_bytes()).findall('.//note')]
                self.assertEqual(pitches,['E','F'] if accepted else ['G'])
                self.assertEqual(result['timingWarnings'],0 if accepted else 1)
                self.assertFalse(list(root.glob('candidate-*'))+list(root.glob('variant-*')))

    def test_deskew_recovers_only_after_all_other_readings_fail_and_cleans_up(self):
        recovered = score([note(24, 'E')])
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); image=root/'input.jpg'; output=root/'result.musicxml'
            Image.new('RGB',(100,100),'white').save(image)
            def straighten(source,target):
                Image.new('RGB',(100,100),'white').save(target)
                return {'rotationDegrees':6.0}
            def reader(source,target,preparation="standard"):
                if source.name!='variant-deskew.png': raise ValueError('Unreadable original')
                target.write_bytes(recovered)
                return {'staffCount':1,'noteCounts':[{'detected':1,'recognized':1}]}
            with patch('recognizer.recognize_once',side_effect=reader) as calls, patch('page_image.prepare_deskewed_page',side_effect=straighten):
                result=recognize(image,output)
            self.assertEqual(calls.call_count,5)
            self.assertEqual(result['attempts'],5)
            self.assertEqual(result['pageDeskew']['rotationDegrees'],6)
            self.assertEqual(validate_score(output.read_bytes()).findtext('.//pitch/step'),'E')
            self.assertEqual({p.name for p in root.iterdir()},{'input.jpg','result.musicxml'})

    def test_failed_deskew_preserves_failure_and_removes_partial_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); image=root/'input.jpg'; output=root/'result.musicxml'
            Image.new('RGB',(100,100),'white').save(image)
            def straighten(source,target):
                target.write_bytes(b'partial image')
                return {'rotationDegrees':6.0}
            def reader(source,target,preparation="standard"):
                target.write_bytes(b'partial export')
                raise ValueError('Unreadable original')
            with patch('recognizer.recognize_once',side_effect=reader) as calls, patch('page_image.prepare_deskewed_page',side_effect=straighten):
                with self.assertRaisesRegex(ValueError,'Unreadable original'):recognize(image,output)
            self.assertEqual(calls.call_count,5)
            self.assertEqual(list(root.iterdir()),[image])

    def test_successful_reading_never_uses_deskew_even_with_timing_warnings(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); image=root/'input.jpg'; output=root/'result.musicxml'
            Image.new('RGB',(100,100),'white').save(image)
            def reader(source,target,preparation="standard"):
                target.write_bytes(score([note(60,'G')]))
                return {'staffCount':1,'noteCounts':[{'detected':1,'recognized':1}]}
            with patch('recognizer.recognize_once',side_effect=reader), patch('page_image.prepare_deskewed_page') as straighten:
                result=recognize(image,output)
            straighten.assert_not_called()
            self.assertEqual(result['attempts'],4)
            self.assertEqual(validate_score(output.read_bytes()).findtext('.//pitch/step'),'G')

    def test_explicitly_unsupported_page_is_not_retried(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); image=root/'input.jpg'; output=root/'result.musicxml'
            Image.new('RGB',(100,100),'white').save(image)
            with patch('recognizer.recognize_once',side_effect=UnsupportedPage('Connected staves')) as mock:
                with self.assertRaises(UnsupportedPage): recognize(image,output)
            self.assertEqual(mock.call_count,1)

    def test_failed_timing_audit_does_not_reuse_the_invalid_first_export(self):
        invalid = score([note(48)]).replace(b'<beats>4</beats>', b'<beats>unknown</beats>')
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); image=root/'input.jpg'; output=root/'result.musicxml'
            Image.new('RGB',(100,100),'white').save(image)
            def reader(source,target,preparation="standard"):
                target.write_bytes(invalid)
                return {'staffCount':1,'noteCounts':[{'detected':1,'recognized':1}]}
            with patch('recognizer.recognize_once',side_effect=reader) as mock:
                with self.assertRaises(ValueError): recognize(image,output)
            self.assertEqual(mock.call_count,4)
            self.assertEqual(list(root.iterdir()),[image])


if __name__ == '__main__': unittest.main()
