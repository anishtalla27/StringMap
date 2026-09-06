"""Research-only Zeus inference on image-derived staff crops, without references.

Preserves every raw token prediction, including undecodable output. Compares
fixed preprocessing variants; does not select a result using ground truth.
Run in the isolated Zeus Python 3.10 environment, never the service worker.
"""
import argparse
import hashlib
import json
import time
from pathlib import Path

import numpy as np
import tensorflow as tf
from zeus import InferenceOptions, Zeus
from zeus.musicxml.lmx_to_musicxml import LmxDecodingError, lmx_to_musicxml


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--crops", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    paths = sorted(args.crops.glob("staff-*.png"), key=lambda p: int(p.stem.split("-")[-1]))
    if not paths:
        raise ValueError("No image-derived staff crops found")
    tight = []
    inputs = []
    for path in paths:
        data = path.read_bytes()
        pixels = tf.io.decode_png(data, channels=1).numpy()
        height, width = pixels.shape[:2]
        rows = np.flatnonzero((pixels[:, :, 0] < 128).sum(axis=1) >= max(4, width // 1000))
        if not rows.size:
            raise ValueError(f"Empty staff crop: {path.name}")
        top, bottom = max(0, int(rows[0]) - 8), min(height, int(rows[-1]) + 9)
        target = args.output / path.name
        target.write_bytes(tf.io.encode_png(pixels[top:bottom]).numpy())
        tight.append(target.read_bytes())
        inputs.append({"staff": path.stem, "sourceSHA256": hashlib.sha256(data).hexdigest(),
                       "cropBounds": [0, top, width, bottom],
                       "cropSHA256": hashlib.sha256(tight[-1]).hexdigest()})
    started = time.monotonic()
    model = Zeus.load(args.model)
    load_seconds = time.monotonic() - started
    variants = []
    for name, transformations in [("tight", []), ("tight-threshold", ["threshold:0.3:0.7:smooth"])]:
        output = args.output / name
        output.mkdir()
        started = time.monotonic()
        predictions = model.predict(tight, InferenceOptions(batch_size=1, transformations=transformations))
        elapsed = time.monotonic() - started
        if len(predictions) != len(paths):
            raise ValueError("Recognizer output count differs from input count")
        results = []
        for path, prediction in zip(paths, predictions):
            (output / (path.stem + ".lmx")).write_text(prediction)
            result = {"staff": path.stem, "tokens": len(prediction.split())}
            try:
                xml = lmx_to_musicxml(prediction)
                (output / (path.stem + ".musicxml")).write_text(xml)
                result["musicXMLProduced"] = True
            except LmxDecodingError as error:
                result.update(musicXMLProduced=False, error=str(error))
            results.append(result)
        variants.append({"variant": name, "inferenceSeconds": elapsed, "results": results})
        print(name, sum(r["musicXMLProduced"] for r in results), "/", len(results), flush=True)
    (args.output / "inference.json").write_text(json.dumps({"model": str(args.model),
        "modelLoadSeconds": load_seconds, "inputs": inputs, "variants": variants,
        "referenceUsedByRecognizer": False, "releaseQualified": False}, indent=2) + "\n")


if __name__ == "__main__":
    main()
