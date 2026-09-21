#!/usr/bin/env python3
"""Hash-bound single-use Restic initialization launcher."""
import argparse
import hashlib
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
common.EXPECTED_STAGE = 'restic_repository_initialization'
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
    'Nautobot/manifests/restic-preflight-result.json',
)))


def require_preflight(document):
    proof = document['preflight']['terminal_proof']
    path = ROOT / 'Nautobot/manifests/restic-preflight-result.json'
    raw = path.read_bytes()
    result = json.loads(raw)
    if (hashlib.sha256(raw).hexdigest() != proof['result_sha256']
        or result['bundle_sha256'] != proof['bundle_sha256']
        or result['result'] != 'passed'
        or result['observations']['config_exit_status'] != 10
        or result['observations']['restic_version_output'] != document['preflight']['last_result']['restic_version']
        or not result['remote_secret_cleanup_passed']
        or not result['controller_secret_file_absent']
        or not result['ansible_local_temp_absent']
        or result['repository_initialization_attempted']):
        raise common.PreflightBlocked('fresh_absence_proof_invalid')
    def git(*args):
        return subprocess.check_output(['git', '-C', str(ROOT), *args], timeout=30)
    if (git('cat-file', '-t', proof['terminal_tag']).strip() != b'tag'
        or git('rev-parse', proof['terminal_tag'] + '^{}').decode().strip() != proof['archive_commit']
        or git('show', proof['terminal_tag'] + ':Nautobot/manifests/restic-preflight-result.json') != raw):
        raise common.PreflightBlocked('absence_archive_mismatch')


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
    require_preflight(document)
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
    document = common.validate_operation()
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
    parser.add_argument('mode', choices=['execute', 'show-command', 'show-hash'])
    parser.add_argument('authorized_hash', nargs='?')
    args = parser.parse_args()
    if args.mode == 'show-command':
        print('python3 Nautobot/ansible/scripts/run-restic-initialization.py execute AUTHORIZED_SHA256')
        print('Requires accepted baseline, archived absence proof, clean source and exact bundle.')
        return 0
    if args.mode == 'show-hash':
        try:
            require_ready(common.validate_operation())
            print(common.bundle_hash())
            return 0
        except common.PreflightBlocked as exc:
            print('result=blocked error=' + exc.code)
            return 69
    if not args.authorized_hash:
        parser.error('execute requires AUTHORIZED_SHA256')
    try:
        return execute(args.authorized_hash)
    except common.PreflightBlocked as exc:
        print('result=blocked error=' + exc.code)
        return 69


if __name__ == '__main__':
    raise SystemExit(main())
