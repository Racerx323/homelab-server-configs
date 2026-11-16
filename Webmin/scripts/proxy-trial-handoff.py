#!/usr/bin/env python3
"""Local Caddy owner readiness/finish handoff; never a release publisher."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re

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


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['ready', 'finish']); parser.add_argument('path', type=Path)
    parser.add_argument('receipt', type=Path, nargs='?')
    parser.add_argument('--owner-exit', type=Path)
    parser.add_argument('--workload-result', type=Path); args = parser.parse_args()
    try:
        ready(args.path, args.receipt, args.owner_exit) if args.action == 'ready' else finish(args.path, args.workload_result)
    except OwnerExited:
        print('owner_already_ended'); raise SystemExit(2)
    except Exception as error:
        print(type(error).__name__); raise SystemExit(1)
