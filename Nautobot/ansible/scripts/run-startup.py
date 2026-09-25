#!/usr/bin/env python3
"""Hash-bound startup launcher; Ansible owns all host mutations and recovery."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import yaml
from jsonschema import Draft202012Validator
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('collector', HERE/'collect-startup.py')
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)
bounded = collector.bounded
node_spec = importlib.util.spec_from_file_location('startup_node', HERE/'startup-node.py')
node = importlib.util.module_from_spec(node_spec)
node_spec.loader.exec_module(node)
ROOT = HERE.parents[2]
FILES = (
    'Nautobot/schemas/startup-execution.schema.json',
    'Nautobot/schemas/startup-operation.schema.json',
    'Nautobot/schemas/startup-policy.schema.json',
    'Nautobot/docs/OPERATIONS.md',
    'Nautobot/manifests/operation.yaml', 'Nautobot/manifests/startup-policy.yaml',
    'Nautobot/manifests/desired-state.yaml', 'Nautobot/manifests/accepted-live-state.yaml',
    'Nautobot/manifests/startup-network-handoff.yaml',
    'Nautobot/ansible/ansible.cfg', 'Nautobot/ansible/playbooks/start-application.yaml',
    'Nautobot/ansible/playbooks/start-service-tasks.yaml',
    'Nautobot/ansible/scripts/run-startup.py', 'Nautobot/ansible/scripts/collect-startup.py',
    'Nautobot/ansible/scripts/startup-node.py',
    'Nautobot/ansible/scripts/runtime-initialization-node.py',
    'Nautobot/ansible/scripts/run-restic-repository-preflight.py',
    'restic/scripts/canary-backup.py',
    'tests/repository/run-with-ansible-local-temp.sh',
    'inventory/prod/hosts.yaml', 'inventory/prod/groups/inventory_automation.yaml',
    'inventory/prod/hosts/j2-svpi4mf.yaml',
)


def regular(path):
    path = Path(path)
    if not path.is_absolute() or any(parent.is_symlink() for parent in (path, *path.parents)) or not path.is_file():
        raise ValueError('unsafe_input')
    return path.read_bytes()


def prepare(specification, root=ROOT):
    raw = regular(specification)
    value = json.loads(raw)
    Draft202012Validator(json.loads((root/'Nautobot/schemas/startup-execution.schema.json').read_text())).validate(value)
    required = {'schema_version', 'host', 'artifacts', 'acceptance_contract', 'baseline', 'recovery', 'helper_sha256', 'probe_files'}
    if set(value) != required or value['schema_version'] != 1 or value['host'] != 'j2-svpi4mf':
        raise ValueError('startup_specification')
    collector.validate(value['acceptance_contract'])
    for key in ('baseline', 'recovery'):
        proof = value[key]
        if set(proof) != {'path', 'sha256'} or hashlib.sha256(regular(proof['path'])).hexdigest() != proof['sha256']:
            raise ValueError('prerequisite_hash')
        record = json.loads(regular(proof['path']))
        if record.get('accepted') is not True or record.get('host') != value['host']:
            raise ValueError('prerequisite_not_accepted')
    baseline = json.loads(regular(value['baseline']['path']))
    if (not re.fullmatch('[0-9a-f-]{36}', baseline.get('boot_id', ''))
            or set(baseline.get('services', {})) != {'postgresql', 'redis', 'migration', 'web', 'worker', 'scheduler'}):
        raise ValueError('baseline_shape')
    for role, state in baseline['services'].items():
        if not node.baseline_stopped(role, state) or 'InvocationID' not in state:
            raise ValueError('baseline_not_stopped')
    expected_helpers = {'startup-node.py', 'runtime-initialization-node.py', 'canary-backup.py'}
    if set(value['helper_sha256']) != expected_helpers:
        raise ValueError('helper_set')
    rows = [(hashlib.sha256(regular(root/name)).hexdigest(), name) for name in FILES]
    for name, digest in value['helper_sha256'].items():
        source = root/('restic/scripts/' if name == 'canary-backup.py' else 'Nautobot/ansible/scripts/')/name
        if hashlib.sha256(regular(source)).hexdigest() != digest:
            raise ValueError('helper_hash')
    destinations = set()
    if not value['artifacts']:
        raise ValueError('empty_artifacts')
    for artifact in value['artifacts']:
        if set(artifact) != {'source', 'destination', 'sha256'}:
            raise ValueError('artifact_shape')
        dest = artifact['destination']
        if (not re.fullmatch(r'/var/lib/nautobot/(runtime/[A-Za-z0-9_.-]+|\.config/containers/systemd/nautobot-[A-Za-z0-9_.-]+)', dest)
                or dest.endswith('.env') or dest in destinations):
            raise ValueError('artifact_destination')
        destinations.add(dest)
        digest = hashlib.sha256(regular(artifact['source'])).hexdigest()
        if digest != artifact['sha256']:
            raise ValueError('artifact_hash')
        rows.append((digest, 'artifact:' + dest))
    if not isinstance(value['probe_files'], dict) or not value['probe_files']:
        raise ValueError('probe_files_required')
    for name, digest in value['probe_files'].items():
        if hashlib.sha256(regular(name)).hexdigest() != digest:
            raise ValueError('probe_file_hash')
        rows.append((digest, 'probe:' + name))
    # Every locally executed Python probe is included in the approved bundle.
    for check in value['acceptance_contract']['checks']:
        argv = check['argv']
        if argv[0] != '/usr/bin/python3' or len(argv) < 2 or argv[1] not in value['probe_files']:
            raise ValueError('unfrozen_probe_entrypoint')
    rows.extend([(hashlib.sha256(raw).hexdigest(), 'startup-specification.json')])
    rows.extend((value[key]['sha256'], key + '.json') for key in ('baseline', 'recovery'))
    bounded.BUNDLE_DOMAIN = 'nautobot-application-startup-v1'
    return value, baseline, rows, bounded.bundle_hash(rows)


def execute(specification, authorized_hash):
    value, baseline, rows, digest = prepare(specification)
    if digest != authorized_hash:
        raise ValueError('authorization_hash')
    policy = yaml.safe_load((ROOT/'Nautobot/manifests/startup-policy.yaml').read_text())
    Draft202012Validator(json.loads((ROOT/'Nautobot/schemas/startup-policy.schema.json').read_text())).validate(policy)
    operation = yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())
    Draft202012Validator(json.loads((ROOT/'Nautobot/schemas/startup-operation.schema.json').read_text())).validate(operation)
    if (policy.get('execution_authorized') is not True
            or operation.get('operation', {}).get('stage') != 'application_startup'
            or operation['operation'].get('authorization_ready') is not True):
        raise ValueError('startup_inactive')
    handoff = yaml.safe_load((ROOT/'Nautobot/manifests/startup-network-handoff.yaml').read_text())
    packet = handoff.get('accepted_packet_qualification', {})
    if packet.get('accepted') is not True or packet.get('git_archival') != 'published_tag_verified':
        raise ValueError('network_archive_pending')
    timestamp = datetime.fromisoformat(baseline['collected_at'].replace('Z', '+00:00'))
    age = (datetime.now(timezone.utc) - timestamp).total_seconds()
    if not 0 <= age <= 3600:
        raise ValueError('baseline_expired')
    recovery = json.loads(regular(value['recovery']['path']))
    if (recovery.get('scope') != 'initialized_database_and_administrator'
            or recovery.get('verified') is not True or recovery.get('boot_id') != baseline['boot_id']):
        raise ValueError('recovery_scope')
    if subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain'], timeout=15):
        raise ValueError('clean_source_required')
    os.umask(0o077)
    evidence = Path(tempfile.mkdtemp(prefix='nautobot-startup.'))
    contract = evidence/'acceptance-contract.json'
    contract.write_text(json.dumps(value['acceptance_contract']))
    variables = {
        'ansible_host': '10.1.2.170', 'startup_bundle_verified': True,
        'startup_network_evidence_verified': True, 'startup_recovery_review_verified': True,
        'startup_evidence': str(evidence), 'startup_controller_evidence': str(evidence),
        'startup_guard': 'nautobot-startup-' + evidence.name.split('.')[-1].lower().replace('_', '-'),
        'startup_artifacts': value['artifacts'], 'startup_before': baseline['services'],
        'startup_expected_boot': baseline['boot_id'], 'startup_helper_sha256': value['helper_sha256'],
        'startup_acceptance_contract': str(contract),
    }
    variables_path = evidence/'variables.json'
    variables_path.write_text(json.dumps(variables))
    (evidence/'bundle.json').write_text(json.dumps({'sha256': digest, 'files': rows}))
    argv = ('/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
            'ansible-playbook', '--inventory', str(ROOT/'inventory/prod/hosts.yaml'),
            '--limit', 'j2-svpi4mf', '--user', 'ama', '--extra-vars', '@' + str(variables_path),
            str(ROOT/'Nautobot/ansible/playbooks/start-application.yaml'))
    environment = bounded.minimal_environment()
    environment['ANSIBLE_CONFIG'] = str(ROOT/'Nautobot/ansible/ansible.cfg')
    bounded.COMMAND_TIMEOUT_SECONDS = 7000
    result = {'accepted': False, 'bundle_sha256': digest}
    try:
        rc, out, err, truncated = bounded.drain_process(argv, environment)
        result.update(ansible_exit_status=rc, output_truncated=truncated)
        receipt = json.loads((evidence/'acceptance.json').read_text()) if (evidence/'acceptance.json').exists() else {}
        lifecycle = json.loads((evidence/'startup-lifecycle.json').read_text())
        if not receipt:
            result['error'] = 'acceptance_not_reached_review_lifecycle_and_readiness'
        result['accepted'] = rc == 0 and not truncated and receipt.get('accepted') is True and lifecycle.get('accepted') is True
    except BaseException:
        result['error'] = 'execution_failed_review_remote_guard_and_evidence'
    finally:
        (evidence/'result.json').write_text(json.dumps(result, indent=2))
    print('evidence_root=' + str(evidence))
    return 0 if result['accepted'] else 69


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['show-hash', 'execute'])
    parser.add_argument('specification', type=Path)
    parser.add_argument('authorized_hash', nargs='?')
    args = parser.parse_args()
    try:
        if args.mode == 'show-hash':
            print(prepare(args.specification)[3])
            return 0
        if not args.authorized_hash:
            raise ValueError('authorization_required')
        return execute(args.specification, args.authorized_hash)
    except Exception:
        print('startup_blocked_local_validation')
        return 69


if __name__ == '__main__':
    raise SystemExit(main())
