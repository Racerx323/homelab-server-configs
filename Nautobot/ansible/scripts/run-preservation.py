#!/usr/bin/env python3
"""Execute an immutable, separately approved cold-copy bundle via Ansible."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def verify(root, approved):
    raw = (root/'bundle.json').read_bytes()
    if hashlib.sha256(raw).hexdigest() != approved:
        raise ValueError('authorization_hash')
    manifest = json.loads(raw)
    if manifest['stage'] != 'startup_database_preservation' or manifest['target'] != 'ama@10.1.2.170':
        raise ValueError('scope')
    required = {'run-preservation.py', 'playbook.yaml', 'operation.json', 'inventory.ini', 'ansible.cfg', 'scripts/inspect-retained-database.py', 'scripts/runtime-initialization-node.py', 'scripts/canary-backup.py'}
    if not required.issubset(manifest['files']):
        raise ValueError('missing_bundle_input')
    for name, digest in manifest['files'].items():
        relative = Path(name)
        path = root/relative
        if (relative.is_absolute() or '..' in relative.parts or path.is_symlink() or not path.is_file()
                or any(parent.is_symlink() for parent in path.parents)
                or hashlib.sha256(path.read_bytes()).hexdigest() != digest):
            raise ValueError('bundle_file')
    return manifest


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('approved_hash')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    verify(root, args.approved_hash)
    evidence = Path(tempfile.mkdtemp(prefix='nautobot-preservation.'))
    env = {k: os.environ[k] for k in ('HOME', 'PATH', 'SSH_AUTH_SOCK', 'LANG') if k in os.environ}
    env['ANSIBLE_CONFIG'] = str(root/'ansible.cfg')
    env['ANSIBLE_LOCAL_TEMP'] = str(evidence/'ansible-tmp')
    result = {'accepted': False, 'bundle_sha256': args.approved_hash}
    try:
        with (evidence/'ansible.stdout').open('xb') as out, (evidence/'ansible.stderr').open('xb') as err:
            process = subprocess.run(['ansible-playbook', '-i', str(root/'inventory.ini'),
                '--extra-vars', json.dumps({'preservation_bundle_verified': True, 'preservation_controller': str(evidence)}),
                str(root/'playbook.yaml')], stdout=out, stderr=err, env=env, timeout=900)
        result['ansible_exit_status'] = process.returncode
        retained = json.loads((evidence/'preservation.json').read_text())
        value = json.loads(retained['stdout'])
        result['accepted'] = process.returncode == 0 and retained['rc'] == 0 and value.get('passed') is True
    finally:
        (evidence/'result.json').write_text(json.dumps(result, indent=2))
        print('evidence_root=' + str(evidence))
    return 0 if result['accepted'] else 69


if __name__ == '__main__':
    raise SystemExit(main())
