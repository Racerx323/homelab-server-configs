#!/usr/bin/env python3
"""Local Caddy owner readiness/finish handoff; never a release publisher."""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import math
import shlex
import subprocess
import stat
import tempfile
import time

spec = importlib.util.spec_from_file_location('workload', Path(__file__).with_name('supervise-proxy-workload.py'))
workload = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workload)


class OwnerExited(Exception):
    pass


def ready(log, receipt, owner_exit=None):
    if owner_exit is not None and owner_exit.exists():
        if not re.fullmatch(r'[0-9]{1,3}\n', workload.private(owner_exit, 4)): raise ValueError('invalid_owner_exit')
        raise OwnerExited('owner_already_ended')
    text = workload.private(log)
    matches = re.findall(r'^application_trial_ready=(/tmp/caddy-ssh-evidence-serving_health\.[A-Za-z0-9]+/application-trial-ready.tsv)$', text, re.M)
    if len(matches) != 1: raise ValueError('one_owner_ready_required')
    path = Path(matches[0]); child = workload.private(path, 256).strip()
    if not re.fullmatch(r'[A-Za-z0-9-]{1,160}', child): raise ValueError('child_identity')
    value = {'ready_path': str(path), 'child': child}
    if receipt.exists():
        if json.loads(workload.private(receipt, 1024)) != value: raise ValueError('changed_handoff')
    else: workload.write(receipt, value)


def finish(receipt, workload_result=None):
    if workload_result is not None and not json.loads(workload.private(workload_result))['browser_cleanup']['group_gone']:
        raise ValueError('browser_cleanup_unverified')
    value = json.loads(workload.private(receipt, 1024))
    path = Path(value['ready_path'])
    if not re.fullmatch(r'/tmp/caddy-ssh-evidence-serving_health\.[A-Za-z0-9]+/application-trial-ready.tsv', str(path)):
        raise ValueError('owner_path')
    if workload.private(path, 256).strip() != value['child']: raise ValueError('changed_child')
    workload.atomic_text(path.with_name('application-trial-finish.tsv'), value['child'] + '\tcomplete\n')



def admit_evidence(directory):
    """Require prepared private storage and exercise the actual receipt writer."""
    if not directory.is_absolute() or any(p.is_symlink() for p in (directory, *directory.parents)):
        raise ValueError('evidence_directory_unsafe')
    try:
        info = directory.lstat()
    except FileNotFoundError:
        raise ValueError('evidence_directory_missing') from None
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or
            stat.S_IMODE(info.st_mode) != 0o700):
        raise ValueError('evidence_directory_private_required')
    # The disposable child cannot overwrite a prior operation's receipts.
    with tempfile.TemporaryDirectory(prefix='.admission-', dir=directory) as name:
        receipt = Path(name) / 'receipt.json'
        workload.write(receipt, {'storage_ready': True})
        if json.loads(workload.private(receipt)) != {'storage_ready': True}:
            raise ValueError('evidence_directory_readback_failed')


def clock_capture(spec_path, receipt):
    """Fixed read-only clock queries for only the reviewed diagnostic hosts."""
    settings = json.loads(workload.private(spec_path, 65536))
    prefixes = settings['clock_ssh_prefixes']
    expected_hosts = {'backend', 'node-a'} if settings.get('scope') == 'primary-ipv4' else {'backend', 'node-a', 'node-b'}
    if set(prefixes) != expected_hosts:
        raise ValueError('clock_hosts')
    program = "import json,time;from pathlib import Path;print(json.dumps({'monotonic':float(Path('/proc/uptime').read_text().split()[0]),'clock':'linux-boottime','boot_id':Path('/proc/sys/kernel/random/boot_id').read_text().strip()}))"
    remote = shlex.join(['/usr/bin/python3', '-I', '-B', '-c', program])
    clocks = {}
    for host, prefix in prefixes.items():
        if not isinstance(prefix, list) or len(prefix) < 2 or prefix[0] != '/usr/bin/ssh' or any(not isinstance(v, str) or '\x00' in v for v in prefix):
            raise ValueError('clock_transport')
        begin = time.monotonic()
        try:
            run = subprocess.run([*prefix, remote], capture_output=True, text=True, timeout=5)
            end = time.monotonic()
            if run.returncode or len(run.stdout) > 1024: raise ValueError('clock_command')
            row = json.loads(run.stdout)
            if (row.get('clock') != 'linux-boottime' or not re.fullmatch('[0-9a-f-]{36}', row['boot_id']) or
                    not isinstance(row['monotonic'], (float, int)) or not math.isfinite(row['monotonic']) or row['monotonic'] < 0):
                raise ValueError('clock_value')
            clocks[host] = dict(row, controller_begin=begin, controller_end=end)
        except (ValueError, KeyError, TypeError, OSError, subprocess.TimeoutExpired):
            clocks[host] = {'failure': 'clock_capture_incomplete', 'controller_begin': begin, 'controller_end': time.monotonic()}
            workload.write(receipt, clocks)
            raise ValueError('clock_capture_incomplete')
    workload.write(receipt, clocks)


