#!/usr/bin/env python3
"""Use the existing one-use Ansible bundle transport for retained-payload upload."""
import importlib.util
import json
from pathlib import Path
import sys
import yaml
from jsonschema import Draft202012Validator

sys.dont_write_bytecode=True
loader=importlib.util.spec_from_file_location('transport',Path(__file__).with_name('capture-resume-bundle.py'))
transport=importlib.util.module_from_spec(loader);loader.loader.exec_module(transport)
transport.STAGE='recurring_upload_integrity_qualification'
transport.FILES={
    'launcher.py':'Nautobot/ansible/scripts/upload-integrity-bundle.py',
    'capture-resume-bundle.py':'Nautobot/ansible/scripts/capture-resume-bundle.py',
    'playbook.yaml':'Nautobot/ansible/playbooks/qualify-upload-integrity.yaml',
    'schema.json':'Nautobot/schemas/upload-integrity.schema.json',
    'operation.yaml':'Nautobot/manifests/operation.yaml',
    'accepted.yaml':'Nautobot/manifests/accepted-live-state.yaml',
    'desired.yaml':'Nautobot/manifests/desired-state.yaml',
    'provider.yaml':'backblaze-b2/manifests/accepted-live-state.yaml',
    'repository.json':'Nautobot/manifests/restic-initialization-result.json',
    'PLAN.md':'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md',
    'ansible-temp.sh':'tests/repository/run-with-ansible-local-temp.sh',
    'runtime/scripts/application-backup.py':'restic/scripts/application-backup.py',
}
transport.FILES.update({'runtime/scripts/'+name:'Nautobot/ansible/scripts/'+name for name in
                        ('upload_node.py','capture_retained.py','recurring_delivery.py','recurring_protection.py')})


def validate(root):
    op=yaml.safe_load((root/'operation.yaml').read_text())
    Draft202012Validator(json.loads((root/'schema.json').read_text())).validate(op)
    transport.require(op==json.loads((root/'runtime/operation.json').read_text()),'operation_identity')
    for name,digest in op['source_sha256'].items():
        transport.require(transport.sha(root/name)==digest,'accepted_source_drift')
    accepted=yaml.safe_load((root/'accepted.yaml').read_text())
    capture=accepted['recurring_capture_resume']
    transport.require(capture['status']=='capture_only_accepted' and op['capture_bundle_sha256']==capture['bundle_sha256']
                      and op['payload_root']==capture['payload_path'],'accepted_capture')
    transport.require(op['content_sha256']==capture['payload_content_sha256'],'capture_hashes')
    transport.require(op['credentials']==accepted['recurring_credentials']['metadata'],'credential_identity')
    repo=json.loads((root/'repository.json').read_text())
    provider=yaml.safe_load((root/'provider.yaml').read_text())
    transport.require(repo['accepted'] and op['repository']==repo['repository'],'repository_identity')
    transport.require(provider['component']['state']=='accepted' and
                      op['repository']['url']=='s3:'+provider['bucket']['s3_endpoint']+'/'+provider['bucket']['name']+'/',
                      'provider_identity')
    return op


transport.validate=validate
if __name__=='__main__':sys.exit(transport.main())
