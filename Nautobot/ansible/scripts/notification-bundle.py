#!/usr/bin/env python3
"""Use the existing one-use Ansible transport for notification qualification."""
import importlib.util
import json
from pathlib import Path
import sys
import yaml
from jsonschema import Draft202012Validator

sys.dont_write_bytecode = True
if (Path(__file__).parent/'runtime/scripts').is_dir():
    sys.path.insert(0, str(Path(__file__).parent/'runtime/scripts'))
from notification_qualification import previews

loader = importlib.util.spec_from_file_location('transport', Path(__file__).with_name('capture-resume-bundle.py'))
transport = importlib.util.module_from_spec(loader); loader.loader.exec_module(transport)
transport.STAGE = 'recurring_notification_qualification'
transport.FILES = {
    'launcher.py': 'Nautobot/ansible/scripts/notification-bundle.py',
    'capture-resume-bundle.py': 'Nautobot/ansible/scripts/capture-resume-bundle.py',
    'playbook.yaml': 'Nautobot/ansible/playbooks/qualify-notification.yaml',
    'schema.json': 'Nautobot/schemas/notification-qualification.schema.json',
    'operation.yaml': 'Nautobot/manifests/operation.yaml',
    'accepted.yaml': 'Nautobot/manifests/accepted-live-state.yaml',
    'desired.yaml': 'Nautobot/manifests/desired-state.yaml',
    'recurring.yaml': 'Nautobot/manifests/recurring-protection.yaml',
    'PLAN.md': 'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md',
    'APPRISE_DELIVERY.md': 'Caddy/docs/APPRISE_DELIVERY.md',
    'ansible-temp.sh': 'tests/repository/run-with-ansible-local-temp.sh',
}
transport.FILES.update({'runtime/scripts/'+name: 'Nautobot/ansible/scripts/'+name for name in
                        ('notification_qualification.py', 'recurring_delivery.py', 'recurring_protection.py', 'capture_retained.py')})


def validate(root):
    op = yaml.safe_load((root/'operation.yaml').read_text())
    Draft202012Validator(json.loads((root/'schema.json').read_text())).validate(op)
    transport.require(op == json.loads((root/'runtime/operation.json').read_text()), 'operation_identity')
    for name, digest in op['source_sha256'].items():
        transport.require(transport.sha(root/name) == digest, 'accepted_source_drift')
    transport.require(op['messages'] == previews(op), 'message_drift')
    accepted = yaml.safe_load((root/'accepted.yaml').read_text())
    transport.require(accepted['recurring_upload_integrity']['status'] == 'upload_integrity_accepted', 'upload_unaccepted')
    transport.require(op['capture_root'] == '/var/lib/nautobot/protection/qualification' and
                      set(op['preserved_trees']) == {op['capture_root'], accepted['recurring_capture_resume']['payload_path']},
                      'preservation_scope')
    return op


transport.validate = validate
if __name__ == '__main__':
    sys.exit(transport.main())
