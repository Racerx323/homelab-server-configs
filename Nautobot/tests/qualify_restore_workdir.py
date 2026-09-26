#!/usr/bin/env python3
"""Exercise the real restore runuser prefix across a disposable UID boundary."""
import argparse
import json
from pathlib import Path
import subprocess
from jinja2 import Environment, StrictUndefined
import yaml

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', required=True, help='Already available disposable image with Python and runuser')
    args = parser.parse_args()
    play = yaml.safe_load((ROOT/'ansible/playbooks/restore-application.yaml').read_text())[0]
    env = Environment(undefined=StrictUndefined)
    context = {'restore_context': 'target'}
    directory = env.from_string(play['module_defaults']['ansible.builtin.command']['chdir']).render(**context)
    # The prefix expression returns a Python literal list, with no secret values.
    import ast
    prefix = ast.literal_eval(env.from_string(play['vars']['restore_user_prefix']).render(**context))
    code = r'''
import json, os, pathlib, subprocess, sys
prefix, directory = json.loads(sys.argv[1]), sys.argv[2]
home = pathlib.Path(directory); home.mkdir(parents=True, exist_ok=True)
os.chown(home, 999, 999); home.chmod(0o700)
private = pathlib.Path('/tmp/administrator-private'); private.mkdir(mode=0o700)
os.chdir(private)
probe = [sys.executable, '-c', 'import os; os.chdir("."); print(os.getuid())']
old = subprocess.run(prefix+probe, capture_output=True, text=True)
fixed = subprocess.run(prefix+probe, cwd=directory, capture_output=True, text=True)
assert old.returncode != 0 and 'PermissionError' in old.stderr
assert fixed.returncode == 0 and fixed.stdout.strip() == '999'
print(json.dumps({'uid_transition':999,'inaccessible_cwd_rejected':True,'explicit_cwd_passed':True,'directory':directory}))
'''
    subprocess.run(['/usr/bin/podman', 'run', '--rm', '--pull=never', '--network=none',
                    '--user=0', '--memory=256m', '--pids-limit=128', '--entrypoint=/usr/local/bin/python3',
                    args.image, '-c', code, json.dumps(prefix), directory], check=True, timeout=60)


if __name__ == '__main__':
    main()
