"""App Attest verification following Apple's server validation procedure.

Production always pins Apple's App Attestation Root CA. Tests inject a separate
test CA; there is no HTTP switch to bypass verification.
"""
from __future__ import annotations

import base64
import hashlib
import io
from datetime import datetime, timezone

from receipt import verify_receipt
import cbor2
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils
from cryptography.x509.oid import ObjectIdentifier


def sha256(value: bytes) -> bytes:
    return hashlib.sha256(value).digest()


def decode(value: bytes):
    stream = io.BytesIO(value)
    result = cbor2.CBORDecoder(stream).decode()
    if stream.read(1):
        raise ValueError("Trailing CBOR data")
    return result


class AppAttestVerifier:
    def __init__(self, app_id: str, root_pem: bytes, environment: str = "production", builds: set[str] | None = None):
        if environment not in {"production", "development"} or not app_id or "." not in app_id:
            raise ValueError("App ID and attestation environment are required")
        self.root_pem = root_pem; self.app_id = app_id
        self.root = x509.load_pem_x509_certificate(root_pem)
        self.rp_id = sha256(app_id.encode())
        self.environment = environment
        self.builds = builds or set()

    def _extensions(self, auth: bytes, offset: int):
        if auth[32] & 0x80:
            ext = decode(auth[offset:])
            category = ext.get("apple_validation_category_01")
            version = ext.get("apple_bundle_version_01")
            allowed = {2, 4} if self.environment == "production" else {3}
            if category not in allowed or (self.builds and version not in self.builds):
                raise ValueError("Unexpected distribution or build")
        elif self.builds:
            # Builds explicitly configured for release must supply signed launch
            # metadata. Physical-device validation confirms its availability.
            raise ValueError("Missing signed build metadata")

    def attest(self, proof: bytes, key_id: str, client_hash: bytes) -> bytes:
        obj = decode(proof)
        if obj.get("fmt") != "apple-appattest":
            raise ValueError("Unexpected attestation format")
        chain = obj["attStmt"]["x5c"]
        if len(chain) != 2:
            raise ValueError("Expected leaf and intermediate certificates")
        leaf, intermediate = [x509.load_der_x509_certificate(item) for item in chain]
        now = datetime.now(timezone.utc)
        for certificate in [leaf, intermediate, self.root]:
            if not certificate.not_valid_before_utc <= now <= certificate.not_valid_after_utc:
                raise ValueError("Expired attestation certificate")
        leaf.verify_directly_issued_by(intermediate)
        intermediate.verify_directly_issued_by(self.root)
        if not intermediate.extensions.get_extension_for_class(x509.BasicConstraints).value.ca:
            raise ValueError("Invalid intermediate")
        auth = obj["authData"]
        if len(auth) < 55 or auth[:32] != self.rp_id or not auth[32] & 0x40 or int.from_bytes(auth[33:37], "big") != 0:
            raise ValueError("Invalid attested authenticator")
        aaguid = b"appattest" + b"\x00" * 7 if self.environment == "production" else b"appattestdevelop"
        if auth[37:53] != aaguid:
            raise ValueError("Wrong App Attest environment")
        key_hash = base64.b64decode(key_id, validate=True)
        length = int.from_bytes(auth[53:55], "big")
        if length != 32 or auth[55:87] != key_hash:
            raise ValueError("Wrong credential identity")
        public = leaf.public_key()
        if not isinstance(public, ec.EllipticCurvePublicKey) or not isinstance(public.curve, ec.SECP256R1):
            raise ValueError("Expected P-256 key")
        if sha256(public.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)) != key_hash:
            raise ValueError("Public key does not match key ID")
        nonce = sha256(auth + client_hash)
        extension = leaf.extensions.get_extension_for_oid(ObjectIdentifier("1.2.840.113635.100.8.2")).value.value
        if extension != b"\x30\x24\xa1\x22\x04\x20" + nonce:
            raise ValueError("Attestation challenge mismatch")
        stream = io.BytesIO(auth[87:]); cose = cbor2.CBORDecoder(stream).decode()
        numbers = public.public_numbers()
        if cose.get(1) != 2 or cose.get(3) != -7 or cose.get(-1) != 1 or cose.get(-2) != numbers.x.to_bytes(32, "big") or cose.get(-3) != numbers.y.to_bytes(32, "big"):
            raise ValueError("Attested COSE key mismatch")
        self._extensions(auth, 87 + stream.tell())
        public_pem = public.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
        verify_receipt(obj["attStmt"].get("receipt"), self.root_pem, self.app_id, public_pem)
        return public_pem

    def assert_key(self, proof: bytes, public_pem: bytes, client_hash: bytes, previous_counter: int) -> int:
        obj = decode(proof); auth = obj["authenticatorData"]
        if len(auth) < 37 or auth[:32] != self.rp_id:
            raise ValueError("Assertion App ID mismatch")
        counter = int.from_bytes(auth[33:37], "big")
        if counter <= previous_counter:
            raise ValueError("Replayed assertion")
        public = serialization.load_pem_public_key(public_pem)
        if not isinstance(public, ec.EllipticCurvePublicKey):
            raise ValueError("Expected EC assertion key")
        public.verify(obj["signature"], sha256(auth + client_hash), ec.ECDSA(utils.Prehashed(hashes.SHA256())))
        self._extensions(auth, 37)
        return counter
