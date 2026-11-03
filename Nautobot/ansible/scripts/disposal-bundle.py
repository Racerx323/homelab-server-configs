#!/usr/bin/env python3
"""Freeze one local disposal and remote retention-dry-run operation."""
import importlib.util
import json
from pathlib import Path
import sys
import yaml
from jsonschema import Draft202012Validator

sys.dont_write_bytecode = True
loader = importlib.util.spec_from_file_location('transport', Path(__file__).with_name('capture-resume-bundle.py'))
transport = importlib.util.module_from_spec(loader); loader.loader.exec_module(transport)
transport.STAGE = 'recurring_disposal_retention_qualification'
transport.FILES = {
    'launcher.py': 'Nautobot/ansible/scripts/disposal-bundle.py',
    'capture-resume-bundle.py': 'Nautobot/ansible/scripts/capture-resume-bundle.py',
    'playbook.yaml': 'Nautobot/ansible/playbooks/qualify-disposal.yaml',
    'schema.json': 'Nautobot/schemas/disposal-qualification.schema.json',
    'operation.yaml': 'Nautobot/manifests/operation.yaml',
    'accepted.yaml': 'Nautobot/manifests/accepted-live-state.yaml',
    'desired.yaml': 'Nautobot/manifests/desired-state.yaml',
    'recurring.yaml': 'Nautobot/manifests/recurring-protection.yaml',
    'provider.yaml': 'backblaze-b2/manifests/accepted-live-state.yaml',
    'repository.json': 'Nautobot/manifests/restic-initialization-result.json',
    'PLAN.md': 'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md',
    'RESTIC_ARCHITECTURE.md': 'restic/docs/RESTIC_ARCHITECTURE.md',
    'ansible-temp.sh': 'tests/repository/run-with-ansible-local-temp.sh',
    'runtime/scripts/application-backup.py': 'restic/scripts/application-backup.py',
}
transport.FILES.update({'runtime/scripts/'+name: 'Nautobot/ansible/scripts/'+name for name in
                        ('disposal_qualification.py', 'recurring_disposal.py', 'recurring_delivery.py',
                         'recurring_protection.py', 'capture_retained.py')})


def validate(root):
    op = yaml.safe_load((root/'operation.yaml').read_text())
    Draft202012Validator(json.loads((root/'schema.json').read_text())).validate(op)
    transport.require(op == json.loads((root/'runtime/operation.json').read_text()), 'operation_identity')
    for name, digest in op['source_sha256'].items():
        transport.require(transport.sha(root/name) == digest, 'accepted_source_drift')
    accepted = yaml.safe_load((root/'accepted.yaml').read_text())
    upload = accepted['recurring_upload_integrity']
    transport.require(upload['status'] == 'upload_integrity_accepted' and upload['full_repository_integrity']
                      and upload['snapshot_id'] == op['snapshot_id'] and upload['payload_path'] == op['payload_root'],
                      'accepted_upload')
    transport.require(op['content_sha256'] == upload['payload_content_sha256'], 'accepted_content')
    transport.require(op['credentials'] == accepted['recurring_credentials']['metadata'], 'credential_identity')
    repo = json.loads((root/'repository.json').read_text())
    transport.require(repo['accepted'] and repo['repository'] == op['repository'], 'repository_identity')
    transport.require(op['eligible_snapshot_ids'] == [op['snapshot_id']] and
                      set(op['snapshot_ids']) == set(op['protected_snapshot_ids']) | {op['snapshot_id']}, 'retention_scope')
    return op


transport.validate = validate
if __name__ == '__main__':
    sys.exit(transport.main())
