"""Bake/check trusted models at build time; requests never fetch model code."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
import oemer


def verify(download=False):
    root=Path(oemer.__file__).parent
    manifest=json.loads((Path(__file__).parent/'model-checksums.json').read_text())
    for name,digest in manifest.items():
        path=root/name
        if not path.exists() and download and path.suffix=='.onnx':
            model='1st_model.onnx' if 'unet_big' in name else '2nd_model.onnx'
            path.parent.mkdir(parents=True,exist_ok=True)
            with urllib.request.urlopen('https://github.com/BreezeWhite/oemer/releases/download/checkpoints/'+model,timeout=180) as response:
                path.write_bytes(response.read())
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
            raise RuntimeError('Recognition model checksum mismatch: '+name)
    return True

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--download',action='store_true');args=parser.parse_args();verify(args.download);print('All pinned model checksums verified')
