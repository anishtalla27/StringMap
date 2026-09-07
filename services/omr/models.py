"""Bake/check CPU HOMR models at build time; requests never fetch model code."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import urllib.request
import zipfile
import homr

REVISION = '457e7c6518a10ba755db2e60883419e56c4d7369'


def verify(download=False):
    root=Path(homr.__file__).parent
    manifest=json.loads((Path(__file__).parent/'homr-model-checksums.json').read_text())
    for name,digest in manifest.items():
        path=root/name
        if not path.exists() and download:
            url='https://github.com/liebharc/homr/releases/download/onnx_checkpoints/'+path.stem+'.zip'
            with urllib.request.urlopen(url,timeout=180) as response:
                data=response.read(100*1024*1024+1)
            if len(data)>100*1024*1024: raise RuntimeError('Model download exceeds limit')
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                matches=[x for x in archive.infolist() if Path(x.filename).name==path.name]
                if len(matches)!=1 or matches[0].file_size>100*1024*1024: raise RuntimeError('Unexpected model archive')
                model=archive.read(matches[0])
            if hashlib.sha256(model).hexdigest()!=digest: raise RuntimeError('Downloaded model checksum mismatch')
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(model)
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
            raise RuntimeError('Recognition model checksum mismatch: '+name)
    return True

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--download',action='store_true');args=parser.parse_args();verify(args.download);print('All pinned model checksums verified')
