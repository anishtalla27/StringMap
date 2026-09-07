"""Security/lifecycle tests use a test CA and fake process, never accuracy claims."""
import base64
from datetime import datetime, timedelta, timezone
import io
from pathlib import Path
import tempfile
import time
import unittest
import uuid

import cbor2
from asn1crypto import core
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils
from cryptography.hazmat.primitives.serialization import pkcs7
from cryptography.x509.oid import NameOID, ObjectIdentifier
from fastapi.testclient import TestClient
from PIL import Image, ImageOps

from attestation import AppAttestVerifier, sha256
from production import APIError, Runtime, create_app, prepare_page
from receipt import Attribute, Attributes

APP='TEAM123456.com.stringmap.app'

class Identity:
    def __init__(self):
        self.rootkey=ec.generate_private_key(ec.SECP256R1()); self.interkey=ec.generate_private_key(ec.SECP256R1()); self.key=ec.generate_private_key(ec.SECP256R1())
        self.root=self.certificate('Root',self.rootkey,'Root',self.rootkey,True)
        self.inter=self.certificate('Intermediate',self.interkey,'Root',self.rootkey,True)
        self.rootpem=self.root.public_bytes(serialization.Encoding.PEM)
        self.keyid=base64.b64encode(sha256(self.key.public_key().public_bytes(serialization.Encoding.X962,serialization.PublicFormat.UncompressedPoint))).decode()
        self.verifier=AppAttestVerifier(APP,self.rootpem,'production',{'1'})
    def certificate(self,name,key,issuer,issuerkey,ca,nonce=None):
        now=datetime.now(timezone.utc)
        b=x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,name)])).issuer_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,issuer)])).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-timedelta(days=1)).not_valid_after(now+timedelta(days=2)).add_extension(x509.BasicConstraints(ca=ca,path_length=None),True)
        if nonce:b=b.add_extension(x509.UnrecognizedExtension(ObjectIdentifier('1.2.840.113635.100.8.2'),b'\x30\x24\xa1\x22\x04\x20'+nonce),False)
        return b.sign(issuerkey,hashes.SHA256())
    def extensions(self):return cbor2.dumps({'apple_validation_category_01':2,'apple_bundle_version_01':'1'})
    def attestation(self,client_hash,app=APP,created=None):
        p=self.key.public_key().public_numbers();cose={1:2,3:-7,-1:1,-2:p.x.to_bytes(32,'big'),-3:p.y.to_bytes(32,'big')}
        auth=sha256(app.encode())+b'\xc0'+bytes(4)+b'appattest'+bytes(7)+b'\x00\x20'+base64.b64decode(self.keyid)+cbor2.dumps(cose)+self.extensions()
        leaf=self.certificate('Device',self.key,'Intermediate',self.interkey,False,sha256(auth+client_hash))
        values={2:core.UTF8String(APP).dump(),3:self.key.public_key().public_bytes(serialization.Encoding.DER,serialization.PublicFormat.SubjectPublicKeyInfo),6:core.UTF8String('ATTEST').dump(),12:core.UTF8String((created or datetime.now(timezone.utc)).isoformat()).dump()}
        payload=Attributes([Attribute({'type':k,'version':1,'value':v}) for k,v in values.items()]).dump()
        receipt=pkcs7.PKCS7SignatureBuilder().set_data(payload).add_signer(leaf,self.key,hashes.SHA256()).add_certificate(self.inter).sign(serialization.Encoding.DER,[pkcs7.PKCS7Options.Binary])
        return cbor2.dumps({'fmt':'apple-appattest','authData':auth,'attStmt':{'x5c':[leaf.public_bytes(serialization.Encoding.DER),self.inter.public_bytes(serialization.Encoding.DER)],'receipt':receipt}})
    def assertion(self,client_hash,counter=1,app=APP):
        auth=sha256(app.encode())+b'\x80'+counter.to_bytes(4,'big')+self.extensions()
        signature=self.key.sign(sha256(auth+client_hash),ec.ECDSA(utils.Prehashed(hashes.SHA256())))
        return cbor2.dumps({'authenticatorData':auth,'signature':signature})


