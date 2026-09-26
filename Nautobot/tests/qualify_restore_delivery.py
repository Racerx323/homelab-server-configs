#!/usr/bin/env python3
"""Prepare the real Ansible staging/injection path with disposable credentials only."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('bundle',ROOT/'Nautobot/ansible/scripts/application-restore-bundle.py')
bundle=importlib.util.module_from_spec(spec);spec.loader.exec_module(bundle)


def main():
    os.umask(0o077)
    p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);p.add_argument('--dump-sha256',required=True);p.add_argument('--parent',type=Path,required=True)
    p.add_argument('--reject-snapshot',action='store_true')
    a=p.parse_args();a.parent.mkdir(mode=0o700,exist_ok=False)
    source=Path(subprocess.check_output(['/usr/bin/python3',str(ROOT/'Nautobot/tests/qualify_restore_target.py'),
        '--fixture',str(a.fixture),'--dump-sha256',a.dump_sha256,'--parent',str(a.parent/'sources')],text=True).strip())
    token=source.name;root=a.parent/'runtime'/token;monitor=a.parent/'monitor';inputs=a.parent/'inputs';inputs.mkdir(mode=0o700)
    runtime=json.loads((source/'runtime.json').read_text());runtime['restic_helper']=str(root/'scripts/application-restore.py')
    (inputs/'runtime.json').write_text(json.dumps(runtime))
    files=[]
    def add(path,destination): files.append({'source':str(path),'destination':str(destination),'uid':os.getuid(),'sha256':bundle.sha(path)})
    for name in bundle.SCRIPTS+('application-restore.py','application-backup.py'):add(ROOT/bundle.FILES[name],root/'scripts'/name)
    add(inputs/'runtime.json',root/'runtime.json')
    for name in ('members.json','logical-reference.json'):add(source/name,root/name)
    if a.reject_snapshot:
        contract=json.loads((source/'retrieval/restore.json').read_text());contract['snapshot_id']='0'*64
        (source/'retrieval/restore.json').write_text(json.dumps(contract))
    for name in ('restore.json','repository'):add(source/'retrieval'/name,root/'retrieval'/name)
    secret=inputs/'credentials.json'
    secret.write_text(json.dumps({'django':(source/'django-secret').read_text(),
        'password':(source/'retrieval/password').read_text(),'id':'synthetic','key':'synthetic'}));secret.chmod(0o600)
    for path in (source/'django-secret',source/'retrieval/password',source/'retrieval/credentials.json'):path.unlink()
    evidence=a.parent/'receipts';evidence.mkdir(mode=0o700)
    extra={'restore_verified':True,'restore_execution_authorized':True,'restore_stage':True,'restore_context':'disposable',
           'restore_root':str(root),'restore_token':token,'restore_scripts':str(root/'scripts'),
           'restore_monitor_scripts':str(monitor),'restore_stage_uid':os.getuid(),'restore_files':files,
           'restore_credentials_file':str(secret),'restore_receipts':bundle.RECEIPTS,'restore_evidence':str(evidence)}
    (a.parent/'ansible.json').write_text(json.dumps(extra))
    (a.parent/'inventory.ini').write_text('[restore_target]\nlocalhost ansible_connection=local\n')
    print(a.parent/'ansible.json')


if __name__=='__main__':main()
