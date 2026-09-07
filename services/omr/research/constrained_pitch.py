"""Research-only rhythm/pitch consistency selection from model logits.

SPDX-License-Identifier: AGPL-3.0-or-later
No reference music, guitar range, octave search or fingering enters selection.
"""
import re
import numpy as np


def select_pitch(rhythm, logits, vocabulary):
    values = np.asarray(logits, dtype=np.float64).reshape(-1)
    if not np.isfinite(values).all() or set(vocabulary) != set(range(len(values))):
        raise ValueError('Invalid pitch logits or vocabulary')
    raw = int(values.argmax())
    if rhythm.startswith('note'):
        allowed = [i for i, label in vocabulary.items() if re.fullmatch(r'[A-G][0-9]', label)]
    elif rhythm.startswith('rest'):
        allowed = [i for i, label in vocabulary.items() if label == '_']
    else:
        return raw, None
    if not allowed:
        raise ValueError('No pitch class matches the predicted rhythm')
    selected = max(sorted(allowed), key=lambda i: values[i])
    if selected == raw:
        return selected, None
    probabilities = np.exp(values - values.max())
    probabilities /= probabilities.sum()
    return selected, {'rhythm': rhythm, 'rawPitch': vocabulary[raw],
                      'selectedPitch': vocabulary[selected],
                      'rawProbability': float(probabilities[raw]),
                      'selectedProbability': float(probabilities[selected])}
