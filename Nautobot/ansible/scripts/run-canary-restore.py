#!/usr/bin/env python3
"""Exact-bundle gate for one isolated canary restore."""
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
common.EXPECTED_OPERATION_ID = 'nautobot-predata-canary-restore-v1'
common.EXPECTED_STAGE = 'isolated_canary_restore'
common.BUNDLE_DOMAIN = 'nautobot-canary-restore-bundle-v1'
common.EVIDENCE_PREFIX = 'nautobot-restore.'
common.COMMAND_TIMEOUT_SECONDS = 1800
common.PLAYBOOK_PATH = ROOT / 'Nautobot/ansible/playbooks/restore-canary.yaml'
common.BUNDLE_FILES = tuple(dict.fromkeys(common.BUNDLE_FILES + (
    'Nautobot/ansible/scripts/run-canary-restore.py',
    'Nautobot/ansible/playbooks/restore-canary.yaml',
    'restic/scripts/canary-backup.py',
    'restic/scripts/restore-canary.py',
    'Nautobot/manifests/canary-backup-result.json',
    'restic/tests/test_canary_restore.py',
    'Nautobot/schemas/canary-restore.schema.json',
    'Nautobot/manifests/restic-initialization-result.json',
    'Nautobot/docs/CANARY_ISOLATED_RESTORE.md',
    'Nautobot/docs/ISOLATED_BACKUP_RESTORE.md',
)))


def validate_operation():
    result = subprocess.run(['check-jsonschema', '--schemafile',
        str(ROOT / 'Nautobot/schemas/canary-restore.schema.json'), str(common.OPERATION_PATH)],
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
    def git(*args):
        try:
            return subprocess.check_output(['git', '-C', str(ROOT), *args],
                                           stderr=subprocess.DEVNULL, timeout=30)
        except (subprocess.SubprocessError, OSError) as exc:
            raise common.PreflightBlocked('local_archive_unavailable') from exc
    for name in ('initialization', 'backup_integrity'):
        proof = document['prerequisites'][name]
        raw = (ROOT / proof['record']).read_bytes()
        result = json.loads(raw)
        if (hashlib.sha256(raw).hexdigest() != proof['record_sha256']
                or result['result'] != proof['result'] or result['accepted'] is not True
                or result['repository'] != document['repository']
                or result['restic_version'] != document['restic_version']
                or result['bundle_sha256'] != proof['bundle_sha256']):
            raise common.PreflightBlocked('predecessor_identity_mismatch')
        if (git('cat-file', '-t', proof['terminal_tag']).strip() != b'tag'
                or git('rev-parse', proof['terminal_tag'] + '^{}').decode().strip() != proof['archive_commit']
                or git('show', proof['terminal_tag'] + ':' + proof['record']) != raw):
            raise common.PreflightBlocked('predecessor_archive_mismatch')
        if name == 'backup_integrity' and (
                result['snapshot_id'] != document['snapshot']['id']
                or result['snapshot_metadata'] != document['snapshot']['metadata']
                or result['source']['root'] != document['snapshot']['source_root']):
            raise common.PreflightBlocked('snapshot_identity_mismatch')
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
            '--extra-vars', json.dumps({'restore_authorized': True,
                                        'restore_evidence_root': str(extra.parent)}),
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
