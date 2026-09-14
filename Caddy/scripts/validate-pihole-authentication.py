#!/usr/bin/env python3
"""Pi-hole Web v5.21 login acceptance. Credentials and sessions stay in memory."""
import argparse
import concurrent.futures
import http.client
from http.cookies import SimpleCookie
import json
import os
import secrets
import selectors
import signal
import socket
import ssl
import subprocess
import sys
import time
from urllib.parse import urlencode, urljoin, urlsplit

TARGETS = {
    "node-a": ("pihole0.local.theama.co", "10.1.0.53", "fd36:5aa8:6971:1::53"),
    "node-b": ("pihole00.local.theama.co", "10.1.0.54", "fd36:5aa8:6971:1::54"),
    "shared": ("pihole-admin.local.theama.co", "10.1.0.56", "fd36:5aa8:6971:1::56"),
}

DOPPLER_COMMAND = (
    "/usr/bin/doppler", "secrets", "get", "PIHOLE_NODE_B_WEB_PASSWORD",
    "--plain", "--raw", "--project", "homelab-dev", "--config", "prd_caddy",
    "--no-check-version", "--attempts", "1", "--timeout", "10s",
    "--no-read-env", "--api-host", "https://api.doppler.com",
)
SECRET_TIMEOUT = 15
MAX_PASSWORD_BYTES = 4096


class AcceptanceFailure(Exception):
    """Only fixed non-secret decision labels may be supplied."""


def require(condition, label):
    if not condition:
        raise AcceptanceFailure(label)


def read_password(stream, timeout=None):
    """Bound pipe reads as well as regular files; never retain provider output."""
    if timeout is None:
        timeout = SECRET_TIMEOUT
    deadline = time.monotonic() + timeout
    raw = bytearray()
    # PollSelector also supports regular files on Linux (epoll does not).
    with selectors.PollSelector() as selector:
        selector.register(stream, selectors.EVENT_READ)
        while True:
            remaining = deadline - time.monotonic()
            require(remaining > 0 and selector.select(remaining), "password-input-timeout")
            chunk = os.read(stream.fileno(), MAX_PASSWORD_BYTES + 1 - len(raw))
            if not chunk:
                break
            raw.extend(chunk)
            require(len(raw) <= MAX_PASSWORD_BYTES, "invalid-password-length")
    require(bool(raw), "invalid-password-length")
    try:
        password = raw.decode("utf-8")
    except UnicodeError:
        raise AcceptanceFailure("invalid-password-input") from None
    # Accept one CLI/file line terminator without stripping password whitespace.
    if password.endswith("\r\n"):
        password = password[:-2]
    elif password.endswith("\n"):
        password = password[:-1]
    require(bool(password) and not any(char in password for char in "\r\n\x00"),
            "invalid-password-input")
    return password


def doppler_password():
    """Require successful retrieval before any HTTP; suppress raw diagnostics."""
    started = time.monotonic()
    with subprocess.Popen(DOPPLER_COMMAND, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          close_fds=True, start_new_session=True) as process:
        try:
            password = read_password(process.stdout)
            remaining = SECRET_TIMEOUT - (time.monotonic() - started)
            require(remaining > 0, "password-input-timeout")
            try:
                status = process.wait(timeout=remaining)
            except subprocess.TimeoutExpired:
                raise AcceptanceFailure("password-input-timeout") from None
            require(status == 0, "secret-provider-failed")
            return password
        finally:
            # Also reap children that retain stdout after the provider exits.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()


class Client:
    def __init__(self, host, address, family, context, port=443):
        self.host, self.address, self.family = host, address, family
        self.context, self.port = context, port
        self.cookies = SimpleCookie()

    def request(self, method, path, password=None):
        conn = http.client.HTTPSConnection(self.host, self.port, context=self.context, timeout=4)
        conn._create_connection = lambda _addr, timeout, source_address=None: socket.create_connection((self.address, self.port), timeout)
        headers = {}
        if self.cookies:
            headers["Cookie"] = "; ".join(f"{key}={value.value}" for key, value in self.cookies.items())
        body = None
        if password is not None:
            body = urlencode({"pw": password}).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        started = time.monotonic()
        status = 0
        try:
            # Exactly one POST attempt; no redirect following or transport retry.
            conn.request(method, path, body=body, headers=headers)
            response = conn.getresponse()
            status = response.status
            content = response.read(2 * 1024 * 1024 + 1)
            require(len(content) <= 2 * 1024 * 1024, "response-too-large")
            for key, value in response.getheaders():
                if key.lower() == "set-cookie":
                    require(len(value) <= 8192, "cookie-too-large")
                    self.cookies.load(value)
            return status, content, response.getheader("Location", "")
        finally:
            conn.close()
            print(json.dumps({"family": self.family, "method": method, "path": path,
                              "status": status, "elapsed": round(time.monotonic() - started, 4)}), flush=True)

    def redirect_is(self, location, path):
        base = f"https://{self.host}:{self.port}/admin/login.php"
        resolved = urlsplit(urljoin(base, location))
        return (resolved.scheme == "https" and resolved.hostname == self.host
                and (resolved.port or 443) == self.port and resolved.path == path
                and not resolved.query and not resolved.fragment and not resolved.username)


