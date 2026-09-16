#!/usr/bin/env python3
"""Offline cross-artifact contracts. Never resolves secrets or contacts targets."""
from pathlib import Path
import json
import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[3]


def validate(desired, workload=None):
    schema = json.loads((ROOT / 'Nautobot/schemas/desired-state.schema.json').read_text())
    Draft202012Validator(schema).validate(desired)
    for image in desired['images'].values():
        if image['reference'].split('@')[-1] != image['manifest_digest']:
            raise ValueError('Image reference and manifest digest disagree')
    container = (ROOT / 'Nautobot/container/Containerfile').read_text()
    if container.splitlines()[0] != 'FROM ' + desired['images']['nautobot_base']['reference']:
        raise ValueError('Containerfile base differs from desired state')
    lock = (ROOT / 'Nautobot/container/requirements.lock').read_text()
    actual = ' '.join(line.strip() for line in lock.splitlines() if not line.startswith('#')).replace('\\', '').split()
    expected = []
    for artifact in desired['custom_image']['python_artifacts']:
        expected += [artifact['package'] + '==' + artifact['version'], '--hash=sha256:' + artifact['sha256']]
    if actual != expected:
        raise ValueError('Python lock differs from desired state')
    if workload is not None:
        Draft202012Validator(json.loads((ROOT / 'Nautobot/schemas/workload-test.schema.json').read_text())).validate(workload)
        f = workload['fixture']
        if f['locations'] > f['devices'] or f['ip_assignments'] > f['devices'] or f['devices'] > 64000:
            raise ValueError('Unsupported fixture cardinality')


if __name__ == '__main__':
    validate(yaml.safe_load((ROOT / 'Nautobot/manifests/desired-state.yaml').read_text()),
             yaml.safe_load((ROOT / 'Nautobot/manifests/workload-test.yaml').read_text()))
    print('Desired state, build inputs, and workload contract agree; no execution authorized.')