def clock_interval(stamp, boot, before, after):
    """Estimated envelope, with observed offset drift retained rather than hidden."""
    if before.get('clock') != 'linux-boottime' or after.get('clock') != 'linux-boottime':
        raise ValueError('clock_source')
    if before.get('boot_id') != boot or after.get('boot_id') != boot:
        raise ValueError('clock_boot_changed')
    values = [stamp] + [row[key] for row in (before, after)
                       for key in ('monotonic', 'controller_begin', 'controller_end')]
    if any(not isinstance(v, (int, float)) or not math.isfinite(v) for v in values):
        raise ValueError('clock_numeric')
    if not before['monotonic'] <= stamp <= after['monotonic']:
        raise ValueError('clock_not_bracketed')
    if before['controller_end'] > after['controller_begin']:
        raise ValueError('clock_order')
    if any(not 0 <= row['controller_end']-row['controller_begin'] <= 5 for row in (before, after)):
        raise ValueError('clock_roundtrip')
    offsets = [(row['controller_begin']-row['monotonic'], row['controller_end']-row['monotonic'])
               for row in (before, after)]
    lo, hi = min(row[0] for row in offsets), max(row[1] for row in offsets)
    if hi-lo > 5: raise ValueError('clock_uncertainty')
    return [stamp+lo, stamp+hi]


def request_records(owner_log):
    text = workload.private(owner_log)
    matches = re.findall(r'^evidence_directory=(/tmp/caddy-ssh-evidence-serving_health\.[A-Za-z0-9]+)$', text, re.M)
    if len(matches) != 1: raise ValueError('owner_evidence_directory')
    directory = Path(matches[0]); records = {}
    for stream in sorted(directory.glob('application-*-readback.stdout')):
        if not re.fullmatch(r'application-(primary|result|restored)-[ab]-readback.stdout', stream.name): continue
        lines = workload.private(stream).splitlines()
        if len(lines) % 2: raise ValueError('readback_pairs')
        names = set()
        for metadata, encoded in zip(lines[::2], lines[1::2]):
            match = re.fullmatch(r'file=([A-Za-z0-9._-]+) bytes=([0-9]+) sha256=([0-9a-f]{64})', metadata)
            if not match or match[1] in names or int(match[2]) > 1048576: raise ValueError('readback_metadata')
            names.add(match[1]); raw = base64.b64decode(encoded, validate=True)
            if len(raw) != int(match[2]) or hashlib.sha256(raw).hexdigest() != match[3]: raise ValueError('readback_hash')
            if match[1] != 'application-requests.tsv': continue
            for line in raw.decode().splitlines():
                identity, node, boot, start, end = line.split('\t')
                if node != ('node-a' if '-a-readback' in stream.name else 'node-b'): raise ValueError('request_node')
                row = dict(request_id=identity, node=node, boot_id=boot, start=float(start), end=float(end))
                if identity in records and records[identity] != row: raise ValueError('changed_request')
                records[identity] = row
    if not records: raise ValueError('request_receipts_missing')
    return list(records.values())



