"""Neutral tests use real local HTTP; they do not stand in for Pi acceptance."""
import http.server
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch, MagicMock

spec = importlib.util.spec_from_file_location(
    "diagnostic", Path(__file__).parents[1] / "scripts/diagnose-http.py")
diagnostic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostic)


path_spec = importlib.util.spec_from_file_location(
    "path_probe", Path(__file__).parents[1] / "scripts/probe-proxy-path.py")
path_probe = importlib.util.module_from_spec(path_spec)
path_spec.loader.exec_module(path_probe)


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
    def test_backend_path_and_safe_phase_evidence(self):
        for failure in (None, TimeoutError('PRIVATE response')):
            connection = MagicMock()
            connection.sock.getsockname.return_value = ('10.1.0.53', 1234)
            connection.sock.getpeername.return_value = ('10.1.3.75', 10000)
            response = connection.getresponse.return_value
            response.status = 200
            response.read.return_value = b'<input name="pass"> PRIVATE'
            if failure: connection.getresponse.side_effect = failure
            with patch.object(path_probe.subprocess, 'run', return_value=MagicMock(stdout='[{"prefsrc":"10.1.0.53"}]')), patch.object(path_probe.http.client, 'HTTPConnection', return_value=connection):
                result = path_probe.probe('10.1.3.75', 'webmin.example', '10.1.0.53')
            self.assertEqual(connection.request.call_args.args[:2], ('GET', '/session_login.cgi'))
            self.assertEqual(result['accepted'], failure is None)
            self.assertIn('connect_seconds', result['timing'])
            self.assertNotIn('PRIVATE', json.dumps(result))
            if failure: self.assertEqual(result['phase'], 'headers')
            connection.close.assert_called_once()

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


    def test_memory_attribution_retains_numeric_rollup_not_private_process_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            group, proc = root / "group", root / "proc"
            group.mkdir()
            (proc / "42").mkdir(parents=True)
            (group / "cgroup.procs").write_text("42\n")
            (group / "memory.stat").write_text("anon 8192\nfile 4096\n")
            (group / "memory.max").write_text("201326592\n")
            (proc / "42/status").write_text("Name:\tperl\nPPid:\t1\nVmRSS:\t16 kB\nSecret: private-canary\n")
            (proc / "42/smaps_rollup").write_text(
                "0000-ffff private-canary\nPss: 12 kB\nPss_Anon: 8 kB\n"
                "Pss_File: 4 kB\nPrivate_Dirty: 8 kB\nSwap: invalid\n")
            (proc / "42/cmdline").write_text("private-canary")
            (proc / "42/environ").write_text("private-canary")
            result = diagnostic.sample(group, time.monotonic(), proc)
            process = result["processes"][0]
            self.assertEqual(process["Pss_kib"], 12)
            self.assertEqual(process["Pss_Anon_kib"], 8)
            self.assertNotIn("Swap_kib", process)
            self.assertEqual(result["memory.stat"], "anon 8192\nfile 4096")
            self.assertTrue(result["process_inventory_complete"])
            self.assertEqual(result["memory.max"], "201326592")
            self.assertNotIn("private-canary", json.dumps(result))

    def test_disappeared_process_and_truncated_inventory_are_explicit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "cgroup.procs").write_text("\n".join(str(n) for n in range(1, 19)))
            result = diagnostic.sample(root, time.monotonic(), root / "absent")
            self.assertEqual(len(result["processes"]), 16)
            self.assertEqual(result["processes_omitted"], 2)
            self.assertFalse(result["process_inventory_complete"])
            self.assertFalse(result["processes"][0]["rollup_available"])
            (root / "cgroup.procs").write_text("1" * 9000)
            result = diagnostic.sample(root, time.monotonic(), root / "absent")
            self.assertFalse(result["process_inventory_complete"])
            self.assertIsNone(result["processes_omitted"])
            self.assertEqual(result["processes"], [])


if __name__ == "__main__":
    unittest.main()
