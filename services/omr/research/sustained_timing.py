"""Research-only timing interpretation for serialized polyphonic note groups.

SPDX-License-Identifier: AGPL-3.0-or-later
Advances to the earliest outstanding note/rest ending, including earlier groups.
Does not alter pitches, written durations, chord membership, or use references.
"""
from fractions import Fraction


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
