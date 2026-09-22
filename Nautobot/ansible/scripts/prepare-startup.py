#!/usr/bin/env python3
"""Render a private, inactive startup review; never contacts hosts or resolves secrets."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('render', Path(__file__).with_name('render-runtime.py'))
render = importlib.util.module_from_spec(spec)
spec.loader.exec_module(render)


def prepare(output):
    policy = yaml.safe_load((ROOT/'Nautobot/manifests/startup-policy.yaml').read_text())
    Draft202012Validator(json.loads((ROOT/'Nautobot/schemas/startup-policy.schema.json').read_text())).validate(policy)
    operation = yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())
    if operation != {'schema_version': 1, 'operation': {'state': 'clean', 'authorization_ready': False}} and operation.get('operation', {}).get('stage') != 'application_startup':
        raise ValueError('active_operation')
    tag = 'nautobot-administrator-bootstrap-v2-accepted'
    git = lambda *args: subprocess.check_output(['git', '-C', str(ROOT), *args], timeout=15)
    if git('cat-file', '-t', tag).strip() != b'tag':
        raise ValueError('annotated_archive_required')
    accepted = (ROOT/'Nautobot/manifests/administrator-bootstrap-result.json').read_bytes()
    if git('show', tag + ':Nautobot/manifests/administrator-bootstrap-result.json') != accepted:
        raise ValueError('bootstrap_archive_drift')
    result = json.loads(accepted)
    if result.get('accepted') is not True or result.get('outcome') != 'administrator_bootstrap_accepted':
        raise ValueError('bootstrap_not_accepted')
    inputs = json.loads((ROOT/'Nautobot/manifests/runtime-inputs.json').read_text())
    render.verify_qualified_inputs(inputs, json.loads((ROOT/'Nautobot/manifests/qualified-image.json').read_text()),
                                   yaml.safe_load((ROOT/'Nautobot/manifests/accepted-live-state.yaml').read_text()))
    artifacts = render.render(yaml.safe_load((ROOT/'Nautobot/manifests/desired-state.yaml').read_text()), inputs)
    for name in ('startup-application.py', 'initialize-application.py', 'startup-job.py', 'startup-job-probe.py'):
        artifacts[name] = Path(__file__).with_name(name).read_text()
    # Compare to actual archived installed unit identities, not the new desired state.
    archived_op = yaml.safe_load(git('show', tag + ':Nautobot/manifests/operation.yaml'))
    baseline = archived_op['runtime']['artifact_sha256']
    changes = {name: {'before_sha256': baseline.get(name),
                      'after_sha256': hashlib.sha256(data.encode()).hexdigest()}
               for name, data in artifacts.items() if name.endswith(('.container', '.volume', '.network'))}
    output.mkdir(mode=0o700)  # A review must never overwrite earlier evidence.
    for name, data in artifacts.items():
        (output/name).write_text(data)
        (output/name).chmod(0o600)
    report = {'execution_authorized': False, 'bootstrap_tag': tag,
              'bootstrap_commit': git('rev-parse', tag+'^{}').decode().strip(),
              'artifact_changes': changes,
              'unchanged_existing_units': sorted(name for name, value in changes.items()
                                                  if value['before_sha256'] == value['after_sha256']),
              'remaining_gates': ['reviewed_baseline_and_recovery_inputs', 'exact_startup_bundle_authorization']}
    (output/'STARTUP_REVIEW.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    prepare(args.output)
    print('Startup review rendered; activation remains blocked.')
