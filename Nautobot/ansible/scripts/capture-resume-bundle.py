#!/usr/bin/env python3
"""Freeze or execute one approved capture-only Ansible definition."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import yaml
from jsonschema import Draft202012Validator

ROOT=Path(__file__).resolve().parents[3]
SCRIPTS=('capture_qualification.py','recurring_node.py','recurring_protection.py','render-recurring-protection.py',
         'recurring_delivery.py','recurring_disposal.py','workload_capture.py','media_namespace.py','recovery_probe.py')
FILES={
    'launcher.py':'Nautobot/ansible/scripts/capture-resume-bundle.py',
    'playbook.yaml':'Nautobot/ansible/playbooks/qualify-capture-resume.yaml',
    'schema.json':'Nautobot/schemas/capture-resume.schema.json',
    'operation.yaml':'Nautobot/manifests/operation.yaml',
    'accepted.yaml':'Nautobot/manifests/accepted-live-state.yaml',
    'PLAN.md':'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md',
    'ansible-temp.sh':'tests/repository/run-with-ansible-local-temp.sh',
    'runtime/ansible-temp.sh':'tests/repository/run-with-ansible-local-temp.sh',
    'runtime/playbooks/recurring-capture.yaml':'Nautobot/ansible/playbooks/recurring-capture.yaml',
    'runtime/tasks/capture-resume-upload.yaml':'Nautobot/ansible/tasks/capture-resume-upload.yaml',
    'runtime/scripts/application-backup.py':'restic/scripts/application-backup.py',
    'runtime/metadata/desired-state.yaml':'Nautobot/manifests/desired-state.yaml',
    'runtime/metadata/requirements.lock':'Nautobot/container/requirements.lock',
    'runtime/metadata/qualified-image.json':'Nautobot/manifests/qualified-image.json',
}
FILES.update({'runtime/scripts/'+p:'Nautobot/ansible/scripts/'+p for p in SCRIPTS})

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,reason):
    if not ok:raise ValueError(reason)

def validate(root):
    op=yaml.safe_load((root/'operation.yaml').read_text())
    Draft202012Validator(json.loads((root/'schema.json').read_text())).validate(op)
    require(op==json.loads((root/'runtime/operation.json').read_text()),'operation_identity')
    accepted=yaml.safe_load((root/'accepted.yaml').read_text())
    require(op['plan_sha256']==sha(root/'PLAN.md'),'plan_drift')
    require(op['baseline']['artifact_sha256']==accepted['application_startup']['artifact_sha256'],'accepted_artifacts')
    require(op['packages']==accepted['recurring_prerequisites']['packages'],'accepted_packages')
    require(op['credential_identity']==accepted['recurring_credentials']['metadata'],'accepted_credentials')
    require(op['accepted_credential_bundle']==accepted['recurring_credentials']['bundle_sha256'],'credential_bundle')
    require(not op['binding']['upload_enabled'] and not op['supervisor']['dispose_successful_payload']
            and 'notification_argv' not in op['supervisor'],'stage_scope')
    require(op['supervisor']['start_hour']==3 and op['supervisor']['end_hour']==4,'approved_window')
    for name,item in op['binding']['metadata_files'].items():
        require(item['sha256']==sha(root/'runtime/metadata'/name),'metadata_drift')
    return op

def freeze(root):
    op=yaml.safe_load((ROOT/FILES['operation.yaml']).read_text())
    require(op['operation'].get('stage')=='recurring_capture_resume_qualification','stage')
    root.mkdir(mode=0o700)
    for name,src in FILES.items():
        dst=root/name;dst.parent.mkdir(parents=True,exist_ok=True,mode=0o700);shutil.copyfile(ROOT/src,dst);dst.chmod(0o600)
    op['operation'].update(execution_enabled=True,authorization_ready=True)
    (root/'operation.yaml').write_text(yaml.safe_dump(op,sort_keys=False))
    (root/'runtime/operation.json').write_text(json.dumps(op,sort_keys=True)+'\n')
    ansible=shutil.which('ansible-playbook');require(ansible is not None,'ansible_missing')
    (root/'controller.json').write_text(json.dumps({'ansible':ansible,'sha256':sha(Path(ansible))}))
    (root/'inventory.ini').write_text('[inventory_automation]\nj2-svpi4mf ansible_host=10.1.2.170 ansible_user=ama ansible_python_interpreter=/usr/bin/python3 ansible_ssh_common_args="-o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10"\n')
    (root/'ansible.cfg').write_text('[defaults]\nhost_key_checking=True\nretry_files_enabled=False\nno_target_syslog=True\n[ssh_connection]\npipelining=True\n')
    shutil.copyfile(root/'ansible.cfg',root/'runtime/ansible.cfg')
    validate(root)
    rows={str(p.relative_to(root)):sha(p) for p in sorted(root.rglob('*')) if p.is_file()}
    (root/'bundle.json').write_text(json.dumps(rows,sort_keys=True)+'\n');print(sha(root/'bundle.json'))

def verify(root,digest):
    require(root.is_absolute() and not any(p.is_symlink() for p in (root,*root.parents)),'bundle_path')
    require(sha(root/'bundle.json')==digest,'bundle_identity')
    rows=json.loads((root/'bundle.json').read_text())
    require(set(rows)==set(FILES)|{'runtime/operation.json','runtime/ansible.cfg','controller.json','inventory.ini','ansible.cfg'},'bundle_members')
    require({str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()}==set(rows)|{'bundle.json'},'unexpected_members')
    for name,digest in rows.items():
        p=root/name;require(not p.is_symlink() and not any(v.is_symlink() for v in p.parents) and sha(p)==digest,'input_drift')
    return validate(root)

def execute(root,digest,evidence):
    op=verify(root,digest);require(op['operation']['execution_enabled'],'disabled')
    require(evidence.is_absolute() and not evidence.exists() and evidence.parent.stat().st_uid==os.getuid()
            and evidence.parent.stat().st_mode & 0o777==0o700
            and not any(p.is_symlink() for p in (evidence,*evidence.parents)),'evidence_path')
    controller=json.loads((root/'controller.json').read_text());require(sha(Path(controller['ansible']))==controller['sha256'],'controller_drift')
    with (root.parent/('consumed-'+digest+'.json')).open('x') as f:json.dump({'bundle_sha256':digest,'evidence':str(evidence)},f)
    evidence.mkdir(mode=0o700)
    inputs=dict(capture_bundle_verified=True,capture_operation=op,capture_bundle=str(root),capture_evidence=str(evidence))
    (evidence/'inputs.json').write_text(json.dumps(inputs))
    env={k:os.environ[k] for k in ('HOME','PATH','SSH_AUTH_SOCK','USER','LOGNAME') if k in os.environ}
    env.update(ANSIBLE_CONFIG=str(root/'ansible.cfg'),PYTHONDONTWRITEBYTECODE='1',ANSIBLE_NOCOLOR='1')
    rc=70
    try:
        with (evidence/'ansible.stdout').open('xb') as out,(evidence/'ansible.stderr').open('xb') as err:
            rc=subprocess.run(['/usr/bin/prlimit','--core=0:0','--fsize=8388608:8388608','--','/bin/bash',str(root/'ansible-temp.sh'),controller['ansible'],'-i',str(root/'inventory.ini'),str(root/'playbook.yaml'),'--extra-vars','@'+str(evidence/'inputs.json')],cwd=root,env=env,stdin=subprocess.DEVNULL,stdout=out,stderr=err,timeout=1500).returncode
    finally:(evidence/'controller-result.json').write_text(json.dumps({'exit_status':rc,'accepted':False}))
    return rc

if __name__=='__main__':
    os.umask(0o077)
    p=argparse.ArgumentParser();p.add_argument('action',choices=['freeze','verify','execute']);p.add_argument('bundle',type=Path);p.add_argument('--approve');p.add_argument('--evidence',type=Path);a=p.parse_args()
    if a.action=='freeze':freeze(a.bundle)
    elif a.action=='verify':verify(a.bundle,a.approve)
    else:sys.exit(execute(a.bundle,a.approve,a.evidence))
