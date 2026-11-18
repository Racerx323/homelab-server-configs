#!/usr/bin/env python3
"""Observe loopback HTTP and Webmin's cgroup without changing the service."""
import argparse
import http.client
import json
import os
from pathlib import Path
import resource
import signal
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


def sample(cgroup, started, proc_root=Path("/proc"), detailed=True):
    result = {"elapsed_seconds": round(time.monotonic() - started, 3)}
    for name in ("memory.current", "memory.peak", "memory.high", "memory.max",
                 "memory.swap.current", "memory.swap.max", "memory.events", "memory.events.local",
                 "memory.pressure", "cpu.stat", "cpu.pressure", "io.pressure", "pids.current"):
        result[name] = read_small(cgroup / name, 2048).strip()
    # Cgroup usage includes charges that per-process RSS/PSS cannot explain alone.
    if detailed:
        result["memory.stat"] = read_small(cgroup / "memory.stat", 8192).strip()
    processes = []
    inventory = read_small(cgroup / "cgroup.procs").split()
    valid_inventory = all(pid.isdecimal() for pid in inventory)
    result["process_inventory_complete"] = valid_inventory and len(inventory) <= 16
    result["processes_omitted"] = max(0, len(inventory) - 16) if valid_inventory else None
    for pid in inventory[:16]:
        if not pid.isdecimal():
            continue
        fields = {"pid": int(pid)}
        for line in read_small(proc_root / pid / "status").splitlines():
            key, _, value = line.partition(":")
            if key in ("Name", "State", "PPid", "VmRSS", "VmSwap", "Threads"):
                fields[key] = value.strip()[:64]
        fields["wchan"] = read_small(proc_root / pid / "wchan", 128).strip()
        raw_stat = read_small(proc_root / pid / "stat", 4096).rsplit(")", 1)[-1].split()
        if len(raw_stat) >= 20 and all(raw_stat[i].isdigit() for i in (11, 12, 19)):
            fields.update(cpu_ticks=int(raw_stat[11]) + int(raw_stat[12]),
                          start_ticks=int(raw_stat[19]))
        fields["vanished"] = not (proc_root / pid).exists()
        if not detailed:
            processes.append(fields)
            continue
        # Whitelist numeric aggregate memory fields; never retain maps, command
        # lines, environments, open files, page bodies or credentials.
        rollup = read_small(proc_root / pid / "smaps_rollup", 8192)
        fields["rollup_available"] = not rollup.startswith("unavailable")
        for line in rollup.splitlines():
            key, _, value = line.partition(":")
            parts = value.split()
            if (key in ("Pss", "Pss_Anon", "Pss_File", "Pss_Shmem", "Private_Dirty", "Swap")
                    and len(parts) == 2 and parts[0].isdecimal() and parts[1] == "kB"):
                fields[key + "_kib"] = int(parts[0])
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


def loopback_curl():
    """Fixed unauthenticated request; native curl owns the total deadline."""
    return ["/usr/bin/curl", "--disable", "--noproxy", "*", "--silent",
            "--max-time", "5", "--connect-timeout", "2", "--output", "/dev/null",
            "--write-out", "%{http_code} %{time_connect} %{time_starttransfer} %{time_total}",
            "--header", "Host: webmin-j2-svpi3bmf.local.theama.co",
            "--header", "X-Forwarded-Host: webmin-j2-svpi3bmf.local.theama.co",
            "--header", "X-Forwarded-Proto: https", "--header", "X-Forwarded-For: 10.1.0.53",
            "--header", "Accept: */*", "--header", "Accept-Encoding: identity",
            "--header", "Connection: close", "--user-agent", "homelab-proxy-diagnostic",
            "http://127.0.0.1:10000/session_login.cgi"]