class AttestationTests(unittest.TestCase):
    def setUp(self): self.identity=Identity(); self.digest=sha256(b'challenge')
    def test_verified_receipt_attestation_and_assertion(self):
        i=self.identity; public=i.verifier.attest(i.attestation(self.digest),i.keyid,self.digest)
        self.assertEqual(i.verifier.assert_key(i.assertion(self.digest),public,self.digest,0),1)
        for previous,challenge,proof in [(1,self.digest,i.assertion(self.digest)),(0,sha256(b'other'),i.assertion(self.digest)),(0,self.digest,i.assertion(self.digest,app='OTHER.app'))]:
            with self.assertRaises(Exception):i.verifier.assert_key(proof,public,challenge,previous)
    def test_untrusted_chain_wrong_app_nonce_environment_build_and_old_receipt(self):
        i=self.identity
        cases=[(i.verifier,i.attestation(self.digest),sha256(b'wrong')),
               (i.verifier,i.attestation(self.digest,app='OTHER.app'),self.digest),
               (AppAttestVerifier(APP,Identity().rootpem),i.attestation(self.digest),self.digest),
               (AppAttestVerifier(APP,i.rootpem,'development'),i.attestation(self.digest),self.digest),
               (AppAttestVerifier(APP,i.rootpem,'production',{'2'}),i.attestation(self.digest),self.digest),
               (i.verifier,i.attestation(self.digest,created=datetime.now(timezone.utc)-timedelta(minutes=6)),self.digest)]
        for verifier,proof,digest in cases:
            with self.assertRaises(Exception):verifier.attest(proof,i.keyid,digest)
    def test_missing_receipt_and_trailing_cbor_rejected(self):
        i=self.identity;obj=cbor2.loads(i.attestation(self.digest));obj['attStmt'].pop('receipt')
        for proof in [cbor2.dumps(obj),i.attestation(self.digest)+b'junk']:
            with self.assertRaises(Exception):i.verifier.attest(proof,i.keyid,self.digest)


