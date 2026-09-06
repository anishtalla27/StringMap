"""Single-part guitar adapter for pinned HOMR, hosted separately from iOS.

SPDX-License-Identifier: AGPL-3.0-or-later
Corresponding source and build material accompany a deployment.
"""
import argparse
import contextlib
import copy
import json
import os
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


class UnsupportedPage(ValueError):
    pass


class SequenceLimitExceeded(ValueError):
    pass


def opening_notation_warnings(symbols):
    """Expose missing model context before any default signature reaches review."""
    opening = []
    for symbol in symbols:
        if symbol.rhythm.startswith(('note', 'rest')):
            break
        opening.append(symbol.rhythm)
    warnings = []
    if not any(value.startswith('clef') for value in opening):
        warnings.append('The opening clef was not recognized. Check every pitch and octave against the page.')
    if not any(value.startswith('timeSignature') for value in opening):
        warnings.append('The opening time signature was not recognized. A 4/4 default may be shown; check Time and Key in review.')
    if not any(value.startswith('keySignature') for value in opening):
        warnings.append('The opening key signature was not recognized. Check Time and Key and every accidental against the page.')
    return warnings


def resolve_single_staff_positions(symbols):
    """Use an independently resolved single treble staff for stray staff labels.

    Caller must first validate that each detected system has exactly one staff.
    A predicted second clef remains ambiguous and is never merged. Pitches,
    durations, order and all other model fields remain exactly as recognized.
    """
    misplaced = [s for s in symbols if s.position == 'lower' and s.rhythm.startswith(('note', 'rest', 'clef'))]
    if not misplaced:
        return symbols, 0
    if any(s.rhythm.startswith('clef') for s in misplaced) or not any(s.rhythm == 'clef_G2' and s.position == 'upper' for s in symbols):
        raise ValueError('The staff-position prediction was ambiguous. No predicted notes were discarded.')
    result = []
    for symbol in symbols:
        if symbol.position == 'lower' and symbol.rhythm.startswith(('note', 'rest')):
            symbol = copy.copy(symbol)
            symbol.position = 'upper'
        result.append(symbol)
    return result, len(misplaced)


def validate_score(data: bytes) -> ET.Element:
    if not 0 < len(data) <= 10 * 1024 * 1024 or b'<!ENTITY' in data.upper():
        raise ValueError('Invalid recognized score')
    root = ET.fromstring(data)
    if root.tag != 'score-partwise' or len(root.findall('part')) != 1:
        raise UnsupportedPage('Import one guitar part at a time. Piano and ensemble scores are not supported.')
    if any(int(x.text or '1') != 1 for x in root.findall('.//staves') + root.findall('.//note/staff')):
        raise UnsupportedPage('Import the guitar staff alone. No staves were discarded.')
    if not root.findall('.//note/pitch'):
        raise ValueError('No readable notes were found. Try a clearer crop of the notation.')
    return root


def clean_preserving_notes(symbols, cleanup):
    """Keep the original prediction when cleanup would change musical content.

    A repeated pitch may be a real unison in independent guitar voices. The
    model cannot reliably distinguish that from an extra prediction, so leave
    that decision to review. Rhythms, rests, ties and grouping are protected too.
    Return a reason for the review warning. Copy symbols so cleanup cannot mutate
    the fallback. Attention arrays are not changed or duplicated.
    """
    def musical_content(sequence):
        return [tuple(getattr(s, field, None) for field in
                      ('rhythm', 'pitch', 'lift', 'position', 'articulation', 'slur'))
                for s in sequence if s.rhythm.startswith(('note', 'rest'))
                or s.rhythm == 'chord' or 'barline' in s.rhythm or 'repeat' in s.rhythm
                or s.rhythm == 'newline']

    original_content = musical_content(symbols)
    cleaned = cleanup([copy.copy(symbol) for symbol in symbols])
    expected = sum(symbol.rhythm.startswith('note') for symbol in symbols)
    actual = sum(symbol.rhythm.startswith('note') for symbol in cleaned)
    if actual != expected:
        return symbols, 'notes'
    if musical_content(cleaned) != original_content:
        return symbols, 'music'
    return cleaned, None


def validate_note_preservation(root, expected, expected_rests=None):
    # The pinned XML writer emits one pitched note per predicted note, including
    # grace notes and unisons. Refuse a partial export or note-to-rest coercion.
    if len(root.findall('./part/measure/note/pitch')) != expected:
        raise ValueError('The recognized notes could not all be exported. No partial score was saved.')
    if expected_rests is not None and len(root.findall('./part/measure/note/rest')) != expected_rests:
        raise ValueError('The recognized rests could not all be exported. No partial score was saved.')


