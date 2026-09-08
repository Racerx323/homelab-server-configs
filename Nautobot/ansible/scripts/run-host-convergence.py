#!/usr/bin/env python3
"""Fail-closed controller for the separately authorized read-only preflight."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import stat
import subprocess
import tempfile
import time

import yaml

ROOT = Path(__file__).resolve().parents[3]
PREFIX = 'nautobot-host-convergence.'
BUNDLE_FILES = (
    'Nautobot/manifests/operation.yaml',
    'Nautobot/schemas/operation.schema.json',
    'Nautobot/schemas/host-convergence.schema.json',
    'Nautobot/ansible/playbooks/preflight-host-convergence.yaml',
    'Nautobot/ansible/scripts/run-host-convergence.py',
    'Nautobot/ansible/scripts/evaluate-host-convergence.py',
    'Nautobot/ansible/scripts/validate-host-convergence.py',
    'Nautobot/docs/HOST_BASELINE_CONVERGENCE.md',
    'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md',
    'inventory/prod/hosts.yaml',
    'inventory/prod/groups/inventory_automation.yaml',
    'inventory/prod/hosts/j2-svpi4mf.yaml',
)


def command(root):
    return ('ansible-playbook', '--inventory', str(ROOT/'inventory/prod/hosts.yaml'),
            '--limit', 'j2-svpi4mf', '--user', 'ama', '--extra-vars', 'ansible_host=10.1.2.170',
            '--extra-vars', f'convergence_evidence_directory={root}',
            str(ROOT/'Nautobot/ansible/playbooks/preflight-host-convergence.yaml'))


def write(root, name, value):
    path = root/name
    with path.open('x', encoding='utf-8') as stream:
        os.chmod(path, 0o600)
        stream.write(value)


def cleanup_temp(root):
    """Remove only this launcher's mode-checked controller temporary child."""
    info = root.lstat()
    if (root.parent != Path('/tmp') or not root.name.startswith(PREFIX)
            or not stat.S_ISDIR(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o700
            or info.st_uid != os.getuid()):
        raise ValueError('unsafe_evidence_root')
    child = root/'ansible-local'
    if child.is_symlink():
        raise ValueError('unsafe_temporary_child')
    if child.exists():
        info = child.lstat()
        if (not stat.S_ISDIR(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o700
                or info.st_uid != os.getuid()):
            raise ValueError('unsafe_temporary_child')
        shutil.rmtree(child)
    return not child.exists()


def capture(argv, root, environment, timeout=1200, limit=4 * 1024 * 1024):
    """Bound both streams and retain partial observations on timeout/overflow."""
    buffers = {'stdout': bytearray(), 'stderr': bytearray()}
    process = None
    error = None
    status = None
    selector = selectors.DefaultSelector()
    try:
        process = subprocess.Popen(argv, cwd=ROOT, env=environment, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        selector.register(process.stdout, selectors.EVENT_READ, 'stdout')
        selector.register(process.stderr, selectors.EVENT_READ, 'stderr')
        deadline = time.monotonic() + timeout
        while selector.get_map():
            remaining = deadline-time.monotonic()
            if remaining <= 0:
                error = 'timeout'
                break
            for key, _ in selector.select(min(remaining, 1)):
                chunk = os.read(key.fileobj.fileno(), 8192)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                target = buffers[key.data]
                room = limit-len(target)
                target.extend(chunk[:room])
                if len(chunk) > room:
                    error = 'output_limit'
                    break
            if error:
                break
        if error is None:
            status = process.wait(timeout=max(0.01, deadline-time.monotonic()))
    except subprocess.TimeoutExpired:
        error = 'timeout'
    except OSError:
        error = 'process_error'
    finally:
        if process is not None:
            # Also terminate descendants that inherited the capture pipes.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            status = process.wait()
            process.stdout.close()
            process.stderr.close()
        selector.close()
        for name, value in buffers.items():
            with (root/f'ansible.{name}').open('xb') as stream:
                os.chmod(stream.name, 0o600)
                stream.write(value)
        write(root, 'process.json', json.dumps({'status':status,'error':error})+'\n')
    return status, error


def execute(authorized_hash):
    document = yaml.safe_load((ROOT/BUNDLE_FILES[0]).read_text())
    # Readiness rejection precedes hashes, local evidence creation and transport.
    if (document['operation']['id'] != 'nautobot-host-baseline-convergence-v1'
            or document['operation']['authorization_ready'] is not True
            or document['preflight']['execution_authorized'] is not True
            or document['authorization']['mutation_authorized'] is not False
            or document['authorization']['blockers'] or document['mutations']['ordered']):
        raise ValueError('unready_read_only_preflight')
    subprocess.run(['check-jsonschema','--schemafile',str(ROOT/BUNDLE_FILES[1]),str(ROOT/BUNDLE_FILES[0])],
                   check=True, timeout=30, stdout=subprocess.DEVNULL)
    if subprocess.check_output(['git','status','--porcelain'], cwd=ROOT, timeout=30):
        raise ValueError('dirty_worktree')
    rows = []
    for relative in BUNDLE_FILES:
        path = ROOT/relative
        if path.is_symlink() or not path.is_file():
            raise ValueError('unsafe_bundle_input')
        rows.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {relative}\n')
    payload = 'nautobot-host-convergence-bundle-v1\n'+''.join(rows)
    digest = hashlib.sha256(payload.encode()).hexdigest()
    if digest != authorized_hash:
        raise ValueError('authorization_hash_mismatch')
    root = Path(tempfile.mkdtemp(prefix=PREFIX, dir='/tmp'))
    root.chmod(0o700)
    write(root, 'bundle-inputs.txt', payload)
    (root/'ansible-local').mkdir(mode=0o700)
    environment = {k:os.environ[k] for k in ['HOME','PATH','SSH_AUTH_SOCK'] if k in os.environ}
    environment.update(LC_ALL='C', ANSIBLE_LOCAL_TEMP=str(root/'ansible-local'))
    status, error = None, 'incomplete'
    clean = False
    try:
        status, error = capture(command(root), root, environment)
    finally:
        try:
            clean = cleanup_temp(root)
        finally:
            write(root, 'terminal.json', json.dumps({'status':status,'error':error,'cleanup_passed':clean,
                  'accepted_live_state_written':False,'mutation_attempted':False})+'\n')
    print(f'evidence_root={root}')
    return 0 if status == 0 and error is None and clean else 69


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['show-command','execute'])
    parser.add_argument('authorized_hash', nargs='?')
    args = parser.parse_args()
    if args.mode == 'show-command':
        print(json.dumps(command('REVIEWED_PROTECTED_DIRECTORY')))
        return 0
    try:
        return execute(args.authorized_hash)
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        print(f'blocked: {type(exc).__name__}')
        return 69


if __name__ == '__main__':
    raise SystemExit(main())
