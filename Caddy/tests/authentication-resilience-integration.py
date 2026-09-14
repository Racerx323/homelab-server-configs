#!/usr/bin/env python3
"""Real Caddy integration with a causal local HTTP backend, never production."""
import concurrent.futures
import http.client
import http.server
import json
import importlib.util
import os
from pathlib import Path
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]


class Backend(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    unavailable = False
    dropped = 0
    gets = 0
    ports = []

    def log_message(self, *_args):
        pass

    def respond(self, status, body=b"", headers=None):
        self.send_response(status)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        type(self).gets += 1
        if self.unavailable:
            self.respond(503)
        elif self.path == "/admin/":
            self.respond(302, headers={"Location": "/admin/login.php"})
        elif self.path == "/admin/login.php":
            self.respond(200, b'<form id="loginform">Login</form>')
        elif self.path == "/admin/index.php":
            if self.headers.get("Cookie") == "session=fixture":
                self.respond(200, b'Authenticated <a href="logout.php">Logout</a>')
            else:
                self.respond(302, headers={"Location": "/admin/login.php"})
        elif self.path == "/admin/logout.php":
            self.respond(302, headers={"Location": "/admin/login.php", "Set-Cookie": "session=; Max-Age=0"})
        else:
            self.respond(404)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        type(self).ports.append(self.client_address[1])
        if self.path == "/admin/connection-fault":
            type(self).dropped += 1
            self.connection.shutdown(socket.SHUT_RDWR)
            self.connection.close()
            self.close_connection = True
        elif body in (b"password=fixture-correct", b"pw=fixture-correct"):
            self.respond(302, headers={"Location": "/admin/index.php", "Set-Cookie": "session=fixture"})
        else:
            self.respond(200, b'<form id="loginform">Wrong password!</form>')


def run(*args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def main():
    assert run("caddy", "version").stdout.startswith(b"v2.11.4 ")
    with tempfile.TemporaryDirectory(prefix="caddy-auth-integration.") as tmp:
        work = Path(tmp)
        tls = work / "tls"
        tls.mkdir()
        run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,DNS:pihole0.local.theama.co,DNS:pihole00.local.theama.co,DNS:pihole-admin.local.theama.co",
            "-keyout", str(tls / "privkey.pem"), "-out", str(tls / "fullchain.pem"))
        prepared = work / "release"
        prepared.mkdir(mode=0o700)
        run("/bin/bash", str(ROOT / "scripts/prepare-pihole-auth-release.sh"), str(prepared), str(tls))
        print("full_candidate_adapt_validate=both-nodes", flush=True)
        # The runtime projection changes only listeners/TLS for isolated testing.
        # The exact candidate snippet and backend address remain unchanged.
        candidate = (prepared / "conf.d/10-pihole-admin.caddy").read_text().split("\npihole-admin.local.theama.co {")[0]
        baseline = (ROOT / "configs/caddy/conf.d/10-pihole-admin.caddy").read_text().split("\npihole-admin.local.theama.co {")[0]
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 8080), Backend)
        server.daemon_threads = True
        threading.Thread(target=server.serve_forever, daemon=True).start()
        context = ssl.create_default_context(cafile=str(tls / "fullchain.pem"))

        def request(family, method="GET", path="/admin/login.php", body=None, cookie=None):
            # Keep certificate verification and localhost SNI with either family.
            conn = http.client.HTTPSConnection("localhost", 14443, context=context, timeout=4)
            address = "127.0.0.1" if family == 4 else "::1"
            conn._create_connection = lambda _addr, timeout, source_address=None: socket.create_connection((address, 14443), timeout)
            headers = {"Content-Type": "application/x-www-form-urlencoded"}
            if cookie:
                headers["Cookie"] = cookie
            start = time.monotonic()
            try:
                conn.request(method, path, body=body, headers=headers)
                response = conn.getresponse()
                result = response.status, response.read(), dict(response.getheaders())
                print(json.dumps({"family": family, "method": method, "path": path,
                                  "status": result[0], "elapsed": round(time.monotonic() - start, 4)}), flush=True)
                return result
            finally:
                conn.close()

        def wait_status(expected, timeout=36):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                try:
                    if request(4)[0] == expected:
                        return
                except (OSError, http.client.HTTPException):
                    pass
                time.sleep(0.5)
            raise AssertionError(f"status {expected} not observed")

        try:
            for name, snippet in (("baseline", baseline), ("candidate", candidate)):
                config = work / "Caddyfile"
                config.write_text("{\n admin off\n auto_https disable_redirects\n skip_install_trust\n}\n"
                                  + f"(local_tls) {{\n tls {tls}/fullchain.pem {tls}/privkey.pem\n}}\n"
                                  + snippet + "\nhttps://localhost:14443 {\n bind 127.0.0.1 ::1\n import pihole_ui\n}\n")
                with (work / "caddy.log").open("w") as log:
                    proc = subprocess.Popen(["caddy", "run", "--config", str(config), "--adapter", "caddyfile"], stdout=log, stderr=log)
                    try:
                        wait_status(200, 8)
                        before = Backend.dropped
                        assert request(4, "POST", "/admin/connection-fault", b"fault=1")[0] == 502
                        assert Backend.dropped == before + 1, "POST was replayed"
                        expected = 503 if name == "baseline" else 200
                        assert request(4)[0] == expected
                        assert request(6)[0] == expected
                        print(f"{name}_transport_failure_next_request={expected}", flush=True)
                        if name == "baseline":
                            continue
                        for idle in (0, 5):
                            for family in (4, 6):
                                time.sleep(idle)
                                before_ports = len(Backend.ports)
                                bad = request(family, "POST", body=b"password=fixture-wrong")
                                assert bad[:2] == (200, b'<form id="loginform">Wrong password!</form>')
                                with concurrent.futures.ThreadPoolExecutor() as pool:
                                    other = pool.submit(request, 6 if family == 4 else 4)
                                    good = request(family, "POST", body=b"password=fixture-correct")
                                    assert other.result()[0] == 200
                                assert good[0] == 302 and good[2]["Location"] == "/admin/index.php"
                                assert request(family, path="/admin/index.php", cookie="session=fixture")[:2] == (200, b'Authenticated <a href="logout.php">Logout</a>')
                                assert request(family, path="/admin/logout.php")[0] == 302
                                assert request(family, path="/admin/index.php")[0] == 302
                                assert len(set(Backend.ports[before_ports:])) == 2, "backend connection reused"
                        spec = importlib.util.spec_from_file_location("pihole_acceptance", ROOT / "scripts/validate-pihole-authentication.py")
                        acceptance = importlib.util.module_from_spec(spec)
                        spec.loader.exec_module(acceptance)
                        acceptance.validate(("localhost", "127.0.0.1", "::1"), "fixture-correct", context,
                                            port=14443, idle_seconds=0, observation_seconds=0)
                        try:
                            acceptance.validate(("localhost", "127.0.0.1", "::1"), "fixture-invalid", context,
                                                port=14443, idle_seconds=0, observation_seconds=0)
                        except acceptance.AcceptanceFailure as error:
                            assert str(error) == "successful-login-redirect-missing"
                        else:
                            raise AssertionError("invalid valid-password input accepted")
                        Backend.unavailable = True
                        wait_status(503)
                        # Prove exclusion from observed backend traffic, not a log phrase.
                        deadline = time.monotonic() + 36
                        while True:
                            before_gets = Backend.gets
                            status = request(4)[0]
                            if status == 503 and Backend.gets == before_gets:
                                break
                            assert time.monotonic() < deadline, "active health did not exclude backend"
                            time.sleep(0.5)
                        Backend.unavailable = False
                        wait_status(200)
                        assert request(6)[0] == 200
                        print("candidate_active_health_failure_and_recovery=true", flush=True)
                    finally:
                        proc.terminate()
                        try:
                            proc.wait(timeout=8)
                        except subprocess.TimeoutExpired:
                            proc.kill()
                            proc.wait()
        finally:
            server.shutdown()
            server.server_close()
    print("authentication_resilience_integration_complete=true", flush=True)


if __name__ == "__main__":
    main()
