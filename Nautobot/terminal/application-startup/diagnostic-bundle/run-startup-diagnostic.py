#!/usr/bin/env python3
"""Verify a frozen diagnostic bundle and invoke its single-host Ansible playbook."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

FILES = {'run-startup-diagnostic.py', 'diagnose-startup-configuration.yaml',
         'diagnose-startup-configuration.py', 'startup-node.py',
         'runtime-initialization-node.py', 'canary-backup.py', 'startup-command.py',
         'inputs.json', 'inventory.yaml', 'ansible.cfg', 'run-with-ansible-local-temp.sh'}


def verify(root):
    rows = {}
    for name in sorted(FILES):
        path = root/name
        if path.is_symlink() or not path.is_file():
            raise ValueError('unsafe_bundle_file')
        rows[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    digest = hashlib.sha256(json.dumps(rows, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    inputs = json.loads((root/'inputs.json').read_text())
    if not re.fullmatch(r'nautobot-startup-[a-z0-9]+', inputs['prior_startup_guard']):
        raise ValueError('guard_identity')
    return digest, inputs


def main():
    root = Path(__file__).resolve().parent
    digest, inputs = verify(root)
    if sys.argv[1:] == ['show-hash']:
        print(digest);return 0
    if sys.argv[1:] != ['execute', digest]:
        raise ValueError('exact_authorization_required')
    os.umask(0o077)
    evidence = Path(tempfile.mkdtemp(prefix='nautobot-config-diagnostic.'))
    variables = {'diagnostic_bundle_verified': True, 'diagnostic_evidence': str(evidence),
                 'diagnostic_guard': 'nautobot-config-diagnostic-' + evidence.name.split('.')[-1].replace('_','-'),
                 'prior_startup_guard': inputs['prior_startup_guard']}
    variables_path = evidence/'variables.json'
    variables_path.write_text(json.dumps(variables))
    (evidence/'bundle-sha256').write_text(digest+'\n')
    environment = {k: os.environ[k] for k in ('PATH','HOME','SSH_AUTH_SOCK') if k in os.environ}
    environment.update(ANSIBLE_CONFIG=str(root/'ansible.cfg'), PYTHONDONTWRITEBYTECODE='1', LC_ALL='C.UTF-8')
    result = {'captured': False, 'bundle_sha256': digest}
    try:
        completed = subprocess.run(['/bin/bash', str(root/'run-with-ansible-local-temp.sh'),
            'ansible-playbook', '-i', str(root/'inventory.yaml'), '--limit', 'j2-svpi4mf',
            '--user', 'ama', '--extra-vars', '@'+str(variables_path),
            str(root/'diagnose-startup-configuration.yaml')], env=environment,
            cwd=root, capture_output=True, timeout=1100)
        for name, output in [('ansible.stdout',completed.stdout),('ansible.stderr',completed.stderr)]:
            (evidence/name).write_bytes(output[-1048576:])
        diagnostic = json.loads((evidence/'diagnostic.json').read_text())
        cleanup = json.loads((evidence/'cleanup.json').read_text())
        result.update(ansible_exit_status=completed.returncode,
            captured=completed.returncode == 0 and diagnostic['rc'] == 0 and cleanup['rc'] == 0)
    except BaseException:
        result['error'] = 'incomplete_review_remote_guard_and_private_evidence'
    finally:
        (evidence/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    print('evidence_root='+str(evidence))
    return 0 if result['captured'] else 69


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception:
        print('diagnostic_blocked_local_validation');raise SystemExit(69)
