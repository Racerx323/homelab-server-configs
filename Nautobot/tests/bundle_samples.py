"""Explicit local definitions for real bundle producers; never execute candidates."""
from pathlib import Path
import copy
import sys
sys.dont_write_bytecode = True
import yaml

ROOT = Path(__file__).resolve().parents[2]


def operation(role, bundle):
    op = yaml.safe_load((ROOT/'Nautobot/tests/fixtures/recurring-bundle-inputs.yaml').read_text())[role]
    accepted = yaml.safe_load((ROOT/'Nautobot/manifests/accepted-live-state.yaml').read_text())
    sha = bundle.transport.sha
    if 'source_sha256' in op:
        op['source_sha256'] = {name: sha(ROOT/bundle.transport.FILES[name]) for name in
                              ('accepted.yaml', 'desired.yaml', 'PLAN.md')}
        for name in ('provider.yaml', 'repository.json', 'recurring.yaml', 'APPRISE_DELIVERY.md', 'RESTIC_ARCHITECTURE.md'):
            if name in bundle.transport.FILES:
                op['source_sha256'][name] = sha(ROOT/bundle.transport.FILES[name])
    if role in ('upload', 'disposal'):
        import json
        op['repository'] = json.loads((ROOT/bundle.transport.FILES['repository.json']).read_text())['repository']
        op['credentials'] = accepted['recurring_credentials']['metadata']
        source = accepted['recurring_capture_resume' if role == 'upload' else 'recurring_upload_integrity']
        op['payload_root'] = source['payload_path']
        op['content_sha256'] = source['payload_content_sha256']
        if role == 'upload':
            op['capture_bundle_sha256'] = source['bundle_sha256']
        else:
            op['snapshot_id'] = source['snapshot_id']
            op['snapshot_ids'] = op['eligible_snapshot_ids'] = [source['snapshot_id']]
            op['protected_snapshot_ids'] = []
    if role == 'notification':
        op['preserved_trees'] = {name: {'files': {}, 'directories': {}} for name in
                                 (op['capture_root'], accepted['recurring_capture_resume']['payload_path'])}
        op['messages'] = bundle.previews(op)
    if role in ('schedule', 'recovery'):
        op['accepted_sha256'] = sha(ROOT/'Nautobot/manifests/accepted-live-state.yaml')
        trials = [op] if role == 'schedule' else op['trials'].values()
        for trial in trials:
            trial['plan_sha256'] = sha(ROOT/'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md')
            trial['baseline']['artifact_sha256'] = accepted['application_startup']['artifact_sha256']
            trial['packages'] = accepted['recurring_prerequisites']['packages']
            trial['credential_identity'] = accepted['recurring_credentials']['metadata']
            for name, item in trial['binding']['metadata_files'].items():
                item['sha256'] = sha(ROOT/bundle.transport.FILES['runtime/metadata/'+name])
        if role == 'schedule':
            op['accepted_stage_bundles'] = {key: accepted[key]['bundle_sha256'] for key in
                ('recurring_capture_resume', 'recurring_upload_integrity', 'recurring_notifications',
                 'recurring_disposal', 'recurring_recovery_timer')}
            op['binding']['credentials'].update(op['credential_identity'])
            op['binding']['artifact_sha256'] = copy.deepcopy(op['baseline']['artifact_sha256'])
            op['baseline']['binding_artifact_sha256'] = op['binding']['artifact_sha256']
            op['binding']['backup_template']['repository_id'] = accepted['recurring_upload_integrity']['repository_id']
    return op


def definition(role, bundle, directory):
    path = directory/'local-operation.yaml'
    path.write_text(yaml.safe_dump(operation(role, bundle), sort_keys=False))
    return path
