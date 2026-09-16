#!/usr/bin/env python3
"""Inactive initialization launcher; current convergence/schema gates reject execution."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('preflight', Path(__file__).with_name('run-restic-repository-preflight.py'))
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
ROOT = common.ROOT
common.BUNDLE_DOMAIN = 'nautobot-restic-initialization-bundle-v1'
common.EVIDENCE_PREFIX = 'nautobot-restic-initialization.'
common.PLAYBOOK_PATH = ROOT / 'Nautobot/ansible/playbooks/initialize-restic-repository.yaml'
common.BUNDLE_FILES = tuple(dict.fromkeys(common.BUNDLE_FILES + (
    'Nautobot/ansible/scripts/run-restic-initialization.py',
    'Nautobot/ansible/playbooks/initialize-restic-repository.yaml',
    'restic/scripts/initialize-repository.py',
    'restic/tests/test_initialization.py',
    'Nautobot/manifests/accepted-live-state.yaml',
    'Nautobot/schemas/accepted-host-baseline.schema.json',
    'backblaze-b2/manifests/accepted-live-state.yaml',
    'Nautobot/ansible/ansible.cfg',
    'tests/repository/run-with-ansible-local-temp.sh',
    'restic/docs/REPOSITORY_INITIALIZATION.md',
)))


def require_ready(document):
    if (document['operation']['stage'] != 'restic_repository_initialization'
        or document['operation']['authorization_ready'] is not True
        or document['authorization']['mutation_authorized'] is not True
        or document['authorization']['blockers']
        or document['initialization']['implementation_state'] != 'reviewed'):
        raise common.PreflightBlocked('initialization_not_ready')
    provider = common.yaml.safe_load((ROOT / 'backblaze-b2/manifests/accepted-live-state.yaml').read_text())
    repo = document['repository']
    policy = provider['application_key_policy']
    if (provider['component']['state'] != 'accepted'
        or provider['bucket']['name'] != repo['bucket']
        or provider['bucket']['s3_endpoint'] != 'https://' + repo['endpoint']
        or provider['bucket']['repository_prefix'] != repo['prefix']
        or provider['provenance']['transport_bundle_sha256'] != document['provider_acceptance']['bundle_sha256']
        or policy['bucket_scope'] != 'exact_bucket'
        or policy['name_prefix_readback'] is not None
        or set(policy['capabilities']) != {'listAllBucketNames', 'listBuckets', 'readBuckets', 'listFiles', 'readFiles', 'writeFiles', 'deleteFiles'}):
        raise common.PreflightBlocked('accepted_provider_mismatch')
    # Readiness needs a later reviewed schema/operation transition, never implicit.
    result = subprocess.run(['check-jsonschema', '--schemafile',
        str(ROOT / 'Nautobot/schemas/accepted-host-baseline.schema.json'),
        str(ROOT / 'Nautobot/manifests/accepted-live-state.yaml')],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    if result.returncode:
        raise common.PreflightBlocked('accepted_baseline_required')
    result = subprocess.run(['git', '-C', str(ROOT), 'status', '--porcelain'],
                            capture_output=True, timeout=30, check=True)
    if result.stdout:
        raise common.PreflightBlocked('clean_reviewed_source_required')


def ansible_argv(extra):
    return ('/bin/bash', str(ROOT / 'tests/repository/run-with-ansible-local-temp.sh'),
            'ansible-playbook', '--inventory', str(common.INVENTORY_PATH), '--limit',
            common.EXPECTED_TARGET, '--user', 'ama', '--extra-vars',
            'ansible_host=' + common.EXPECTED_ADDRESS, '--extra-vars', '@' + str(extra),
            '--extra-vars', json.dumps({'restic_init_authorized': True,
                                        'restic_init_evidence_root': str(extra.parent)}),
            str(common.PLAYBOOK_PATH))


common.ansible_argv = ansible_argv
original_environment = common.minimal_environment

def environment():
    result = original_environment()
    result.update(ANSIBLE_CONFIG=str(ROOT / 'Nautobot/ansible/ansible.cfg'),
                  LC_ALL='C.UTF-8', PYTHONDONTWRITEBYTECODE='1')
    return result


common.minimal_environment = environment


def execute(authorized_hash):
    document = common.validate_operation()  # Reject current active convergence before credentials.
    require_ready(document)
    rows = common.bundle_file_hashes()
    digest = common.bundle_hash(rows)
    if authorized_hash != digest:
        raise common.PreflightBlocked('bundle_hash_mismatch')
    root, fd = common.prepare_evidence(rows, digest)
    status, error = None, None
    try:
        try:
            status = common.run_preflight(root, fd)  # Bounded secret delivery/Ansible/cleanup only.
        except common.PreflightBlocked as exc:
            error = exc.code
        except BaseException:
            error = 'interrupted_or_internal_failure'
        # Missing node evidence never means no mutation.
        record = {'bundle_sha256': digest, 'ansible_exit_status': status,
                  'error_class': error, 'mutation_status': 'consult_node_records_or_unknown',
                  'result': 'review_required', 'accepted': False,
                  'controller_credentials_absent': not os.path.lexists(root / 'protected-extra-vars.json'),
                  'controller_temp_absent': not os.path.lexists(root / 'ansible-local')}
        common.write_exclusive(fd, 'terminal-result.json', json.dumps(record).encode())
    finally:
        os.close(fd)
    print(f'evidence_root={root} result=review_required')
    return 0 if status == 0 and error is None else 69


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['execute', 'show-command'])
    parser.add_argument('authorized_hash', nargs='?')
    args = parser.parse_args()
    if args.mode == 'show-command':
        print('python3 Nautobot/ansible/scripts/run-restic-initialization.py execute AUTHORIZED_SHA256')
        print('Inactive: requires accepted baseline, reviewed schema/operation and exact bundle.')
        return 0
    if not args.authorized_hash:
        parser.error('execute requires AUTHORIZED_SHA256')
    try:
        return execute(args.authorized_hash)
    except common.PreflightBlocked as exc:
        print('result=blocked error=' + exc.code)
        return 69


if __name__ == '__main__':
    raise SystemExit(main())