class ImagePreparationTests(unittest.TestCase):
    def test_jpeg_decoded_pixels_survive_preparation_and_png_storage_exactly(self):
        image=Image.new('RGB',(160,120))
        image.putdata([((x*17+y*13)%256,(x*11)%256,(y*23)%256) for y in range(120) for x in range(160)])
        encoded=io.BytesIO();image.save(encoded,'JPEG',quality=75)
        with Image.open(io.BytesIO(encoded.getvalue())) as decoded:
            expected=decoded.convert('RGB').tobytes()
        prepared=prepare_page(encoded.getvalue());stored=io.BytesIO();prepared.save(stored,'PNG')
        with Image.open(io.BytesIO(stored.getvalue())) as decoded:
            self.assertEqual(decoded.format,'PNG')
            self.assertEqual(decoded.tobytes(),expected)
            self.assertEqual(decoded.info,{})

    def test_camera_orientation_is_applied_and_metadata_is_stripped(self):
        image=Image.new('RGB',(160,120),'white');image.paste('black',(0,0,40,30))
        exif=Image.Exif();exif[274]=6;exif[270]='QA metadata must not survive'
        encoded=io.BytesIO();image.save(encoded,'JPEG',exif=exif)
        with Image.open(io.BytesIO(encoded.getvalue())) as original:
            expected=ImageOps.exif_transpose(original).convert('RGB')
        prepared=prepare_page(encoded.getvalue())
        self.assertEqual(prepared.size,(120,160))
        self.assertEqual(prepared.tobytes(),expected.tobytes())
        stored=io.BytesIO();prepared.save(stored,'PNG')
        with Image.open(io.BytesIO(stored.getvalue())) as decoded:
            self.assertFalse(decoded.getexif())
            self.assertEqual(decoded.info,{})

    def test_preparation_keeps_size_bounds_and_rejects_invalid_images(self):
        encoded=io.BytesIO();Image.new('RGB',(3200,1600),'white').save(encoded,'PNG')
        self.assertEqual(prepare_page(encoded.getvalue()).size,(3000,1500))
        small=io.BytesIO();Image.new('RGB',(99,200),'white').save(small,'PNG')
        for data in [small.getvalue(),b'invalid image']:
            with self.assertRaises((ValueError,OSError)):prepare_page(data)


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.directory=Path(self.temp.name);self.script=self.directory/'recognizer'
        self.script.write_text('#!/usr/bin/env python3\nimport pathlib,sys,time\ntime.sleep(0.1)\npathlib.Path(sys.argv[sys.argv.index("--output-path")+1]).write_text("<score-partwise><part id=\'P1\'><measure number=\'1\'><note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note></measure></part></score-partwise>")\n');self.script.chmod(0o755)
        self.identity=Identity();self.runtime=Runtime(self.directory/'data',self.identity.verifier,str(self.script))
        self.client=TestClient(create_app(self.runtime));self.client.__enter__()
        page=io.BytesIO();Image.new('RGB',(200,200),'white').save(page,'JPEG');self.image=page.getvalue()
    def tearDown(self):self.client.__exit__(None,None,None);self.temp.cleanup()
    def auth(self,identity=None):
        i=identity or self.identity;r=self.client.post('/v1/attest/challenge',json={'keyID':i.keyid});self.assertEqual(r.status_code,200);c=r.json();digest=sha256(f"StringMap:session:{c['id']}:{c['nonce']}".encode())
        body={'keyID':i.keyid,'challengeID':c['id'],'kind':'attestation','proof':base64.b64encode(i.attestation(digest)).decode()}
        r=self.client.post('/v1/attest/session',json=body);self.assertEqual(r.status_code,200,r.text)
        return {'Authorization':'Bearer '+r.json()['token']},body
    def submit(self,headers,key=None):return self.client.post('/v1/recognitions',content=self.image,headers={**headers,'Content-Type':'image/jpeg','Idempotency-Key':key or str(uuid.uuid4())})
    def wait(self,key):
        for _ in range(100):
            with self.runtime.lock:r=self.runtime.db.execute('SELECT status FROM jobs WHERE id=?',(key,)).fetchone()
            if r['status'] in {'completed','cancelled','failed'}:return r['status']
            time.sleep(.02)
        self.fail('Job did not finish')
    def test_session_replay_auth_and_ownership(self):
        headers,body=self.auth();self.assertEqual(self.client.post('/v1/attest/session',json=body).status_code,401)
        self.assertEqual(self.submit({}).status_code,401)
        r=self.submit(headers);self.assertEqual(r.status_code,202);key=r.json()['id'];self.assertEqual(self.wait(key),'completed')
        self.assertEqual(self.client.get('/v1/recognitions/'+key).status_code,401)
        # Another valid session still cannot read or cancel this owner's job.
        with self.runtime.lock:
            self.runtime.db.execute('INSERT INTO sessions VALUES (?,?,?)',(sha256(b'other-token').hex(),'other-owner',time.time()+100));self.runtime.db.commit()
        other={'Authorization':'Bearer other-token'}
        self.assertEqual(self.client.get('/v1/recognitions/'+key,headers=other).status_code,404)
        self.client.delete('/v1/recognitions/'+key,headers=other)
        self.assertEqual(self.client.get('/v1/recognitions/'+key,headers=headers).json()['status'],'completed')
        self.assertFalse(any(self.runtime.images.iterdir()))

    def test_sequence_limit_failure_is_actionable_and_cleans_the_image(self):
        self.script.write_text('#!/usr/bin/env python3\nimport pathlib,sys,json\noutput=pathlib.Path(sys.argv[sys.argv.index("--output-path")+1])\noutput.with_suffix(".error.json").write_text(json.dumps({"code":"sequence-limit"}))\nsys.exit(2)\n')
        headers,_=self.auth();response=self.submit(headers)
        self.assertEqual(response.status_code,202)
        key=response.json()['id'];self.assertEqual(self.wait(key),'failed')
        body=self.client.get('/v1/recognitions/'+key,headers=headers).json()
        self.assertIn('Crop a shorter passage',body['error'])
        self.assertIn('No partial score',body['error'])
        self.assertFalse(body.get('musicXMLBase64'))
        self.assertFalse(any(self.runtime.images.iterdir()))
    def test_idempotency_invalid_upload_limits_and_expiry(self):
        headers,_=self.auth();key=str(uuid.uuid4());r=self.submit(headers,key);self.assertEqual(r.status_code,202)
        self.assertEqual(self.submit(headers,key).json()['id'],key);self.wait(key)
        r=self.client.post('/v1/recognitions',content=b'bad',headers={**headers,'Content-Type':'image/jpeg','Idempotency-Key':str(uuid.uuid4())});self.assertEqual(r.status_code,422)
        with self.runtime.lock:
            self.runtime.db.execute('UPDATE jobs SET updated=0 WHERE id=?',(key,));self.runtime.db.commit()
        self.assertEqual(self.client.get('/v1/recognitions/'+key,headers=headers).status_code,404)
        for _ in range(2):self.runtime.limit('test',2)
        with self.assertRaises(APIError) as error:self.runtime.limit('test',2)
        self.assertEqual(error.exception.status,429)
    def test_running_process_cancellation_and_cleanup(self):
        self.script.write_text('#!/usr/bin/env python3\nimport time,pathlib\npathlib.Path("started").write_text("yes")\ntime.sleep(60)\n')
        headers,_=self.auth();r=self.submit(headers);key=r.json()['id'];path=self.runtime.images/key
        for _ in range(100):
            if (path/'started').exists():break
            time.sleep(.02)
        self.assertTrue((path/'started').exists());start=time.monotonic()
        self.assertEqual(self.client.get('/v1/recognitions/'+key.upper(),headers=headers).json()['status'],'processing')
        self.assertEqual(self.client.delete('/v1/recognitions/'+key.upper(),headers=headers).status_code,204)
        self.assertLess(time.monotonic()-start,3);self.assertFalse(path.exists());self.assertEqual(self.wait(key),'cancelled')
    def test_restart_removes_crash_images_and_returns_recoverable_failure(self):
        self.client.__exit__(None,None,None)
        path=self.directory/'data/images/crash';path.mkdir();(path/'page').write_bytes(b'sensitive')
        import sqlite3
        db=sqlite3.connect(self.directory/'data/state.sqlite3');db.execute("INSERT INTO jobs VALUES ('crash','owner','hash','page','processing',0,0,NULL,NULL)");db.commit();db.close()
        self.runtime=Runtime(self.directory/'data',self.identity.verifier,str(self.script));self.client=TestClient(create_app(self.runtime));self.client.__enter__()
        self.assertFalse(path.exists());self.assertEqual(self.runtime.job('crash','owner')['status'],'failed')
    def test_production_requires_verifier(self):
        with self.assertRaises(ValueError):Runtime(self.directory/'unsafe',None,str(self.script))


if __name__=='__main__':unittest.main()
