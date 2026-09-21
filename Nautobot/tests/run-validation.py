#!/usr/bin/env python3
"""Local validation entry point; no remote operations or containers."""
from pathlib import Path
import subprocess
import sys
import os
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
import yaml
ROOT = Path(__file__).resolve().parents[2]

def run(argv):
    subprocess.run(argv, cwd=ROOT, check=True)

if __name__ == '__main__':
    config = yaml.safe_load((ROOT / '.pre-commit-config.yaml').read_text())
    hooks = [h['id'] for repo in config['repos'] for h in repo['hooks']
             if h['id'].startswith('nautobot-') and h['id'] != 'nautobot-candidate-contracts']
    for hook in hooks:
        run(['pre-commit', 'run', hook, '--all-files'])
    for script in ('Nautobot/ansible/scripts/validate-contracts.py',
                   'Nautobot/ansible/scripts/validate-memory-controller.py',
                   'Nautobot/ansible/scripts/validate-package-cleanup.py',
                   'Nautobot/tests/test_runtime.py', 'restic/tests/test_initialization.py', 'restic/tests/test_canary_backup.py',
                   'restic/tests/test_canary_restore.py'):
        run(['/bin/bash', 'tests/repository/run-with-ansible-local-temp.sh', sys.executable, script])
