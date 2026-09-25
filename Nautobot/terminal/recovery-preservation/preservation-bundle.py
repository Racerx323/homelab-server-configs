#!/usr/bin/env python3
"""Freeze preparation or launch a separately authorized, published preservation."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import resource
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[3]
FILES = {
    'preservation-bundle.py': 'Nautobot/ansible/scripts/preservation-bundle.py',
    'preservation-node.py': 'Nautobot/ansible/scripts/preservation-node.py',
    'preservation-backup.py': 'Nautobot/ansible/scripts/preservation-backup.py',
    'recovery_probe.py': 'Nautobot/ansible/scripts/recovery_probe.py',
    'logical_database.py': 'Nautobot/ansible/scripts/logical_database.py',
    'workload_capture.py': 'Nautobot/ansible/scripts/workload_capture.py',
    'workload_sampler.py': 'Nautobot/ansible/scripts/workload_sampler.py',
    'logout-node.py': 'Nautobot/ansible/scripts/logout-node.py',
    'application-backup.py': 'restic/scripts/application-backup.py',
    'run-workload.py': 'Nautobot/ansible/scripts/run-workload.py',
    'workload_controller.py': 'Nautobot/ansible/scripts/workload_controller.py',
    'run-restic-repository-preflight.py': 'Nautobot/ansible/scripts/run-restic-repository-preflight.py',
    'playbook.yaml': 'Nautobot/ansible/playbooks/preserve-application.yaml',
    'schema.json': 'Nautobot/schemas/preservation-execution.schema.json',
    'desired-state.yaml': 'Nautobot/manifests/desired-state.yaml',
    'qualified-image.json': 'Nautobot/manifests/qualified-image.json',
    'requirements.lock': 'Nautobot/container/requirements.lock',
    'PLAN.md': 'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md',
    'OPERATIONS.md': 'Nautobot/docs/OPERATIONS.md',
    'accepted-state.yaml': 'Nautobot/manifests/accepted-live-state.yaml',
    'ansible.cfg': 'Nautobot/ansible/ansible.cfg',
    'ansible-temp.sh': 'tests/repository/run-with-ansible-local-temp.sh',
}


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(op, schema):
    from jsonschema import Draft202012Validator, FormatChecker
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(op)
    if op['root'] != '/tmp/nautobot-preservation.' + op['token']:
        raise ValueError('root_token')
    if any(op['image_ids'][role] != op['app_image_id'] for role in ('web', 'worker', 'scheduler')):
        raise ValueError('application_image_set')


def freeze(op_path, destination, backup_path, source_path):
    op=json.loads(op_path.read_text()); schema=json.loads((ROOT/FILES['schema.json']).read_text())
    validate(op,schema)
    destination.mkdir(mode=0o700,exist_ok=False)
    for name, source in FILES.items():
        shutil.copyfile(ROOT/source,destination/name)
    (destination/'preservation.json').write_text(json.dumps(op,sort_keys=True)+'\n')
    backup=json.loads(backup_path.read_text())
    prefix=['/usr/bin/python3',op['root']+'/preservation-node.py','--root',op['root'],'section']
    backup.update(operation_id=op['operation']['id'],authorized=True,source_consistency_reviewed=True)
    for name, capture in backup['captures'].items(): capture['argv']=prefix+[name]
    backup['dump_validator']=prefix+['validate_dump']
    (destination/'application-backup.json').write_text(json.dumps(backup,sort_keys=True)+'\n')
    prior_sources=json.loads(source_path.read_text())
    sources={key:prior_sources[key] for key in ('consistency','quiet_window_confirmed')}
    sources['files']={name:digest for name,digest in op['artifact_sha256'].items()
                      if name.endswith('nautobot_config.py') or '/.config/containers/systemd/' in name}
    (destination/'backup-sources.json').write_text(json.dumps(sources,sort_keys=True)+'\n')
    (destination/'inventory.ini').write_text('[inventory_automation]\nj2-svpi4mf ansible_host=10.1.2.170 ansible_user=ama\n')
    manifest={'schema_version':1,'files':{p.name:sha(p) for p in sorted(destination.iterdir())},'source_commit':op['operation']['source_commit']}
    (destination/'bundle.json').write_text(json.dumps(manifest,sort_keys=True)+'\n')
    verify(destination,sha(destination/'bundle.json'),executing=False)
    return sha(destination/'bundle.json')


def module(path,name):
    spec=importlib.util.spec_from_file_location(name,path)
    obj=importlib.util.module_from_spec(spec);spec.loader.exec_module(obj);return obj


def verify(bundle,approval,executing=True):
    if bundle.is_symlink() or sha(bundle/'bundle.json')!=approval: raise ValueError('bundle_identity')
    manifest=json.loads((bundle/'bundle.json').read_text())
    required=set(FILES)|{'preservation.json','application-backup.json','backup-sources.json','inventory.ini'}
    if set(manifest['files'])!=required or {p.name for p in bundle.iterdir()}!=required|{'bundle.json'}:
        raise ValueError('bundle_file_set')
    for name,digest in manifest['files'].items():
        path=bundle/name
        if path.is_symlink() or not path.is_file() or sha(path)!=digest: raise ValueError('bundle_drift')
    op=json.loads((bundle/'preservation.json').read_text())
    validate(op,json.loads((bundle/'schema.json').read_text()))
    if sha(bundle/'PLAN.md')!=op['plan_sha256'] or sha(bundle/'accepted-state.yaml')!=op['accepted_state_sha256']:
        raise ValueError('authority_drift')
    backup=json.loads((bundle/'application-backup.json').read_text())
    owner=module(bundle/'application-backup.py','preservation_owner');owner.validate(backup)
    prefix=['/usr/bin/python3',op['root']+'/preservation-node.py','--root',op['root'],'section']
    if backup['operation_id']!=op['operation']['id'] or backup['dump_validator']!=prefix+['validate_dump']:
        raise ValueError('backup_identity')
    if any(value['argv']!=prefix+[name] for name,value in backup['captures'].items()): raise ValueError('capture_arguments')
    sources=json.loads((bundle/'backup-sources.json').read_text())
    expected={p:h for p,h in op['artifact_sha256'].items() if p.endswith('nautobot_config.py') or '/.config/containers/systemd/' in p}
    if sources['files']!=expected or sources['quiet_window_confirmed'] is not True or sources['consistency']!='quiet_pilot_empty_media':
        raise ValueError('source_contract')
    if manifest['source_commit'] != op['operation']['source_commit']: raise ValueError('source_commit_identity')
    if executing:
        if sha(Path(__file__)) != manifest['files']['preservation-bundle.py']: raise ValueError('launcher_drift')
        import yaml
        active=yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())
        if active!=op or op['operation']['authorization_ready'] is not True: raise ValueError('operation_not_active')
        age=(datetime.now(timezone.utc)-datetime.fromisoformat(op['baseline_collected_at'])).total_seconds()
        if not 0<=age<=86400: raise ValueError('baseline_expired')
        commit=op['operation']['source_commit']
        if op['ci_success_commit']!=commit: raise ValueError('ci_not_reviewed')
        for name,source in FILES.items():
            data=subprocess.run(['git','show',commit+':'+source],cwd=ROOT,capture_output=True,check=True,timeout=10).stdout
            if hashlib.sha256(data).hexdigest()!=manifest['files'][name]: raise ValueError('uncommitted_source')
    return manifest,op


def execute(bundle,approval,evidence):
    manifest,op=verify(bundle,approval)
    if not re.fullmatch('[0-9a-f]{32}',os.environ.get('INVOCATION_ID','')): raise ValueError('supervised_controller_required')
    search=os.pathsep.join((str(Path.home()/'.local/bin'),os.defpath))
    ansible=shutil.which('ansible-playbook',path=search)
    if not ansible: raise ValueError('ansible_unavailable')
    sys.path.insert(0,str(bundle))
    controller=module(bundle/'workload_controller.py','preservation_controller')
    controller.persistent_path(evidence);controller.private_directory(evidence.parent)
    evidence.mkdir(mode=0o700,exist_ok=False)
    runtime=Path('/run/user')/str(os.getuid())
    if subprocess.run(['/usr/bin/loginctl','show-user',str(os.getuid()),'-p','Linger','--value'],capture_output=True,text=True,check=True,timeout=10).stdout.strip()!='yes':
        raise ValueError('controller_linger_required')
    secrets=module(bundle/'run-restic-repository-preflight.py','preservation_secrets')
    doppler=shutil.which('doppler',path=search)
    if not doppler: raise ValueError('doppler_unavailable')
    secrets.DOPPLER_BASE=(doppler,*secrets.DOPPLER_BASE[1:])
    lifecycle=module(bundle/'run-workload.py','preservation_credential_lifecycle')
    status=None
    try:
        with lifecycle.resolved_credentials(bundle,evidence,reader=secrets.read_secret,runtime=runtime) as directory:
            extra={'preservation_verified':True,'preservation_execution_authorized':True,'preservation_root':op['root'],
                   'preservation_secrets':str(directory),'preservation_evidence':str(evidence),
                   'preservation_files':[{'name':name,'source':str(bundle/name),'sha256':digest} for name,digest in manifest['files'].items()]}
            inputs=evidence/'ansible-inputs.json';inputs.write_text(json.dumps(extra));inputs.chmod(0o600)
            env={k:v for k,v in os.environ.items() if k in ('HOME','USER','LOGNAME','SSH_AUTH_SOCK','LANG','LC_ALL')}
            env.update(PATH=search,ANSIBLE_CONFIG=str(bundle/'ansible.cfg'),PYTHONDONTWRITEBYTECODE='1')
            def limit_output(): resource.setrlimit(resource.RLIMIT_FSIZE,(8388608,8388608))
            with (evidence/'ansible.log').open('xb') as output:
                status=subprocess.run(['/bin/bash',str(bundle/'ansible-temp.sh'),ansible,'-i',str(bundle/'inventory.ini'),
                    str(bundle/'playbook.yaml'),'--extra-vars','@'+str(inputs)],cwd=bundle,env=env,stdout=output,stderr=output,timeout=4200,preexec_fn=limit_output).returncode
    finally:
        controller.receipt(evidence/'controller-result.json',{'ansible_status':status,'accepted':False,'review_required':True})
    return status


if __name__=='__main__':
    os.umask(0o077)
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='action',required=True)
    freeze_parser=sub.add_parser('freeze')
    for name in ('operation','destination','backup','sources'):freeze_parser.add_argument('--'+name,type=Path,required=True)
    run_parser=sub.add_parser('execute')
    run_parser.add_argument('--bundle',type=Path,required=True);run_parser.add_argument('--approve',required=True);run_parser.add_argument('--evidence',type=Path,required=True)
    args=parser.parse_args()
    if args.action=='freeze':print(freeze(args.operation,args.destination,args.backup,args.sources))
    else:raise SystemExit(execute(args.bundle,args.approve,args.evidence))
