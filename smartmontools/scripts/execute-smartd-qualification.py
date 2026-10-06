#!/usr/bin/env python3
"""Verify the approved manifest, claim once, and stage a private smartd trial."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
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
    if manifest.get('scope') == 'candidate_smartd_repeated_checks':
        required |= {'observe-smartd.py', 'smartd-observation-control.py'}
    elif manifest.get('scope', 'candidate_smartd_single_check') != 'candidate_smartd_single_check':
        raise ValueError('unreviewed_scope')
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
p=Path(tempfile.mkdtemp(prefix="smartd-observation." if REPEATED else "smartd-qualification.",dir="/var/tmp"))
print(json.dumps({"remote_evidence":str(p)}),flush=True)
for name,data in FILES.items():
 b=base64.b64decode(data)
 assert hashlib.sha256(b).hexdigest()==HASHES[name]
 (p/name).write_bytes(b)
os.chmod(p/"smartd",0o700)
sys.dont_write_bytecode=True
sys.argv=[str(p/"qualify-smartd.py"),str(p)]
if REPEATED:
 module=runpy.run_path(str(p/"smartd-observation-control.py"))
 print(json.dumps(module['start'](p)),flush=True)
else:
 runpy.run_path(str(p/"qualify-smartd.py"),run_name="__main__")
'''
    program = ('FILES='+repr(files)+'\nHASHES='+repr(manifest['files'])+'\nREPEATED='
               +repr(manifest.get('scope') == 'candidate_smartd_repeated_checks')+'\n'+remote)
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


def control(directory, authorization, action, remote_root):
    root = Path(directory).resolve()
    manifest, _ = verify(root, authorization)
    if manifest.get('scope') != 'candidate_smartd_repeated_checks' or action not in ('status', 'cancel'):
        raise ValueError('unreviewed_control')
    if not re.fullmatch(r'/var/tmp/smartd-observation\.[a-z0-9_]{8}', remote_root):
        raise ValueError('unsafe_remote_root')
    if (root/'.execution-claimed').read_text().strip() != authorization:
        raise ValueError('missing_execution_claim')
    rows = [json.loads(x) for x in (root/'controller-evidence/stdout').read_text().splitlines()]
    if not rows or rows[0].get('remote_evidence') != remote_root:
        raise ValueError('unowned_remote_root')
    program = '''import hashlib,json,runpy
from pathlib import Path
p=Path(ROOT)
for name,expected in HASHES.items():
 f=p/name
 assert not f.is_symlink() and f.is_file() and hashlib.sha256(f.read_bytes()).hexdigest()==expected
m=runpy.run_path(str(p/'smartd-observation-control.py'))
print(json.dumps(m[ACTION](p)))
'''
    source = 'ROOT='+repr(remote_root)+'\nHASHES='+repr(manifest['files'])+'\nACTION='+repr(action)+'\n'+program
    result = subprocess.run(['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
                             '-o', 'ConnectTimeout=15', 'ama@10.1.2.170',
                             'cd / && sudo -n /usr/bin/python3 -'], input=source.encode(),
                            capture_output=True, timeout=45)
    if len(result.stdout)+len(result.stderr) > 65536:
        raise ValueError('control_output_limit')
    # Status is read-only; a cancel request is not a terminal cancellation receipt.
    print(result.stdout.decode(), end='')
    if result.stderr:
        print(result.stderr.decode(), file=sys.stderr, end='')
    return result.returncode


if __name__ == '__main__':
    root = Path(__file__).resolve().parent
    if len(sys.argv) == 2:
        raise SystemExit(main(root, sys.argv[1]))
    if len(sys.argv) == 4:
        raise SystemExit(control(root, sys.argv[1], sys.argv[2], sys.argv[3]))
    raise SystemExit('expected HASH [status|cancel REMOTE_ROOT]')
