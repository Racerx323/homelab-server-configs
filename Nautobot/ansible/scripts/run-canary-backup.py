#!/usr/bin/env python3
"""Exact-bundle gate for one canary upload and full integrity check."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('initialization_transport', Path(__file__).with_name('run-restic-initialization.py'))
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)
common = transport.common
ROOT = common.ROOT
common.EXPECTED_OPERATION_ID = 'nautobot-predata-canary-backup-v1'
common.EXPECTED_STAGE = 'canary_backup_integrity'
common.BUNDLE_DOMAIN = 'nautobot-canary-backup-bundle-v1'
common.EVIDENCE_PREFIX = 'nautobot-canary.'
common.COMMAND_TIMEOUT_SECONDS = 1800
common.PLAYBOOK_PATH = ROOT / 'Nautobot/ansible/playbooks/backup-canary.yaml'
common.BUNDLE_FILES = tuple(dict.fromkeys(common.BUNDLE_FILES + (
    'Nautobot/ansible/scripts/run-canary-backup.py',
    'Nautobot/ansible/playbooks/backup-canary.yaml',
    'restic/scripts/canary-backup.py',
    'restic/tests/test_canary_backup.py',
    'Nautobot/schemas/canary-backup.schema.json',
    'Nautobot/manifests/restic-initialization-result.json',
    'Nautobot/docs/CANARY_BACKUP_INTEGRITY.md',
    'Nautobot/docs/ISOLATED_BACKUP_RESTORE.md',
)))


def validate_operation():
    result = subprocess.run(['check-jsonschema', '--schemafile',
        str(ROOT / 'Nautobot/schemas/canary-backup.schema.json'), str(common.OPERATION_PATH)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    if result.returncode:
        raise common.PreflightBlocked('canary_schema_invalid')
    return common.load_operation()


def require_ready(document):
    if (not document['operation']['authorization_ready']
            or not document['authorization']['mutation_authorized']
            or document['authorization']['blockers']
            or document['implementation']['state'] != 'reviewed'):
        raise common.PreflightBlocked('canary_not_ready')
    proof = document['prerequisites']['initialization']
    raw = (ROOT / proof['record']).read_bytes()
    result = json.loads(raw)
    if (hashlib.sha256(raw).hexdigest() != proof['record_sha256']
            or result['result'] != 'repository_initialization_accepted'
            or result['accepted'] is not True or result['repository'] != document['repository']
            or result['restic_version'] != document['restic_version']
            or result['bundle_sha256'] != proof['bundle_sha256']):
        raise common.PreflightBlocked('initialization_identity_mismatch')
    def git(*args):
        try:
            return subprocess.check_output(['git', '-C', str(ROOT), *args],
                                           stderr=subprocess.DEVNULL, timeout=30)
        except (subprocess.SubprocessError, OSError) as exc:
            raise common.PreflightBlocked('local_archive_unavailable') from exc
    if (git('cat-file', '-t', proof['terminal_tag']).strip() != b'tag'
            or git('rev-parse', proof['terminal_tag'] + '^{}').decode().strip() != proof['archive_commit']
            or git('show', proof['terminal_tag'] + ':' + proof['record']) != raw):
        raise common.PreflightBlocked('initialization_archive_mismatch')
    pre = document['prerequisites']
    if hashlib.sha256((ROOT / pre['accepted_host']).read_bytes()).hexdigest() != pre['accepted_host_sha256']:
        raise common.PreflightBlocked('host_identity_changed')
    if hashlib.sha256((ROOT / pre['provider']['accepted_live_state']).read_bytes()).hexdigest() != pre['provider_sha256']:
        raise common.PreflightBlocked('provider_identity_changed')
    if git('status', '--porcelain'):
        raise common.PreflightBlocked('clean_reviewed_source_required')


def ansible_argv(extra):
    return ('/bin/bash', str(ROOT / 'tests/repository/run-with-ansible-local-temp.sh'),
            'ansible-playbook', '--inventory', str(common.INVENTORY_PATH), '--limit',
            common.EXPECTED_TARGET, '--user', 'ama', '--extra-vars',
            'ansible_host=' + common.EXPECTED_ADDRESS, '--extra-vars', '@' + str(extra),
            '--extra-vars', json.dumps({'canary_authorized': True,
                                        'canary_evidence_root': str(extra.parent)}),
            str(common.PLAYBOOK_PATH))


common.validate_operation = validate_operation
common.ansible_argv = ansible_argv
transport.require_ready = require_ready

if __name__ == '__main__':
    # Reuse bounded capture, secret delivery, cleanup and review-required result.
    # show-command is omitted because the shared display names initialization.
    if len(sys.argv) > 1 and sys.argv[1] not in ('execute', 'show-hash'):
        raise SystemExit('Use show-hash or execute APPROVED_SHA256')
    raise SystemExit(transport.main())
