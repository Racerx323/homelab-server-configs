#!/usr/bin/env python3
"""Render a bounded controller service; never install, start, or retry it."""
import argparse
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]


def identity(approval):
    if not re.fullmatch(r'[0-9a-f]{64}', approval):
        raise ValueError('approval_identity')
    return 'nautobot-workload-' + approval[:24]


def safe_path(path):
    path = Path(path)
    if not path.is_absolute() or '..' in path.parts or any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError('unsafe_path')
    # No systemd specifiers, environment substitution or command-line escapes.
    if not re.fullmatch(r'/[A-Za-z0-9_./-]+', str(path)):
        raise ValueError('unsafe_path')
    return path


def persistent_path(path):
    path = safe_path(path)
    if any(path.is_relative_to(p) for p in ('/tmp', '/var/tmp', '/run', '/dev', '/proc', '/sys')):
        raise ValueError('volatile_evidence')
    return path


def private_directory(path):
    path = safe_path(path)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError('directory_metadata')
    return path


def receipt(path, value):
    """Exclusive, durable, private receipt; never overwrite a prior invocation."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(value, stream, sort_keys=True)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def runtime(approval):
    expected = Path('/run/user') / str(os.getuid()) / identity(approval)
    if os.environ.get('RUNTIME_DIRECTORY') != str(expected) or not re.fullmatch(r'[0-9a-f]{32}', os.environ.get('INVOCATION_ID', '')):
        raise ValueError('supervised_controller_required')
    private_directory(expected)
    for argv, required in (
        (['/usr/bin/loginctl', 'show-user', str(os.getuid()), '--property=Linger', '--value'], 'yes'),
        (['/usr/bin/findmnt', '--noheadings', '--output', 'FSTYPE', '--target', str(expected)], 'tmpfs'),
    ):
        result = subprocess.run(argv, capture_output=True, text=True, timeout=10, check=True)
        if result.stdout.strip() != required:
            raise ValueError('controller_linger_or_runtime_filesystem')
    return expected


def render(bundle, approval, evidence, ssh_socket):
    name = identity(approval)
    bundle, evidence = safe_path(bundle), persistent_path(evidence)
    safe_path(ROOT)
    private_directory(evidence.parent)
    if evidence.exists():
        raise ValueError('evidence_already_exists')
    ssh_socket = safe_path(ssh_socket)
    launcher = ROOT / 'Nautobot/ansible/scripts/run-workload.py'
    helper = Path(__file__).resolve()
    return f'''[Unit]
Description=Bounded Nautobot workload controller
ConditionPathExists=!{evidence}/controller-started.json

[Service]
Type=exec
WorkingDirectory={ROOT}
UMask=0077
Restart=no
RuntimeMaxSec=12000
TimeoutStopSec=45
KillMode=control-group
RuntimeDirectory={name}
RuntimeDirectoryMode=0700
RuntimeDirectoryPreserve=no
Environment=SSH_AUTH_SOCK={ssh_socket}
StandardOutput=null
StandardError=null
ExecStart=/usr/bin/python3 {launcher} --bundle {bundle} --approve {approval} --evidence {evidence} --resolve-doppler
ExecStopPost=/usr/bin/python3 {helper} --record-stop --approve {approval} --evidence {evidence}
'''


def record_stop(approval, evidence):
    """Manager exit is not remote acceptance or proof of cleanup."""
    evidence = private_directory(persistent_path(evidence))
    started = json.loads((evidence / 'controller-started.json').read_text())
    if started['approval'] != approval or started['invocation_id'] != os.environ.get('INVOCATION_ID'):
        raise ValueError('invocation_mismatch')
    fields = {}
    for key in ('SERVICE_RESULT', 'EXIT_CODE', 'EXIT_STATUS'):
        value = os.environ.get(key, 'unavailable')
        fields[key.lower()] = value if re.fullmatch(r'[A-Za-z0-9_-]{1,64}', value) else 'invalid'
    receipt(evidence / 'controller-stop.json', {
        'approval': approval, **fields, 'acceptance': 'requires_independent_review',
        'runtime_cleanup': 'verify_absence_after_unit_stops',
    })


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path)
    parser.add_argument('--approve', required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--ssh-socket', type=Path)
    parser.add_argument('--record-stop', action='store_true')
    args = parser.parse_args()
    identity(args.approve)
    if args.record_stop:
        record_stop(args.approve, args.evidence)
    else:
        if not args.bundle or not args.ssh_socket:
            parser.error('--bundle and --ssh-socket are required for rendering')
        print(render(args.bundle, args.approve, args.evidence, args.ssh_socket), end='')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError):
        print('controller_contract_failed', file=sys.stderr)
        sys.exit(1)