def validate_prediction_length(symbols, sequence_limit):
    # In pinned HOMR, EOS exits before appending a symbol. Reaching the full
    # loop limit means EOS was never seen, even when the prefix exports as XML.
    if len(symbols) >= sequence_limit:
        raise SequenceLimitExceeded('A staff exceeded the recognition sequence limit. No truncated score was saved. Try a shorter crop.')


def recognize_once(image: Path, output: Path, preparation='standard') -> dict:
    # Lazy imports keep validation tests independent of the neural runtime.
    from patch_homr import verify as verify_exporter
    verify_exporter()
    from homr.main import ProcessingConfig, detect_staffs_in_image
    from homr.music_xml_generator import XmlGeneratorArguments, generate_xml
    from homr.staff_parsing import prepare_staff_image
    from homr.staff_regions import StaffRegions
    from homr.transformer.configs import Config
    from homr.transformer.staff2score import Staff2Score
    from homr.transformer.vocabulary import EncodedSymbol, remove_duplicated_symbols
    from staff_image import common_staff_span, crop_staff

    config = ProcessingConfig(False, False, False, False, -1, False, False, False, False)
    debug = None
    try:
        groups, pixels, debug, _, staff_count = detect_staffs_in_image(str(image), config)
        # Do not use upstream's heuristic regrouping/trimming of inconsistent
        # systems. A guitar page has one staff per system, and can have many systems.
        if any(len(g.staffs) != 1 or g.staffs[0].is_grandstaff for g in groups):
            raise UnsupportedPage('This page contains connected staves. Crop the guitar part alone.')
        if len(groups) != staff_count:
            raise UnsupportedPage('The page layout cannot be resolved without losing a staff.')
        span = common_staff_span([g.staffs[0] for g in groups])
        if preparation == 'column' and span is None:
            raise ValueError('The detected staff widths do not warrant extending a crop.')
        settings = Config(); settings.use_gpu_inference = False; settings.use_coreml_encoder = False
        inference = Staff2Score(settings)
        regions = StaffRegions(groups)
        tokens, counts, uncertain_staffs = [], [], []
        for index, group in enumerate(groups):
            staff = group.staffs[0]
            if preparation == 'column':
                staff_image = crop_staff(pixels, staff, minimum_span=span)
            else:
                staff_image, _ = prepare_staff_image(debug, index, staff, pixels, regions=regions)
            recognized = inference.predict(staff_image)
            validate_prediction_length(recognized, settings.max_seq_len)
            recognized, uncertain = resolve_single_staff_positions(recognized)
            if uncertain:
                uncertain_staffs.append(index + 1)
            if not recognized or not any(x.rhythm.startswith(('note', 'rest')) for x in recognized):
                raise ValueError('A staff could not be read. No staff was skipped.')
            counts.append({'detected': staff.get_number_of_notes(),
                           'recognized': sum(x.rhythm.startswith('note') for x in recognized)})
            tokens.extend(recognized); tokens.append(EncodedSymbol('newline'))
        # Meter-based tuplet rewriting is a recognition guess, not lossless
        # cleanup. The independent guard also protects rests and chord grouping.
        cleaned, cleanup_warning = clean_preserving_notes(
            tokens, lambda items: remove_duplicated_symbols(items, cleanup_tuplets=False))
        root = generate_xml(XmlGeneratorArguments(), [cleaned], '')
        validate_note_preservation(root, sum(c['recognized'] for c in counts),
                                   sum(s.rhythm.startswith('rest') for s in tokens))
        warnings = opening_notation_warnings(tokens)
        if cleanup_warning == 'notes':
            warnings.append('Some stacked notes have the same pitch. All predicted notes were kept, including possible duplicates. Compare their durations and voices with the page; remove a note only if it is absent from the source.')
        elif cleanup_warning:
            warnings.append('Automatic cleanup would change the recognized music. Original notes, rests, rhythms, and stacked-note grouping were kept. Compare them with the page before saving.')
        for staff_number in uncertain_staffs:
            warnings.append(f'Staff {staff_number} has notes with uncertain placement. Their pitches and rhythms were kept; compare every note on this staff with the source page.')
        if any(c['detected'] != c['recognized'] for c in counts):
            warnings.append('The image detector and recognizer disagree on the note count. Check for missing or extra notes on every staff before saving.')
        warnings.append('Compare all repeats, ties, accidentals and rhythms with the source page. Scanning can miss symbols; text and chord names are not interpreted.')
        miscellaneous = ET.SubElement(root.find('identification'), 'miscellaneous')
        for warning in warnings:
            ET.SubElement(miscellaneous, 'miscellaneous-field', name='stringmap:recognition-warning').text = warning
        data = ET.tostring(root, encoding='utf-8', xml_declaration=True)
        validate_score(data)
        temporary = output.with_suffix('.tmp')
        temporary.write_bytes(data); temporary.replace(output)
        return {'staffCount': staff_count, 'noteCounts': counts, 'preparation': preparation}
    finally:
        if debug is not None: debug.clean_debug_files_from_previous_runs()


