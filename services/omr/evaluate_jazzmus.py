"""Offline research evaluation only; this is not a shipping recognition adapter.

Uses a separately cloned MIT Jazzmus repository and pinned local model assets.
No reference MusicXML is supplied to inference. Raw per-staff predictions remain
available even if symbolic conversion fails. General handwriting is not guitar
qualification, and staff detection does not establish that no staff was missed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("images", type=Path, nargs="+")
parser.add_argument("--repository", type=Path, default=Path("artifacts/jazzmus-evaluation"))
parser.add_argument("--model", type=Path, default=Path("artifacts/jazzmus-model"))
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
sys.path.insert(0, str(args.repository.resolve()))

import torch
from safetensors.torch import load_file
from ultralytics import YOLO
from predict import detect_staves, preprocess_staff, transcribe_staff
from jazzmus.model.smt.configuration_smt import SMTConfig
from jazzmus.model.smt.modeling_smt import SMTModelForCausalLM

torch.set_num_threads(4)
torch.manual_seed(0)
config = SMTConfig.from_pretrained(str(args.model.resolve()), local_files_only=True)
state = load_file(str(args.model / "model.safetensors"))
original_categories = config.out_categories
config.out_categories = state["decoder.embedding.weight"].shape[0]
model = SMTModelForCausalLM(config)
output_categories = state["decoder.out_layer.weight"].shape[0]
if config.out_categories != output_categories:
    model.decoder.out_layer = torch.nn.Conv1d(config.d_model, output_categories, kernel_size=1)
model.load_state_dict(state, strict=True)
config.out_categories = original_categories
model.eval()
yolo = YOLO(str(args.model / "yolo_staff_detector.pt"))
args.output.mkdir(parents=True, exist_ok=True)
model_hash = hashlib.sha256((args.model / "model.safetensors").read_bytes()).hexdigest()

for image in args.images:
    result = {"image": str(image), "imageSHA256": hashlib.sha256(image.read_bytes()).hexdigest(),
              "modelSHA256": model_hash, "device": "cpu", "staves": []}
    started = time.monotonic()
    try:
        crops = detect_staves(image, yolo)
        for index, crop in enumerate(crops):
            staff_started = time.monotonic()
            with torch.inference_mode():
                kern = transcribe_staff(model, preprocess_staff(crop))
            target = args.output / f"{image.stem}-staff-{index + 1}.krn"
            target.write_text(kern)
            result["staves"].append({"prediction": target.name, "seconds": time.monotonic() - staff_started})
            print(image.name, "staff", index + 1, "of", len(crops), flush=True)
        result["detectedStaves"] = len(crops)
    except Exception as error:
        result["error"] = str(error)
    result["seconds"] = time.monotonic() - started
    (args.output / f"{image.stem}.json").write_text(json.dumps(result, indent=2) + "\n")
    print(image.name, "finished", round(result["seconds"], 1), result.get("error", ""), flush=True)
