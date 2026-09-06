#!/usr/bin/env python3
"""Small asynchronous HTTP adapter around the oemer command-line tool.

The service intentionally exposes a narrow, engine-neutral contract. StringMap's
iOS client only knows that it submits a printed score image and receives
MusicXML; guitar optimization and playback stay inside the app.

This development server binds to loopback by default and has no authentication.
Do not expose it to the public internet without TLS, authentication, rate
limiting, and an explicit image-retention policy.
"""

from __future__ import annotations

import argparse
import base64
import json
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Protocol
from urllib.parse import urlparse


MAX_IMAGE_BYTES = 20 * 1024 * 1024
JOB_RETENTION_SECONDS = 60 * 60
ALLOWED_IMAGE_TYPES = {"image/jpeg": ".jpg", "image/png": ".png"}


class RecognitionRunner(Protocol):
    def recognize(self, image: bytes, suffix: str, job_id: str) -> bytes: ...


class OemerRunner:
    """Runs the MIT-licensed oemer package without copying its implementation."""

    def __init__(self, executable: str = "oemer", timeout_seconds: int = 10 * 60):
        self.executable = str(Path(executable).expanduser().resolve()) if "/" in executable else executable
        self.timeout_seconds = timeout_seconds

    @property
    def is_ready(self) -> bool:
        return shutil.which(self.executable) is not None

    def recognize(self, image: bytes, suffix: str, job_id: str) -> bytes:
        if not self.is_ready:
            raise RuntimeError(
                "oemer is not installed. Run ./services/omr/bootstrap.sh, then restart this service."
            )
        with tempfile.TemporaryDirectory(prefix=f"stringmap-omr-{job_id}-") as directory:
            work = Path(directory)
            input_path = work / f"score{suffix}"
            output_path = work / "recognized.musicxml"
            input_path.write_bytes(image)
            completed = self._run(input_path, output_path, work)
            if completed.returncode != 0:
                # oemer documents --without-deskew as the first recovery step.
                # A straight scan can fail its dewarping heuristics even when the
                # staff itself is readable, so retry once without that transform.
                completed = self._run(input_path, output_path, work, without_deskew=True)
            if completed.returncode != 0:
                detail = (completed.stderr or completed.stdout).strip()[-2_000:]
                raise RuntimeError(f"oemer failed ({completed.returncode}): {detail}")
            if not output_path.exists():
                raise RuntimeError("oemer completed without producing MusicXML.")
            result = output_path.read_bytes()
            if not result:
                raise RuntimeError("oemer produced an empty MusicXML file.")
            return result

    def _run(
        self,
        input_path: Path,
        output_path: Path,
        work: Path,
        without_deskew: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        command = [self.executable, str(input_path), "--output-path", str(output_path)]
        if without_deskew:
            command.append("--without-deskew")
        return subprocess.run(
            command,
            cwd=work,
            capture_output=True,
            text=True,
            timeout=self.timeout_seconds,
            check=False,
        )


@dataclass
class RecognitionJob:
    id: str
    source_name: str
    status: str = "queued"
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    music_xml: bytes | None = None
    error: str | None = None

    def response(self) -> dict[str, object]:
        payload: dict[str, object] = {
            "id": self.id,
            "status": self.status,
            "sourceName": self.source_name,
        }
        if self.music_xml is not None:
            payload["musicXMLBase64"] = base64.b64encode(self.music_xml).decode("ascii")
        if self.error:
            payload["error"] = self.error
        return payload


class RecognitionService:
    def __init__(self, runner: RecognitionRunner, workers: int = 1):
        self.runner = runner
        self.jobs: dict[str, RecognitionJob] = {}
        self.lock = threading.Lock()
        self.executor = ThreadPoolExecutor(max_workers=workers, thread_name_prefix="stringmap-omr")

    def create(self, image: bytes, suffix: str, source_name: str) -> RecognitionJob:
        job = RecognitionJob(id=str(uuid.uuid4()), source_name=source_name)
        with self.lock:
            self._purge_locked()
            self.jobs[job.id] = job
        self.executor.submit(self._run, job.id, image, suffix)
        return job

    def get(self, job_id: str) -> RecognitionJob | None:
        with self.lock:
            self._purge_locked()
            return self.jobs.get(job_id)

    def delete(self, job_id: str) -> bool:
        with self.lock:
            return self.jobs.pop(job_id, None) is not None

    def _run(self, job_id: str, image: bytes, suffix: str) -> None:
        with self.lock:
            job = self.jobs[job_id]
            job.status = "processing"
            job.updated_at = time.time()
        try:
            music_xml = self.runner.recognize(image, suffix, job_id)
            with self.lock:
                job = self.jobs.get(job_id)
                if job is not None:
                    job.music_xml = music_xml
                    job.status = "completed"
                    job.updated_at = time.time()
        except Exception as error:  # The job boundary must report model/process failures.
            with self.lock:
                job = self.jobs.get(job_id)
                if job is not None:
                    job.error = str(error)
                    job.status = "failed"
                    job.updated_at = time.time()

    def _purge_locked(self) -> None:
        cutoff = time.time() - JOB_RETENTION_SECONDS
        expired = [job_id for job_id, job in self.jobs.items() if job.updated_at < cutoff]
        for job_id in expired:
            self.jobs.pop(job_id, None)


def make_handler(service: RecognitionService, runner: OemerRunner | RecognitionRunner):
    class Handler(BaseHTTPRequestHandler):
        server_version = "StringMapOMR/1"

        def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            path = urlparse(self.path).path
            if path == "/health":
                ready = getattr(runner, "is_ready", True)
                self._json(HTTPStatus.OK, {"status": "ok", "engine": "oemer", "engineReady": ready})
                return
            job_id = self._job_id(path)
            if job_id is None:
                self._json(HTTPStatus.NOT_FOUND, {"error": "Not found."})
                return
            job = service.get(job_id)
            if job is None:
                self._json(HTTPStatus.NOT_FOUND, {"error": "Recognition job not found."})
                return
            self._json(HTTPStatus.OK, job.response())

        def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            if urlparse(self.path).path != "/v1/recognitions":
                self._json(HTTPStatus.NOT_FOUND, {"error": "Not found."})
                return
            content_type = self.headers.get("Content-Type", "").split(";", 1)[0].lower()
            suffix = ALLOWED_IMAGE_TYPES.get(content_type)
            if suffix is None:
                self._json(HTTPStatus.UNSUPPORTED_MEDIA_TYPE, {"error": "Send a JPEG or PNG image."})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = 0
            if length <= 0 or length > MAX_IMAGE_BYTES:
                self._json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "Image must be between 1 byte and 20 MB."})
                return
            image = self.rfile.read(length)
            if len(image) != length:
                self._json(HTTPStatus.BAD_REQUEST, {"error": "Incomplete image upload."})
                return
            source_name = self.headers.get("X-StringMap-Source-Name", "Scanned sheet music")[:200]
            job = service.create(image, suffix, source_name)
            self._json(HTTPStatus.ACCEPTED, job.response())

        def do_DELETE(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            job_id = self._job_id(urlparse(self.path).path)
            if job_id is None or not service.delete(job_id):
                self._json(HTTPStatus.NOT_FOUND, {"error": "Recognition job not found."})
                return
            self.send_response(HTTPStatus.NO_CONTENT)
            self.end_headers()

        def log_message(self, format: str, *args: object) -> None:
            print(f"[{self.log_date_time_string()}] {format % args}")

        @staticmethod
        def _job_id(path: str) -> str | None:
            prefix = "/v1/recognitions/"
            value = path[len(prefix):] if path.startswith(prefix) else ""
            return value if value and "/" not in value else None

        def _json(self, status: HTTPStatus, payload: dict[str, object]) -> None:
            data = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

    return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description="StringMap development OMR service")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8765, type=int)
    parser.add_argument("--oemer", default="oemer", help="Path to the oemer executable")
    args = parser.parse_args()

    runner = OemerRunner(executable=args.oemer)
    service = RecognitionService(runner)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(service, runner))
    print(f"StringMap OMR listening at http://{args.host}:{server.server_port}")
    print(f"oemer ready: {runner.is_ready}")
    server.serve_forever()


if __name__ == "__main__":
    main()
