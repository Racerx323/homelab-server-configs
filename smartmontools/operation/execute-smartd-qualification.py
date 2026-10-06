#!/usr/bin/env python3
"""Verify the approved manifest, claim once, and stage a private smartd trial."""
import base64
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys


def verify(root, authorization):
    raw = (root/'manifest.json').read_bytes()
    if hashlib.sha256(raw).hexdigest() != authorization:
        raise ValueError('authorization_hash_mismatch')
    manifest = json.loads(raw)
    required = {'execute-smartd-qualification.py', 'qualify-smartd.py',
                'compare-ci-smartctl.py', 'smartd', 'smartd.conf', 'empty.drivedb',
                'baseline.json', 'specification.json', 'PROCEDURE.md'}
    if set(manifest['files']) != required:
        raise ValueError('unreviewed_bundle_members')
    files = {}
    for name, expected in manifest['files'].items():
        path = root/name
        mode = path.lstat().st_mode
        if not stat.S_ISREG(mode) or mode & 0o022 or path.stat().st_uid != os.getuid():
            raise ValueError('unsafe_bundle_member')
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError('bundle_file_mismatch')
        files[name] = base64.b64encode(data).decode()
    return manifest, files


def main(directory, authorization):
    os.umask(0o077)
    root = Path(directory).resolve()
    manifest, files = verify(root, authorization)
    with (root/'.execution-claimed').open('x') as claim:
        claim.write(authorization+'\n')
    evidence = root/'controller-evidence'
    evidence.mkdir(mode=0o700)
    remote = '''import base64,hashlib,json,os,runpy,signal,sys,tempfile
from pathlib import Path
os.umask(0o077)
signal.alarm(420)
p=Path(tempfile.mkdtemp(prefix="smartd-qualification.",dir="/var/tmp"))
print(json.dumps({"remote_evidence":str(p)}),flush=True)
for name,data in FILES.items():
 b=base64.b64decode(data)
 assert hashlib.sha256(b).hexdigest()==HASHES[name]
 (p/name).write_bytes(b)
os.chmod(p/"smartd",0o700)
sys.dont_write_bytecode=True
sys.argv=[str(p/"qualify-smartd.py"),str(p)]
runpy.run_path(str(p/"qualify-smartd.py"),run_name="__main__")
'''
    program = 'FILES='+repr(files)+'\nHASHES='+repr(manifest['files'])+'\n'+remote
    ssh = ['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
           '-o', 'ConnectTimeout=15', 'ama@10.1.2.170', 'cd / && sudo -n /usr/bin/python3 -']
    with (evidence/'stdout').open('xb') as out, (evidence/'stderr').open('xb') as err:
        try:
            result = subprocess.run(ssh, input=program.encode(), stdout=out, stderr=err, timeout=480)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
    (evidence/'transport.json').write_text(json.dumps({'exit_status': code, 'bundle_sha256': authorization})+'\n')
    print(json.dumps({'controller_evidence': str(evidence), 'exit_status': code}))
    return code


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('expected approved manifest SHA-256')
    raise SystemExit(main(Path(__file__).resolve().parent, sys.argv[1]))
