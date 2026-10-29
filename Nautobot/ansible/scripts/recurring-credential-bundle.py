#!/usr/bin/env python3
"""Freeze one credential definition; run one playbook only with its approved hash."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import sys

import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[3]
DOPPLER = '/usr/bin/doppler'
FILES = {
    'launcher.py': 'Nautobot/ansible/scripts/recurring-credential-bundle.py',
    'recurring_credentials.py': 'Nautobot/ansible/scripts/recurring_credentials.py',
    'prerequisite_node.py': 'Nautobot/ansible/scripts/prerequisite_node.py',
    'recurring_delivery.py': 'Nautobot/ansible/scripts/recurring_delivery.py',
    'recurring_protection.py': 'Nautobot/ansible/scripts/recurring_protection.py',
    'playbook.yaml': 'Nautobot/ansible/playbooks/provision-recurring-credentials.yaml',
    'delivery.yaml': 'Nautobot/ansible/tasks/deliver-recurring-token.yaml',
    'qualification.json': 'Nautobot/manifests/recurring-credential-review.json',
    'schema.json': 'Nautobot/schemas/recurring-credentials.schema.json',
    'operation.yaml': 'Nautobot/manifests/operation.yaml',
    'accepted.yaml': 'Nautobot/manifests/accepted-live-state.yaml',
    'recurring.yaml': 'Nautobot/manifests/recurring-protection.yaml',
    'PLAN.md': 'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md',
    'OPERATIONS.md': 'Nautobot/docs/OPERATIONS.md',
    'ansible-temp.sh': 'tests/repository/run-with-ansible-local-temp.sh',
}
GENERATED = {'operation.json', 'accepted.json', 'inventory.ini', 'ansible.cfg', 'controller.json'}


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(root):
    op = json.loads((root / 'operation.json').read_text())
    Draft202012Validator(json.loads((root / 'schema.json').read_text())).validate(op)
    require(op == yaml.safe_load((root / 'operation.yaml').read_text()), 'operation_identity')
    accepted = json.loads((root / 'accepted.json').read_text())
    require(accepted == yaml.safe_load((root / 'accepted.yaml').read_text()), 'accepted_identity')
    require(op['plan_sha256'] == sha(root / 'PLAN.md'), 'plan_identity')
    require(all(accepted['recurring_prerequisites'][k] == v for k, v in op['accepted_prerequisite'].items()), 'prerequisite_identity')
    require(op['baseline']['artifact_sha256'] == accepted['application_startup']['artifact_sha256'], 'application_identity')
    policy = yaml.safe_load((root / 'recurring.yaml').read_text())['credentials']
    require(op['provider']['references'] == {k: '${' + v.replace('/', '.') + '}' for k, v in policy['canonical_references'].items()}, 'reference_identity')
    require(op['delivery']['token_file'] == policy['token_file'], 'token_path')
    return op


def freeze(root):
    op = yaml.safe_load((ROOT / FILES['operation.yaml']).read_text())
    require(op['operation'].get('stage') == 'recurring_credential_provisioning', 'operation_stage')
    root.mkdir(mode=0o700)
    for name, source in FILES.items():
        shutil.copyfile(ROOT / source, root / name)
    op['operation'].update(execution_enabled=True, authorization_ready=True)
    (root / 'operation.yaml').write_text(yaml.safe_dump(op, sort_keys=False))
    (root / 'operation.json').write_text(json.dumps(op, sort_keys=True) + '\n')
    accepted = yaml.safe_load((root / 'accepted.yaml').read_text())
    (root / 'accepted.json').write_text(json.dumps(accepted, sort_keys=True) + '\n')
    (root / 'inventory.ini').write_text('[inventory_automation]\nj2-svpi4mf ansible_host=10.1.2.170 ansible_user=ama ansible_python_interpreter=/usr/bin/python3 ansible_ssh_common_args="-o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10"\n')
    (root / 'ansible.cfg').write_text('[defaults]\nhost_key_checking=True\nretry_files_enabled=False\nno_target_syslog=True\nstdout_callback=default\n[ssh_connection]\npipelining=True\n')
    ansible = shutil.which('ansible-playbook')
    require(ansible is not None, 'controller_ansible')
    ansible = str(Path(ansible).absolute())
    controller = {p: sha(Path(p)) for p in (ansible, DOPPLER)}
    (root / 'controller.json').write_text(json.dumps(controller, sort_keys=True) + '\n')
    validate(root)
    for path in root.iterdir():
        path.chmod(0o600)
    (root / 'bundle.json').write_text(json.dumps({p.name: sha(p) for p in sorted(root.iterdir())}, sort_keys=True) + '\n')
    print(sha(root / 'bundle.json'))


def verify(root, digest):
    require(root.is_absolute() and not any(p.is_symlink() for p in (root, *root.parents)), 'bundle_path')
    require(sha(root / 'bundle.json') == digest, 'bundle_identity')
    rows = json.loads((root / 'bundle.json').read_text())
    require(set(rows) == set(FILES) | GENERATED and {p.name for p in root.iterdir()} == set(rows) | {'bundle.json'}, 'bundle_members')
    for name, digest in rows.items():
        path = root / name
        require(path.is_file() and not path.is_symlink() and sha(path) == digest, 'bundle_member')
    return validate(root)


def execute(root, digest, evidence):
    op = verify(root, digest)
    require(op['operation']['execution_enabled'] and op['operation']['authorization_ready'], 'execution_disabled')
    require(evidence.is_absolute() and evidence.parent.stat().st_uid == os.getuid()
            and evidence.parent.stat().st_mode & 0o777 == 0o700
            and not any(p.is_symlink() for p in (evidence, *evidence.parents)), 'evidence_path')
    controller = json.loads((root / 'controller.json').read_text())
    require(all(sha(Path(p)) == digest for p, digest in controller.items()), 'controller_drift')
    # One claim per exact bundle, including failed attempts; no automatic replay.
    claim = root.parent / ('consumed-' + digest + '.json')
    with claim.open('x') as out:
        json.dump({'bundle_sha256': digest, 'evidence': str(evidence)}, out)
    evidence.mkdir(mode=0o700)
    inputs = dict(credential_bundle_verified=True, credential_operation=op,
                  credential_bundle=str(root), credential_evidence=str(evidence))
    (evidence / 'inputs.json').write_text(json.dumps(inputs))
    env = {k: os.environ[k] for k in ('HOME', 'PATH', 'SSH_AUTH_SOCK', 'USER', 'LOGNAME') if k in os.environ}
    env.update(ANSIBLE_CONFIG=str(root / 'ansible.cfg'), LC_ALL='C.UTF-8', ANSIBLE_NOCOLOR='1', PYTHONDONTWRITEBYTECODE='1')
    ansible = next(p for p in controller if Path(p).name == 'ansible-playbook')
    status = 70
    try:
        with (evidence / 'ansible.stdout').open('xb') as out, (evidence / 'ansible.stderr').open('xb') as err:
            status = subprocess.run(['/usr/bin/prlimit', '--core=0:0', '--fsize=8388608:8388608', '--', '/bin/bash',
                                     str(root / 'ansible-temp.sh'), ansible, '-i', str(root / 'inventory.ini'),
                                     str(root / 'playbook.yaml'), '--extra-vars', '@' + str(evidence / 'inputs.json')],
                                    env=env, cwd=root, stdin=subprocess.DEVNULL, stdout=out, stderr=err, timeout=600).returncode
    finally:
        (evidence / 'controller-result.json').write_text(json.dumps({'exit_status': status, 'accepted': False}))
    return status


def main():
    os.umask(0o077)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['freeze', 'verify', 'execute'])
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--approve')
    parser.add_argument('--evidence', type=Path)
    args = parser.parse_args()
    if args.action == 'freeze':
        return freeze(args.bundle)
    require(args.approve, 'exact_approval_required')
    if args.action == 'verify':
        verify(args.bundle, args.approve)
        return 0
    require(args.evidence is not None, 'evidence_required')
    return execute(args.bundle, args.approve, args.evidence)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception:
        raise SystemExit('credential_bundle_refused; no provider output logged')
