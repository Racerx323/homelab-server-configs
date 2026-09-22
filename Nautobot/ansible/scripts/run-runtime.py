#!/usr/bin/env python3
"""Exact-bundle initialization gate and bounded Ansible launcher."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import stat
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('bounded', Path(__file__).with_name('run-restic-repository-preflight.py'))
bounded = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bounded)
ROOT = bounded.ROOT


def validate():
    try:
        subprocess.run(['check-jsonschema', '--schemafile', str(ROOT/'Nautobot/schemas/operation.schema.json'),
                        str(ROOT/'Nautobot/manifests/operation.yaml')], check=True, timeout=30,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError as exc:
        raise bounded.PreflightBlocked('runtime_not_ready') from exc
    operation = bounded.yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())
    if (operation['operation'].get('stage') not in ('runtime_initialization', 'runtime_continuation', 'administrator_bootstrap')
            or not operation['operation']['authorization_ready']
            or not operation['authorization']['mutation_authorized'] or operation['authorization']['blockers']):
        raise bounded.PreflightBlocked('runtime_not_ready')
    return operation


def verify_prerequisites(operation, require_clean=True):
    def git(*args):
        try:return subprocess.check_output(['git','-C',str(ROOT),*args],stderr=subprocess.DEVNULL,timeout=30)
        except (OSError,subprocess.SubprocessError) as exc:raise bounded.PreflightBlocked('archive_unavailable') from exc
    for proof in operation['prerequisites']:
        raw=(ROOT/proof['path']).read_bytes(); result=json.loads(raw)
        if (hashlib.sha256(raw).hexdigest()!=proof['sha256'] or result.get('accepted') is not True
                or result.get('result',result.get('outcome',result.get('phase')))!=proof['outcome']
                or git('cat-file','-t',proof['tag']).strip()!=b'tag'
                or git('rev-parse',proof['tag']+'^{}').decode().strip()!=proof['commit']
                or git('show',proof['tag']+':'+proof['path'])!=raw):
            raise bounded.PreflightBlocked('prerequisite_identity')
    for name,digest in operation['input_sha256'].items():
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest:
            raise bounded.PreflightBlocked('accepted_input_drift')
    if require_clean and git('status','--porcelain'):raise bounded.PreflightBlocked('clean_source_required')


def bundle_rows(operation):
    sources = [
        'Nautobot/manifests/operation.yaml', 'Nautobot/manifests/desired-state.yaml',
        'Nautobot/manifests/accepted-live-state.yaml', 'Nautobot/schemas/operation.schema.json', 'Nautobot/schemas/runtime-initialization.schema.json',
        'Nautobot/schemas/host-convergence.schema.json', 'Nautobot/schemas/repository-initialization.schema.json',
        'Nautobot/schemas/accepted-host-baseline.schema.json',
        'Nautobot/schemas/runtime-continuation.schema.json',
        'Nautobot/schemas/administrator-bootstrap.schema.json',
        'Nautobot/ansible/playbooks/continue-runtime-tasks.yaml',
        'Nautobot/ansible/scripts/continuation-node.py',
        'Nautobot/ansible/scripts/inspect-retained-database.py',
        'Nautobot/ansible/scripts/migration-continuation.py',
        'Nautobot/tests/test_runtime_continuation.py',
        'Nautobot/ansible/scripts/run-runtime.py', 'Nautobot/ansible/scripts/validate-contracts.py',
        'Nautobot/schemas/desired-state.schema.json', 'Nautobot/container/Containerfile',
        'Nautobot/container/requirements.lock', 'Nautobot/ansible/scripts/render-runtime.py',
        'Nautobot/ansible/scripts/run-restic-repository-preflight.py',
        'Nautobot/ansible/playbooks/deploy-runtime.yaml', 'Nautobot/ansible/scripts/initialize-application.py',
        'Nautobot/ansible/callback_plugins/runtime_progress.py',
        'Nautobot/ansible/playbooks/inspect-retained-database.yaml',
        'Nautobot/ansible/scripts/runtime-initialization-node.py', 'restic/scripts/canary-backup.py',
        'Nautobot/tests/test_runtime_initialization.py', 'Nautobot/docs/RUNTIME_INITIALIZATION.md', 'Nautobot/ansible/ansible.cfg',
        'Nautobot/ansible/templates/runtime/container.j2', 'Nautobot/ansible/templates/runtime/network.j2',
        'Nautobot/ansible/templates/runtime/volume.j2', 'Nautobot/docs/OPERATIONS.md',
        'inventory/prod/hosts.yaml', 'inventory/prod/groups/inventory_automation.yaml',
        'inventory/prod/hosts/j2-svpi4mf.yaml', 'tests/repository/run-with-ansible-local-temp.sh']
    if operation['operation']['stage'] == 'administrator_bootstrap':
        sources += ['Nautobot/ansible/playbooks/bootstrap-administrator.yaml',
                    'Nautobot/ansible/scripts/bootstrap-node.py',
                    'Nautobot/ansible/scripts/bootstrap-application.py',
                    'Nautobot/ansible/scripts/bootstrap-secret.py',
                    'Nautobot/ansible/scripts/provision-credentials.py',
                    'Nautobot/tests/test_administrator_bootstrap.py',
                    'Nautobot/docs/BOOTSTRAP_AND_STARTUP.md']
    sources += [p['path'] for p in operation['prerequisites']] + list(operation['input_sha256'])
    rows=[]
    for name in dict.fromkeys(sources):
        path=ROOT/name
        if path.is_symlink() or not path.is_file():raise bounded.PreflightBlocked('unsafe_source')
        rows.append((hashlib.sha256(path.read_bytes()).hexdigest(), name))
    if operation['operation']['stage'] == 'administrator_bootstrap':
        identity = Path(operation['bootstrap']['identity_reference'])
        try:
            info = identity.lstat()
        except OSError as exc:
            raise bounded.PreflightBlocked('bootstrap_identity_metadata') from exc
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > 4096):
            raise bounded.PreflightBlocked('bootstrap_identity_metadata')
        raw = identity.read_bytes()
        data = json.loads(raw)
        if (set(data) != {'username', 'email'} or data['username'] != 'admin'
                or not isinstance(data['email'], str) or '@' not in data['email']):
            raise bounded.PreflightBlocked('bootstrap_identity_shape')
        # This private identity contains no password. Its hash is only in the
        # private bundle manifest, never the public operation definition.
        rows.append((hashlib.sha256(raw).hexdigest(), 'private/bootstrap-identity.json'))
    rendered=Path(operation['runtime']['rendered_directory'])
    if not rendered.is_absolute() or rendered.is_symlink():raise bounded.PreflightBlocked('unsafe_rendered_directory')
    for name,digest in sorted(operation['runtime']['artifact_sha256'].items()):
        if Path(name).name != name:raise bounded.PreflightBlocked('unsafe_artifact_name')
        path=rendered/name
        if path.is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
            raise bounded.PreflightBlocked('artifact_hash_mismatch')
        rows.append((digest,'rendered/'+name))
    return rows


def execute(authorized_hash):
    operation=validate()
    rows=bundle_rows(operation)
    bounded.BUNDLE_DOMAIN='nautobot-runtime-bundle-v1'
    digest=bounded.bundle_hash(rows)
    if digest!=authorized_hash:raise bounded.PreflightBlocked('bundle_hash_mismatch')
    verify_prerequisites(operation)
    rendered=Path(operation['runtime']['rendered_directory'])
    bounded.EVIDENCE_PREFIX='nautobot-runtime.'
    root,fd=bounded.prepare_evidence(rows,digest)
    bounded.write_exclusive(fd,'ansible-progress.jsonl',b'')
    environment=bounded.minimal_environment()
    environment.update(ANSIBLE_CONFIG=str(ROOT/'Nautobot/ansible/ansible.cfg'),LC_ALL='C.UTF-8',PYTHONDONTWRITEBYTECODE='1')
    environment.update(ANSIBLE_CALLBACK_PLUGINS=str(ROOT/'Nautobot/ansible/callback_plugins'),
                       ANSIBLE_CALLBACKS_ENABLED='runtime_progress',
                       NAUTOBOT_PROGRESS_FILE=str(root/'ansible-progress.jsonl'))
    bootstrap = operation['operation']['stage'] == 'administrator_bootstrap'
    secret_directory = tempfile.mkdtemp(prefix='nautobot-bootstrap.', dir='/dev/shm') if bootstrap else None
    if secret_directory:
        bounded.write_exclusive(fd, 'bootstrap-input-location.json',
                                json.dumps({'directory': secret_directory, 'contains_secret_values': False}).encode())
    argv=('/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
          'ansible-playbook','--inventory',str(ROOT/'inventory/prod/hosts.yaml'),
          '--limit','j2-svpi4mf','--user','ama','--extra-vars',
          json.dumps({'ansible_host':'10.1.2.170','runtime_bundle_verified':True,
                      'runtime_rendered_directory':str(rendered),'runtime_evidence_root':str(root),
                      'runtime_secret_directory':secret_directory,
                      'runtime_bootstrap_identity_sha256':dict((name, digest) for digest, name in rows).get('private/bootstrap-identity.json')}),
          str(ROOT/'Nautobot/ansible/playbooks'/('bootstrap-administrator.yaml' if bootstrap else 'deploy-runtime.yaml')))
    result={'accepted':False,'mutation_status':'unknown_until_review','bundle_sha256':digest}
    try:
        bounded.COMMAND_TIMEOUT_SECONDS=operation['runtime']['overall_timeout_seconds']
        rc,out,err,truncated=bounded.drain_process(argv,environment)
        # Do not retain service output: diagnostics may contain application secrets.
        result.update(ansible_exit_status=rc,output_truncated=truncated,
                      stdout_bytes=len(out),stderr_bytes=len(err))
    except BaseException:
        result['error_class']='execution_interrupted_or_failed'
    finally:
        if secret_directory:
            try:
                (Path(secret_directory)/'input.json').unlink(missing_ok=True)
                Path(secret_directory).rmdir()
                result['controller_secret_cleanup'] = True
            except OSError:
                result['controller_secret_cleanup'] = False
        try:
            events=[json.loads(line) for line in (root/'ansible-progress.jsonl').read_text().splitlines()]
            result['task_diagnostics_complete']=bool(events) and events[-1].get('event')=='playbook_complete'
            result['task_failures']=[e for e in events if e.get('event') in ('task_failed','unreachable')]
        except (OSError,ValueError):
            result['task_diagnostics_complete']=False
        bounded.write_exclusive(fd,'result.json',json.dumps(result).encode())
        os.close(fd)
    print('Review required; evidence_root='+str(root))
    return 0 if (result.get('ansible_exit_status')==0 and not result.get('output_truncated')
                 and result.get('task_diagnostics_complete') and result.get('controller_secret_cleanup', True)) else 69


def main():
    os.umask(0o077)
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['show-command','show-hash','execute']);p.add_argument('authorized_hash',nargs='?');a=p.parse_args()
    if a.mode=='show-command':
        print('python3 Nautobot/ansible/scripts/run-runtime.py execute AUTHORIZED_SHA256')
        print('One reviewed runtime stage only; exact-bundle live authorization required.')
        return 0
    if a.mode=='show-hash':
        operation=validate();verify_prerequisites(operation, require_clean=False)
        bounded.BUNDLE_DOMAIN='nautobot-runtime-bundle-v1'
        print(bounded.bundle_hash(bundle_rows(operation)));return 0
    if not a.authorized_hash:p.error('exact authorized SHA256 required')
    try:return execute(a.authorized_hash)
    except bounded.PreflightBlocked as exc:
        print('result=blocked error='+exc.code);return 69
    except Exception:
        print('result=blocked error=local_validation_failed');return 69


if __name__=='__main__':raise SystemExit(main())