def backend_wire_evidence(path, requests):
    rows = workload.rows(path)
    if not rows or not rows[-1].get('terminal') or rows[-1].get('issues') or rows[-1].get('kernel_drops') != 0:
        raise ValueError('backend_wire_incomplete')
    flows = {}
    for row in rows[:-1]:
        if row.get('event') not in ('request-first-byte', 'request-headers', 'request-close',
                                    'response-first-byte', 'response-headers', 'response-close'):
            raise ValueError('backend_wire_event_unknown')
        if not isinstance(row.get('kernel_epoch'), (float, int)) or not math.isfinite(row['kernel_epoch']):
            raise ValueError('backend_wire_timestamp')
        flows.setdefault(row['flow'], []).append(row)
    marked = {}
    health = []
    no_payload = []
    for flow in flows.values():
        heads = [r for r in flow if r.get('event') == 'request-headers']
        if not heads and all(r.get('event') in ('request-close', 'response-close') for r in flow):
            # Fresh TCP connections can close without sending HTTP. Keep that
            # evidence distinct; partial HTTP and unknown events still reject.
            if (len({r['event'] for r in flow}) != len(flow) or
                    any(set(r) != {'event', 'flow', 'kernel_epoch', 'observed_boottime', 'kind'} or
                        r['kind'] not in ('fin', 'reset') for r in flow)):
                raise ValueError('backend_wire_close_invalid')
            no_payload.append({'flow': flow[0]['flow'], 'classification': 'no-observed-payload',
                               'capture_events': flow})
            continue
        if len(heads) != 1:
            raise ValueError('backend_wire_headers_incomplete')
        head = heads[0]
        first = [r for r in flow if r.get('event') == 'request-first-byte']
        if len(first) != 1:
            raise ValueError('backend_wire_arrival_incomplete')
        end = [r for r in flow if r.get('event') in ('response-close', 'request-close') and
               (r.get('kind') == 'reset' or r['event'] == 'response-close')]
        statuses = [r['status'] for r in flow if r.get('event') == 'response-headers']
        record = {'request_id': head['request_id'], 'received_headers': head['headers'],
                  'arrival_kernel_epoch': first[0]['kernel_epoch'],
                  'capture_events': flow, 'response_status': statuses[0] if len(statuses) == 1 else None,
                  'completion': 'connection-ended' if end else 'unobserved',
                  'interval': [first[0]['kernel_epoch'], max(r['kernel_epoch'] for r in end) if end else None]}
        if head['kind'] == 'marked':
            if head['request_id'] in marked: raise ValueError('duplicate_backend_marker')
            marked[head['request_id']] = record
        elif head['kind'] == 'health':
            health.append(record)
    if set(marked) != {r['request_id'] for r in requests}:
        raise ValueError('backend_wire_request_ids')
    for record in marked.values():
        start, end = record['interval']
        record['possibly_overlapping_health'] = [r['interval'] for r in health
            if (end is None or r['interval'][0] <= end) and (r['interval'][1] is None or start <= r['interval'][1])]
    return {'boundary': 'backend interface; CGI execution/completion not established',
            'requests': list(marked.values()), 'health_connections': len(health),
            'no_payload_connections': no_payload}


