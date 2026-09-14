#!/usr/bin/env python3
"""Exercise the real secret reader with isolated producers; never call Doppler."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/validate-pihole-authentication.py"
SPEC = importlib.util.spec_from_file_location("authentication", SCRIPT)
AUTH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUTH)
CANARY = "fixture-only secret &%=+"


class SecretBoundary(unittest.TestCase):
    def invoke(self, producer, target="node-b"):
        command = (sys.executable, "-c", producer)
        argv = [str(SCRIPT), "--target", target, "--password-doppler"]
        with patch.object(AUTH, "DOPPLER_COMMAND", command), \
                patch.object(sys, "argv", argv), \
                patch.object(AUTH, "validate") as validate:
            try:
                AUTH.main()
            except AUTH.AcceptanceFailure:
                validate.assert_not_called()
                raise
            return validate.call_args

    def test_success_preserves_whitespace_and_only_then_validates(self):
        secret = "  " + CANARY + "  "
        result = self.invoke(f"print({secret!r})")
        self.assertEqual(result.args[:2], (AUTH.TARGETS["node-b"], secret))

    def test_nonzero_provider_with_valid_output_never_logs_in(self):
        with self.assertRaisesRegex(AUTH.AcceptanceFailure, "secret-provider-failed"):
            self.invoke(f"import sys; print({CANARY!r}); sys.exit(9)")

    def test_malformed_provider_never_logs_in(self):
        for value in (b"", b"\n", b"\xff", b"a\x00b", b"a\nb", b"a\n\n", b"a" * 4097):
            with self.subTest(size=len(value)), self.assertRaises(AUTH.AcceptanceFailure):
                self.invoke(f"import sys; sys.stdout.buffer.write({value!r})")

    def test_raw_provider_errors_are_discarded(self):
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            with self.assertRaises(AUTH.AcceptanceFailure):
                self.invoke(f"import sys; print({CANARY!r}, file=sys.stderr); sys.exit(9)")
        self.assertEqual(output.getvalue() + errors.getvalue(), "")

    def test_provider_exit_is_bounded_after_closing_stdout(self):
        with patch.object(AUTH, "SECRET_TIMEOUT", 0.3):
            with self.assertRaisesRegex(AUTH.AcceptanceFailure, "password-input-timeout"):
                self.invoke(f"import os,time; os.write(1,{CANARY.encode()!r}); os.close(1); time.sleep(30)")

    def test_reader_rejects_a_stalled_pipe(self):
        read_fd, write_fd = os.pipe()
        try:
            with os.fdopen(read_fd, "rb") as stream:
                with self.assertRaisesRegex(AUTH.AcceptanceFailure, "password-input-timeout"):
                    AUTH.read_password(stream, timeout=0.05)
        finally:
            os.close(write_fd)

    def test_provider_descendant_cannot_hold_the_pipe_open(self):
        with tempfile.TemporaryDirectory(prefix="caddy-auth-secret-test.") as directory:
            pid_file = Path(directory) / "child.pid"
            producer = ("import subprocess,sys,pathlib; "
                        "p=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); "
                        f"pathlib.Path({str(pid_file)!r}).write_text(str(p.pid)); "
                        f"print({CANARY!r})")
            try:
                with patch.object(AUTH, "SECRET_TIMEOUT", 0.3):
                    with self.assertRaisesRegex(AUTH.AcceptanceFailure, "password-input-timeout"):
                        self.invoke(producer)
                child = int(pid_file.read_text())
                deadline = time.monotonic() + 2
                while Path(f"/proc/{child}/stat").exists():
                    if Path(f"/proc/{child}/stat").read_text().split()[2] == "Z":
                        break
                    self.assertLess(time.monotonic(), deadline, "provider child survived cleanup")
                    time.sleep(0.01)
            finally:
                if pid_file.exists():
                    try:
                        os.kill(int(pid_file.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_doppler_reference_cannot_be_used_for_other_routes(self):
        for target in ("node-a", "shared"):
            with self.subTest(target=target), patch.object(AUTH.subprocess, "Popen") as producer:
                with self.assertRaisesRegex(AUTH.AcceptanceFailure, "doppler-reference-is-node-b-only"):
                    self.invoke("raise SystemExit('must not execute')", target)
                producer.assert_not_called()

    def test_regular_file_input_is_consumed_and_closed(self):
        with tempfile.TemporaryFile() as source:
            source.write(CANARY.encode())
            source.seek(0)
            descriptor = os.dup(source.fileno())
            with patch.object(sys, "argv", [str(SCRIPT), "--target", "node-b", "--password-fd", str(descriptor)]), \
                    patch.object(AUTH, "validate") as validate:
                AUTH.main()
                self.assertEqual(validate.call_args.args[1], CANARY)
            with self.assertRaises(OSError):
                os.fstat(descriptor)

    def test_cli_sanitizes_invalid_input(self):
        with tempfile.TemporaryFile() as source:
            source.write((CANARY + "\ninvalid\n").encode())
            source.seek(0)
            result = subprocess.run([sys.executable, str(SCRIPT), "--target", "node-b",
                                     "--password-fd", str(source.fileno())],
                                    pass_fds=(source.fileno(),), capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b"pihole_authentication_failure=invalid-password-input\n")


if __name__ == "__main__":
    unittest.main()
