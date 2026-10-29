#!/usr/bin/env python3
"""Prepare one immutable review candidate; execute only with its approved hash."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import secrets
import subprocess
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[3]
FILES = {
    'prerequisite-bundle.py': 'Nautobot/ansible/scripts/prerequisite-bundle.py',
    'prerequisite_node.py': 'Nautobot/ansible/scripts/prerequisite_node.py',
    'playbook.yaml': 'Nautobot/ansible/playbooks/install-recurring-prerequisites.yaml',
    'install-tasks.yaml': 'Nautobot/ansible/tasks/install-recurring-prerequisites.yaml',
    'ansible.cfg': 'Nautobot/ansible/ansible.cfg',
    'ansible-temp.sh': 'tests/repository/run-with-ansible-local-temp.sh',
    'desired-state.yaml': 'Nautobot/manifests/desired-state.yaml',
    'accepted-state.yaml': 'Nautobot/manifests/accepted-live-state.yaml',
    'recurring-protection.yaml': 'Nautobot/manifests/recurring-protection.yaml',
    'operation.yaml': 'Nautobot/manifests/operation.yaml',
    'qualification.json': 'Nautobot/manifests/recurring-prerequisite-review.json',
    'schema.json': 'Nautobot/schemas/recurring-prerequisites.schema.json',
    'PLAN.md': 'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md',
    'OPERATIONS.md': 'Nautobot/docs/OPERATIONS.md',
}


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def external_names(op):
    return {p['name'] + '.deb' for p in op['packages']} | {
        s[k] for s in op['sources'].values() for k in ('release', 'index', 'keyring')}


def target_names(op):
    return {'prerequisite_node.py', 'operation.json', 'ansible-temp.sh'} | {
        p['name'] + '.deb' for p in op['packages']}


def validate(bundle, op):
    import yaml
    from jsonschema import Draft202012Validator
    Draft202012Validator(json.loads((bundle / 'schema.json').read_text())).validate(op)
    require(op == yaml.safe_load((bundle / 'operation.yaml').read_text()), 'operation_identity')
    require(op['plan_sha256'] == sha(bundle / 'PLAN.md'), 'plan_drift')
    accepted = yaml.safe_load((bundle / 'accepted-state.yaml').read_text())
    require(op['baseline']['artifact_sha256'] == accepted['application_startup']['artifact_sha256'], 'accepted_identity')
    candidate = yaml.safe_load((bundle / 'recurring-protection.yaml').read_text())
    pins = candidate['dependency_transaction_lock']['new_packages']
    doppler = candidate['prerequisite_preparation']['packages']['doppler']
    expected = {p['name']: (p['version'], p['sha256'], 'all') for p in pins}
    expected[doppler['name']] = (doppler['version'], doppler['sha256'], 'arm64')
    require(len(op['packages']) == len(expected) and
            {p['name']: (p['version'], p['sha256'], p['architecture']) for p in op['packages']} == expected,
            'package_binding_drift')


def freeze(destination, artifacts):
    import yaml
    op = yaml.safe_load((ROOT / FILES['operation.yaml']).read_text())
    require(op['operation'].get('stage') == 'recurring_prerequisite_installation', 'operation_stage')
    destination.mkdir(mode=0o700, parents=False, exist_ok=False)
    for name, source in FILES.items():
        shutil.copyfile(ROOT / source, destination / name)
    # Prepare the final execution bytes once. Only execute --approve authorizes
    # their use; freezing never contacts the target or changes repository gates.
    op['operation'].update(execution_enabled=True, authorization_ready=True)
    (destination / 'operation.yaml').write_text(yaml.safe_dump(op, sort_keys=False))
    for name in external_names(op):
        path = artifacts / name
        require(path.is_file() and not path.is_symlink(), 'external_input')
        shutil.copyfile(path, destination / name)
    (destination / 'operation.json').write_text(json.dumps(op, sort_keys=True, indent=2) + '\n')
    (destination / 'inventory.ini').write_text('[inventory_automation]\nj2-svpi4mf ansible_host=10.1.2.170 ansible_user=ama ansible_python_interpreter=/usr/bin/python3\n')
    validate(destination, op)
    spec = importlib.util.spec_from_file_location('prerequisite_node', destination / 'prerequisite_node.py')
    node = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(node)
    node.verify_sources(destination, op)
    manifest = {'files': {p.name: sha(p) for p in sorted(destination.iterdir())}}
    for path in destination.iterdir():
        path.chmod(0o600)
    (destination / 'bundle.json').write_text(json.dumps(manifest, sort_keys=True, separators=(',', ':')) + '\n')
    print(sha(destination / 'bundle.json'))


def verify(bundle, approval):
    require(bundle.is_absolute() and not any(p.is_symlink() for p in (bundle, *bundle.parents)), 'bundle_path')
    require(sha(bundle / 'bundle.json') == approval, 'bundle_identity')
    manifest = json.loads((bundle / 'bundle.json').read_text())
    require(set(p.name for p in bundle.iterdir()) == set(manifest['files']) | {'bundle.json'}, 'bundle_residue')
    for name, digest in manifest['files'].items():
        path = bundle / name
        require(path.is_file() and not path.is_symlink() and sha(path) == digest, 'input_identity')
    op = json.loads((bundle / 'operation.json').read_text())
    require(set(manifest['files']) == set(FILES) | external_names(op) | {'operation.json', 'inventory.ini'}, 'input_set')
    validate(bundle, op)
    return manifest, op


def execute(bundle, approval, evidence):
    manifest, op = verify(bundle, approval)
    require(op['operation']['execution_enabled'] is True and op['operation']['authorization_ready'] is True,
            'execution_disabled')
    age = (datetime.now(timezone.utc) - datetime.fromisoformat(op['baseline']['collected_at'])).total_seconds()
    require(0 <= age <= 86400, 'baseline_expired')
    require(evidence.is_absolute() and evidence.parent.is_dir()
            and evidence.parent.stat().st_uid == os.getuid()
            and evidence.parent.stat().st_mode & 0o777 == 0o700
            and not any(p.is_symlink() for p in (evidence, *evidence.parents)), 'evidence_path')
    evidence.mkdir(mode=0o700)
    inputs = {'prerequisite_verified': True, 'prerequisite_operation': op,
              'prerequisite_bundle': str(bundle),
              'prerequisite_hashes': {name: manifest['files'][name] for name in sorted(target_names(op))},
              'prerequisite_root': '/tmp/nautobot-prerequisites-' + approval[:16] + '-' + secrets.token_hex(4),
              'prerequisite_evidence': str(evidence)}
    path = evidence / 'inputs.json'
    path.write_text(json.dumps(inputs))
    ansible = shutil.which('ansible-playbook', path=str(Path.home() / '.local/bin') + ':/usr/bin:/bin')
    require(ansible is not None, 'controller_ansible_missing')
    env = {k: v for k, v in os.environ.items() if k in ('HOME', 'PATH', 'SSH_AUTH_SOCK', 'LANG', 'USER', 'LOGNAME')}
    env['ANSIBLE_CONFIG'] = str(bundle / 'ansible.cfg')
    status = 70
    try:
        with (evidence / 'ansible.stdout').open('xb') as out, (evidence / 'ansible.stderr').open('xb') as err:
            status = subprocess.run(['/usr/bin/prlimit', '--fsize=8388608:8388608', '--', '/bin/bash',
                                     str(bundle / 'ansible-temp.sh'), ansible, '-i', str(bundle / 'inventory.ini'),
                                     str(bundle / 'playbook.yaml'), '--extra-vars', '@' + str(path)],
                                    env=env, cwd=bundle, stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                                    timeout=900).returncode
    finally:
        (evidence / 'controller-result.json').write_text(json.dumps({'ansible_exit_status': status, 'accepted': False}))
    return status


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='action', required=True)
    prepare = commands.add_parser('freeze')
    prepare.add_argument('destination', type=Path)
    prepare.add_argument('--artifacts', required=True, type=Path)
    run = commands.add_parser('execute')
    run.add_argument('--bundle', required=True, type=Path)
    run.add_argument('--approve', required=True)
    run.add_argument('--evidence', required=True, type=Path)
    args = parser.parse_args()
    if args.action == 'freeze':
        freeze(args.destination, args.artifacts)
        return 0
    return execute(args.bundle, args.approve, args.evidence)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
