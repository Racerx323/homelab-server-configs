#!/usr/bin/env python3
"""Execution-time read-only host comparison before credentials or restore load."""
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('restore_baseline', Path(__file__).with_name('persistence-preflight.py'))
baseline = importlib.util.module_from_spec(spec); spec.loader.exec_module(baseline)


def assess(current, expected):
    if current['host'] != 'j2-svpi4mf' or current['boot_id'] != expected['boot_id']:
        raise ValueError('baseline_identity')
    if not baseline.assess(current)['preconditions_observed']:
        raise ValueError('runtime_preconditions')
    for role, row in expected['services'].items():
        if current['persistence_services'][role] != row: raise ValueError('service_drift')
    observed = {}
    for key, prefix in (('runtime_files','/var/lib/nautobot/runtime/'),
                        ('quadlets','/var/lib/nautobot/.config/containers/systemd/')):
        for name, row in current[key].items():
            if 'sha256' in row:
                if not row['regular'] or row['uid'] != 999 or row['mode'] != ('0o644' if key == 'runtime_files' else '0o600'):
                    raise ValueError('artifact_metadata')
                observed[prefix+name] = row['sha256']
    if observed != expected['artifact_sha256']: raise ValueError('artifact_drift')


def main():
    op = json.loads(Path(sys.argv[1]).read_text())
    current = baseline.collect()
    assess(current, op['baseline'])
    command = baseline.baseline.command
    if command(['/usr/bin/uname','-m']).strip() != 'aarch64': raise ValueError('architecture')
    if command(['/usr/bin/restic','version']).strip() != op['restic_version']: raise ValueError('restic_version')
    if command(baseline.baseline.USER+['/usr/bin/podman','--version']).strip() != 'podman version 5.4.2':
        raise ValueError('podman_version')
    print(json.dumps({'preflight_passed':True,'accepted':False,'boot_id':current['boot_id']}))


if __name__ == '__main__':
    try: main()
    except Exception as error:
        print(json.dumps({'preflight_passed':False,'failure_class':type(error).__name__}))
        raise SystemExit(1)
