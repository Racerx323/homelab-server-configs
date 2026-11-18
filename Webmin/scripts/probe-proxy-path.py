#!/usr/bin/env python3
"""Bounded unauthenticated Webmin path/counter evidence; no configuration writes."""
import argparse
import http.client
import ipaddress
import json
import os
import re
import socket
import select
import struct
import secrets
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
    timing = {'started_epoch': time.time(), 'path': '/session_login.cgi',
              'request_id': secrets.token_hex(16),
              'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
              'start': time.clock_gettime(time.CLOCK_BOOTTIME)}
    try:
        connection.connect()
        timing['connect_seconds'] = time.monotonic()-start
        phase = 'headers'
        actual_source = str(ipaddress.ip_address(connection.sock.getsockname()[0]))
        actual_target = str(ipaddress.ip_address(connection.sock.getpeername()[0]))
        if actual_source != source or actual_target != str(target):
            return {'accepted': False, 'failure': 'socket_endpoint_mismatch', 'expected_source': source,
                    'expected_target': str(target), 'observed_source': actual_source, 'observed_target': actual_target}
        connection.request('GET', '/session_login.cgi', headers={'X-Homelab-Diagnostic': timing['request_id'], 'Host': hostname, 'X-Forwarded-Proto': 'https', 'X-Forwarded-Host': hostname, 'X-Forwarded-For': source, 'Connection': 'close', 'Accept': '*/*', 'Accept-Encoding': 'identity', 'User-Agent': 'homelab-proxy-diagnostic'})
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
        timing['end'] = time.clock_gettime(time.CLOCK_BOOTTIME)
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



