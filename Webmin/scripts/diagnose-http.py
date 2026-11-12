#!/usr/bin/env python3
"""Observe loopback HTTP and Webmin's cgroup without changing the service."""
import argparse
import http.client
import json
from pathlib import Path
import socket
import subprocess
import threading
import time


def read_small(path, limit=8192):
    try:
        with path.open() as stream:
            value = stream.read(limit + 1)
        return value if len(value) <= limit else "unavailable:oversize"
    except OSError:
        return "unavailable"


def verify_profile(config, policy):
    expected = json.loads(policy.read_text())
    found = {}
    for line in read_small(config, 262144).splitlines():
        key, separator, value = line.partition("=")
        if separator and key in expected:
            if key in found:
                raise ValueError("duplicate managed setting")
            found[key] = value
    if found != expected:
        raise ValueError("managed Webmin settings differ")
    return {"managed_profile_matches": True}


def probe(host, port, path, timeout):
    if host not in ("127.0.0.1", "::1") or path not in ("/", "/session_login.cgi"):
        raise ValueError("loopback diagnostic endpoints required")
    result = {"host": host, "path": path, "timeout_seconds": timeout}
    started = time.monotonic()
    connection = http.client.HTTPConnection(host, port, timeout=timeout)
    try:
        connection.request("GET", path, headers={"User-Agent": "ansible-httpget",
                                                "Connection": "close"})
        response = connection.getresponse()
        # Never read bodies, cookies or arbitrary response headers.
        result["status"] = response.status
    except (OSError, http.client.HTTPException) as error:
        result["error_type"] = type(error).__name__
    finally:
        connection.close()
    result["elapsed_seconds"] = round(time.monotonic() - started, 3)
    return result


def sample(cgroup, started):
    result = {"elapsed_seconds": round(time.monotonic() - started, 3)}
    for name in ("memory.current", "memory.peak", "memory.events", "memory.events.local",
                 "memory.pressure", "cpu.stat", "cpu.pressure", "io.pressure", "pids.current"):
        result[name] = read_small(cgroup / name, 2048).strip()
    processes = []
    for pid in read_small(cgroup / "cgroup.procs").split()[:16]:
        if not pid.isdecimal():
            continue
        fields = {"pid": int(pid)}
        for line in read_small(Path("/proc") / pid / "status").splitlines():
            key, _, value = line.partition(":")
            if key in ("Name", "State", "VmRSS", "Threads"):
                fields[key] = value.strip()[:64]
        fields["wchan"] = read_small(Path("/proc") / pid / "wchan", 128).strip()
        processes.append(fields)
    result["processes"] = processes
    return result


def observe(port, request_timeout, duration):
    properties = subprocess.run(
        ["systemctl", "show", "webmin.service",
         "--property=ControlGroup,MainPID,ActiveState,ActiveEnterTimestampMonotonic"],
        capture_output=True, text=True, check=True, timeout=5)
    unit = dict(line.split("=", 1) for line in properties.stdout.splitlines() if "=" in line)
    if unit.get("ControlGroup") != "/system.slice/webmin.service" or unit.get("ActiveState") != "active":
        raise ValueError("active Webmin cgroup required")
    cgroup = Path("/sys/fs/cgroup/system.slice/webmin.service")
    started = time.monotonic()
    done = threading.Event()
    result = {"format": "webmin-http-diagnostic-v1", "unit": unit, "requests": [], "samples": []}

    def requests():
        try:
            while time.monotonic() - started < 15:
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=1):
                        break
                except OSError:
                    time.sleep(1)
            result["tcp_readiness_elapsed_seconds"] = round(time.monotonic() - started, 3)
            for host, path, timeout in (("127.0.0.1", "/", 5),
                                        ("127.0.0.1", "/session_login.cgi", request_timeout),
                                        ("::1", "/session_login.cgi", request_timeout)):
                result["requests"].append(probe(host, port, path, timeout))
        finally:
            done.set()

    threading.Thread(target=requests, daemon=True).start()
    stored_bytes = 0
    result["samples_omitted"] = 0
    while True:
        current = sample(cgroup, started)
        size = len(json.dumps(current).encode())
        if stored_bytes + size <= 360000:
            result["samples"].append(current)
            stored_bytes += size
        else:
            result["samples_omitted"] += 1
        if done.is_set() or time.monotonic() - started >= duration:
            break
        done.wait(1)
    result["completed"] = done.is_set() and len(result["requests"]) == 3
    result["last_sample"] = current
    result["elapsed_seconds"] = round(time.monotonic() - started, 3)
    encoded = json.dumps(result, separators=(",", ":"))
    if len(encoded.encode()) > 524288:
        raise ValueError("diagnostic output exceeds 512 KiB")
    print(encoded, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-profile", type=Path)
    parser.add_argument("--policy", type=Path)
    parser.add_argument("--port", type=int, default=10000)
    parser.add_argument("--request-timeout", type=int, default=75)
    parser.add_argument("--duration", type=int, default=180)
    args = parser.parse_args()
    if args.verify_profile:
        if not args.policy:
            parser.error("profile verification needs its policy")
        print(json.dumps(verify_profile(args.verify_profile, args.policy)))
    else:
        if not (1 <= args.port <= 65535 and 1 <= args.request_timeout <= 75
                and 1 <= args.duration <= 180):
            parser.error("diagnostic bounds exceeded")
        observe(args.port, args.request_timeout, args.duration)
