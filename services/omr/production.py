"""Bounded, authenticated photo recognition service. Run one process/replica.

SQLite on a persistent private volume holds job status and anonymous keys. Image
files are temporary, never backed up, and removed on every terminal path/startup.
"""
from __future__ import annotations

import asyncio
import base64
import contextlib
import hashlib
import fcntl
import resource
import sys
import io
import json
import os
import secrets
import shutil
import signal
import sqlite3
import subprocess
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import unquote

from fastapi import FastAPI, Request
from fastapi.responses import FileResponse, JSONResponse, Response
from PIL import Image, ImageOps, UnidentifiedImageError

from attestation import AppAttestVerifier, decode, sha256

MAX_BYTES = 20 * 1024 * 1024
RESULT_TTL_SECONDS = 55 * 60  # Cleanup cadence leaves headroom below the one-hour maximum.
Image.MAX_IMAGE_PIXELS = 20_000_000


class APIError(Exception):
    def __init__(self, status: int, message: str):
        self.status = status; self.message = message


def prepare_page(image: bytes) -> Image.Image:
    """Decode, orient, bound and strip metadata before recognition."""
    with Image.open(io.BytesIO(image)) as page:
        if page.format not in {"JPEG", "PNG"} or page.width * page.height > Image.MAX_IMAGE_PIXELS:
            raise ValueError("Invalid image")
        page.verify()
    with Image.open(io.BytesIO(image)) as page:
        page.load()
        if min(page.size) < 100:
            raise ValueError("Image is too small")
        prepared = ImageOps.exif_transpose(page).convert("RGB")
        prepared.thumbnail((3000, 3000))
        # Retain displayed orientation, not EXIF or descriptive metadata.
        prepared.info.clear()
        return prepared


