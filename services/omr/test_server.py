import base64
import http.client
import json
import threading
import time
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch

from server import OemerRunner, RecognitionJob, RecognitionService, make_handler


MUSIC_XML = b'<score-partwise version="4.0"></score-partwise>'


class FakeRunner:
    is_ready = True

    def recognize(self, image: bytes, suffix: str, job_id: str) -> bytes:
        if image == b"fail":
            raise RuntimeError("recognition failed")
        self.received = (image, suffix, job_id)
        return MUSIC_XML


class OMRServerTests(unittest.TestCase):
    def setUp(self):
        self.runner = FakeRunner()
        self.service = RecognitionService(self.runner)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.service, self.runner))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.service.executor.shutdown(wait=True)

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=2)
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        data = response.read()
        connection.close()
        return response.status, json.loads(data) if data else None

    def wait_for_job(self, job_id):
        for _ in range(100):
            status, payload = self.request("GET", f"/v1/recognitions/{job_id}")
            if payload["status"] in {"completed", "failed"}:
                return status, payload
            time.sleep(0.01)
        self.fail("job did not complete")

    def test_health_and_successful_recognition(self):
        status, health = self.request("GET", "/health")
        self.assertEqual(status, 200)
        self.assertTrue(health["engineReady"])

        status, submitted = self.request(
            "POST",
            "/v1/recognitions",
            body=b"jpeg-data",
            headers={"Content-Type": "image/jpeg", "Content-Length": "9"},
        )
        self.assertEqual(status, 202)
        status, result = self.wait_for_job(submitted["id"])
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "completed")
        self.assertEqual(base64.b64decode(result["musicXMLBase64"]), MUSIC_XML)

    def test_rejects_unsupported_upload_and_reports_runner_failure(self):
        status, payload = self.request(
            "POST", "/v1/recognitions", body=b"bad", headers={"Content-Type": "image/gif", "Content-Length": "3"}
        )
        self.assertEqual(status, 415)
        self.assertIn("JPEG or PNG", payload["error"])

        status, submitted = self.request(
            "POST", "/v1/recognitions", body=b"fail", headers={"Content-Type": "image/png", "Content-Length": "4"}
        )
        self.assertEqual(status, 202)
        _, result = self.wait_for_job(submitted["id"])
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["error"], "recognition failed")

    def test_runner_normalizes_a_relative_executable_path(self):
        runner = OemerRunner("./.venv/bin/oemer")
        self.assertTrue(runner.executable.startswith("/"))

    def test_runner_retries_without_deskew(self):
        runner = OemerRunner("/bin/echo")
        commands = []

        def run(command, **kwargs):
            commands.append(command)
            if len(commands) == 1:
                return CompletedProcess(command, 1, "", "deskew failed")
            output = Path(command[command.index("--output-path") + 1])
            output.write_bytes(MUSIC_XML)
            return CompletedProcess(command, 0, "", "")

        with patch("server.subprocess.run", side_effect=run):
            result = runner.recognize(b"image", ".jpg", "retry-job")

        self.assertEqual(result, MUSIC_XML)
        self.assertNotIn("--without-deskew", commands[0])
        self.assertIn("--without-deskew", commands[1])

    def test_expired_results_are_purged(self):
        expired = RecognitionJob(id="expired", source_name="old", updated_at=0)
        self.service.jobs[expired.id] = expired
        self.assertIsNone(self.service.get(expired.id))


if __name__ == "__main__":
    unittest.main()
