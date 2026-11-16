#!/usr/bin/env python3
"""Bounded unauthenticated Webmin path/counter evidence; no configuration writes."""
import argparse
import http.client
import ipaddress
import json
import os
import re
import socket
import subprocess
import time
from pathlib import Path


def probe(address, hostname, expected_source):
    target = ipaddress.ip_address(address)
    source = str(ipaddress.ip_address(expected_source))
    if not re.fullmatch(r'[a-z0-9.-]+', hostname): raise ValueError('hostname')
    route = json.loads(subprocess.run(['ip', '-j', '-' + str(target.version), 'route', 'get', str(target)],
                                    check=True, capture_output=True, text=True, timeout=3).stdout)
    if len(route) != 1 or route[0].get('prefsrc', route[0].get('src')) != source:
        return {'accepted': False, 'failure': 'route_selected_source_mismatch',
                'target': str(target), 'expected_source': source, 'observed_route': route}
    start = time.monotonic()
    connection = http.client.HTTPConnection(str(target), 10000, timeout=5)
    phase = 'connect'
    timing = {'started_epoch': time.time(), 'path': '/session_login.cgi'}
    try:
        connection.connect()
        timing['connect_seconds'] = time.monotonic()-start
        phase = 'headers'
        actual_source = str(ipaddress.ip_address(connection.sock.getsockname()[0]))
        actual_target = str(ipaddress.ip_address(connection.sock.getpeername()[0]))
        if actual_source != source or actual_target != str(target):
            return {'accepted': False, 'failure': 'socket_endpoint_mismatch', 'expected_source': source,
                    'expected_target': str(target), 'observed_source': actual_source, 'observed_target': actual_target}
        connection.request('GET', '/session_login.cgi', headers={'Host': hostname, 'X-Forwarded-Proto': 'https', 'Connection': 'close'})
        response = connection.getresponse()
        timing['headers_seconds'] = time.monotonic()-start
        phase = 'body'
        body = response.read(65537)
        login = len(body) <= 65536 and bool(re.search(rb'name\s*=\s*[\"\x27]?pass\b', body))
        return {'accepted': response.status == 200 and login, 'target': str(target), 'source': actual_source,
                'family': target.version, 'status': response.status, 'login_page': login,
                'seconds': time.monotonic()-start, 'route': route[0], 'timing': timing}
    except (OSError, http.client.HTTPException) as error:
        return {'accepted': False, 'failure': type(error).__name__, 'phase': phase,
                'target': str(target), 'expected_source': source, 'timing': timing,
                'seconds': time.monotonic()-start}
    finally:
        connection.close()


