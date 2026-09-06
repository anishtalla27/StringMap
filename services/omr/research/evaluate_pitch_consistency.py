"""Image-only decoding experiment; the production decoder is not modified.

SPDX-License-Identifier: AGPL-3.0-or-later
Unconstrained decoding must reproduce upstream before constrained inference.
Retain all decisions, including low model probabilities; these are not calibrated
accuracy estimates. References are evaluated separately after inference.
"""
import argparse
import contextlib
import gc
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image
from homr.music_xml_generator import generate_xml, XmlGeneratorArguments
from homr.transformer.configs import Config
from homr.transformer.staff2score import Staff2Score, _transform
from homr.transformer.vocabulary import EncodedSymbol
from constrained_pitch import select_pitch
from evaluate_homr_beam import HEADS, INPUTS, serial

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from recognizer import resolve_single_staff_positions, validate_note_preservation, validate_score


def decode(decoder, context, constrained=False):
    cache, inputs, outputs = decoder.init_cache()
    last = (1, 0, 0, 0, 0, 0)
    vocabularies = [getattr(decoder, 'inv_' + head + '_vocab') for head in HEADS]
    symbols = []; changes = []; terminated = False
    for step in range(decoder.max_seq_len):
        binding = decoder.io_binding
        for name, head in INPUTS:
            binding.bind_cpu_input(name, np.array([[last[head]]], dtype=np.int64))
        binding.bind_cpu_input('context', context if step == 0 else context[:, :1])
        binding.bind_cpu_input('cache_len', np.array([step], dtype=np.int64))
        for name, value in zip(inputs, cache, strict=True): binding.bind_ortvalue_input(name, value)
        for name in decoder.output_names + outputs: binding.bind_output(name, decoder.device, decoder.device_id)
        decoder.net.run_with_iobinding(binding)
        result = binding.get_outputs(); cache = result[7:]
        logits = [value.numpy()[:, -1, :] for value in result[:6]]
        ids = [int(value.argmax()) for value in logits]
        if ids[0] == decoder.eos_token:
            terminated = True
            break
        if constrained:
            ids[1], change = select_pitch(vocabularies[0][ids[0]], logits[1], vocabularies[1])
            if change is not None: changes.append({'step': step, **change})
        text = [vocabulary[i] for vocabulary, i in zip(vocabularies, ids, strict=True)]
        # XML export does not use attention coordinates. Avoid retaining these
        # large arrays across the three comparison decodes.
        symbols.append(EncodedSymbol(**dict(zip(HEADS, text, strict=True))))
        last = tuple(ids)
    return symbols, changes, terminated


def export(tokens, path):
    resolved, _ = resolve_single_staff_positions(tokens)
    root = generate_xml(XmlGeneratorArguments(), [resolved], '')
    validate_note_preservation(root, sum(s.rhythm.startswith('note') for s in tokens),
                               sum(s.rhythm.startswith('rest') for s in tokens))
    data = ET.tostring(root, encoding='utf-8', xml_declaration=True)
    validate_score(data); path.write_bytes(data)


def main():
    p = argparse.ArgumentParser(); p.add_argument('--crops', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True); p.add_argument('--limit', type=int)
    args = p.parse_args(); args.output.mkdir(parents=True, exist_ok=False)
    paths = sorted(args.crops.glob('staff-*.png'), key=lambda p: int(p.stem.split('-')[-1]))
    if args.limit: paths = paths[:args.limit]
    if not paths: raise ValueError('No staff images')
    report = {'referencesUsed': False, 'shipping': False, 'inputs': []}
    with open(os.devnull, 'w') as quiet, contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
        config = Config(); config.use_gpu_inference = False; config.use_coreml_encoder = False
        model = Staff2Score(config)
    all_tokens = {'greedy': [], 'constrained': []}
    for path in paths:
        started = time.monotonic()
        row = {'staff': path.stem, 'imageSHA256': hashlib.sha256(path.read_bytes()).hexdigest()}
        with open(os.devnull, 'w') as quiet, contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
            pixels = np.asarray(Image.open(path).convert('L'))
            original = model.predict(pixels)
            context = model.encoder.generate(_transform(pixels)).astype(np.float32)
            baseline, _, terminated = decode(model.decoder, context)
            row['greedyReproduced'] = serial(original) == serial(baseline)
            if not row['greedyReproduced']: raise AssertionError('Unconstrained decode differs from upstream')
            del original; gc.collect()
            constrained, changes, constrained_terminated = decode(model.decoder, context, True)
            row.update(changes=changes, baselineTerminated=terminated, constrainedTerminated=constrained_terminated)
            for name, tokens, ended in [('greedy', baseline, terminated), ('constrained', constrained, constrained_terminated)]:
                folder = args.output / name; folder.mkdir(exist_ok=True)
                (folder / (path.stem + '.json')).write_text(json.dumps(serial(tokens), indent=2) + '\n')
                all_tokens[name].extend(tokens); all_tokens[name].append(EncodedSymbol('newline'))
                try:
                    if not ended: raise ValueError('No EOS before sequence limit')
                    export(tokens, folder / (path.stem + '.musicxml'))
                    row[name + 'Exported'] = True
                except Exception as error: row[name + 'Exported'] = False; row[name + 'Error'] = str(error)
        row['seconds'] = time.monotonic() - started; report['inputs'].append(row)
        (args.output / 'inference.json').write_text(json.dumps(report, indent=2) + '\n')
        print(path.stem, 'changes', len(changes), 'exported', row['constrainedExported'], flush=True)
    report['pageExports'] = {}
    for name, tokens in all_tokens.items():
        try:
            if not all(r['baselineTerminated' if name == 'greedy' else 'constrainedTerminated'] for r in report['inputs']):
                raise ValueError('Incomplete staff sequence')
            with open(os.devnull, 'w') as quiet, contextlib.redirect_stderr(quiet):
                export(tokens, args.output / (name + '-page.musicxml'))
            report['pageExports'][name] = {'exported': True}
        except Exception as error: report['pageExports'][name] = {'exported': False, 'error': str(error)}
    (args.output / 'inference.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__': main()