class Runtime:
    def __init__(self, directory: Path, verifier: AppAttestVerifier | None, executable: str, development: bool = False, command_prefix: list[str] | None = None):
        if verifier is None and not development:
            raise ValueError("Production requires App Attest verification")
        self.directory = directory; directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.process_lock = open(directory / "runtime.lock", "a+b")
        try: fcntl.flock(self.process_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.process_lock.close()
            raise RuntimeError("Only one recognition process may own this data volume.") from None
        self.images = directory / "images"
        # No jobs survive a restart as running. The client gets a clear retry
        # state; uploaded images are not retained for automatic reprocessing.
        shutil.rmtree(self.images, ignore_errors=True); self.images.mkdir(mode=0o700)
        self.db = sqlite3.connect(directory / "state.sqlite3", check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.lock = threading.RLock(); self.verifier = verifier; self.development = development
        self.executable = executable; self.events: dict[str, threading.Event] = {}
        self.command_prefix = command_prefix or [executable]
        self.pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="omr")
        self.stopping = threading.Event()
        self.db.executescript("""
          PRAGMA journal_mode=DELETE;
          PRAGMA secure_delete=ON;
          CREATE TABLE IF NOT EXISTS keys(id TEXT PRIMARY KEY, public BLOB, counter INTEGER, used REAL);
          CREATE TABLE IF NOT EXISTS challenges(id TEXT PRIMARY KEY, key_id TEXT, nonce TEXT, expires REAL);
          CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY, owner TEXT, expires REAL);
          CREATE TABLE IF NOT EXISTS limits(bucket TEXT PRIMARY KEY, count INTEGER, expires REAL);
          CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY, owner TEXT, hash TEXT, source TEXT, status TEXT,
             created REAL, updated REAL, xml BLOB, error TEXT);
        """)
        if "receipt" not in {r[1] for r in self.db.execute("PRAGMA table_info(keys)")}:
            self.db.execute("ALTER TABLE keys ADD COLUMN receipt BLOB")
        self.db.execute("UPDATE jobs SET status='failed',error='Recognition was interrupted. Please resubmit the page.',updated=? WHERE status IN ('queued','processing')", (time.time(),))
        self.db.commit()
        self.cleaner = threading.Thread(target=self._cleanup_loop, daemon=True); self.cleaner.start()

    def cleanup(self):
        with self.lock:
            now = time.time()
            for table in ["challenges", "sessions", "limits"]:
                self.db.execute(f"DELETE FROM {table} WHERE expires < ?", (now,))
            self.db.execute("DELETE FROM jobs WHERE updated < ? AND status NOT IN ('processing','queued')", (now - RESULT_TTL_SECONDS,))
            self.db.execute("DELETE FROM keys WHERE used < ?", (now - 90 * 86400,))
            self.db.commit()

    def _cleanup_loop(self):
        while not self.stopping.wait(30): self.cleanup()

    def close(self):
        self.stopping.set()
        with self.lock:
            for event in self.events.values(): event.set()
        self.pool.shutdown(wait=True, cancel_futures=False)
        self.cleaner.join(timeout=2)
        self.cleanup(); self.db.close(); self.process_lock.close()

    def limit(self, bucket: str, maximum: int, seconds: int = 3600):
        with self.lock:
            now = time.time(); row = self.db.execute("SELECT * FROM limits WHERE bucket=?", (bucket,)).fetchone()
            if row and row["expires"] > now:
                if row["count"] >= maximum: raise APIError(429, "Recognition limit reached. Please try again later.")
                self.db.execute("UPDATE limits SET count=count+1 WHERE bucket=?", (bucket,))
            else:
                self.db.execute("INSERT OR REPLACE INTO limits VALUES (?,1,?)", (bucket, now + seconds))
            self.db.commit()

    def owner(self, request: Request) -> str:
        if self.development:
            if request.client and request.client.host not in {"127.0.0.1", "::1", "testclient"}:
                raise APIError(403, "Development recognition only accepts loopback connections.")
            return "local-development"
        token = request.headers.get("Authorization", "").removeprefix("Bearer ")
        with self.lock:
            row = self.db.execute("SELECT owner FROM sessions WHERE hash=? AND expires>?", (hashlib.sha256(token.encode()).hexdigest(), time.time())).fetchone()
        if not row: raise APIError(401, "Recognition session expired. Please reconnect.")
        return row["owner"]

    def challenge(self, key: str, address: str) -> dict:
        try:
            if len(base64.b64decode(key, validate=True)) != 32: raise ValueError()
        except Exception: raise APIError(400, "Invalid key") from None
        self.limit("challenge:" + hashlib.sha256(address.encode()).hexdigest(), 30)
        value = {"id": str(uuid.uuid4()), "nonce": secrets.token_urlsafe(32)}
        with self.lock:
            value["registered"] = self.db.execute("SELECT 1 FROM keys WHERE id=?", (key,)).fetchone() is not None
            self.db.execute("INSERT INTO challenges VALUES (?,?,?,?)", (value["id"], key, value["nonce"], time.time() + 120))
            self.db.commit()
        return value

    def session(self, body: dict) -> dict:
        if self.verifier is None: raise APIError(404, "Attestation is not used by the local development service.")
        if any(not isinstance(body.get(k), str) for k in ["keyID", "challengeID", "kind", "proof"]):
            raise APIError(400, "Invalid verification request.")
        with self.lock:
            row = self.db.execute("SELECT * FROM challenges WHERE id=? AND key_id=? AND expires>?", (body.get("challengeID"), body.get("keyID"), time.time())).fetchone()
            if not row: raise APIError(401, "Challenge expired or already used.")
            # Consume before verification, under the same lock as counter updates.
            self.db.execute("DELETE FROM challenges WHERE id=?", (row["id"],)); self.db.commit()
            try:
                proof = base64.b64decode(body["proof"], validate=True)
                client_hash = sha256(f"StringMap:session:{row['id']}:{row['nonce']}".encode())
                key = self.db.execute("SELECT * FROM keys WHERE id=?", (row["key_id"],)).fetchone()
                if key:
                    if body.get("kind") != "assertion": raise ValueError("Key is already registered")
                    counter = self.verifier.assert_key(proof, key["public"], client_hash, key["counter"])
                    self.db.execute("UPDATE keys SET counter=?,used=? WHERE id=?", (counter, time.time(), key["id"]))
                else:
                    if body.get("kind") != "attestation": raise ValueError("Key is not registered")
                    public = self.verifier.attest(proof, row["key_id"], client_hash)
                    self.db.execute("INSERT INTO keys (id,public,counter,used,receipt) VALUES (?,?,0,?,?)", (row["key_id"], public, time.time(), decode(proof)["attStmt"]["receipt"]))
            except Exception:
                self.db.rollback(); raise APIError(401, "App verification failed.") from None
            token = secrets.token_urlsafe(32)
            self.db.execute("INSERT INTO sessions VALUES (?,?,?)", (hashlib.sha256(token.encode()).hexdigest(), row["key_id"], time.time() + 3600))
            self.db.commit()
            return {"token": token, "expiresIn": 3600}

    @staticmethod
    def payload(row) -> dict:
        payload = {"id": row["id"], "status": row["status"], "sourceName": row["source"], "expiresAt": row["updated"] + RESULT_TTL_SECONDS}
        if row["xml"] is not None: payload["musicXMLBase64"] = base64.b64encode(row["xml"]).decode()
        if row["error"]: payload["error"] = row["error"]
        return payload

    def job(self, job_id: str, owner: str) -> dict:
        job_id = job_id.lower()
        self.cleanup()
        with self.lock:
            row = self.db.execute("SELECT * FROM jobs WHERE id=? AND owner=?", (job_id, owner)).fetchone()
        if not row: raise APIError(404, "Recognition result was deleted or expired. Please resubmit the page.")
        return self.payload(row)

    def submit(self, image: bytes, source: str, job_id: str, owner: str) -> dict:
        self.cleanup()
        try: job_id = str(uuid.UUID(job_id))
        except ValueError: raise APIError(400, "A UUID Idempotency-Key is required.") from None
        digest = hashlib.sha256(image).hexdigest()
        with self.lock:
            previous = self.db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
            if previous:
                if previous["owner"] != owner or previous["hash"] != digest: raise APIError(409, "This request ID was already used.")
                return self.payload(previous)
            if not shutil.which(self.executable): raise APIError(503, "Recognition is temporarily unavailable.")
            if self.db.execute("SELECT count(*) FROM jobs WHERE status IN ('queued','processing')").fetchone()[0] >= 4:
                raise APIError(429, "The recognition queue is full. Please try again shortly.")
            if self.db.execute("SELECT 1 FROM jobs WHERE owner=? AND status IN ('queued','processing')", (owner,)).fetchone():
                raise APIError(409, "Finish or cancel your current page before scanning another.")
            self.limit("scan:" + owner, int(os.environ.get("MAX_HOURLY_SCANS_PER_DEVICE", "20")))
            self.limit("global-scans", int(os.environ.get("MAX_DAILY_SCANS", "100")), 86400)
            try:
                page = prepare_page(image)
                work = self.images / job_id; work.mkdir(mode=0o700)
                page.save(work / "page.jpg", "JPEG", quality=95)
            except (UnidentifiedImageError, ValueError, OSError, Image.DecompressionBombError):
                shutil.rmtree(self.images / job_id, ignore_errors=True)
                raise APIError(422, "Choose a valid, readable JPEG or PNG page under 20 megapixels.") from None
            now = time.time()
            self.db.execute("INSERT INTO jobs VALUES (?,?,?,?,?,?,?,?,?)", (job_id, owner, digest, unquote(source)[:200], "queued", now, now, None, None))
            self.db.commit()
            event = threading.Event(); self.events[job_id] = event
            self.pool.submit(self._run, job_id, work, event)
            return self.job(job_id, owner)

    def delete(self, job_id: str, owner: str):
        job_id = job_id.lower()
        with self.lock:
            row = self.db.execute("SELECT status FROM jobs WHERE id=? AND owner=?", (job_id, owner)).fetchone()
            if not row: return  # Idempotent and reveals no other user's job.
            if event := self.events.get(job_id): event.set()
            self.db.execute("UPDATE jobs SET status='cancelled',xml=NULL,error=NULL,updated=? WHERE id=?", (time.time(), job_id))
            self.db.commit()
            if row["status"] == "queued": shutil.rmtree(self.images / job_id, ignore_errors=True)
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            with self.lock:
                if not (self.images / job_id).exists(): return
            time.sleep(0.05)
        raise APIError(503, "Cancellation is in progress. Please try again shortly.")

    def _run(self, job_id: str, work: Path, cancelled: threading.Event):
        usage_before = resource.getrusage(resource.RUSAGE_CHILDREN)
        started = time.monotonic(); state = "failed"; result = None; error = None
        try:
            with self.lock:
                row = self.db.execute("SELECT created,status FROM jobs WHERE id=?", (job_id,)).fetchone()
                if cancelled.is_set() or row["status"] == "cancelled": return
                if time.time() - row["created"] > 120: raise TimeoutError("Queue timed out. Please try again.")
                self.db.execute("UPDATE jobs SET status='processing',updated=? WHERE id=?", (time.time(), job_id)); self.db.commit()
            if cancelled.is_set(): return
            command = self.command_prefix + [str(work / "page.jpg"), "--output-path", str(work / "result.musicxml")]
            process = subprocess.Popen(command, cwd=work, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            try:
                while process.poll() is None:
                    if cancelled.wait(0.1): return
                    if time.monotonic() - started > 180: raise TimeoutError("Recognition timed out. Try a clearer or smaller crop.")
            finally:
                if process.poll() is None:
                    with contextlib.suppress(ProcessLookupError): os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
            output = work / "result.musicxml"
            if process.returncode != 0 or not output.exists():
                failure_code = work / "result.error.json"
                if failure_code.exists() and failure_code.stat().st_size < 1024:
                    with contextlib.suppress(json.JSONDecodeError):
                        code = json.loads(failure_code.read_bytes()).get('code')
                        if code == 'unsupported':
                            raise ValueError("This layout contains multiple or unresolved staves. Crop the guitar part alone; no staves were discarded.")
                        if code == 'sequence-limit':
                            raise ValueError("This passage is too long or dense to finish reading. Crop a shorter passage or import MusicXML. No partial score was saved.")
                raise ValueError("The page could not be read. Retake it or import MusicXML.")
            if not 0 < output.stat().st_size <= 10 * 1024 * 1024: raise ValueError("Recognition produced an invalid score.")
            from recognizer import validate_score
            result = output.read_bytes(); validate_score(result); state = "completed"
        except (ValueError, TimeoutError) as failure:
            error = str(failure)
        except Exception:
            error = "Recognition failed. Your photo was deleted; please try again."
        finally:
            shutil.rmtree(work, ignore_errors=True)
            with self.lock:
                if cancelled.is_set(): state = "cancelled"; result = None; error = None
                self.db.execute("UPDATE jobs SET status=?,xml=?,error=?,updated=? WHERE id=?", (state, result, error, time.time(), job_id))
                self.db.commit(); self.events.pop(job_id, None)
            # Operational events contain no filenames, images, score text or identifiers.
            usage_after = resource.getrusage(resource.RUSAGE_CHILDREN)
            cpu_seconds = usage_after.ru_utime + usage_after.ru_stime - usage_before.ru_utime - usage_before.ru_stime
            print(json.dumps({"event": "recognition_finished", "status": state, "seconds": round(time.monotonic() - started, 2),
                "cpuSeconds": round(cpu_seconds, 2), "lifetimeChildPeakRSSBytes": usage_after.ru_maxrss * (1 if sys.platform == "darwin" else 1024)}), flush=True)


def create_app(runtime: Runtime) -> FastAPI:
    @contextlib.asynccontextmanager
    async def lifespan(app):
        yield
        await asyncio.to_thread(runtime.close)
    app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

    uploads = asyncio.Semaphore(4)

    @app.middleware("http")
    async def no_cache(request, call_next):
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    @app.exception_handler(APIError)
    async def failure(request, error):
        return JSONResponse({"error": error.message}, status_code=error.status, headers={"Cache-Control": "no-store", "Retry-After": "60"})

    async def read(request: Request, maximum: int) -> bytes:
        data = bytearray()
        try:
            async with asyncio.timeout(30):
                async for part in request.stream():
                    data.extend(part)
                    if len(data) > maximum: raise APIError(413, "Upload is too large.")
        except TimeoutError: raise APIError(408, "Upload timed out. Please try again on a stable connection.") from None
        if not data: raise APIError(400, "Empty request.")
        return bytes(data)

    async def body(request: Request) -> dict:
        try:
            value = json.loads(await read(request, 100_000))
            if not isinstance(value, dict): raise ValueError()
            return value
        except (ValueError, TypeError): raise APIError(400, "Invalid request.") from None

    @app.get("/health")
    def health():
        ready = bool(shutil.which(runtime.executable))
        return JSONResponse({"status": "ok" if ready else "unavailable", "engineReady": ready}, status_code=200 if ready else 503)

    @app.get('/recognizer-source.tar.gz')
    def recognizer_source():
        source = Path(__file__).with_name('recognizer-source.tar.gz')
        if not source.is_file(): raise APIError(404, 'The recognition source bundle is unavailable in this development build.')
        return FileResponse(source, media_type='application/gzip', filename='stringmap-recognizer-source.tar.gz')

    @app.post("/v1/attest/challenge")
    async def challenge(request: Request):
        payload = await body(request)
        return runtime.challenge(str(payload.get("keyID", "")), request.client.host if request.client else "unknown")

    @app.post("/v1/attest/session")
    async def session(request: Request): return runtime.session(await body(request))

    @app.post("/v1/recognitions", status_code=202)
    async def submit(request: Request):
        owner = runtime.owner(request)
        if request.headers.get("Content-Type", "").split(";")[0] not in {"image/jpeg", "image/png"}:
            raise APIError(415, "Send a JPEG or PNG image.")
        try: await asyncio.wait_for(uploads.acquire(), timeout=0.1)
        except TimeoutError: raise APIError(429, "Uploads are busy. Please try again shortly.") from None
        try:
            image = await read(request, MAX_BYTES)
            return await asyncio.to_thread(runtime.submit, image, request.headers.get("X-StringMap-Source-Name", "Guitar page"), request.headers.get("Idempotency-Key", ""), owner)
        finally: uploads.release()

    @app.get("/v1/recognitions/{job_id}")
    def job(job_id: str, request: Request): return JSONResponse(runtime.job(job_id, runtime.owner(request)), headers={"Cache-Control": "no-store"})

    @app.delete("/v1/recognitions/{job_id}", status_code=204)
    def delete(job_id: str, request: Request):
        runtime.delete(job_id, runtime.owner(request)); return Response(status_code=204)

    return app


def configured_app() -> FastAPI:
    development = os.environ.get("OMR_ENV") == "development"
    verifier = None
    if not development:
        root = (Path(__file__).parent / "certificates/Apple_App_Attestation_Root_CA.pem").read_bytes()
        app_id = os.environ["APPLE_APP_ID"]
        builds = set(os.environ["ALLOWED_APP_BUILDS"].split(","))
        environment = os.environ.get("APP_ATTEST_ENVIRONMENT", "production")
        if environment != "production" and os.environ.get("OMR_ENV") != "staging":
            raise RuntimeError("Development attestations are allowed only on a separate staging service.")
        verifier = AppAttestVerifier(app_id, root, environment, builds)
    from models import verify
    verify()
    from patch_homr import verify as verify_exporter
    verify_exporter()
    if not development and not Path(__file__).with_name('recognizer-source.tar.gz').is_file():
        raise RuntimeError('Production requires the corresponding-source bundle')
    executable = sys.executable
    command = [executable, str(Path(__file__).with_name('recognizer.py').resolve())]
    return create_app(Runtime(Path(os.environ.get("OMR_DATA_DIR", "/data")), verifier, executable, development, command))
