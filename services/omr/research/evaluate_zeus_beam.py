"""Isolated image-only beam-search evaluation for the pinned Zeus model.

No production dependency changes. Saves every candidate, conversion failure,
and normalized model score. References are consumed only by separate scorers.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import time
import xml.etree.ElementTree as ET

import tensorflow as tf
from zeus import InferenceOptions, Zeus
from zeus.model.construct_tf_dataset import construct_tf_dataset_for_images
from zeus.musicxml.lmx_to_musicxml import lmx_to_musicxml


def decoder(model, width, maximum=700, alpha=0.6):
    """Fixed-width beam search; no symbolic reference or score-repair rules."""
    @tf.function(input_signature=[tf.TensorSpec([1, None, model.architecture_options.rnn_dim], tf.float32)])
    def predict(encoded):
        model._target_rnn.cell.setup_memory(tf.repeat(encoded, width, axis=0))
        inputs = tf.fill([width], model.BOS)
        states = model._target_rnn.cell.get_initial_state(batch_size=width, dtype=tf.float32)
        scores = tf.concat([tf.zeros([1]), tf.fill([width - 1], -1e9)], axis=0)
        finished = tf.zeros([width], tf.bool)
        lengths = tf.zeros([width], tf.int32)
        sequences = tf.fill([width, maximum], model.EOS)
        index = tf.constant(0)
        vocabulary = len(model.token_map)
        while tf.logical_and(index < maximum, tf.logical_not(tf.reduce_all(finished))):
            hidden = model._target_embedding(inputs)
            hidden, next_states = model._target_rnn.cell(hidden, states)
            logits = model._target_output_layer(hidden)
            probabilities = tf.nn.log_softmax(logits)
            absorbing = tf.one_hot(model.EOS, vocabulary, on_value=0.0, off_value=-1e9)
            probabilities = tf.where(finished[:, None], absorbing[None, :], probabilities)
            candidate_scores = scores[:, None] + probabilities
            candidate_lengths = tf.where(finished, lengths, index + 1)
            normalization = tf.pow((5.0 + tf.cast(candidate_lengths, tf.float32)) / 6.0, alpha)
            ranking = candidate_scores / normalization[:, None]
            _, best = tf.math.top_k(tf.reshape(ranking, [-1]), k=width)
            parents = best // vocabulary
            tokens = best % vocabulary
            scores = tf.gather(tf.reshape(candidate_scores, [-1]), best)
            lengths = tf.gather(candidate_lengths, parents)
            finished = tf.logical_or(tf.gather(finished, parents), tokens == model.EOS)
            sequences = tf.gather(sequences, parents)
            sequences = tf.tensor_scatter_nd_update(sequences, tf.stack([tf.range(width), tf.fill([width], index)], axis=1), tokens)
            states = tf.nest.map_structure(lambda value: tf.gather(value, parents), next_states)
            inputs = tokens
            index += 1
        rank = scores / tf.pow((5.0 + tf.cast(lengths, tf.float32)) / 6.0, alpha)
        return sequences, lengths, rank, finished
    return predict


def convert(prediction):
    diagnostics = io.StringIO()
    xml = lmx_to_musicxml(prediction, errout=diagnostics)
    if diagnostics.getvalue().strip():
        raise ValueError('Decoder reported unsupported or malformed tokens: ' + diagnostics.getvalue())
    root = ET.fromstring(xml)
    tokens = sum(re.fullmatch(r'[A-G]-?\d+', token) is not None for token in prediction.split())
    actual = len(root.findall('./part/measure/note/pitch'))
    if tokens != actual or not actual:
        raise ValueError(f'Pitch-token preservation failed: {tokens} tokens, {actual} exported notes')
    return xml


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--crops', type=Path, required=True)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timing-guard', action='store_true')
    parser.add_argument('--width', type=int, default=4, choices=[2,4,8])
    args = parser.parse_args()
    args.output.mkdir(exist_ok=False, parents=True)
    paths = sorted((p for p in args.crops.glob('staff-*.png') if re.fullmatch(r'staff-\d+', p.stem)), key=lambda p: int(p.stem.split('-')[1]))
    if not paths:
        raise ValueError('No staff images found')
    model = Zeus.load(args.model)
    options = InferenceOptions(batch_size=1)
    images = [p.read_bytes() for p in paths]
    greedy = model.predict(images, options)
    single = decoder(model.model, 1)
    beam = decoder(model.model, args.width)
    timing_decoder = None
    if args.timing_guard:
        from zeus_timing_search import make_timing_decoder
        timing_decoder = make_timing_decoder(model.model, model.token_map, args.width)
    dataset = construct_tf_dataset_for_images(images, model.architecture_options, options)
    results = []
    for path, batch, original in zip(paths, dataset, greedy, strict=True):
        started = time.monotonic()
        encoded = model.model.encoder(batch, training=False)
        one, one_lengths, _, _ = single(encoded)
        reproduced = model.token_map.indices_to_lmx(one[0, :one_lengths[0]].numpy().tolist())
        if reproduced != original:
            raise ValueError(f'Width-one decoder differs from upstream greedy prediction: {path.name}')
        search_details = {}
        if timing_decoder:
            readings, search_details = timing_decoder(encoded)
        else:
            sequences, lengths, scores, ended = beam(encoded)
            readings = [{'prediction':model.token_map.indices_to_lmx(sequences[i, :lengths[i]].numpy().tolist()),'modelScore':float(scores[i]),'terminated':bool(ended[i])} for i in range(args.width)]
        candidates = []
        chosen = None
        for i,reading in enumerate(readings):
            prediction = reading['prediction']
            (args.output / f'{path.stem}-candidate-{i}.lmx').write_text(prediction)
            candidate = {'index':i, 'modelScore':reading['modelScore'], 'terminated':reading['terminated']}
            try:
                if not candidate['terminated']:
                    raise ValueError('Prediction reached token limit without end-of-sequence')
                xml = convert(prediction)
                (args.output / f'{path.stem}-candidate-{i}.musicxml').write_text(xml)
                candidate['musicXMLProduced'] = True
                if chosen is None:
                    chosen = i
                    (args.output / f'{path.stem}.musicxml').write_text(xml)
                    (args.output / f'{path.stem}.lmx').write_text(prediction)
            except Exception as error:
                candidate.update(musicXMLProduced=False, error=str(error))
            candidates.append(candidate)
        row = {'staff':path.stem,'inputSHA256':hashlib.sha256(path.read_bytes()).hexdigest(),'greedyExactlyReproduced':True,'chosenCandidate':chosen,'seconds':time.monotonic()-started,'candidates':candidates,'timingSearch':search_details}
        results.append(row)
        report = {'referenceUsedByRecognizer':False,'shipping':False,'releaseQualified':False,'beamWidth':args.width,'timingGuard':args.timing_guard,'lengthPenalty':0.6,'selection':'First model-ranked terminated candidate with diagnostic-free decoding and exact predicted pitch-token preservation','model':str(args.model),'results':results}
        (args.output / 'inference.json').write_text(json.dumps(report,indent=2)+'\n')
        print(path.stem,'chosen',chosen,'seconds',round(row['seconds'],1),flush=True)


if __name__ == '__main__':
    main()