class BackendWire:
    """Bounded IPv4/TCP wire evidence, not Webmin CGI instrumentation.

    Observe only fresh connections from the reviewed primary to port 10000.
    No packet, body, cookie or arbitrary header value is written. Gaps,
    fragmentation, reordering and dropped packets invalidate completeness.
    """
    def __init__(self, output, peer, backend, hostname):
        self.output, self.peer, self.backend, self.hostname = output, peer, backend, hostname
        self.flows = {}
        self.count = 0
        self.issues = set()
        self.packet_epoch = None

    def emit(self, row):
        self.count += 1
        if self.count > 512:
            raise ValueError('wire_event_limit')
        row['kernel_epoch'] = self.packet_epoch
        row['observed_boottime'] = time.clock_gettime(time.CLOCK_BOOTTIME)
        self.output.write(json.dumps(row, sort_keys=True)+'\n')
        self.output.flush()

    def packet(self, data, kernel_epoch=None):
        self.packet_epoch = kernel_epoch
        if len(data) < 40 or data[0] >> 4 != 4 or data[9] != 6:
            return
        src, dst = socket.inet_ntoa(data[12:16]), socket.inet_ntoa(data[16:20])
        inbound = (src, dst) == (self.peer, self.backend)
        if not inbound and (src, dst) != (self.backend, self.peer):
            return
        ihl = (data[0] & 15)*4
        if ihl < 20 or len(data) < ihl+20:
            self.issues.add('short_ip'); return
        sport, dport, seq = struct.unpack('!HHI', data[ihl:ihl+8])
        if (dport if inbound else sport) != 10000:
            return
        if struct.unpack('!H', data[6:8])[0] & 0x3fff:
            self.issues.add('fragment'); return
        total = struct.unpack('!H', data[2:4])[0]
        thl = (data[ihl+12] >> 4)*4
        if thl < 20 or total < ihl+thl or total > len(data):
            self.issues.add('truncated_packet'); return
        flags = data[ihl+13]
        port = sport if inbound else dport
        if inbound and flags & 2 and port not in self.flows:
            if len(self.flows) >= 64:
                raise ValueError('wire_flow_limit')
            self.flows[port] = {'id': len(self.flows)+1, 'request': {}, 'response': {}}
        flow = self.flows.get(port)
        if flow is None:
            self.issues.add('connection_before_capture'); return
        direction = 'request' if inbound else 'response'
        stream = flow[direction]
        payload = data[ihl+thl:total]
        if flags & 2:
            stream.setdefault('next', (seq+1) & 0xffffffff)
        if payload:
            if 'next' not in stream or seq > stream['next']:
                self.issues.add('tcp_gap_or_reordering'); return
            skip = stream['next']-seq
            if skip < len(payload):
                payload = payload[skip:]
                stream['next'] += len(payload)
                if 'first' not in stream:
                    stream['first'] = time.clock_gettime(time.CLOCK_BOOTTIME)
                    self.emit({'event': direction+'-first-byte', 'flow': flow['id']})
                if direction == 'request' and stream.get('headers_done'):
                    self.issues.add('request_reuse_or_body')
                if not stream.get('headers_done'):
                    buf = stream.get('buffer', b'') + payload[:8193]
                    if b'\r\n\r\n' not in buf and len(buf) > 8192:
                        self.issues.add('header_limit'); stream['headers_done'] = True
                    elif b'\r\n\r\n' in buf:
                        head = buf.split(b'\r\n\r\n', 1)[0]
                        if len(head) > 8192:
                            self.issues.add('header_limit')
                        else:
                            self.headers(flow, direction, head)
                        stream['headers_done'] = True
                    else:
                        stream['buffer'] = buf
                    if stream.get('headers_done'):
                        stream.pop('buffer', None)
        if flags & (1 | 4) and not stream.get('closed'):
            stream['closed'] = True
            self.emit({'event': direction+'-close', 'flow': flow['id'],
                       'kind': 'reset' if flags & 4 else 'fin'})

    def headers(self, flow, direction, head):
        lines = head.split(b'\r\n')
        if direction == 'response':
            match = re.fullmatch(rb'HTTP/1\.[01] ([0-9]{3})(?: [^\r\n]*)?', lines[0])
            if not match:
                self.issues.add('response_header_format'); return
            self.emit({'event': 'response-headers', 'flow': flow['id'], 'status': int(match[1])})
            return
        if lines[0] != b'GET /session_login.cgi HTTP/1.1':
            self.issues.add('unexpected_request'); return
        allowed = {'host': self.hostname, 'x-forwarded-host': self.hostname,
                   'x-forwarded-proto': 'https', 'x-forwarded-for': self.peer,
                   'accept': '*/*', 'accept-encoding': 'identity',
                   'user-agent': 'homelab-proxy-diagnostic', 'connection': 'close',
                   'x-homelab-health': 'webmin-primary-diagnostic'}
        values = {}; seen = set(); marker = None
        for line in lines[1:]:
            name, sep, value = line.partition(b':')
            name = name.lower().decode('ascii', errors='replace')
            if not sep:
                self.issues.add('request_header_format'); continue
            if name in seen:
                self.issues.add('duplicate_header')
            seen.add(name)
            value = value.strip()
            if name == 'x-homelab-diagnostic':
                if re.fullmatch(rb'[0-9a-f]{32}', value):
                    marker = value.decode()
                else:
                    self.issues.add('invalid_marker')
            if name in allowed:
                # Retain expected constants only; arbitrary input never reaches evidence.
                values[name] = allowed[name] if value == allowed[name].encode() else 'unexpected'
        self.emit({'event': 'request-headers', 'flow': flow['id'], 'request_id': marker,
                   'kind': 'marked' if marker else 'health' if values.get('x-homelab-health') == 'webmin-primary-diagnostic' else 'unmarked-login', 'headers': values})

    def finish(self, drops):
        if drops:
            self.issues.add('kernel_packet_drops')
        self.emit({'terminal': True, 'issues': sorted(self.issues), 'kernel_drops': drops,
                   'boundary': 'backend-interface; not proof of CGI execution or completion'})