def diagnostic_coverage(before_path, after_path, samples_path, requests_path, receipt, owner_log=False):
    """No causal attribution: prove coverage and report ambiguous event association."""
    before, after = (json.loads(workload.private(path, 65536)) for path in (before_path, after_path))
    samples = workload.rows(samples_path)
    wire = None
    requests = request_records(requests_path) if owner_log else json.loads(workload.private(requests_path))
    if set(before) not in ({'backend', 'node-a'}, {'backend', 'node-a', 'node-b'}) or set(after) != set(before):
        raise ValueError('clock_hosts')
    if owner_log and set(before) == {'backend', 'node-a'}:
        directory = samples_path.parent
        direct = json.loads(workload.private(directory / 'backend-path-a-ipv4.json'))
        timing = json.loads(direct['client']['stdout'])['timing']
        requests.append(dict(request_id=timing['request_id'], node='node-a', boot_id=timing['boot_id'],
                             start=timing['start'], end=timing['end']))
        wire = backend_wire_evidence(directory / 'backend-wire.jsonl', requests)
    if not samples or not samples[-1].get('terminal') or not requests:
        raise ValueError('diagnostic_incomplete')
    readings = samples[:-1]
    if len(readings) < 2: raise ValueError('resource_samples_missing')
    boot = readings[0]['boot_id']
    if any(row.get('clock') != 'linux-boottime' for row in readings): raise ValueError('resource_clock_source')
    if any(row['boot_id'] != boot for row in readings): raise ValueError('resource_boot_changed')
    times = [row['monotonic'] for row in readings]
    if any(not 0 < right-left <= 2 for left, right in zip(times, times[1:])):
        raise ValueError('resource_sample_gap')
    if wire and any(not times[0] <= event['observed_boottime'] <= times[-1]
                    for request in wire['requests'] + wire['no_payload_connections']
                    for event in request['capture_events']):
        raise ValueError('backend_wire_outside_resource_coverage')
    mapped = [clock_interval(row['monotonic'], boot, before['backend'], after['backend']) for row in readings]
    result = []
    seen = set()
    for request in requests:
        identity = request['request_id']; host = request['node']
        if not re.fullmatch('[0-9a-f]{32}', identity) or identity in seen or host not in before or host not in ('node-a', 'node-b'):
            raise ValueError('request_identity')
        seen.add(identity)
        start = clock_interval(request['start'], request['boot_id'], before[host], after[host])
        end = clock_interval(request['end'], request['boot_id'], before[host], after[host])
        if request['end'] < request['start'] or not mapped[0][1] <= start[0] <= end[1] <= mapped[-1][0]:
            raise ValueError('request_outside_resource_coverage')
        overlaps = []
        for index, row in enumerate(readings[1:], 1):
            if mapped[index][1] >= start[0] and mapped[index-1][0] <= end[1]:
                deltas = row.get('event_delta', {})
                if set(deltas) != {'webmin.service', 'uptime-kuma.service'} or any(v.get('status') != 'comparable' for v in deltas.values()):
                    raise ValueError('resource_delta_unknown')
                overlaps.append({'sample_index': index, 'events': deltas})
        if not overlaps: raise ValueError('resource_overlap_missing')
        result.append({'request_id': identity, 'estimated_controller_interval': [start[0], end[1]],
                       'clock_uncertainty_seconds': max(start[1]-start[0], end[1]-end[0]),
                       'possible_event_intervals': overlaps})
    workload.write(receipt, {'coverage_accepted': True, 'causal_attribution': False,
                            'clock_model': 'envelope of measured pre/post offsets; intervening drift unobserved',
                            'requests': result, 'backend_wire': wire})

if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['ready', 'finish', 'clock', 'diagnostic-coverage', 'admit-evidence']); parser.add_argument('path', type=Path)
    parser.add_argument('receipt', type=Path, nargs='?')
    parser.add_argument('--owner-log', action='store_true')
    parser.add_argument('--after', type=Path); parser.add_argument('--samples', type=Path); parser.add_argument('--requests', type=Path)
    parser.add_argument('--owner-exit', type=Path)
    parser.add_argument('--workload-result', type=Path); args = parser.parse_args()
    try:
        if args.action == 'admit-evidence': admit_evidence(args.path)
        elif args.action == 'clock': clock_capture(args.path, args.receipt)
        elif args.action == 'diagnostic-coverage': diagnostic_coverage(args.path, args.after, args.samples, args.requests, args.receipt, args.owner_log)
        elif args.action == 'ready': ready(args.path, args.receipt, args.owner_exit)
        else: finish(args.path, args.workload_result)
    except OwnerExited:
        print('owner_already_ended'); raise SystemExit(2)
    except Exception as error:
        code = str(error) if re.fullmatch('[a-z_]{1,64}', str(error)) else 'unavailable'
        if args.action == 'diagnostic-coverage' and args.receipt and not args.receipt.exists():
            workload.write(args.receipt, {'coverage_accepted': False, 'failure': code})
        print(json.dumps({'failure_type': type(error).__name__, 'code': code})); raise SystemExit(1)
