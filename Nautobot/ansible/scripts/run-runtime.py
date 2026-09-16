#!/usr/bin/env python3
"""Thin inactive runtime deployment gate and bounded Ansible launcher."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('bounded', Path(__file__).with_name('run-restic-repository-preflight.py'))
bounded = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bounded)
ROOT = bounded.ROOT


def execute(authorized_hash):
    subprocess.run(['check-jsonschema', '--schemafile', str(ROOT/'Nautobot/schemas/operation.schema.json'),
                    str(ROOT/'Nautobot/manifests/operation.yaml')], check=True, timeout=30,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    operation = bounded.yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())
    if (operation['operation']['stage'] != 'nautobot_pilot'
        or operation['operation']['authorization_ready'] is not True
        or operation['authorization']['mutation_authorized'] is not True
        or operation['authorization']['blockers']):
        raise bounded.PreflightBlocked('runtime_not_ready')
    subprocess.run(['check-jsonschema', '--schemafile', str(ROOT/'Nautobot/schemas/accepted-host-baseline.schema.json'),
                    str(ROOT/'Nautobot/manifests/accepted-live-state.yaml')], check=True, timeout=30,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    dirty = subprocess.run(['git', '-C', str(ROOT), 'status', '--porcelain'], capture_output=True, check=True, timeout=30)
    if dirty.stdout:
        raise bounded.PreflightBlocked('clean_source_required')
    sources = [
        'Nautobot/manifests/operation.yaml', 'Nautobot/manifests/desired-state.yaml',
        'Nautobot/manifests/accepted-live-state.yaml', 'Nautobot/schemas/operation.schema.json',
        'Nautobot/schemas/host-convergence.schema.json', 'Nautobot/schemas/repository-initialization.schema.json',
        'Nautobot/schemas/accepted-host-baseline.schema.json',
        'Nautobot/ansible/scripts/run-runtime.py', 'Nautobot/ansible/scripts/validate-contracts.py',
        'Nautobot/schemas/desired-state.schema.json', 'Nautobot/container/Containerfile',
        'Nautobot/container/requirements.lock', 'Nautobot/ansible/scripts/render-runtime.py',
        'Nautobot/ansible/scripts/run-restic-repository-preflight.py',
        'Nautobot/ansible/playbooks/deploy-runtime.yaml', 'Nautobot/ansible/ansible.cfg',
        'Nautobot/ansible/templates/runtime/container.j2', 'Nautobot/ansible/templates/runtime/network.j2',
        'Nautobot/ansible/templates/runtime/volume.j2', 'Nautobot/docs/OPERATIONS.md',
        'inventory/prod/hosts.yaml', 'inventory/prod/groups/inventory_automation.yaml',
        'inventory/prod/hosts/j2-svpi4mf.yaml', 'tests/repository/run-with-ansible-local-temp.sh']
    rows=[]
    for name in sources:
        path=ROOT/name
        if path.is_symlink() or not path.is_file():raise bounded.PreflightBlocked('unsafe_source')
        rows.append((hashlib.sha256(path.read_bytes()).hexdigest(), name))
    rendered=Path(operation['runtime']['rendered_directory'])
    if not rendered.is_absolute() or rendered.is_symlink():raise bounded.PreflightBlocked('unsafe_rendered_directory')
    for name,digest in sorted(operation['runtime']['artifact_sha256'].items()):
        if Path(name).name != name:raise bounded.PreflightBlocked('unsafe_artifact_name')
        path=rendered/name
        if path.is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
            raise bounded.PreflightBlocked('artifact_hash_mismatch')
        rows.append((digest,'rendered/'+name))
    bounded.BUNDLE_DOMAIN='nautobot-runtime-bundle-v1'
    digest=bounded.bundle_hash(rows)
    if digest!=authorized_hash:raise bounded.PreflightBlocked('bundle_hash_mismatch')
    bounded.EVIDENCE_PREFIX='nautobot-runtime.'
    root,fd=bounded.prepare_evidence(rows,digest)
    environment=bounded.minimal_environment()
    environment.update(ANSIBLE_CONFIG=str(ROOT/'Nautobot/ansible/ansible.cfg'),LC_ALL='C.UTF-8')
    argv=('/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
          'ansible-playbook','--inventory',str(ROOT/'inventory/prod/hosts.yaml'),
          '--limit','j2-svpi4mf','--user','ama','--extra-vars',
          json.dumps({'ansible_host':'10.1.2.170','runtime_bundle_verified':True,
                      'runtime_rendered_directory':str(rendered),'runtime_evidence_root':str(root)}),
          str(ROOT/'Nautobot/ansible/playbooks/deploy-runtime.yaml'))
    result={'accepted':False,'mutation_status':'unknown_until_review','bundle_sha256':digest}
    try:
        bounded.COMMAND_TIMEOUT_SECONDS=1800
        rc,out,err,truncated=bounded.drain_process(argv,environment)
        # Do not retain service output: diagnostics may contain application secrets.
        result.update(ansible_exit_status=rc,output_truncated=truncated,
                      stdout_bytes=len(out),stderr_bytes=len(err))
    except BaseException:
        result['error_class']='execution_interrupted_or_failed'
    finally:
        bounded.write_exclusive(fd,'result.json',json.dumps(result).encode())
        os.close(fd)
    print('Review required; evidence_root='+str(root))
    return 0 if result.get('ansible_exit_status')==0 and not result.get('output_truncated') else 69


def main():
    os.umask(0o077)
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['show-command','execute']);p.add_argument('authorized_hash',nargs='?');a=p.parse_args()
    if a.mode=='show-command':
        print('python3 Nautobot/ansible/scripts/run-runtime.py execute AUTHORIZED_SHA256')
        print('Inactive: no runtime operation or accepted custom image has been selected.')
        return 0
    if not a.authorized_hash:p.error('exact authorized SHA256 required')
    try:return execute(a.authorized_hash)
    except bounded.PreflightBlocked as exc:
        print('result=blocked error='+exc.code);return 69
    except Exception:
        print('result=blocked error=local_validation_failed');return 69


if __name__=='__main__':raise SystemExit(main())