def recognize(image: Path, output: Path) -> dict:
    from PIL import Image
    from score_quality import audit, rank
    first = quality = best = chosen = None
    initial_error = None
    attempts = 1
    try:
        first = recognize_once(image, output)
        chosen = output.read_bytes()
        quality = audit(chosen)
        best = rank(quality, first['noteCounts'])
    except UnsupportedPage:
        raise
    except ValueError as error:
        # A bad first reading (including a note with no predicted pitch) can
        # improve on rereading the image. Never invent a pitch or export a rest
        # in its place. An explicitly unsupported page still fails immediately.
        initial_error = error
        first = quality = best = chosen = None
        output.unlink(missing_ok=True)
    # Retry only a structurally suspicious reading. Each alternative comes from
    # re-reading the actual image; never delete a rest or force a bar to fit.
    if best != (0, 0, 0):
        with Image.open(image) as page:
            for index, angle in enumerate([2.0, -2.0]):
                variant = output.with_name(f'variant-{index}.jpg')
                candidate = output.with_name(f'candidate-{index}.musicxml')
                attempts += 1
                try:
                    page.convert('RGB').rotate(angle, resample=Image.Resampling.BICUBIC, expand=True, fillcolor='white').save(variant, quality=95)
                    details = recognize_once(variant, candidate)
                    check = audit(candidate.read_bytes()); candidate_rank = rank(check, details['noteCounts'])
                    if best is None or candidate_rank < best:
                        best = candidate_rank; chosen = candidate.read_bytes(); first = details; quality = check
                    if best == (0, 0, 0): break
                except Exception:
                    # Preserve the original usable recognition if an alternate
                    # view fails. A failed retry must not erase recognized music.
                    pass
                finally:
                    variant.unlink(missing_ok=True); candidate.unlink(missing_ok=True)
        if chosen is not None:
            output.write_bytes(chosen)
    # A short detected staff range can cut notes off an otherwise complete
    # photograph. Try image-only rectification with majority-supported wider
    # bounds, but never replace a reading with another rhythmically suspect one.
    if chosen is None or quality['warnings']:
        candidate = output.with_name('candidate-column.musicxml')
        attempts += 1
        try:
            details = recognize_once(image, candidate, preparation='column')
            data = candidate.read_bytes(); check = audit(data)
            if not check['warnings']:
                chosen = data; first = details; quality = check
                output.write_bytes(chosen)
        except Exception:
            pass
        finally:
            candidate.unlink(missing_ok=True)
    # Recover only a failed reading, with one independently measured page
    # rotation. Successful scores and explicitly unsupported layouts retain the
    # earlier paths; no note or duration is edited to repair the recognition.
    if chosen is None:
        from page_image import prepare_deskewed_page
        variant = output.with_name('variant-deskew.png')
        candidate = output.with_name('candidate-deskew.musicxml')
        try:
            geometry = prepare_deskewed_page(image, variant)
            if geometry is not None:
                attempts += 1
                details = recognize_once(variant, candidate)
                data = candidate.read_bytes()
                check = audit(data)
                output.write_bytes(data)
                chosen = data; first = {**details, 'pageDeskew': geometry}; quality = check
        except Exception:
            pass
        finally:
            variant.unlink(missing_ok=True); candidate.unlink(missing_ok=True)
    if chosen is None:
        raise initial_error
    root = ET.fromstring(chosen)
    if quality['warnings']:
        miscellaneous = root.find('identification/miscellaneous')
        for warning in quality['warnings']:
            ET.SubElement(miscellaneous, 'miscellaneous-field', name='stringmap:recognition-warning').text = warning
        output.write_bytes(ET.tostring(root, encoding='utf-8', xml_declaration=True))
    return {**first, 'attempts': attempts, 'timingWarnings': len(quality['warnings'])}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('image', type=Path)
    parser.add_argument('--output-path', required=True, type=Path)
    args = parser.parse_args()
    try:
        # Raw upstream diagnostics include the notes. Never put them in logs.
        with open(os.devnull, 'w') as quiet, contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
            result = recognize(args.image, args.output_path)
        print(json.dumps({'status': 'completed', **result}))
    except Exception as error:
        args.output_path.unlink(missing_ok=True)
        # Only whitelisted error codes reach the service, never raw exception text.
        code = 'unsupported' if isinstance(error, UnsupportedPage) else ('sequence-limit' if isinstance(error, SequenceLimitExceeded) else 'unreadable')
        args.output_path.with_suffix('.error.json').write_text(json.dumps({'code': code}))
        print(json.dumps({'status': 'failed', 'type': type(error).__name__}))
        sys.exit(2)


if __name__ == '__main__': main()
