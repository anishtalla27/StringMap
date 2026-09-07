"""Verify App Attest's signed PKCS#7 receipt against the pinned Apple CA."""
from datetime import datetime, timezone
from pathlib import Path
import subprocess
import tempfile

from asn1crypto import core
from cryptography import x509
from cryptography.hazmat.primitives import serialization


class Attribute(core.Sequence):
    _fields = [('type', core.Integer), ('version', core.Integer), ('value', core.OctetString)]


class Attributes(core.SetOf):
    _child_spec = Attribute


def receipt_text(raw):
    # Apple receipt attributes carry an ASN.1 string. Decode that type explicitly
    # rather than accepting arbitrary BER values or replacement characters.
    item = core.Asn1Value.load(raw, strict=True)
    if not isinstance(item, (core.UTF8String, core.IA5String, core.GeneralizedTime)):
        raise ValueError('Invalid receipt string')
    return item.native


def verify_receipt(receipt, root_pem, app_id, public_pem):
    if not isinstance(receipt, bytes) or not 0 < len(receipt) < 100_000:
        raise ValueError('Missing or invalid receipt')
    with tempfile.TemporaryDirectory(prefix='appattest-') as directory:
        root = Path(directory)/'root.pem'; root.write_bytes(root_pem)
        verified = subprocess.run(['openssl', 'cms', '-verify', '-binary', '-inform', 'DER',
            '-CAfile', str(root), '-no-CApath', '-purpose', 'any'], input=receipt,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=5)
        if verified.returncode: raise ValueError('Receipt signature or chain invalid')
    attributes = Attributes.load(verified.stdout, strict=True)
    values = {}
    for attribute in attributes:
        field = attribute['type'].native
        if field in values: raise ValueError('Duplicate receipt attribute')
        values[field] = attribute['value'].native
    if receipt_text(values[2]) != app_id or receipt_text(values[6]) != 'ATTEST':
        raise ValueError('Receipt app or type mismatch')
    created = receipt_text(values[12])
    if isinstance(created, str): created = datetime.fromisoformat(created.replace('Z', '+00:00'))
    age = (datetime.now(timezone.utc) - created).total_seconds()
    if not -30 <= age <= 300: raise ValueError('Receipt creation time outside challenge window')
    try: public = serialization.load_der_public_key(values[3])
    except ValueError: public = x509.load_der_x509_certificate(values[3]).public_key()
    if public.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo) != public_pem:
        raise ValueError('Receipt public key mismatch')
