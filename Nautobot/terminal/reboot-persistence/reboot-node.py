#!/usr/bin/env python3
"""Bounded reboot observations; Ansible alone owns writer transitions/reboot."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import time

spec = importlib.util.spec_from_file_location('preservation', Path(__file__).with_name('preservation-node.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


REASONS = frozenset(("http_health", "service_set", "service_state", "application_login_session",
    "logical_identity_changed", "invocation_identity", "native_receipt_count", "native_receipt_shape",
    "native_receipt_failed", "boot_identity", "kernel_identity", "image_identity", "stale_invocation",
    "boot_gate_state", "journal_cursor", "root_identity", "target", "drain_receipt", "media_changed",
    "final_boot", "settlement_drift", "storage_error", "automatic_startup_timeout"))


def require(value, reason):
    if not value:
        raise ValueError(reason)


def healthy(sample):
    require(sample['http_status'] == '200', 'http_health')
    require(set(sample['units']) == {'nautobot-' + r + '.service' for r in p.node.ROLES}, 'service_set')
    for row in sample['units'].values():
        require(row['ActiveState'] == 'active' and row['SubState'] == 'running'
                and row['Result'] == 'success' and row['NRestarts'] == '0', 'service_state')
    require(all(p.node.manager(s) for s in sample['sessions'].values()), 'application_login_session')


def compare(reference, current):
    require(p.logical_database.compare(reference, current)['equal'], 'logical_identity_changed')


def native_receipt(raw, role, invocation):
    require(re.fullmatch('[0-9a-f]{32}', invocation), 'invocation_identity')
    rows = []
    for line in raw.splitlines():
        message = json.loads(line).get('MESSAGE', '')
        if message.startswith('NAUTOBOT_STARTUP_RESULT='):
            value = json.loads(message.split('=', 1)[1])
            if isinstance(value, dict) and value.get('invocation') == invocation:
                rows.append(value)
    require(len(rows) == 1, 'native_receipt_count')
    row = rows[0]
    expected = {'configuration', 'pending_migrations'}
    if role == 'web':
        expected.add('static_collection')
    require(row.get('role') == role and row.get('passed') is True
            and isinstance(row.get('steps'), dict) and set(row['steps']) == expected,
            'native_receipt_shape')
    require(all(isinstance(v, dict) and type(v.get('exit_status')) is int
                and v['exit_status'] == 0 and not v.get('error')
                and v.get('output_limited') is False for v in row['steps'].values()), 'native_receipt_failed')
    return {'role': role, 'invocation': invocation, 'passed': True}


def running(root, op, postboot=False):
    p.verify_artifacts(op)
    sample = p.node.snapshot()
    healthy(sample)
    require((sample['boot_id'] != op['boot_id']) if postboot else
            (sample['boot_id'] == op['boot_id']), 'boot_identity')
    require(p.bounded(['/usr/bin/uname', '-r']).decode().strip() == op['expected_kernel'], 'kernel_identity')
    for role in p.node.ROLES:
        image = p.pod(['inspect', '--format', '{{.Image}}', 'nautobot-' + role]).decode().strip()
        if not image.startswith('sha256:'):
            image = 'sha256:' + image
        require(image == op['image_ids'][role], 'image_identity')
    media = p.capture.empty_media()
    if postboot:
        old = p.load(root, 'before')['sample']
        for name, row in sample['units'].items():
            require(row['InvocationID'] != old['units'][name]['InvocationID'], 'stale_invocation')
        raw = p.bounded(p.node.USER + ['/usr/bin/systemctl', '--user', 'show',
            'nautobot-migration.service', '--property=ActiveState,SubState,Result,InvocationID']).decode()
        gate = p.node.pairs(raw)
        require(gate.get('ActiveState') == 'active' and gate.get('SubState') == 'exited'
                and gate.get('Result') == 'success', 'boot_gate_state')
        receipts = []
        for role in ('migration', 'web', 'worker', 'scheduler'):
            invocation = gate['InvocationID'] if role == 'migration' else sample['units']['nautobot-' + role + '.service']['InvocationID']
            raw = p.bounded(['/usr/bin/journalctl', 'CONTAINER_NAME=nautobot-' + role,
                '_UID=999', '-b', '-o', 'json', '--no-pager', '--quiet', '-n', '1000']).decode()
            receipts.append(native_receipt(raw, role, invocation))
        return {'sample': sample, 'media': media, 'native': receipts}
    cursor = p.bounded(['/usr/bin/journalctl', '-n', '0', '--show-cursor', '--no-pager']).decode()
    cursors = [s.removeprefix('-- cursor: ') for s in cursor.splitlines() if s.startswith('-- cursor: ')]
    require(len(cursors) == 1, 'journal_cursor')
    return {'sample': sample, 'media': media, 'cursor': cursors[0]}


def observe(root, op):
    deadline = time.monotonic() + 600
    last = 'not_ready'
    while time.monotonic() < deadline:
        try:
            result = running(root, op, True)
            p.save(root, 'automatic', result)
            return
        except Exception as error:
            last = str(error) if type(error) is ValueError and str(error) in REASONS else 'observation_failed'
            time.sleep(5)
    p.save(root, 'automatic-failure', {'reason': last, 'passed': False})
    raise ValueError('automatic_startup_timeout')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('phase', choices=['before', 'drain-before', 'drain-after', 'logical-before',
        'logical-after', 'automatic', 'final'])
    args = parser.parse_args()
    root = args.root
    require(re.fullmatch(r'/tmp/nautobot-reboot\.[0-9a-f]{32}', str(root)), 'root_identity')
    require(os.getuid() == 0 and p.bounded(['/usr/bin/hostname']).decode().strip() == 'j2-svpi4mf', 'target')
    op = p.load(root, 'reboot')
    if args.phase == 'before':
        p.save(root, 'before', running(root, op))
    elif args.phase.startswith('drain-'):
        code = (root/'recovery_probe.py').read_text() + "\nprint('REBOOT_DRAIN='+json.dumps(native_drain()))"
        raw = p.pod(p.drain_command(), data=code.encode(), timeout=240).decode()
        rows = [s.removeprefix('REBOOT_DRAIN=') for s in raw.splitlines() if s.startswith('REBOOT_DRAIN=')]
        require(len(rows) == 1, 'drain_receipt')
        p.save(root, args.phase, json.loads(rows[0]))
    elif args.phase.startswith('logical-'):
        current = p.logical(root, op, args.phase)
        compare(p.load(root, 'preserved-logical'), current)
        if args.phase == 'logical-after':
            compare(p.load(root, 'logical-before'), current)
        require(p.capture.empty_media() == p.load(root, 'before')['media'], 'media_changed')
        p.save(root, args.phase + '-verified', {'equal': True})
    elif args.phase == 'automatic':
        observe(root, op)
    else:
        deadline = time.monotonic() + 600
        while True:
            try:
                result = p.node.snapshot()
                healthy(result)
                break
            except Exception:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(5)
        expected_boot = p.load(root, 'automatic')['sample']['boot_id'] if (root/'automatic.json').exists() else op['boot_id']
        require(result['boot_id'] == expected_boot, 'final_boot')
        time.sleep(75)
        p.verify_artifacts(op)
        settled = p.node.snapshot()
        healthy(settled)
        require(settled['boot_id'] == result['boot_id'] and settled['units'] == result['units'], 'settlement_drift')
        journal = p.bounded(['/usr/bin/journalctl', '-k', '-b', '--no-pager']).decode()
        require(not p.node.STORAGE.search(journal), 'storage_error')
        p.save(root, 'final', {'healthy': True, 'sample': settled, 'accepted': False})


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Never publish command stderr or application exception text.
        print(json.dumps({'passed': False, 'failure_class': type(error).__name__,
            'reason': str(error) if type(error) is ValueError and str(error) in REASONS else p.safe_reason(error)}))
        raise SystemExit(69)
