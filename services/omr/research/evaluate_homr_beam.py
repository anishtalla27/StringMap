"""Research-only joint-head beam decoding for the pinned HOMR ONNX model.

SPDX-License-Identifier: AGPL-3.0-or-later
Uses image/model only. Width one must reproduce upstream greedy symbols before
wider inference is evaluated. Export never removes duplicate predicted notes.
"""
import argparse
import contextlib
from dataclasses import dataclass
import hashlib
import heapq
import json
import math
import os
from pathlib import Path
import sys
import time
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image
from homr.music_xml_generator import XmlGeneratorArguments, generate_xml
from homr.transformer.configs import Config
from homr.transformer.staff2score import Staff2Score, _transform
from homr.transformer.vocabulary import EncodedSymbol

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from recognizer import resolve_single_staff_positions, validate_note_preservation, validate_score

HEADS = ('rhythm', 'pitch', 'lift', 'position', 'articulation', 'slur')
INPUTS = (('rhythms',0), ('pitchs',1), ('lifts',2), ('articulations',4), ('slurs',5))


def joint_top(logits, width):
    """Exact top-k Cartesian combinations of independent head probabilities."""
    probabilities, orders = [], []
    for raw in logits:
        raw = np.asarray(raw, dtype=np.float64).reshape(-1)
        if not np.isfinite(raw).all():
            raise ValueError('Nonfinite model logits')
        shifted = raw - raw.max()
        logp = shifted - math.log(float(np.exp(shifted).sum()))
        order = np.argsort(-logp, kind='stable')
        probabilities.append(logp); orders.append(order)
    start = (0,) * len(logits)
    def value(index):
        return sum(float(p[order[i]]) for p,order,i in zip(probabilities,orders,index))
    heap = [(-value(start), start)]; seen = {start}; result = []
    while heap and len(result) < width:
        negative, indices = heapq.heappop(heap)
        result.append((tuple(int(order[i]) for order,i in zip(orders,indices)), -negative))
        for axis in range(len(indices)):
            next_indices = list(indices); next_indices[axis] += 1; next_indices = tuple(next_indices)
            if next_indices[axis] < len(orders[axis]) and next_indices not in seen:
                seen.add(next_indices); heapq.heappush(heap, (-value(next_indices),next_indices))
    return result


@dataclass
class Hypothesis:
    last: tuple
    cache: list
    symbols: list
    score: float = 0.0
    terminated: bool = False


def search(decoder, context, width, penalty=0.6):
    cache, ins, outs = decoder.init_cache()
    active = [Hypothesis((1,0,0,0,0,0),cache,[])]
    finished = []
    inv = [getattr(decoder,'inv_'+key+'_vocab') for key in HEADS]
    def rank(h):
        return h.score / (((5 + len(h.symbols) + int(h.terminated))/6) ** penalty)
    for step in range(decoder.max_seq_len):
        expanded = []
        for h in active:
            binding = decoder.io_binding
            for name, head in INPUTS:
                binding.bind_cpu_input(name, np.array([[h.last[head]]],dtype=np.int64))
            binding.bind_cpu_input('context', context if step == 0 else context[:,:1])
            binding.bind_cpu_input('cache_len',np.array([step],dtype=np.int64))
            for name, val in zip(ins,h.cache): binding.bind_ortvalue_input(name,val)
            for name in decoder.output_names + outs: binding.bind_output(name,decoder.device,decoder.device_id)
            decoder.net.run_with_iobinding(binding)
            output = binding.get_outputs()
            logits = [v.numpy()[:,-1,:] for v in output[:6]]
            attention = output[6].numpy()
            candidates = joint_top(logits,width)
            eos_seen = False
            for ids, logp in candidates:
                if ids[0] == decoder.eos_token:
                    # Non-rhythm heads on EOS are not part of the emitted score.
                    if not eos_seen:
                        finished.append(Hypothesis(ids,[],h.symbols,h.score+logp,True))
                        eos_seen = True
                    continue
                text = [vocab[i] for vocab,i in zip(inv,ids)]
                symbol = EncodedSymbol(**dict(zip(HEADS,text)), coordinates=attention)
                expanded.append(Hypothesis(ids,output[7:],h.symbols+[symbol],h.score+logp))
        active = sorted(expanded,key=rank,reverse=True)[:width]
        finished = sorted(finished,key=rank,reverse=True)[:width]
        if not active: break
        # An active path can add only nonpositive log probability. Even at the
        # maximum allowed length it cannot beat this completed beam's score.
        if len(finished) >= width:
            optimistic = max(h.score / (((5+decoder.max_seq_len)/6)**penalty) for h in active)
            if optimistic <= rank(finished[-1]): break
    return sorted(finished or active,key=rank,reverse=True)


