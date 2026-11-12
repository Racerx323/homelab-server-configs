"""Neutral tests use real local HTTP; they do not stand in for Pi acceptance."""
import http.server
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest

spec = importlib.util.spec_from_file_location(
    "diagnostic", Path(__file__).parents[1] / "scripts/diagnose-http.py")
diagnostic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostic)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Set-Cookie", "sid=private-test-value")
        self.end_headers()
        try:
            self.wfile.write(b"private response body")
        except BrokenPipeError:
            pass

    def log_message(self, *_args):
        pass


class SlowHandler(Handler):
    def do_GET(self):
        time.sleep(0.3)
        super().do_GET()


class DiagnosticTests(unittest.TestCase):
    def request(self, handler, timeout=2):
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            return diagnostic.probe("127.0.0.1", server.server_port, "/session_login.cgi", timeout)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_actual_http_retains_status_without_private_response(self):
        result = self.request(Handler)
        self.assertEqual(result["status"], 200)
        self.assertNotIn("private", json.dumps(result))
        self.assertEqual(set(result), {"host", "path", "timeout_seconds", "status", "elapsed_seconds"})

    def test_slow_headers_are_bounded_and_recorded(self):
        result = self.request(SlowHandler, 0.05)
        self.assertEqual(result["error_type"], "TimeoutError")
        self.assertLess(result["elapsed_seconds"], 1)

    def test_remote_or_unreviewed_endpoints_are_rejected(self):
        for host, path in [("192.0.2.1", "/"), ("127.0.0.1", "/useradmin/")]:
            with self.assertRaises(ValueError):
                diagnostic.probe(host, 10000, path, 1)

    def test_profile_verification_rejects_duplicate_or_changed_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            config, policy = Path(directory) / "config", Path(directory) / "policy"
            policy.write_text('{"ssl":"0"}')
            config.write_text("unmanaged_secret=private\nssl=0\n")
            self.assertEqual(diagnostic.verify_profile(config, policy), {"managed_profile_matches": True})
            self.assertIn("private", config.read_text())
            for content in ["ssl=1\n", "ssl=0\nssl=0\n"]:
                config.write_text(content)
                with self.assertRaises(ValueError):
                    diagnostic.verify_profile(config, policy)


if __name__ == "__main__":
    unittest.main()
