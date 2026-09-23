#!/usr/bin/env python3
"""Frozen credential operation; private process output and no secret evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import secrets
import shutil
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True

ROOT = next((p for p in Path(__file__).resolve().parents if (p/'Nautobot/manifests').is_dir()), None)
FILES = {'active.yaml':'Nautobot/manifests/operation.yaml',
         'schema.json':'Nautobot/schemas/credential-operation.schema.json',
         'launcher.py':'Nautobot/ansible/scripts/provision-credentials.py',
         'playbook.yaml':'Nautobot/ansible/playbooks/provision-credentials.yaml',
         'settings.py':'Nautobot/ansible/templates/runtime/nautobot_config.py',
         'operation.json':'Nautobot/manifests/credential-operation.json',
         'policy.json':'Nautobot/manifests/credential-preparation.json',
         'accepted.yaml':'Nautobot/manifests/accepted-live-state.yaml',
         'qualified.json':'Nautobot/manifests/qualified-image.json',
         'tests.py':'Nautobot/tests/test_credentials.py',
         'PROCEDURE.md':'Nautobot/docs/CREDENTIAL_PROVISIONING.md',
         'ansible-temp.sh':'tests/repository/run-with-ansible-local-temp.sh'}
KEYS = ['NAUTOBOT_DJANGO_SECRET_KEY','NAUTOBOT_POSTGRESQL_PASSWORD',
        'NAUTOBOT_REDIS_PASSWORD','NAUTOBOT_INITIAL_ADMIN_PASSWORD']
META = {'DOPPLER_CONFIG','DOPPLER_ENVIRONMENT','DOPPLER_PROJECT'}


class Blocked(Exception):
    pass


def private_run(argv, timeout=60, extra_env=None):
    """Anonymous output files; bound child output/core size; never expose stderr."""
    def bound():
        resource.setrlimit(resource.RLIMIT_CORE,(0,0))
        resource.setrlimit(resource.RLIMIT_FSIZE,(1024*1024,1024*1024))
    fds=[os.memfd_create('private-output',os.MFD_CLOEXEC) for _ in range(2)]
    try:
        env={k:os.environ[k] for k in ['HOME','PATH','SSH_AUTH_SOCK'] if k in os.environ}
        env.update(extra_env or {})
        env.update(LC_ALL='C.UTF-8',ANSIBLE_NOCOLOR='1',ANSIBLE_DISPLAY_ARGS_TO_STDOUT='false')
        try:
            p=subprocess.Popen(argv,stdout=fds[0],stderr=fds[1],env=env,preexec_fn=bound,start_new_session=True)
            try:p.wait(timeout=timeout)
            except BaseException:
                os.killpg(p.pid,signal.SIGKILL);p.wait()
                raise
        except (subprocess.TimeoutExpired,OSError):
            raise Blocked('private_command_timeout_or_unavailable') from None
        if p.returncode or any(os.fstat(fd).st_size >= 1024*1024 for fd in fds):
            raise Blocked('private_command_failed')
        os.lseek(fds[0],0,0)
        return os.read(fds[0],1024*1024).decode()
    finally:
        for fd in fds:os.close(fd)


def doppler(*args):
    return private_run(['doppler',*args,'--project','homelab-dev','--api-host','https://api.doppler.com',
                        '--no-check-version','--no-verify-tls=false','--attempts','1','--timeout','10s'])


def names(config):
    result=json.loads(doppler('secrets','--only-names','--config',config,'--json'))
    if not isinstance(result,dict) or not all(isinstance(k,str) for k in result):
        raise Blocked('names_response_shape')
    return set(result)


def create_values():
    return {key:secrets.token_hex(64 if i==0 else 32) for i,key in enumerate(KEYS)}


def write_private(path, text):
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f:f.write(text)


def payloads(values):
    import re
    if set(values)!=set(KEYS) or any(not re.fullmatch('[0-9a-f]{'+str(128 if i==0 else 64)+'}',values[k]) for i,k in enumerate(KEYS)):
        raise Blocked('secret_properties')
    app={'NAUTOBOT_SECRET_KEY':values[KEYS[0]],'NAUTOBOT_DB_PASSWORD':values[KEYS[1]],
         'NAUTOBOT_DB_USER':'nautobot','NAUTOBOT_DB_NAME':'nautobot','NAUTOBOT_DB_HOST':'postgresql',
         'NAUTOBOT_REDIS_HOST':'redis','NAUTOBOT_REDIS_PASSWORD':values[KEYS[2]]}
    encode=lambda d:''.join(k+'='+v+'\n' for k,v in d.items())
    result={name+'.env':encode(app) for name in ['migration','web','worker','scheduler']}
    result['postgresql.env']=encode({'POSTGRES_PASSWORD':values[KEYS[1]]})
    result['redis.env']=encode({'REDISCLI_AUTH':values[KEYS[2]]})
    result['redis.conf']='appendonly yes\nappendfsync everysec\nmaxmemory 384mb\nmaxmemory-policy noeviction\nrequirepass '+values[KEYS[2]]+'\n'
    return result


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(bundle,digest):
    index=bundle/'SHA256SUMS.json'
    if bundle.is_symlink() or index.is_symlink() or sha(index)!=digest:raise Blocked('bundle_hash')
    rows=json.loads(index.read_text())
    if set(rows)!=set(FILES)|{'inventory.json','ansible.cfg'} or {p.name for p in bundle.iterdir()}!=set(rows)|{'SHA256SUMS.json'}:
        raise Blocked('bundle_members')
    for name,value in rows.items():
        p=bundle/name
        if p.is_symlink() or not p.is_file() or sha(p)!=value:raise Blocked('bundle_member')


def prepare(bundle):
    if ROOT is None:raise Blocked('repository_required')
    import yaml
    from jsonschema import Draft202012Validator
    operation=json.loads((ROOT/FILES['operation.json']).read_text())
    Draft202012Validator(json.loads((ROOT/FILES['schema.json']).read_text())).validate(operation)
    if yaml.safe_load((ROOT/FILES['active.yaml']).read_text())!=operation:raise Blocked('active_operation_mismatch')
    bundle.mkdir(mode=0o700)
    for name,source in FILES.items():shutil.copyfile(ROOT/source,bundle/name)
    (bundle/'inventory.json').write_text(json.dumps({'all':{'hosts':{'credential_target':{
        'ansible_host':'j2-svpi4mf.local.theama.co','ansible_user':'ama','ansible_python_interpreter':'/usr/bin/python3',
        'ansible_ssh_common_args':'-o StrictHostKeyChecking=yes -o HostKeyAlias=10.1.2.170 -o BatchMode=yes -o ConnectTimeout=6'}}}})+'\n')
    (bundle/'ansible.cfg').write_text('[defaults]\nhost_key_checking=True\nretry_files_enabled=False\nstdout_callback=default\nno_target_syslog=True\n')
    (bundle/'SHA256SUMS.json').write_text(json.dumps({p.name:sha(p) for p in sorted(bundle.iterdir())},indent=2)+'\n')
    digest=sha(bundle/'SHA256SUMS.json');verify(bundle,digest);print(digest)


def transact(bundle,evidence,run_play):
    root=None
    phase='preflight'
    result={'accepted':False,'phase':phase,'doppler_state':'unchanged','host_state':'unchanged','runtime_started':False}
    checkpoint=lambda:(evidence/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    checkpoint()
    try:
        run_play('preflight',None)
        configs=json.loads(doppler('configs','--json'))
        configs=configs.get('configs') if isinstance(configs,dict) else configs
        if not isinstance(configs,list) or any(not isinstance(c,dict) or not isinstance(c.get('name'),str) for c in configs):raise Blocked('config_response_shape')
        if any(c['name']=='prd_nautobot' for c in configs):raise Blocked('config_already_exists')
        if not any(c['name']=='prd' and c.get('environment')=='prd' for c in configs):raise Blocked('parent_missing')
        if names('prd')!=META:raise Blocked('parent_secret_drift')
        result.update(phase='config_create',doppler_state='creation_attempted')
        checkpoint()
        doppler('configs','create','prd_nautobot','--environment','prd','--json')
        if names('prd_nautobot')!=META:raise Blocked('new_config_not_empty')
        values=create_values()
        with tempfile.TemporaryDirectory(prefix='nautobot-credentials.',dir='/tmp') as tmp:
            root=Path(tmp);root.chmod(0o700)
            upload=root/'upload.json';write_private(upload,json.dumps(values))
            result.update(phase='secret_write',doppler_state='write_attempted')
            checkpoint()
            doppler('secrets','upload',str(upload),'--config','prd_nautobot','--silent')
            upload.unlink()
            if names('prd_nautobot')!=META|set(KEYS):raise Blocked('key_set_mismatch')
            for key,value in values.items():
                if doppler('secrets','get',key,'--plain','--config','prd_nautobot').strip()!=value:raise Blocked('secret_readback_mismatch')
            result.update(doppler_state='verified',phase='injection',host_state='injection_attempted')
            checkpoint()
            for name,value in payloads(values).items():write_private(root/name,value)
            run_play('inject',root)
            result.update(accepted=True,phase='complete',host_state='injection_verified')
    except Exception as exc:
        # Only fixed codes, never exception strings from libraries or command output.
        result['accepted']=False
        result['error']=str(exc) if isinstance(exc,Blocked) else 'operation_failed_review_required'
    finally:
        result['controller_payload_cleanup_verified']=root is None or not root.exists()
        if not result['controller_payload_cleanup_verified']:
            result.update(accepted=False,controller_payload_path=str(root),error='controller_cleanup_failed')
        (evidence/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    return 0 if result['accepted'] else 69


def execute(bundle,digest):
    verify(bundle,digest)
    evidence=Path(tempfile.mkdtemp(prefix='nautobot-credential-evidence.'));print('evidence='+str(evidence),flush=True)
    with tempfile.TemporaryDirectory(prefix='nautobot-credential-snapshot.') as tmp:
        snapshot=Path(tmp)/'bundle';shutil.copytree(bundle,snapshot);verify(snapshot,digest)
        def play(mode,payload):
            args={'credential_bundle_verified':True,'credential_mode':mode,'bundle_root':str(snapshot),'payload_root':str(payload) if payload else ''}
            private_run(['/bin/bash',str(snapshot/'ansible-temp.sh'),'ansible-playbook','-i',str(snapshot/'inventory.json'),str(snapshot/'playbook.yaml'),'-e',json.dumps(args)],timeout=300,extra_env={'ANSIBLE_CONFIG':str(snapshot/'ansible.cfg')})
        return transact(snapshot,evidence,play)


def main():
    os.umask(0o077)
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    parser=argparse.ArgumentParser();parser.add_argument('mode',choices=['prepare','verify','execute']);parser.add_argument('bundle',type=Path);parser.add_argument('digest',nargs='?');a=parser.parse_args()
    try:
        if a.mode=='prepare':prepare(a.bundle.resolve());return 0
        if not a.digest:raise Blocked('exact_bundle_approval_required')
        if a.mode=='verify':verify(a.bundle.resolve(),a.digest);return 0
        return execute(a.bundle.resolve(),a.digest)
    except Exception:
        print('blocked; no raw diagnostic output retained');return 69


if __name__=='__main__':raise SystemExit(main())