def serial(symbols):
    return [{key:getattr(s,key) for key in HEADS} for s in symbols]


def export(symbols, destination):
    resolved,_ = resolve_single_staff_positions(symbols)
    expected = sum(s.rhythm.startswith('note') for s in resolved)
    root = generate_xml(XmlGeneratorArguments(), [resolved], '')
    validate_note_preservation(root,expected)
    data = ET.tostring(root,encoding='utf-8',xml_declaration=True)
    validate_score(data)
    destination.write_bytes(data)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--crops',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--beam',type=int,default=4,choices=[1,2,4,8])
    parser.add_argument('--limit',type=int)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    paths=sorted(args.crops.glob('staff-*.png'),key=lambda p:int(p.stem.split('-')[-1]))
    if args.limit:paths=paths[:args.limit]
    if not paths:raise ValueError('No crops')
    report={'releaseQualified':False,'referencesUsed':False,'beamWidth':args.beam,'lengthPenalty':0.6,'inputs':[]}
    with open(os.devnull,'w') as quiet,contextlib.redirect_stdout(quiet),contextlib.redirect_stderr(quiet):
        config=Config();config.use_gpu_inference=False;config.use_coreml_encoder=False
        model=Staff2Score(config)
    for path in paths:
        row={'staff':path.stem,'imageSHA256':hashlib.sha256(path.read_bytes()).hexdigest()}
        with open(os.devnull,'w') as quiet,contextlib.redirect_stdout(quiet),contextlib.redirect_stderr(quiet):
            pixels=np.asarray(Image.open(path).convert('L'))
            original=model.predict(pixels)
            context=model.encoder.generate(_transform(pixels)).astype(np.float32)
            started=time.monotonic();greedy=search(model.decoder,context,1)[0]
            row['greedyReproduced']=serial(greedy.symbols)==serial(original)
            if not row['greedyReproduced']:raise AssertionError('Width one differs from upstream')
            greedy_dir=args.output/'greedy';greedy_dir.mkdir(exist_ok=True)
            (greedy_dir/(path.stem+'.json')).write_text(json.dumps(serial(original),indent=2))
            try:export(original,greedy_dir/(path.stem+'.musicxml'));row['greedyExported']=True
            except Exception as error:row['greedyExported']=False;row['greedyExportError']=str(error)
            candidates=[greedy] if args.beam == 1 else search(model.decoder,context,args.beam)
            row['searchSeconds']=time.monotonic()-started
            row['candidates']=[];row['selected']=None
            for i,h in enumerate(candidates):
                record={'rank':i,'logProbability':h.score,'terminated':h.terminated,'symbols':len(h.symbols)}
                (args.output/(path.stem+f'-candidate-{i}.json')).write_text(json.dumps(serial(h.symbols),indent=2))
                try:
                    if not h.terminated:raise ValueError('No EOS before sequence limit')
                    target=args.output/(path.stem+f'-candidate-{i}.musicxml')
                    export(h.symbols,target);record['exported']=True
                    if row['selected'] is None:
                        row['selected']=i;(args.output/(path.stem+'.musicxml')).write_bytes(target.read_bytes())
                except Exception as error:record['exported']=False;record['error']=str(error)
                row['candidates'].append(record)
        report['inputs'].append(row)
        (args.output/'inference.json').write_text(json.dumps(report,indent=2)+'\n')
        print(path.stem,'greedy matched',row['greedyReproduced'],'selected',row['selected'],'seconds',round(row['searchSeconds'],2),flush=True)


if __name__=='__main__':main()
