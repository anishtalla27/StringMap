"""Exact-duration XML export fix for the pinned HOMR source.

SPDX-License-Identifier: AGPL-3.0-or-later
Apply at installation/build time; the request worker never edits dependencies.
The upstream timing grid considers only each chord's shortest duration and its
writer emits only the first simultaneous rest. Its cursor also overlooks earlier
sustained voices. Preserve durations, rests, and interleaved onset timing.
"""
import argparse
import hashlib
import importlib.util
from pathlib import Path

ORIGINAL_SHA256 = 'b337f97cf0cc8d9892e1eba89df911d2a6346b53675223258bcc37efac2a8f80'
DURATION_PATCHED_SHA256 = '0a92f02bea0eda50f8a6606c37c222bbfaf9d792010b98f56ecc2d18ccab4dce'
REST_PATCHED_SHA256 = '6779fcdde4190ddd3508552f66ac28948740c2ff2464a63e4b6d5808df8089aa'
PATCHED_SHA256 = 'f032842abdce276377f40593a0566edde3db72607cada3abaf0e282c01e7f579'
TIMING_IMPORT_ORIGINAL = b'from homr import constants\n'
TIMING_IMPORT_REPLACEMENT = TIMING_IMPORT_ORIGINAL + b'from symbol_timing import schedule_interleaved_groups\n'
TIMING_ORIGINAL = b'    groups = add_tuplet_start_stop(group_into_chords(voice))\n'
TIMING_REPLACEMENT = b'    groups = schedule_interleaved_groups(add_tuplet_start_stop(group_into_chords(voice)))\n'
ORIGINAL = b'                durations.append(duration)\n'
REPLACEMENT = (
    b'                durations.extend(\n'
    b'                    symbol.get_duration().fraction\n'
    b'                    for symbol in chord.symbols\n'
    b'                    if symbol.rhythm.startswith(("note", "rest"))\n'
    b'                )\n'
)
REST_ORIGINAL = (
    b'            # Ideally we expect len(rests) == 1, but in dataset we see cases where\n'
    b'            # there are multiple rests. So here we just take the first rest\n'
    b'            result.append(build_note_or_rest(rests[0], i, False, state, note_chord.tuplet_mark))\n'
)
REST_REPLACEMENT = (
    b'            # Separate rhythmic voices may rest at the same onset. Keep each\n'
    b'            # predicted rest, returning the cursor before emitting the next one.\n'
    b'            for rest_index, rest in enumerate(rests):\n'
    b'                if rest_index:\n'
    b'                    result.append(build_backup(group_duration, state))\n'
    b'                result.append(build_note_or_rest(rest, i, False, state, note_chord.tuplet_mark))\n'
)


def installed_path() -> Path:
    spec = importlib.util.find_spec('homr')
    if spec is None or not spec.submodule_search_locations:
        raise RuntimeError('Install the pinned HOMR dependency first.')
    return Path(next(iter(spec.submodule_search_locations))) / 'music_xml_generator.py'


def verify(path: Path | None = None) -> None:
    path = path if path is not None else installed_path()
    if hashlib.sha256(path.read_bytes()).hexdigest() != PATCHED_SHA256:
        raise RuntimeError('HOMR XML exporter is not the pinned exact-duration build. Run patch_homr.py during installation.')


def apply(path: Path | None = None) -> bool:
    path = path if path is not None else installed_path()
    source = path.read_bytes()
    digest = hashlib.sha256(source).hexdigest()
    if digest == PATCHED_SHA256:
        return False
    if digest not in (ORIGINAL_SHA256, DURATION_PATCHED_SHA256, REST_PATCHED_SHA256):
        raise RuntimeError('Unexpected HOMR XML exporter source; no file was changed.')
    if digest == ORIGINAL_SHA256:
        if source.count(ORIGINAL) != 1:
            raise RuntimeError('Unexpected HOMR timing-grid source; no file was changed.')
        source = source.replace(ORIGINAL, REPLACEMENT)
    if digest != REST_PATCHED_SHA256:
        if source.count(REST_ORIGINAL) != 1:
            raise RuntimeError('Unexpected HOMR rest-export source; no file was changed.')
        source = source.replace(REST_ORIGINAL, REST_REPLACEMENT)
    if source.count(TIMING_IMPORT_ORIGINAL) != 1 or source.count(TIMING_ORIGINAL) != 1:
        raise RuntimeError('Unexpected HOMR voice-timing source; no file was changed.')
    patched = source.replace(TIMING_IMPORT_ORIGINAL, TIMING_IMPORT_REPLACEMENT).replace(TIMING_ORIGINAL, TIMING_REPLACEMENT)
    if hashlib.sha256(patched).hexdigest() != PATCHED_SHA256:
        raise RuntimeError('Unexpected HOMR patch result; no file was changed.')
    temporary = path.with_suffix('.stringmap.tmp')
    try:
        temporary.write_bytes(patched)
        temporary.chmod(path.stat().st_mode & 0o777)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    verify(path)
    return True


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.check:
        verify()
    else:
        apply()
    print('Pinned HOMR exact-duration exporter verified')
