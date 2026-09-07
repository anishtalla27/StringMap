"""Narrow fix for oemer dbe2a933 single-staff scalar iteration crashes.

Fixes scalar iteration and empty key-signature detection. Uses the CPU provider
on every host to match the production container. Refuses a different
upstream source revision. MIT upstream notices accompany the container.
"""
import hashlib
from pathlib import Path
import oemer

ORIGINAL = {'utils.py': '02ccddf5ef489031289b06df76edebe1a39e0c6656b1660411cb1d3c5d616bf5', 'staffline_extraction.py': 'ba60d544d0ccd737db11a982a3addf94b31ff433f7572c192b501bd812ad7d9d', 'barline_extraction.py': 'b2accc144b641609eedca0dd9cc12b949e4cbe70347c578812d294004c29231a'}

EXTRA = {'build_system.py': ('5ca7bc0d359bcfdfdbc1fcf718fd358844b4ffb039a9d5ebf1f1fa57ca14a046', 'return all(isinstance(sym, Sfn) for sym in syms)', 'return len(syms) == total_tracks and all(isinstance(sym, Sfn) for sym in syms)'), 'inference.py': ('5cac4cee8d486e8cd29f2c4a14930beb547fada1e42c348a96600272cea35c79', 'providers = ["CoreMLExecutionProvider", "CPUExecutionProvider"]', 'providers = ["CPUExecutionProvider"]')}

def apply():
    root = Path(oemer.__file__).parent
    for name, digest in ORIGINAL.items():
        path = root/name; raw = path.read_bytes()
        old = b'staffs.reshape(-1, 1).squeeze()'; new = b'staffs.reshape(-1)'
        if old not in raw:
            # Recognize only exactly our own already-patched source.
            restored = raw.replace(new, old)
            if hashlib.sha256(restored).hexdigest() != digest:
                raise RuntimeError('Unknown oemer source: '+name)
            continue
        if hashlib.sha256(raw).hexdigest() != digest:
            raise RuntimeError('Unknown oemer source: '+name)
        path.write_bytes(raw.replace(old, new))
    for name, (digest, before, after) in EXTRA.items():
        path = root/name; raw = path.read_text()
        if after in raw:
            if hashlib.sha256(raw.replace(after, before).encode()).hexdigest() != digest:
                raise RuntimeError('Unknown oemer source: '+name)
            continue
        if hashlib.sha256(raw.encode()).hexdigest() != digest: raise RuntimeError('Unknown oemer source: '+name)
        path.write_text(raw.replace(before, after))
    print('Applied pinned single-staff, empty-key and CPU-provider fixes')

if __name__ == '__main__': apply()
