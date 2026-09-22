#!/usr/bin/env python3
"""Exact approval boundary for cold preservation and ledger inspection."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('runtime', Path(__file__).with_name('run-runtime.py'))
runtime = importlib.util.module_from_spec(spec); spec.loader.exec_module(runtime)
bounded = runtime.bounded
ROOT = runtime.ROOT


def validate():
    subprocess.run(['check-jsonschema','--schemafile',str(ROOT/'Nautobot/schemas/database-inspection.schema.json'),
                    str(ROOT/'Nautobot/manifests/operation.yaml')],check=True,timeout=30,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    return bounded.yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())


def rows(op):
    result = runtime.bundle_rows(op)
    for name in ('Nautobot/ansible/scripts/run-database-inspection.py',
                 'Nautobot/ansible/scripts/inspect-retained-database.py',
                 'Nautobot/ansible/playbooks/inspect-retained-database.yaml',
                 'Nautobot/schemas/database-inspection.schema.json',
                 'Nautobot/tests/test_database_inspection.py'):
        p = ROOT/name
        if p.is_symlink() or not p.is_file(): raise bounded.PreflightBlocked('unsafe_source')
        result.append((hashlib.sha256(p.read_bytes()).hexdigest(),name))
    return list(dict.fromkeys(result))


def verify(op):
    runtime.verify_prerequisites(op)
    old = op['predecessor']
    raw = subprocess.check_output(['git','-C',str(ROOT),'show',old['tag']+':Nautobot/manifests/runtime-initialization-result.json'],timeout=30)
    kind = subprocess.check_output(['git','-C',str(ROOT),'cat-file','-t',old['tag']],timeout=30).strip()
    commit = subprocess.check_output(['git','-C',str(ROOT),'rev-parse',old['tag']+'^{}'],timeout=30).decode().strip()
    if (hashlib.sha256(raw).hexdigest()!=old['result_sha256'] or kind!=b'tag' or commit!=old['commit']
            or json.loads(raw)['outcome']!='native_post_upgrade_timeout_partial_initialization_retained'):
        raise bounded.PreflightBlocked('predecessor_identity')


def execute(approved):
    op=validate(); inputs=rows(op); bounded.BUNDLE_DOMAIN='nautobot-database-inspection-v1'
    digest=bounded.bundle_hash(inputs)
    if digest!=approved: raise bounded.PreflightBlocked('bundle_hash_mismatch')
    verify(op); bounded.EVIDENCE_PREFIX='nautobot-inspection.'
    root,fd=bounded.prepare_evidence(inputs,digest)
    bounded.write_exclusive(fd,'ansible-progress.jsonl',b'')
    env=bounded.minimal_environment()
    env.update(ANSIBLE_CONFIG=str(ROOT/'Nautobot/ansible/ansible.cfg'),PYTHONDONTWRITEBYTECODE='1',
               ANSIBLE_CALLBACK_PLUGINS=str(ROOT/'Nautobot/ansible/callback_plugins'),ANSIBLE_CALLBACKS_ENABLED='runtime_progress',
               NAUTOBOT_PROGRESS_FILE=str(root/'ansible-progress.jsonl'))
    argv=('/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i',str(ROOT/'inventory/prod/hosts.yaml'),
          '--limit','j2-svpi4mf','--user','ama','--extra-vars',json.dumps({'ansible_host':'10.1.2.170','inspection_bundle_verified':True,'inspection_evidence_root':str(root)}),
          str(ROOT/'Nautobot/ansible/playbooks/inspect-retained-database.yaml'))
    result={'accepted':False,'bundle_sha256':digest,'mutation_status':'review_required'}
    try:
        bounded.COMMAND_TIMEOUT_SECONDS=1200
        rc,out,err,truncated=bounded.drain_process(argv,env)
        result.update(ansible_exit_status=rc,output_truncated=truncated,stdout_bytes=len(out),stderr_bytes=len(err))
    except BaseException:
        result['error_class']='execution_interrupted_or_failed'
    finally:
        events=[json.loads(x) for x in (root/'ansible-progress.jsonl').read_text().splitlines()]
        result['task_diagnostics_complete']=bool(events) and events[-1]['event']=='playbook_complete'
        result['task_failures']=[x for x in events if x['event'] in ('task_failed','unreachable')]
        bounded.write_exclusive(fd,'result.json',json.dumps(result).encode());os.close(fd)
    print('Review required; evidence_root='+str(root))
    return 0 if result.get('ansible_exit_status')==0 and not result.get('output_truncated') and result['task_diagnostics_complete'] else 69


def main():
    os.umask(0o077)
    p=argparse.ArgumentParser();p.add_argument('mode',choices=('show-hash','execute'));p.add_argument('hash',nargs='?');a=p.parse_args()
    if a.mode=='show-hash':
        op=validate();verify(op);bounded.BUNDLE_DOMAIN='nautobot-database-inspection-v1';print(bounded.bundle_hash(rows(op)));return 0
    if not a.hash:p.error('exact approved hash required')
    try:return execute(a.hash)
    except Exception:print('blocked: local_validation_or_identity');return 69

if __name__=='__main__':raise SystemExit(main())
