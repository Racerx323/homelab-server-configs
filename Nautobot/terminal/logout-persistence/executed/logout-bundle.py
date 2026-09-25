#!/usr/bin/env python3
"""Freeze or execute one reviewed logout bundle. Freeze never contacts a host."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[3]
FILES={
    'logout-bundle.py':'Nautobot/ansible/scripts/logout-bundle.py',
    'logout-node.py':'Nautobot/ansible/scripts/logout-node.py',
    'playbook.yaml':'Nautobot/ansible/playbooks/logout-persistence.yaml',
    'schema.json':'Nautobot/schemas/logout-persistence.schema.json',
    'ansible.cfg':'Nautobot/ansible/ansible.cfg',
    'ansible-temp.sh':'tests/repository/run-with-ansible-local-temp.sh',
    'PLAN.md':'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md',
    'OPERATIONS.md':'Nautobot/docs/OPERATIONS.md',
    'accepted-state.yaml':'Nautobot/manifests/accepted-live-state.yaml',
    'startup-network-client.py':'Nautobot/ansible/scripts/startup-network-client.py',
}


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(op,schema):
    from jsonschema import Draft202012Validator, FormatChecker
    Draft202012Validator(schema,format_checker=FormatChecker()).validate(op)
    suffix=op['root'].rsplit('.',1)[-1]
    if op['test_unit']!='nautobot-logout-test-'+suffix+'.service' or op['observer_unit']!='nautobot-logout-observer-'+suffix+'.service':
        raise ValueError('unit_identity')
    for path in op['baseline']['artifact_sha256']:
        if not (re.fullmatch(r'/var/lib/nautobot/runtime/[a-z0-9-]+\.py',path)
                or re.fullmatch(r'/var/lib/nautobot/\.config/containers/systemd/[a-z0-9_.-]+',path)):
            raise ValueError('artifact_path')


def freeze(destination):
    import yaml
    op=yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())
    validate(op,json.loads((ROOT/FILES['schema.json']).read_text()))
    if op['plan_sha256']!=sha(ROOT/FILES['PLAN.md']):raise ValueError('plan_drift')
    accepted=yaml.safe_load((ROOT/FILES['accepted-state.yaml']).read_text())
    if op['baseline']['artifact_sha256']!=accepted['application_startup']['artifact_sha256']:raise ValueError('accepted_identity')
    destination.mkdir(mode=0o700,parents=False,exist_ok=False)
    for name,source in FILES.items():shutil.copyfile(ROOT/source,destination/name)
    (destination/'operation.json').write_text(json.dumps(op,indent=2)+'\n')
    (destination/'inventory.ini').write_text('j2-svpi4mf ansible_host=10.1.2.170 ansible_user=ama\nlogout_proxy ansible_host=10.1.0.53 ansible_user=pi\n')
    manifest={'source_commit':op['operation']['source_commit'],'stage':'logout_persistence','targets':['ama@10.1.2.170','pi@10.1.0.53'],
              'files':{p.name:sha(p) for p in sorted(destination.iterdir()) if p.is_file()}}
    (destination/'bundle.json').write_text(json.dumps(manifest,sort_keys=True,indent=2)+'\n')
    print(sha(destination/'bundle.json'))


def verify(bundle,approval):
    if not re.fullmatch(r'[0-9a-f]{64}',approval) or sha(bundle/'bundle.json')!=approval:raise ValueError('approval_hash')
    manifest=json.loads((bundle/'bundle.json').read_text())
    if manifest.get('stage')!='logout_persistence' or manifest.get('targets')!=['ama@10.1.2.170','pi@10.1.0.53']:raise ValueError('scope')
    if set(manifest['files'])!=set(FILES)|{'operation.json','inventory.ini'}:raise ValueError('input_set')
    for name,digest in manifest['files'].items():
        path=bundle/name
        if path.is_symlink() or any(p.is_symlink() for p in path.parents) or not path.is_file() or sha(path)!=digest:raise ValueError('input_identity')
    op=json.loads((bundle/'operation.json').read_text())
    validate(op,json.loads((bundle/'schema.json').read_text()))
    if manifest.get('source_commit')!=op['operation']['source_commit']:raise ValueError('source_commit_identity')
    if sha(bundle/'PLAN.md')!=op['plan_sha256']:raise ValueError('plan_identity')
    age=(datetime.now(timezone.utc)-datetime.fromisoformat(op['baseline']['collected_at'])).total_seconds()
    if not 0<=age<=86400:raise ValueError('baseline_expired')
    return manifest,op


def ansible_executable():
    # systemd user services do not inherit interactive-shell PATH additions.
    # Resolve only the account's conventional install directory and system paths.
    search=os.pathsep.join((str(Path.home()/'.local/bin'),os.defpath))
    executable=shutil.which('ansible-playbook',path=search)
    if not executable or not Path(executable).is_absolute():
        raise ValueError('ansible_executable_unavailable')
    return executable


def execute(bundle,approval,evidence):
    manifest,op=verify(bundle,approval)
    ansible=ansible_executable()
    if not re.fullmatch(r'[0-9a-f]{32}',os.environ.get('INVOCATION_ID','')):
        raise ValueError('supervised_controller_required')
    linger=subprocess.run(['/usr/bin/loginctl','show-user',str(os.getuid()),'-p','Linger','--value'],capture_output=True,text=True,check=True,timeout=10)
    if linger.stdout.strip()!='yes':raise ValueError('controller_linger_required')
    if not evidence.is_absolute() or any(p.is_symlink() for p in (evidence,*evidence.parents)) or any(evidence.is_relative_to(p) for p in ('/tmp','/run','/var/tmp')):
        raise ValueError('persistent_evidence_path')
    info=evidence.parent.stat()
    if info.st_uid!=os.getuid() or info.st_mode&0o777!=0o700:raise ValueError('evidence_parent_metadata')
    evidence.mkdir(mode=0o700,parents=False,exist_ok=False)
    (evidence/'controller-started.json').write_text(json.dumps({'approval':approval,'invocation_id':os.environ['INVOCATION_ID'],'remote_root':op['root'],'status':'running'})+'\n')
    extra={'logout_bundle_verified':True,'logout_bundle':str(bundle),'logout_evidence':str(evidence),
           'logout_operation':op,'logout_hashes':manifest['files']}
    inputs=evidence/'ansible-inputs.json';inputs.write_text(json.dumps(extra));inputs.chmod(0o600)
    env={k:v for k,v in os.environ.items() if k in ('HOME','PATH','SSH_AUTH_SOCK','LANG','USER','LOGNAME')}
    env['ANSIBLE_CONFIG']=str(bundle/'ansible.cfg')
    result={'accepted':False,'bundle_sha256':approval,'status':'incomplete'}
    try:
        with (evidence/'ansible.stdout').open('xb') as out,(evidence/'ansible.stderr').open('xb') as err:
            process=subprocess.run(['/usr/bin/prlimit','--fsize=8388608:8388608','--','/bin/bash',str(bundle/'ansible-temp.sh'),
                ansible,'-i',str(bundle/'inventory.ini'),str(bundle/'playbook.yaml'),'--extra-vars','@'+str(inputs)],
                stdin=subprocess.DEVNULL,stdout=out,stderr=err,env=env,cwd=bundle,timeout=900)
        result.update(status='collected' if process.returncode==0 else 'failed',ansible_exit_status=process.returncode)
    finally:
        # No inference of live acceptance from a process return code.
        (evidence/'controller-result.json').write_text(json.dumps(result,indent=2)+'\n')
    return process.returncode


def main():
    os.umask(0o077)
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='action',required=True)
    prepare=sub.add_parser('freeze');prepare.add_argument('destination',type=Path)
    run=sub.add_parser('execute');run.add_argument('--approve',required=True);run.add_argument('--evidence',required=True,type=Path)
    args=parser.parse_args()
    if args.action=='freeze':freeze(args.destination.resolve());return 0
    return execute(Path(__file__).resolve().parent,args.approve,args.evidence)

if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception:raise SystemExit(69)
