"""Preserve overlapping rhythmic voices when advancing serialized note groups.

SPDX-License-Identifier: AGPL-3.0-or-later
HOMR serializes notes in onset order, joining simultaneous members with chord
markers. A voice from an earlier group can resume while the newest note sustains.
Only cursor advances change here; pitches, durations and grouping remain intact.
"""
from fractions import Fraction
from types import MethodType


def advances_for_measure(groups):
    now = Fraction(0)
    active = set()
    result = []
    for index, durations in enumerate(groups):
        if not durations or any(duration <= 0 for duration in durations):
            raise ValueError('Only positive, explicit note and rest durations are supported')
        active = {end for end in active if end > now}
        active.update(now + duration for duration in durations)
        next_time = max(active) if index == len(groups) - 1 else min(active)
        result.append(next_time - now)
        now = next_time
    return result


def schedule_interleaved_groups(groups):
    pending = []

    def finish():
        durations = [[s.get_duration().fraction for s in group.symbols
                      if s.rhythm.startswith(('note', 'rest'))] for group in pending]
        # Grace and multi-measure rests have separate semantics. Keep upstream
        # handling for these unsupported measures; do not infer missing time.
        unsupported = any('G' in s.rhythm or s.rhythm.endswith('m')
                          for group in pending for s in group.symbols)
        if not unsupported and all(ds and all(d > 0 for d in ds) for ds in durations):
            for group, advance in zip(pending, advances_for_measure(durations), strict=True):
                group.get_duration = MethodType(lambda self, value=advance: value, group)
        pending.clear()

    for group in groups:
        if group.is_barline():
            finish()
        elif group.symbols[0].rhythm.startswith(('note', 'rest')):
            pending.append(group)
    finish()
    return groups