def compare_loopback(expected_cpus=1):
    """Stream evidence before checks. No service/configuration writes or retries."""
    started = time.monotonic()
    children = []
    phase = "admission"
    outcome = "stopped"
    cgroup = Path("/sys/fs/cgroup/system.slice/webmin.service")

    def emit(kind, **values):
        print(json.dumps(dict(kind=kind, phase=phase,
                              elapsed=round(time.monotonic()-started, 3), **values)), flush=True)

    def require(condition, check, expected, observed):
        if not condition:
            emit("stop", check=check, expected=expected, observed=observed)
            raise ValueError(check)

    def capture():
        row = sample(cgroup, started, detailed=False)
        row["boot_id"] = read_small(Path("/proc/sys/kernel/random/boot_id")).strip()
        row["cpu.max"] = read_small(cgroup / "cpu.max").strip()
        row["io.stat"] = read_small(cgroup / "io.stat", 4096).strip()
        kuma = Path("/sys/fs/cgroup/system.slice/uptime-kuma.service")
        row["kuma"] = {k: read_small(kuma / k, 2048).strip() for k in
                       ("memory.high", "memory.max", "memory.swap.max", "memory.events")}
        row["available_kib"] = int(next(l.split()[1] for l in Path("/proc/meminfo").read_text().splitlines()
                                        if l.startswith("MemAvailable:")))
        row["connections"] = sum(int(l.split()[1].rsplit(":", 1)[1], 16) == 10000
                                 and l.split()[3] not in ("0A", "06")
                                 for name in ("tcp", "tcp6")
                                 for l in Path("/proc/net", name).read_text().splitlines()[1:])
        usage = resource.getrusage(resource.RUSAGE_SELF)
        row["observer_cpu_seconds"] = usage.ru_utime + usage.ru_stime
        row["observer_pid"] = os.getpid()
        emit("sample", observation=row)
        return row

    def identities(row):
        return {(p["pid"], p["start_ticks"]) for p in row["processes"] if "start_ticks" in p}

    def healthy(row):
        require(row["available_kib"] >= 96*1024, "reserve_kib", ">=98304", row["available_kib"])
        for key in ("boot_id", "cpu.max", "memory.high", "memory.max", "memory.swap.max"):
            require(row[key] == baseline[key], key, baseline[key], row[key])
        require(row["process_inventory_complete"] and
                all("start_ticks" in p or p.get("vanished", False) for p in row["processes"]),
                "process_evidence", "complete PID/start identities", row["processes"])
        require("usage_usec" in row["cpu.stat"] and "throttled_usec" in row["cpu.stat"],
                "cpu.stat", "usage and throttle counters", row["cpu.stat"])
        require(main_identity in identities(row), "main_process", main_identity, sorted(identities(row)))
        for key in ("high", "max", "oom", "oom_kill"):
            events = dict(l.split() for l in row["memory.events"].splitlines())
            require(events[key] == events_before[key], "memory.events."+key, events_before[key], events[key])
        for key in ("memory.high", "memory.max", "memory.swap.max"):
            require(row["kuma"][key] == baseline["kuma"][key], "kuma."+key,
                    baseline["kuma"][key], row["kuma"][key])
        old_events = dict(l.split() for l in baseline["kuma"]["memory.events"].splitlines())
        new_events = dict(l.split() for l in row["kuma"]["memory.events"].splitlines())
        for key in ("high", "max", "oom", "oom_kill"):
            require(new_events[key] == old_events[key], "kuma.memory.events."+key,
                    old_events[key], new_events[key])

    def settle():
        until = time.monotonic()+10
        stable = 0
        while time.monotonic() < until:
            row = capture(); healthy(row)
            stable = stable+1 if row["connections"] == 0 and identities(row) <= standing else 0
            if stable >= 2:
                return
            time.sleep(1)
        require(False, "settling", "no connections or new processes for two samples",
                {"connections": row["connections"], "new_processes": sorted(identities(row)-standing)})

    def interrupted(signum, _frame):
        raise TimeoutError("deadline_or_signal_" + str(signum))

    old = {s: signal.signal(s, interrupted) for s in (signal.SIGALRM, signal.SIGTERM, signal.SIGINT, signal.SIGHUP)}
    signal.alarm(45)
    try:
        baseline = capture()
        emit("identity", hostname=socket.gethostname())
        require(socket.gethostname() == "j2-svpi3bmf", "hostname", "j2-svpi3bmf", socket.gethostname())
        for key, value in {"memory.high": "134217728", "memory.max": "201326592", "memory.swap.max": "0"}.items():
            require(baseline[key] == value, key, value, baseline[key])
        for key, value in {"memory.high": "268435456", "memory.max": "335544320", "memory.swap.max": "0"}.items():
            require(baseline["kuma"][key] == value, "kuma."+key, value, baseline["kuma"][key])
        quota = baseline["cpu.max"].split()
        require(expected_cpus in (1, 2) and len(quota) == 2 and all(v.isdigit() for v in quota)
                and int(quota[0]) == expected_cpus * int(quota[1]),
                "cpu.max", f"quota equal to {expected_cpus} times period", baseline["cpu.max"])
        require("usage_usec" in baseline["cpu.stat"] and "throttled_usec" in baseline["cpu.stat"],
                "cpu.stat", "usage and throttle counters", baseline["cpu.stat"])
        phase = "main_pid_read"
        main = subprocess.run(["/usr/bin/systemctl", "show", "webmin.service", "--property=MainPID", "--value"],
                              capture_output=True, text=True, timeout=3, check=True).stdout.strip()
        require(main.isdigit(), "main_pid", "numeric MainPID", main[:32])
        main_identity = next((v for v in identities(baseline) if v[0] == int(main)), None)
        require(main_identity is not None, "main_pid_membership", int(main), sorted(identities(baseline)))
        standing = identities(baseline)
        events_before = dict(l.split() for l in baseline["memory.events"].splitlines())
        phase = "baseline_settling"
        healthy(baseline); settle()
        for count in (1, 3):
            phase = "single" if count == 1 else "overlap"
            emit("batch_start", count=count)
            try:
                for _ in range(count):
                    children.append(subprocess.Popen(loopback_curl(), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL))
                deadline = time.monotonic()+6
                while any(p.poll() is None for p in children):
                    row = capture(); healthy(row)
                    require(time.monotonic() < deadline, "client_deadline", "<=6 seconds including cleanup dispatch", "exceeded")
                    time.sleep(0.5)
            finally:
                results = []
                for child in children:
                    if child.poll() is None:
                        child.kill()
                    output = child.communicate(timeout=1)[0].decode("ascii", "replace")
                    parts = output.split()
                    valid = len(parts) == 4 and all(v.replace(".", "", 1).isdigit() for v in parts)
                    results.append({"exit": child.returncode, "timing": parts if valid else None})
                children.clear()
                emit("batch_result", requests=results,
                     timing_fields=["http_code", "connect_seconds", "first_byte_seconds", "total_seconds"])
            passed = all(r["exit"] == 0 and r["timing"] and r["timing"][0] == "200" for r in results)
            phase += "_settling"
            settle()
            require(passed, "request_outcome", "all HTTP 200 within 5 seconds", results)
        outcome = "comparison_completed"
    except Exception as error:
        emit("failure", error_type=type(error).__name__, errno=getattr(error, "errno", None),
             command_exit=getattr(error, "returncode", None),
             missing_path=getattr(error, "filename", None))
    finally:
        signal.alarm(0)
        for child in children:
            if child.poll() is None: child.kill()
            child.wait(timeout=1)
        phase = "final_readback"
        try:
            last = capture()
            healthy(last)
            unresolved = last["connections"] != 0 or bool(identities(last)-standing)
        except Exception as error:
            unresolved = True
            emit("readback_unavailable", error_type=type(error).__name__)
        emit("terminal", outcome=outcome, owned_clients_reaped=True,
             backend_work_unresolved=unresolved,
             service_changed=False, service_recovery_attempted=False)
        for sig, handler in old.items(): signal.signal(sig, handler)
    return 0 if outcome == "comparison_completed" and not unresolved else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-profile", type=Path)
    parser.add_argument("--policy", type=Path)
    parser.add_argument("--port", type=int, default=10000)
    parser.add_argument("--request-timeout", type=int, default=75)
    parser.add_argument("--duration", type=int, default=180)
    parser.add_argument("--compare-loopback", action="store_true")
    args = parser.parse_args()
    if args.compare_loopback:
        raise SystemExit(compare_loopback())
    elif args.verify_profile:
        if not args.policy:
            parser.error("profile verification needs its policy")
        print(json.dumps(verify_profile(args.verify_profile, args.policy)))
    else:
        if not (1 <= args.port <= 65535 and 1 <= args.request_timeout <= 75
                and 1 <= args.duration <= 180):
            parser.error("diagnostic bounds exceeded")
        observe(args.port, args.request_timeout, args.duration)
