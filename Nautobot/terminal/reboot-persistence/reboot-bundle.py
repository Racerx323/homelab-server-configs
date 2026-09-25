#!/usr/bin/env python3
"""Freeze a reboot contract and dispatch it once from a durable supervisor."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
FILES = {
    'reboot-access.py': 'Nautobot/ansible/scripts/reboot-access.py',
    'reboot-bundle.py': 'Nautobot/ansible/scripts/reboot-bundle.py',
    'reboot-node.py': 'Nautobot/ansible/scripts/reboot-node.py',
    'preservation-node.py': 'Nautobot/ansible/scripts/preservation-node.py',
    'recovery_probe.py': 'Nautobot/ansible/scripts/recovery_probe.py',
    'logical_database.py': 'Nautobot/ansible/scripts/logical_database.py',
    'workload_capture.py': 'Nautobot/ansible/scripts/workload_capture.py',
    'logout-node.py': 'Nautobot/ansible/scripts/logout-node.py',
    'workload_controller.py': 'Nautobot/ansible/scripts/workload_controller.py',
    'playbook.yaml': 'Nautobot/ansible/playbooks/reboot-persistence.yaml',
    'reboot-stage.yaml': 'Nautobot/ansible/playbooks/reboot-stage.yaml',
    'reboot-quiesce.yaml': 'Nautobot/ansible/playbooks/reboot-quiesce.yaml',
    'schema.json': 'Nautobot/schemas/reboot-execution.schema.json',
    'PLAN.md': 'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md',
    'OPERATIONS.md': 'Nautobot/docs/OPERATIONS.md',
    'accepted-state.yaml': 'Nautobot/manifests/accepted-live-state.yaml',
    'ansible.cfg': 'Nautobot/ansible/ansible.cfg',
    'ansible-temp.sh': 'tests/repository/run-with-ansible-local-temp.sh',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(op, schema):
    from jsonschema import Draft202012Validator, FormatChecker
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(op)
    if op['root'] != '/tmp/nautobot-reboot.' + op['token']:
        raise ValueError('root_token')
    if any(op['image_ids'][r] != op['app_image_id'] for r in ('web', 'worker', 'scheduler')):
        raise ValueError('image_set')


def freeze(operation, destination, logical):
    op = json.loads(operation.read_text())
    validate(op, json.loads((ROOT/FILES['schema.json']).read_text()))
    if sha(logical) != op['preserved_logical_sha256']:
        raise ValueError('preserved_receipt_identity')
    destination.mkdir(mode=0o700, exist_ok=False)
    for name, source in FILES.items():
        shutil.copyfile(ROOT/source, destination/name)
    shutil.copyfile(logical, destination/'preserved-logical.json')
    (destination/'reboot.json').write_text(json.dumps(op, sort_keys=True)+'\n')
    (destination/'inventory.ini').write_text('[inventory_automation]\nj2-svpi4mf ansible_host=10.1.2.170 ansible_user=ama\n')
    manifest = {'schema_version': 1, 'files': {p.name: sha(p) for p in sorted(destination.iterdir())}}
    (destination/'bundle.json').write_text(json.dumps(manifest, sort_keys=True)+'\n')
    identity = sha(destination/'bundle.json')
    verify(destination, identity, executing=False)
    return identity


def verify(bundle, approval, executing=True):
    import yaml
    if bundle.is_symlink() or sha(bundle/'bundle.json') != approval:
        raise ValueError('bundle_identity')
    manifest = json.loads((bundle/'bundle.json').read_text())
    names = set(FILES) | {'reboot.json', 'preserved-logical.json', 'inventory.ini'}
    if set(manifest['files']) != names or {p.name for p in bundle.iterdir()} != names | {'bundle.json'}:
        raise ValueError('bundle_membership')
    for name, digest in manifest['files'].items():
        p = bundle/name
        if p.is_symlink() or not p.is_file() or sha(p) != digest:
            raise ValueError('bundle_drift')
    op = json.loads((bundle/'reboot.json').read_text())
    validate(op, json.loads((bundle/'schema.json').read_text()))
    if sha(bundle/'PLAN.md') != op['plan_sha256'] or sha(bundle/'accepted-state.yaml') != op['accepted_state_sha256']:
        raise ValueError('authority_drift')
    accepted = yaml.safe_load((bundle/'accepted-state.yaml').read_text())['recovery_preservation']
    if accepted['snapshot_id'] != op['snapshot_id'] or accepted['logical_before_sha256'] != op['preserved_logical_sha256'] or sha(bundle/'preserved-logical.json') != op['preserved_logical_sha256']:
        raise ValueError('recovery_identity')
    if executing:
        if sha(Path(__file__)) != manifest['files']['reboot-bundle.py']:
            raise ValueError('launcher_drift')
        if yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text()) != op or not op['operation']['authorization_ready']:
            raise ValueError('inactive_operation')
        age = (datetime.now(timezone.utc)-datetime.fromisoformat(op['baseline_collected_at'])).total_seconds()
        if not 0 <= age <= 86400:
            raise ValueError('baseline_expired')
        commit = op['operation']['source_commit']
        if op['ci_success_commit'] != commit:
            raise ValueError('ci_unverified')
        for name, source in FILES.items():
            raw = subprocess.run(['git', 'show', commit+':'+source], cwd=ROOT, capture_output=True, check=True, timeout=10).stdout
            if hashlib.sha256(raw).hexdigest() != manifest['files'][name]:
                raise ValueError('uncommitted_source')
    return manifest, op


def arm(evidence):
    # Exclusive durable receipt survives controller restart. A restart never resumes
    # the playbook or resends a potentially delivered request.
    for name in ('before', 'drain-before', 'logical-before', 'logical-before-verified'):
        p = evidence/(name+'.json')
        if p.is_symlink() or not p.is_file():
            raise ValueError('missing_preboot_evidence')
        with p.open('rb') as stream:
            os.fsync(stream.fileno())
    if json.loads((evidence/'logical-before-verified.json').read_text()) != {'equal': True}:
        raise ValueError('logical_comparison_failed')
    fd = os.open(evidence/'reboot-intent.json', os.O_CREAT|os.O_EXCL|os.O_WRONLY|os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump({'single_attempt': True, 'accepted': False}, stream)
        stream.flush()
        os.fsync(stream.fileno())
    directory = os.open(evidence, os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def controller_unit(bundle, approval, evidence):
    verify(bundle, approval, executing=False)
    sys.path.insert(0, str(bundle))
    import workload_controller as controller
    for path in (bundle, evidence, ROOT):
        controller.safe_path(path)
    controller.persistent_path(evidence)
    controller.private_directory(evidence.parent)
    if evidence.exists():
        raise ValueError('evidence_already_exists')
    socket = os.environ.get('SSH_AUTH_SOCK')
    environment = ''
    if socket:
        controller.safe_path(socket)
        environment = 'Environment=SSH_AUTH_SOCK=' + socket + '\n'
    return ('[Unit]\nDescription=Bounded Nautobot reboot qualification\n'
            '[Service]\nType=exec\nRestart=no\nKillMode=control-group\n'
            'TimeoutStopSec=30\nRuntimeMaxSec=4500\nUMask=0077\nLimitFSIZE=8388608\n'
            + environment + 'ExecStart=/usr/bin/python3 ' + str(ROOT/'Nautobot/ansible/scripts/reboot-bundle.py')
            + ' execute --bundle ' + str(bundle) + ' --approve ' + approval + ' --evidence ' + str(evidence) + '\n')


def execute(bundle, approval, evidence):
    manifest, op = verify(bundle, approval)
    if not re.fullmatch('[0-9a-f]{32}', os.environ.get('INVOCATION_ID', '')):
        raise ValueError('supervised_controller_required')
    sys.path.insert(0, str(bundle))
    import workload_controller as controller
    controller.persistent_path(evidence)
    controller.private_directory(evidence.parent)
    if subprocess.run(['/usr/bin/loginctl', 'show-user', str(os.getuid()), '-p', 'Linger', '--value'], capture_output=True, text=True, check=True, timeout=10).stdout.strip() != 'yes':
        raise ValueError('controller_linger_required')
    search = os.pathsep.join((str(Path.home()/'.local/bin'), os.defpath))
    ansible = shutil.which('ansible-playbook', path=search)
    if not ansible:
        raise ValueError('ansible_unavailable')
    evidence.mkdir(mode=0o700, exist_ok=False)
    inputs = {'reboot_verified': True, 'reboot_execution_authorized': True,
              'reboot_root': op['root'], 'reboot_original_boot': op['boot_id'],
              'reboot_bundle': str(bundle), 'reboot_evidence': str(evidence),
              'reboot_files': [{'name': n, 'source': str(bundle/n), 'sha256': d} for n, d in manifest['files'].items()]}
    config = evidence/'ansible-inputs.json'
    config.write_text(json.dumps(inputs)); config.chmod(0o600)
    env = {k: v for k, v in os.environ.items() if k in ('HOME', 'USER', 'LOGNAME', 'SSH_AUTH_SOCK', 'LANG', 'LC_ALL')}
    env.update(PATH=search, ANSIBLE_CONFIG=str(bundle/'ansible.cfg'), PYTHONDONTWRITEBYTECODE='1')
    status = None
    try:
        def limits():
            resource.setrlimit(resource.RLIMIT_FSIZE, (8388608, 8388608))
        with (evidence/'ansible.log').open('xb') as out:
            status = subprocess.run(['/bin/bash', str(bundle/'ansible-temp.sh'), ansible,
                '-i', str(bundle/'inventory.ini'), str(bundle/'playbook.yaml'), '--extra-vars', '@'+str(config)],
                cwd=bundle, env=env, stdout=out, stderr=out, timeout=4200, preexec_fn=limits).returncode
    finally:
        controller.receipt(evidence/'controller-result.json', {'ansible_status': status, 'accepted': False,
            'review_required': True, 'automatic_retry': False})
    return status


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    subs = parser.add_subparsers(dest='action', required=True)
    f = subs.add_parser('freeze')
    for name in ('operation', 'destination', 'logical'):
        f.add_argument('--'+name, type=Path, required=True)
    a = subs.add_parser('arm'); a.add_argument('--evidence', type=Path, required=True)
    c = subs.add_parser('controller')
    c.add_argument('--bundle', type=Path, required=True); c.add_argument('--approve', required=True)
    c.add_argument('--evidence', type=Path, required=True)
    e = subs.add_parser('execute')
    e.add_argument('--bundle', type=Path, required=True); e.add_argument('--approve', required=True)
    e.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    if args.action == 'freeze':
        print(freeze(args.operation, args.destination, args.logical))
    elif args.action == 'controller':
        print(controller_unit(args.bundle, args.approve, args.evidence), end='')
    elif args.action == 'arm':
        arm(args.evidence)
    else:
        raise SystemExit(execute(args.bundle, args.approve, args.evidence))
