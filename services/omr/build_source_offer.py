"""Build the exact server recognizer's downloadable corresponding-source bundle."""
import argparse
import hashlib
import io
from pathlib import Path
import tarfile
import urllib.request

REVISION = '457e7c6518a10ba755db2e60883419e56c4d7369'
DIGEST = '41511b373d6ae1a182f07c8657eec86a52aea706f54351cdd79228a7c76bafa5'


def build(output: Path):
    with urllib.request.urlopen('https://codeload.github.com/liebharc/homr/tar.gz/'+REVISION, timeout=120) as response:
        source = response.read(30*1024*1024+1)
    if hashlib.sha256(source).hexdigest() != DIGEST: raise RuntimeError('Unexpected HOMR source archive')
    root = Path(__file__).parent
    files = {p.name: p.read_bytes() for p in root.glob('*.py') if not p.name.startswith(('test_', 'legacy_', 'patch_oemer'))}
    for name in ['Dockerfile', 'entrypoint.sh', 'bootstrap.sh', 'README.md', 'requirements.txt', 'requirements-lock.txt', 'homr-model-checksums.json', 'COPYING.homr', 'RECOGNIZER-LICENSE.md']:
        files[name] = (root/name).read_bytes()
    for certificate in sorted((root/'certificates').glob('*')):
        if certificate.is_file(): files['certificates/'+certificate.name] = certificate.read_bytes()
    files['HOMR-upstream.tar.gz'] = source
    files['SOURCE-README.txt'] = (
        'StringMap hosted recognizer corresponding source\n'
        'HOMR revision '+REVISION+'; its complete source, training and model-export code are in HOMR-upstream.tar.gz.\n'
        'The guitar adapter and all service build scripts are included here. No recognition engine is embedded in the iOS app.\n'
        'Install Python 3.12, pip install -r requirements-lock.txt, then python patch_homr.py and python models.py --download.\n'
        'patch_homr.py verifies the pinned upstream XML writer, preserves its exact rational timing grid and emits every simultaneous rest.\n'
        'symbol_timing.py preserves interleaved onsets while earlier rhythmic voices sustain.\n'
        'The checksum-verified CPU model weights are obtained from the upstream release URLs in models.py.\n'
        'For a local run: OMR_ENV=development OMR_DATA_DIR=/tmp/stringmap uvicorn production:configured_app --factory --host 127.0.0.1.\n'
        'Production requires Apple App Attest configuration as described in production.py and deployment authentication setup.\n'
    ).encode()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(output, 'w:gz') as archive:
        for name, data in sorted(files.items()):
            info = tarfile.TarInfo('stringmap-recognizer/'+name); info.size = len(data); info.mode = 0o755 if name in ['entrypoint.sh', 'bootstrap.sh'] else 0o644
            archive.addfile(info, io.BytesIO(data))
    print('Prepared corresponding source:', output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--output', type=Path, default=Path('recognizer-source.tar.gz'))
    build(parser.parse_args().output)
