#!/usr/bin/env python3
"""Assemble or execute an exact frozen Ansible image qualification bundle."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True
import yaml

ROOT = next((p for p in Path(__file__).resolve().parents
             if (p/'Nautobot/container/Containerfile').is_file()), None)
PREVIOUS_EVIDENCE = Path('/home/aaron/code/.local-evidence/nautobot-image-build-20260921')
PREVIOUS_BUNDLE_SHA256 = '21c15632af42c3e7d1aeb689889a0538a58e58a6b00b2a2f5024ca243f7c06a4'
FILES = {
    'failure-evidence.json':'Nautobot/manifests/image-qualification-failure.json',
    'image-build-node.py':'Nautobot/ansible/scripts/image-build-node.py',
    'qualify-image.yaml':'Nautobot/ansible/playbooks/qualify-image.yaml',
    'build.service.j2':'Nautobot/ansible/templates/image-build/build.service.j2',
    'watch.service.j2':'Nautobot/ansible/templates/image-build/watch.service.j2',
    'input/Containerfile':'Nautobot/container/Containerfile',
    'input/requirements.lock':'Nautobot/container/requirements.lock',
    'input-evidence.json':'Nautobot/manifests/image-build-input-evidence.json',
    'test_image_build.py':'Nautobot/tests/test_image_build.py',
    'accepted.yaml':'Nautobot/manifests/accepted-live-state.yaml',
    'desired.yaml':'Nautobot/manifests/desired-state.yaml',
    'operation.yaml':'Nautobot/manifests/operation.yaml',
    'operation.schema.json':'Nautobot/schemas/image-build.schema.json',
    'PROCEDURE.md':'Nautobot/docs/OPERATIONS.md',
    'run-with-ansible-local-temp.sh':'tests/repository/run-with-ansible-local-temp.sh',
    'launcher.py':'Nautobot/ansible/scripts/prepare-image-build.py',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(bundle, expected):
    index = bundle/'SHA256SUMS.json'
    if index.is_symlink() or sha(index) != expected:
        raise ValueError('bundle_hash_mismatch')
    rows = json.loads(index.read_text())
    if set(rows) != set(FILES) | {'spec.json', 'inventory.json', 'ansible.cfg', 'predecessor.json'}:
        raise ValueError('bundle_members')
    entries = list(bundle.rglob('*'))
    if any(p.is_symlink() for p in entries):
        raise ValueError('bundle_symlink')
    if {str(p.relative_to(bundle)) for p in entries if p.is_dir()} != {'input'}:
        raise ValueError('unexpected_bundle_directory')
    actual = {str(p.relative_to(bundle)) for p in entries if not p.is_dir()}
    if actual != set(rows) | {'SHA256SUMS.json'}:
        raise ValueError('unexpected_bundle_file')
    for name, digest in rows.items():
        p = bundle/name
        if any(q.is_symlink() for q in [p, *p.parents]) or not p.is_file() or sha(p) != digest:
            raise ValueError('bundle_member_mismatch')
    return rows


def prepare(destination, retry=False):
    if ROOT is None:
        raise ValueError('prepare_requires_repository_checkout')
    from jsonschema import Draft202012Validator
    operation = yaml.safe_load((ROOT/FILES['operation.yaml']).read_text())
    schema = json.loads((ROOT/FILES['operation.schema.json']).read_text())
    Draft202012Validator(schema).validate(operation)
    accepted = yaml.safe_load((ROOT/FILES['accepted.yaml']).read_text())
    identity = accepted['dual_stack_identity']
    git = lambda *args: subprocess.check_output(['git', '-C', str(ROOT), *args])
    if git('rev-parse', identity['terminal_tag']+'^{}').decode().strip() != identity['definition_commit']:
        raise ValueError('terminal_provenance')
    terminal = git('show', identity['terminal_tag']+':Nautobot/manifests/terminal-identity-evidence.json')
    if hashlib.sha256(terminal).hexdigest() != identity['terminal_evidence_sha256']:
        raise ValueError('terminal_evidence')
    baseline = accepted['provenance']
    if git('rev-parse', baseline['terminal_tag']+'^{}').decode().strip() != baseline['definition_commit']:
        raise ValueError('baseline_provenance')
    if hashlib.sha256(git('show', baseline['terminal_tag']+':Nautobot/manifests/terminal-evidence.yaml')).hexdigest() != baseline['terminal_evidence_sha256']:
        raise ValueError('baseline_evidence')
    if operation['build']['boot_id'] != accepted['host_baseline']['boot_id']:
        raise ValueError('boot_identity')
    for name, digest in operation['build']['input_sha256'].items():
        if sha(ROOT/'Nautobot/container'/name) != digest:
            raise ValueError('stale_build_input')
    desired = yaml.safe_load((ROOT/FILES['desired.yaml']).read_text())
    if desired['images']['nautobot_base']['reference'] != operation['build']['base_image']:
        raise ValueError('desired_base_drift')
    evidence = json.loads((ROOT/FILES['input-evidence.json']).read_text())
    if 'sha256:'+evidence['base_manifest_sha256'] != operation['build']['base_image'].split('@')[1]:
        raise ValueError('registry_manifest_drift')
    if evidence['platform'] != {'os':'linux','architecture':'arm64'}:
        raise ValueError('registry_platform')
    if evidence['validation_test_sha256'] != sha(ROOT/FILES['test_image_build.py']):
        raise ValueError('validation_test_drift')
    predecessor = None
    if retry:
        # Preserve the active consumed definition; this is an unactivated candidate.
        old = PREVIOUS_EVIDENCE
        approved = old/'approved-bundle'
        old_hash = PREVIOUS_BUNDLE_SHA256
        index = json.loads((approved/'SHA256SUMS.json').read_text())
        if sha(approved/'SHA256SUMS.json') != old_hash:
            raise ValueError('predecessor_bundle_hash')
        for name, digest in index.items():
            if sha(approved/name) != digest:
                raise ValueError('predecessor_member_hash')
        if (approved/'operation.yaml').read_bytes() != (ROOT/FILES['operation.yaml']).read_bytes():
            raise ValueError('consumed_definition_changed')
        result_path = old/'execution/result.json'
        result = json.loads(result_path.read_text())
        if result != {'passed':False,'reason':'failed_unit','stop_confirmed':True,
                      'artifacts_retained':True,'runtime_accepted':False}:
            raise ValueError('predecessor_not_stopped_failure')
        predecessor = {'repository':str(ROOT), 'tag':'nautobot-image-qualification-v1-failed',
                       'operation_sha256':sha(approved/'operation.yaml'),
                       'bundle_sha256':old_hash, 'id':operation['build']['id'],
                       'result_sha256':sha(result_path),
                       'terminal_evidence_sha256':sha(ROOT/FILES['failure-evidence.json'])}
        operation['operation']['id'] = 'nautobot-image-qualification-v2'
        operation['build']['id'] = hashlib.sha256((old_hash+sha(ROOT/FILES['image-build-node.py'])).encode()).hexdigest()[:12]
        operation['build']['predecessor'] = predecessor
        schema['const'] = operation
    destination.mkdir(mode=0o700)
    for name, source in FILES.items():
        p = ROOT/source
        if p.is_symlink() or not p.is_file():
            raise ValueError('unsafe_source')
        target = destination/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(p, target)
    if retry:
        (destination/'operation.yaml').write_text(yaml.safe_dump(operation, sort_keys=False))
        (destination/'operation.schema.json').write_text(json.dumps(schema, indent=2)+'\n')
    (destination/'predecessor.json').write_text(json.dumps(predecessor, indent=2)+'\n')
    spec = operation['build']
    (destination/'spec.json').write_text(json.dumps(spec, indent=2)+'\n')
    inventory = {'all':{'hosts':{'build_target':{'ansible_host':'j2-svpi4mf.local.theama.co',
                 'ansible_user':'ama','ansible_python_interpreter':'/usr/bin/python3',
                 'ansible_ssh_common_args':'-o StrictHostKeyChecking=yes -o HostKeyAlias=10.1.2.170 -o BatchMode=yes -o ConnectTimeout=6'}}}}
    (destination/'inventory.json').write_text(json.dumps(inventory)+'\n')
    (destination/'ansible.cfg').write_text('[defaults]\nhost_key_checking = True\nretry_files_enabled = False\ntimeout = 10\n')
    names = set(FILES) | {'spec.json', 'inventory.json', 'ansible.cfg', 'predecessor.json'}
    rows = {name:sha(destination/name) for name in sorted(names)}
    (destination/'SHA256SUMS.json').write_text(json.dumps(rows, indent=2)+'\n')
    digest = sha(destination/'SHA256SUMS.json')
    verify(destination, digest)
    print(digest)
    return digest


def require_predecessor_archive(bundle):
    prior = json.loads((bundle/'predecessor.json').read_text())
    if prior is None:
        return
    git = lambda *args: subprocess.check_output(
        ['git','-C',prior['repository'],*args], stderr=subprocess.PIPE, timeout=20)
    tag = prior['tag']
    if git('cat-file','-t',tag).strip() != b'tag':
        raise ValueError('predecessor_annotated_archive_required')
    definition = git('show',tag+':Nautobot/manifests/operation.yaml')
    if hashlib.sha256(definition).hexdigest() != prior['operation_sha256']:
        raise ValueError('predecessor_archive_definition')
    terminal = git('show',tag+':Nautobot/manifests/image-qualification-failure.json')
    if hashlib.sha256(terminal).hexdigest() != prior['terminal_evidence_sha256']:
        raise ValueError('predecessor_archive_evidence')
    tag_id = git('rev-parse',tag).decode().strip()
    published = git('ls-remote','--tags','origin','refs/tags/'+tag).decode().split()
    if published != [tag_id,'refs/tags/'+tag]:
        raise ValueError('predecessor_archive_not_published')


def execute(bundle, digest):
    # The literal digest is external execution authorization. Preparation is not.
    verify(bundle, digest)
    require_predecessor_archive(bundle)
    with tempfile.TemporaryDirectory(prefix='nautobot-image-execute.') as tmp:
        snapshot = Path(tmp)/'bundle'
        shutil.copytree(bundle, snapshot)
        verify(snapshot, digest)
        evidence = Path(tempfile.mkdtemp(prefix='nautobot-image-evidence.'))
        env = {k:os.environ[k] for k in ['HOME','PATH','SSH_AUTH_SOCK'] if k in os.environ}
        env.update(ANSIBLE_CONFIG=str(snapshot/'ansible.cfg'), LC_ALL='C.UTF-8')
        argv = ['/bin/bash', str(snapshot/'run-with-ansible-local-temp.sh'), 'ansible-playbook',
                '-i', str(snapshot/'inventory.json'), str(snapshot/'qualify-image.yaml'),
                '--extra-vars', json.dumps({'bundle_root':str(snapshot),'evidence_root':str(evidence),
                                          'image_bundle_verified':True})]
        print('controller_evidence='+str(evidence), flush=True)
        # Controller timeout is not node cancellation; watchdog remains independent.
        module_spec = importlib.util.spec_from_file_location('bounded_build', snapshot/'image-build-node.py')
        bounded = importlib.util.module_from_spec(module_spec)
        module_spec.loader.exec_module(bounded)
        bounded.AUDIT = evidence/'controller-command.jsonl'
        try:
            bounded.capture(argv, timeout=3000, limit=4*1024**2, env=env)
            return 0
        except Exception as exc:
            (evidence/'controller-failure.json').write_text(json.dumps({'error':str(exc)[:200], 'remote_outcome':'requires_node_evidence_review'})+'\n')
            return 69


def main():
    os.umask(0o077)
    p = argparse.ArgumentParser()
    p.add_argument('mode', choices=['prepare','prepare-retry','verify','execute'])
    p.add_argument('bundle', type=Path)
    p.add_argument('hash', nargs='?')
    a = p.parse_args()
    if a.mode in ['prepare','prepare-retry']:
        prepare(a.bundle.resolve(), retry=a.mode == 'prepare-retry')
    else:
        if not a.hash or not re.fullmatch('[0-9a-f]{64}', a.hash):
            p.error('exact SHA-256 authorization required')
        if a.mode == 'verify':
            verify(a.bundle.resolve(), a.hash)
        else:
            raise SystemExit(execute(a.bundle.resolve(), a.hash))


if __name__ == '__main__':
    main()
