#!/usr/bin/env python3
"""Verify the temporary capture qualification bundle and invoke Ansible only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def verify(root, approved):
    raw=(root/'bundle.json').read_bytes()
    if hashlib.sha256(raw).hexdigest()!=approved:raise ValueError('bundle_identity')
    manifest=json.loads(raw)
    for name,digest in manifest['files'].items():
        path=root/name
        if not re.fullmatch(r'[A-Za-z0-9_.-]+',name) or path.is_symlink() or not path.is_file():
            raise ValueError('bundle_path')
        if hashlib.sha256(path.read_bytes()).hexdigest()!=digest:raise ValueError('bundle_drift')
    if hashlib.sha256(Path(__file__).read_bytes()).hexdigest()!=manifest['files']['run-capture-qualification.py']:
        raise ValueError('launcher_drift')
    return manifest


def main():
    os.umask(0o077)
    parser=argparse.ArgumentParser()
    parser.add_argument('--bundle',type=Path,required=True)
    parser.add_argument('--approve',required=True)
    args=parser.parse_args();root=args.bundle.resolve()
    verify(root,args.approve)
    inputs=json.loads((root/'inputs.json').read_text())
    evidence=Path(inputs['qualification_evidence']);evidence.mkdir(mode=0o700,exist_ok=False)
    env={k:v for k,v in os.environ.items() if k in ('PATH','HOME','USER','LOGNAME','SSH_AUTH_SOCK','LANG','LC_ALL')}
    env['ANSIBLE_CONFIG']=str(root/'ansible.cfg')
    result=subprocess.run(['/bin/bash',str(root/'run-with-ansible-local-temp.sh'),'ansible-playbook',
        '-i',str(root/'inventory.yaml'),'--limit','j2-svpi4mf','--user','ama',
        str(root/'qualify-workload-capture.yaml'),'--extra-vars','@'+str(root/'inputs.json')],
        cwd=root,env=env,timeout=1100)
    return result.returncode

if __name__=='__main__':raise SystemExit(main())
