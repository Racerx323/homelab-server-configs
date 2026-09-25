#!/usr/bin/env python3
"""Build a new immutable preservation bundle; no host contact or execution."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[3]


def freeze(destination):
    op = yaml.safe_load((ROOT/'Nautobot/manifests/startup-preservation.yaml').read_text())
    schema = json.loads((ROOT/'Nautobot/schemas/startup-preservation.schema.json').read_text())
    Draft202012Validator(schema).validate(op)
    previous = op['source_archive']
    if subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', previous['tag']+'^{}']).decode().strip() != previous['commit']:
        raise ValueError('archive_identity')
    old = yaml.safe_load(subprocess.check_output(['git', '-C', str(ROOT), 'show', previous['tag']+':Nautobot/manifests/operation.yaml']))
    if any(old['runtime'][key] != value for key, value in op['runtime'].items()):
        raise ValueError('archive_input_drift')
    os.umask(0o077)
    destination.mkdir(mode=0o700)
    files = {
        'run-preservation.py': 'Nautobot/ansible/scripts/run-preservation.py',
        'playbook.yaml': 'Nautobot/ansible/playbooks/preserve-startup-database.yaml',
        'scripts/inspect-retained-database.py': 'Nautobot/ansible/scripts/inspect-retained-database.py',
        'scripts/runtime-initialization-node.py': 'Nautobot/ansible/scripts/runtime-initialization-node.py',
        'scripts/canary-backup.py': 'restic/scripts/canary-backup.py',
        'ansible.cfg': 'Nautobot/ansible/ansible.cfg',
        'schema.json': 'Nautobot/schemas/startup-preservation.schema.json',
        'REVIEW.md': 'Nautobot/docs/OPERATIONS.md',
    }
    for name, source in files.items():
        target = destination/name; target.parent.mkdir(exist_ok=True)
        shutil.copyfile(ROOT/source, target)
    (destination/'operation.json').write_text(json.dumps(op, indent=2)+'\n')
    (destination/'inventory.ini').write_text('j2-svpi4mf ansible_host=10.1.2.170 ansible_user=ama\n')
    manifest = {'stage':'startup_database_preservation','target':'ama@10.1.2.170',
                'files': {str(path.relative_to(destination)):hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in sorted(destination.rglob('*')) if path.is_file()}}
    raw = (json.dumps(manifest,indent=2,sort_keys=True)+'\n').encode()
    (destination/'bundle.json').write_bytes(raw)
    digest = hashlib.sha256(raw).hexdigest()
    (destination/'SHA256').write_text(digest+'\n')
    print(digest)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument('destination',type=Path)
    freeze(parser.parse_args().destination)
