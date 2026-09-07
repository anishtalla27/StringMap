"""Research-only beam pruning for impossible negative MusicXML cursors.

Uses only each model prefix. It never alters a predicted duration or inserts
notes/rests, and it imposes no reference-derived measure length or pitch range.
"""
from fractions import Fraction
from functools import lru_cache
import io
import re
import xml.etree.ElementTree as ET
import numpy as np
import tensorflow as tf
from zeus.musicxml.lmx_to_musicxml import lmx_to_musicxml


def prefix_has_nonnegative_timing(prediction):
    try:
        xml = lmx_to_musicxml(prediction, errout=io.StringIO())
    except Exception as error:
        # A partial token tree can lack a duration, pitch or attribute. Only
        # reject a proved negative onset, leaving other syntax to final export.
        return 'Onset must be non-negative' not in str(error)
    root = ET.fromstring(xml)
    divisions = Fraction(1)
    for measure in root.findall('./part/measure'):
        cursor = Fraction(0)
        for element in measure:
            if element.tag == 'attributes' and element.find('divisions') is not None:
                divisions = Fraction(element.findtext('divisions'))
            elif element.tag in ('forward', 'backup'):
                duration = Fraction(element.findtext('duration', '0')) / divisions
                cursor += -duration if element.tag == 'backup' else duration
            elif element.tag == 'note' and element.find('chord') is None and element.find('grace') is None:
                cursor += Fraction(element.findtext('duration', '0')) / divisions
            if cursor < 0:
                return False
    return True


def make_timing_decoder(model, token_map, width, maximum=700, alpha=0.6):
    @tf.function(reduce_retracing=True)
    def step(encoded, inputs, states):
        model._target_rnn.cell.setup_memory(tf.repeat(encoded, width, axis=0))
        hidden = model._target_embedding(inputs)
        hidden, states = model._target_rnn.cell(hidden, states)
        return tf.nn.log_softmax(model._target_output_layer(hidden)), states

    def decode(encoded):
        inputs = tf.fill([width], model.BOS)
        states = model._target_rnn.cell.get_initial_state(batch_size=width, dtype=tf.float32)
        sequences = [[] for _ in range(width)]
        scores = np.array([0.0] + [-1e9] * (width - 1))
        finished = [False] * width
        boundary = {i for i,t in enumerate(token_map.tokens) if t in ['measure','backup','forward','rest','chord'] or re.fullmatch(r'[A-G]-?\d+', t)} | {model.EOS}
        rejected = 0
        @lru_cache(maxsize=2048)
        def valid_prefix(tokens):
            return prefix_has_nonnegative_timing(token_map.indices_to_lmx(list(tokens)))
        for _ in range(maximum):
            probabilities, next_states = step(encoded, inputs, states)
            probabilities = probabilities.numpy().astype(float)
            for i, done in enumerate(finished):
                if done:
                    probabilities[i,:] = -1e9
                    probabilities[i,model.EOS] = 0.0
            candidates = scores[:,None] + probabilities
            lengths = np.array([len(s) + (0 if done else 1) for s,done in zip(sequences,finished)])
            ranking = candidates / (((5.0 + lengths[:,None])/6.0)**alpha)
            flat = ranking.ravel()
            # Exhaust candidates in rank order if a structurally invalid prefix
            # dominates. Sorting is deterministic, including exact ties.
            order = np.argsort(-flat, kind='stable')
            chosen = []
            vocabulary = probabilities.shape[1]
            for candidate in order:
                parent, token = divmod(int(candidate), vocabulary)
                if candidates[parent,token] < -1e8:
                    break
                if token in boundary and not finished[parent] and not valid_prefix(tuple(sequences[parent])):
                    rejected += 1
                    continue
                chosen.append((parent,token))
                if len(chosen) == width:
                    break
            if not chosen:
                return [], {'prunedBoundaryCandidates':rejected, 'error':'No beam can continue without a negative cursor'}
            # Maintain fixed tensor shapes for the recurrent model; duplicates
            # are not presented as independent final hypotheses.
            chosen += [chosen[-1]] * (width-len(chosen))
            parents = [p for p,_ in chosen]
            new_sequences = [sequences[p] if finished[p] else sequences[p]+[t] for p,t in chosen]
            scores = np.array([candidates[p,t] for p,t in chosen])
            finished = [finished[p] or t == model.EOS for p,t in chosen]
            sequences = new_sequences
            states = tf.nest.map_structure(lambda value: tf.gather(value,parents),next_states)
            inputs = tf.constant([t for _,t in chosen],tf.int32)
            if all(finished):
                break
        result = []
        seen = set()
        for sequence,score,done in zip(sequences,scores,finished):
            prediction = token_map.indices_to_lmx(sequence)
            if prediction in seen:
                continue
            seen.add(prediction)
            result.append({'prediction':prediction,'modelScore':float(score/(((5+len(sequence))/6)**alpha)),'terminated':done})
        result.sort(key=lambda r:-r['modelScore'])
        return result, {'prunedBoundaryCandidates':rejected}
    return decode
