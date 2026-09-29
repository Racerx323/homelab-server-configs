#!/usr/bin/env python3
"""Target entrypoint for a separately authorized, hash-reviewed observation."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true', required=True)
    parser.parse_args()
    if os.geteuid() != 0:
        raise RuntimeError('root_required')
    sys.dont_write_bytecode = True
    bundle = Path(__file__).resolve().parent
    checks = json.loads((bundle / 'checksums.json').read_text())
    expected = {'observer.py', 'start.py', 'operation.json', 'PROCEDURE.md'}
    if set(checks) != expected:
        raise RuntimeError('unexpected_bundle_members')
    for name, digest in checks.items():
        path = bundle / name
        if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise RuntimeError('bundle_hash_mismatch: ' + name)
    spec = json.loads((bundle / 'operation.json').read_text())
    stage = Path(spec['remote_stage'])
    unit = spec['unit']
    if stage != Path('/var/lib/webmin-discovery-observation') or unit != 'webmin-discovery-observation':
        raise RuntimeError('unexpected_owned_paths')
    if stage.exists() or stage.is_symlink():
        raise RuntimeError('existing_operation_requires_review')
    module_spec = importlib.util.spec_from_file_location('passive_observer', bundle / 'observer.py')
    observer = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(observer)
    if observer.run(['systemctl', 'show', unit + '.service', '-p', 'LoadState']).strip() != 'LoadState=not-found':
        raise RuntimeError('existing_observer_unit')
    processes = observer.run(['ps', '-eo', 'comm'])
    if any(line.strip() in ('strace', 'trace-cmd', 'bpftrace') for line in processes.splitlines()):
        raise RuntimeError('concurrent_tracer_requires_review')
    units = observer.run(['systemctl', 'list-units', '--state=active,activating', '--no-legend', '--plain', '--no-pager'])
    if any('webmin' in line and any(word in line for word in ('polling', 'observation', 'qualification')) for line in units.splitlines()):
        raise RuntimeError('concurrent_webmin_observer_requires_review')
    baseline = observer.collect(spec, time.time() - spec['interval_seconds'])
    observer.validate(spec, baseline, baseline)
    os.umask(0o077)
    stage.mkdir(mode=0o700)
    root = stage / 'evidence'
    root.mkdir(mode=0o700)
    for name in checks:
        shutil.copyfile(bundle / name, stage / name)
    shutil.copyfile(bundle / 'checksums.json', stage / 'checksums.json')
    observer.write(root / 'launch-preflight.json', baseline)
    # Exact configuration preservation is private and never used to change it.
    for name in spec['files']:
        if name.startswith('/etc/'):
            dest = root / 'configuration' / name.lstrip('/')
            dest.parent.mkdir(parents=True, exist_ok=True)
            data = observer.read(name)
            if hashlib.sha256(data).hexdigest() != spec['files'][name]:
                observer.alert(root, 'configuration_changed_during_start')
                raise RuntimeError('configuration_changed_during_start')
            dest.write_bytes(data)
    cmd = ['systemd-run', '--quiet', '--unit=' + unit,
           '--property=Type=notify', '--property=NotifyAccess=main', '--property=WatchdogSec=180s',
           '--property=RuntimeMaxSec=87000s', '--property=TimeoutStartSec=90s',
           '--property=TimeoutStopSec=30s', '--property=Restart=no', '--property=UMask=0077',
           '--property=ExecStopPost=/usr/bin/python3 ' + str(stage / 'observer.py') + ' finalize ' + str(root),
           '/usr/bin/python3', str(stage / 'observer.py'), 'observe', str(stage / 'operation.json'), str(root)]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=100)
        observer.write(root / 'launch.json', {'status': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
        if result.returncode:
            raise RuntimeError('observer_start_failed')
    except Exception as exc:
        observer.alert(root, str(exc))
        raise
    print('Passive observation started; inspect private checkpoint and result records.')


if __name__ == '__main__':
    main()