def snapshot():
    """One fixed numeric cgroup snapshot; no process arguments or service logs."""
    result = {'epoch': time.time(), 'monotonic': float(Path('/proc/uptime').read_text().split()[0]), 'clock': 'linux-boottime',
              'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip(), 'cgroups': {}}
    for unit in ('webmin.service', 'uptime-kuma.service'):
        group = Path('/sys/fs/cgroup/system.slice') / unit
        try:
            identity = group.stat()
            fields = {'identity': [identity.st_dev, identity.st_ino]}
        except OSError:
            fields = {'identity': None}
        for name in ('memory.current', 'memory.peak', 'memory.events', 'memory.pressure'):
            try:
                with (Path('/sys/fs/cgroup/system.slice') / unit / name).open() as stream:
                    value = stream.read(2049)
                if len(value) > 2048 or not re.fullmatch(r'[a-z0-9 ._=\n]+', value):
                    value = 'unavailable'
            except OSError:
                value = 'unavailable'
            fields[name] = value
        result['cgroups'][unit] = fields
    return result


def event_delta(before, after):
    """Counter changes locate an interval, never identify the responsible request."""
    result = {}
    for unit in ('webmin.service', 'uptime-kuma.service'):
        old, new = before['cgroups'][unit], after['cgroups'][unit]
        try:
            if before['boot_id'] != after['boot_id'] or old['identity'] is None or old['identity'] != new['identity']:
                raise ValueError('continuity')
            left_rows = [line.split() for line in old['memory.events'].splitlines()]
            right_rows = [line.split() for line in new['memory.events'].splitlines()]
            left, right = dict(left_rows), dict(right_rows)
            if len(left) != len(left_rows) or len(right) != len(right_rows):
                raise ValueError('duplicate')
            required = {'low', 'high', 'max', 'oom', 'oom_kill'}
            if not required <= left.keys() or left.keys() != right.keys():
                raise ValueError('fields')
            if any(not value.isdecimal() for value in [*left.values(), *right.values()]):
                raise ValueError('numeric')
            changes = {key: int(right[key])-int(left[key]) for key in left}
            if any(value < 0 for value in changes.values()):
                raise ValueError('reset')
            result[unit] = {'status': 'comparable', 'events': changes}
        except (ValueError, KeyError):
            result[unit] = {'status': 'unavailable-or-reset'}
    return result


def observe(directory, seconds=300):
    """One bounded numeric sampler in the existing root-private trial directory."""
    directory = Path(directory)
    metadata = directory.lstat()
    if directory.is_symlink() or not directory.is_dir() or metadata.st_uid != os.geteuid() or metadata.st_mode & 0o077:
        raise ValueError('private_directory')
    if not 0 < seconds <= 300:
        raise ValueError('duration')
    os.umask(0o077)
    # Exclusive creation prevents reusing a consumed observation.
    with (directory / 'resource-samples.jsonl').open('x') as output:
        previous = snapshot()
        initial = event_delta(previous, previous)
        if any(row['status'] != 'comparable' for row in initial.values()):
            raise ValueError('resource_baseline_unavailable')
        output.write(json.dumps(previous)+'\n'); output.flush()
        with (directory / 'resource-ready').open('x') as ready:
            ready.write('ready\n')
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline and not (directory / 'resource-stop').exists():
            time.sleep(min(1, max(0, deadline-time.monotonic())))
            current = snapshot()
            current['event_delta'] = event_delta(previous, current)
            encoded = json.dumps(current)+'\n'
            if output.tell() + len(encoded) > 1048000:
                raise ValueError('resource_evidence_limit')
            output.write(encoded); output.flush()
            previous = current
        output.write(json.dumps({'terminal': True, 'reason': 'stop' if (directory / 'resource-stop').exists() else 'deadline',
                                 'epoch': time.time(), 'monotonic': float(Path('/proc/uptime').read_text().split()[0]), 'clock': 'linux-boottime'})+'\n')
    return {'observer_exited': True}


def denied(address):
    target = ipaddress.ip_address(address)
    sock = socket.socket(socket.AF_INET6 if target.version == 6 else socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(3)
    try:
        sock.connect((str(target), 10000))
        return {'accepted': False, 'reason': 'connected'}
    except TimeoutError:
        return {'accepted': True, 'reason': 'timeout', 'target': str(target),
                'client_source': sock.getsockname()[0]}
    finally:
        sock.close()


def counters():
    run = subprocess.run(['nft', '-j', 'list', 'table', 'inet', 'webmin'], check=True,
                         capture_output=True, text=True, timeout=3)
    if len(run.stdout) > 65536: raise ValueError('guard_evidence_limit')
    result = {}
    for item in json.loads(run.stdout)['nftables']:
        rule = item.get('rule', {})
        comment = rule.get('comment', '')
        if comment.startswith('webmin-'):
            values = [entry['counter']['packets'] for entry in rule['expr'] if 'counter' in entry]
            if len(values) != 1 or comment in result: raise ValueError('guard_counter_identity')
            result[comment] = values[0]
    if not {'webmin-denied-4', 'webmin-denied-6'} <= result.keys(): raise ValueError('guard_counters_missing')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', action='store_true')
    parser.add_argument('--observe-directory')
    parser.add_argument('--counters', action='store_true')
    parser.add_argument('--deny', action='store_true')
    parser.add_argument('--address'); parser.add_argument('--hostname'); parser.add_argument('--source')
    args = parser.parse_args()
    try:
        row = observe(args.observe_directory) if args.observe_directory else snapshot() if args.snapshot else counters() if args.counters else denied(args.address) if args.deny else probe(args.address, args.hostname, args.source)
        print(json.dumps(row)); raise SystemExit(0 if args.observe_directory or args.snapshot or args.counters or row['accepted'] else 1)
    except Exception as error:
        # Fixed classification only; no response bodies or exceptions with private data.
        print(json.dumps({'accepted': False, 'failure': type(error).__name__,
                          'expected_target': args.address, 'expected_source': args.source,
                          'native_exit': getattr(error, 'returncode', None)})); raise SystemExit(1)