def validate(target, password, context, port=443, idle_seconds=5, observation_seconds=64):
    host, ipv4, ipv6 = target
    for family, address, other_address in ((4, ipv4, ipv6), (6, ipv6, ipv4)):
        for idle in (0, idle_seconds):
            client = Client(host, address, family, context, port)
            other = Client(host, other_address, 6 if family == 4 else 4, context, port)
            try:
                initial = client.request("GET", "/admin/login.php")
                require(initial[0] == 200 and b'id="loginform"' in initial[1], "login-form-missing")
                time.sleep(idle)
                wrong = secrets.token_urlsafe(32)
                while wrong == password:
                    wrong = secrets.token_urlsafe(32)
                rejected = client.request("POST", "/admin/login.php", wrong)
                require(rejected[0] == 200 and b"Wrong password!" in rejected[1]
                        and b'id="loginform"' in rejected[1], "incorrect-password-not-rejected-normally")
                with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                    independent = pool.submit(other.request, "GET", "/admin/login.php")
                    accepted = client.request("POST", "/admin/login.php", password)
                    require(independent.result()[0] == 200, "other-client-unavailable")
                require(accepted[0] == 302 and client.redirect_is(accepted[2], "/admin/index.php"), "successful-login-redirect-missing")
                dashboard = client.request("GET", "/admin/index.php")
                require(dashboard[0] == 200 and b'href="logout.php"' in dashboard[1]
                        and b'id="loginform"' not in dashboard[1], "authenticated-dashboard-missing")
                logged_out = client.request("GET", "/admin/logout.php")
                require(logged_out[0] == 302 and client.redirect_is(logged_out[2], "/admin/login.php"), "logout-redirect-missing")
                denied = client.request("GET", "/admin/index.php")
                require(denied[0] == 302 and client.redirect_is(denied[2], "/admin/login.php"), "session-survived-logout")
            finally:
                # End any session created before a failed assertion; no cookie file.
                try:
                    client.request("GET", "/admin/logout.php")
                finally:
                    client.cookies.clear()
                    other.cookies.clear()
    deadline = time.monotonic() + observation_seconds
    while time.monotonic() < deadline:
        for family, address in ((4, ipv4), (6, ipv6)):
            require(Client(host, address, family, context, port).request("GET", "/admin/login.php")[0] == 200,
                    "post-login-observation-failed")
        time.sleep(min(2, max(0, deadline - time.monotonic())))
    print("pihole_authentication_http_acceptance=true", flush=True)


def connectivity_check(target, context, port=443):
    """Check both numeric-address paths with verified SNI, without credentials."""
    host, ipv4, ipv6 = target
    failures = []
    for family, address in ((4, ipv4), (6, ipv6)):
        failure = None
        try:
            status, body, _ = Client(host, address, family, context, port).request("GET", "/admin/login.php")
            if status != 200:
                failure = "http-status"
            elif b'id="loginform"' not in body:
                failure = "login-form-missing"
        except ssl.SSLError:
            failure = "tls"
        except OSError:
            failure = "connection"
        except (http.client.HTTPException, AcceptanceFailure):
            failure = "http-response"
        print(json.dumps({"check": "workstation-connectivity", "family": family,
                          "result": failure or "healthy"}), flush=True)
        if failure:
            failures.append(family)
    require(not failures, "workstation-connectivity-failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True, choices=TARGETS)
    password_source = parser.add_mutually_exclusive_group()
    password_source.add_argument("--password-fd", type=int, help="inherited descriptor >=3; never put the password in argv")
    password_source.add_argument("--password-doppler", action="store_true",
                                 help="retrieve the fixed Node B Doppler reference using local CLI authentication")
    parser.add_argument("--connectivity-only", action="store_true", help="verified IPv4/IPv6 login-page GETs; no credentials or POSTs")
    parser.add_argument("--idle-seconds", type=float, default=5)
    parser.add_argument("--observation-seconds", type=float, default=64)
    args = parser.parse_args()
    if args.connectivity_only:
        require(args.password_fd is None and not args.password_doppler, "connectivity-check-takes-no-secret")
        connectivity_check(TARGETS[args.target], ssl.create_default_context())
        return
    require(args.password_fd is not None or args.password_doppler, "password-source-required")
    require(0 <= args.idle_seconds <= 60 and 64 <= args.observation_seconds <= 600, "invalid-observation-bound")
    if args.password_doppler:
        require(args.target == "node-b", "doppler-reference-is-node-b-only")
        password = doppler_password()
    else:
        require(args.password_fd >= 3, "invalid-password-descriptor")
        # Consume the inherited descriptor; it must not leak into later children.
        with os.fdopen(args.password_fd, "rb") as stream:
            password = read_password(stream)
    validate(TARGETS[args.target], password, ssl.create_default_context(), idle_seconds=args.idle_seconds,
             observation_seconds=args.observation_seconds)


if __name__ == "__main__":
    try:
        main()
    except AcceptanceFailure as error:
        print(f"pihole_authentication_failure={error}", file=sys.stderr)
        sys.exit(1)
    except Exception:
        # Exception text may contain headers, URLs, session data, or credentials.
        print("pihole_authentication_failure=transport-or-runtime-error", file=sys.stderr)
        sys.exit(1)