def observe(directory, seconds=300, wire=None, interface="eth0", sample_check=None):
    """One bounded numeric sampler in the existing root-private trial directory."""
    directory = Path(directory)
    metadata = directory.lstat()
    if directory.is_symlink() or not directory.is_dir() or metadata.st_uid != os.geteuid() or metadata.st_mode & 0o077:
        raise ValueError('private_directory')
    if not 0 < seconds <= 300:
        raise ValueError('duration')
    os.umask(0o077)
    capture = wire_output = observer = None
    if wire:
        peer, backend, hostname = wire
        if not isinstance(hostname, str) or not re.fullmatch(r'[a-z0-9.-]+', hostname):
            raise ValueError('wire_hostname')
        for address in (peer, backend):
            if ipaddress.ip_address(address).version != 4: raise ValueError('wire_ipv4')
        wire_output = (directory / 'backend-wire.jsonl').open('x')
        observer = BackendWire(wire_output, peer, backend, hostname)
        capture = socket.socket(socket.AF_PACKET, socket.SOCK_DGRAM, socket.htons(3))
        capture.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 262144)
        capture.setsockopt(socket.SOL_SOCKET, 35, 1)  # SO_TIMESTAMPNS on the selected 64-bit Linux hosts
        capture.bind((interface, 0))
        capture.setblocking(False)
    # Exclusive creation prevents reusing a consumed observation.
    with (directory / 'resource-samples.jsonl').open('x') as output:
        previous = snapshot()
        initial = event_delta(previous, previous)
        if any(row['status'] != 'comparable' for row in initial.values()):
            raise ValueError('resource_baseline_unavailable')
        if sample_check is not None: sample_check(previous)
        output.write(json.dumps(previous)+'\n'); output.flush()
        with (directory / 'resource-ready').open('x') as ready:
            ready.write('ready\n')
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline and not (directory / 'resource-stop').exists():
            next_sample = min(deadline, time.monotonic()+1)
            if capture:
                while time.monotonic() < next_sample:
                    if not select.select([capture], [], [], max(0, next_sample-time.monotonic()))[0]: break
                    data, ancillary, flags, _ = capture.recvmsg(65535, socket.CMSG_SPACE(16))
                    stamps = [struct.unpack('ll', value) for level, kind, value in ancillary
                              if level == socket.SOL_SOCKET and kind == 35 and len(value) == 16]
                    if flags & (socket.MSG_TRUNC | socket.MSG_CTRUNC) or len(stamps) != 1:
                        observer.issues.add('packet_timestamp_or_truncation')
                    packet_epoch = stamps[0][0]+stamps[0][1]/1e9 if len(stamps) == 1 else None
                    if packet_epoch is not None and not 0 <= time.time()-packet_epoch <= 2:
                        observer.issues.add('kernel_delivery_lag_or_clock_change')
                    observer.packet(data, packet_epoch)
            else:
                time.sleep(max(0, next_sample-time.monotonic()))
            current = snapshot()
            current['event_delta'] = event_delta(previous, current)
            if sample_check is not None: sample_check(current)
            encoded = json.dumps(current)+'\n'
            if output.tell() + len(encoded) > 1048000:
                raise ValueError('resource_evidence_limit')
            output.write(encoded); output.flush()
            previous = current
        output.write(json.dumps({'terminal': True, 'reason': 'stop' if (directory / 'resource-stop').exists() else 'deadline',
                                 'epoch': time.time(), 'monotonic': float(Path('/proc/uptime').read_text().split()[0]), 'clock': 'linux-boottime'})+'\n')
    if capture:
        # SOL_PACKET/PACKET_STATISTICS: packet and drop counters, reset on read.
        _, drops = struct.unpack('II', capture.getsockopt(263, 6, 8))
        observer.finish(drops)
        capture.close(); wire_output.close()
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
    parser.add_argument('--wire-peer'); parser.add_argument('--wire-backend'); parser.add_argument('--wire-hostname')
    parser.add_argument('--counters', action='store_true')
    parser.add_argument('--deny', action='store_true')
    parser.add_argument('--address'); parser.add_argument('--hostname'); parser.add_argument('--source')
    args = parser.parse_args()
    try:
        row = observe(args.observe_directory, wire=(args.wire_peer, args.wire_backend, args.wire_hostname) if args.wire_peer else None) if args.observe_directory else snapshot() if args.snapshot else counters() if args.counters else denied(args.address) if args.deny else probe(args.address, args.hostname, args.source)
        print(json.dumps(row)); raise SystemExit(0 if args.observe_directory or args.snapshot or args.counters or row['accepted'] else 1)
    except Exception as error:
        # Fixed classification only; no response bodies or exceptions with private data.
        print(json.dumps({'accepted': False, 'failure': type(error).__name__,
                          'expected_target': args.address, 'expected_source': args.source,
                          'native_exit': getattr(error, 'returncode', None)})); raise SystemExit(1)
