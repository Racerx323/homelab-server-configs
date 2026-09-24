#!/usr/bin/env python3
"""Verify an externally prepared exact workload bundle before invoking Ansible.

This runner does not prepare authorization, accept a baseline, resolve secrets,
implement a backup, or mutate the current operation manifest.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
REQUIRED = {'execution.json', 'contract.json', 'dataset.json', 'workload_adapter.py',
            'workload_jobs.py', 'workload_control.py', 'workload_session.py', 'workload_sampler.py', 'run-workload.yaml', 'workload_capture.py', 'backup-sources.json', 'desired-state.yaml', 'requirements.lock', 'qualified-image.json', 'application-backup.py', 'application-backup.json'}
DATA_FILES = {'desired-state.yaml': 'Nautobot/manifests/desired-state.yaml',
              'requirements.lock': 'Nautobot/container/requirements.lock',
              'qualified-image.json': 'Nautobot/manifests/qualified-image.json'}
SOURCE_FILES = ('Nautobot/container/requirements.lock', 'Nautobot/manifests/qualified-image.json', 'restic/scripts/application-backup.py', 'Nautobot/ansible/scripts/run-workload.py', 'Nautobot/ansible/ansible.cfg', 'Nautobot/schemas/workload-test.schema.json', 'Nautobot/schemas/workload-execution.schema.json',
    'Nautobot/ansible/scripts/make-workload-fixture.py', 'Nautobot/ansible/scripts/validate-contracts.py',
    'Nautobot/schemas/desired-state.schema.json', 'Nautobot/manifests/desired-state.yaml',
    'tests/repository/run-with-ansible-local-temp.sh', 'inventory/prod/hosts.yaml',
    'inventory/prod/groups/inventory_automation.yaml', 'inventory/prod/hosts/j2-svpi4mf.yaml')


def verify(bundle, approved):
    raw = (bundle/'bundle.json').read_bytes()
    if hashlib.sha256(raw).hexdigest() != approved: raise ValueError('bundle_identity')
    manifest = json.loads(raw)
    if set(manifest['source_files']) != set(SOURCE_FILES): raise ValueError('source_inputs')
    for name, digest in manifest['source_files'].items():
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest() != digest: raise ValueError('source_drift')
    files = manifest['files']
    if not REQUIRED.issubset(files): raise ValueError('bundle_inputs_missing')
    for name, digest in files.items():
        path = bundle/name
        if not re.fullmatch('[A-Za-z0-9_.-]+', name) or path.is_symlink() or not path.is_file(): raise ValueError('bundle_path')
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest: raise ValueError('input_identity')
    # A self-consistent bundle must also contain the reviewed repository code.
    for name in REQUIRED - {'execution.json', 'contract.json', 'dataset.json', 'application-backup.json', 'backup-sources.json'}:
        source = (ROOT/DATA_FILES[name] if name in DATA_FILES else ROOT/'restic/scripts'/name if name == 'application-backup.py' else
                  ROOT/'Nautobot/ansible/playbooks'/name if name.endswith('.yaml') else
                  ROOT/'Nautobot/ansible/scripts'/name)
        if hashlib.sha256(source.read_bytes()).hexdigest() != files[name]:
            raise ValueError('execution_source_identity')
    execution = json.loads((bundle/'execution.json').read_text())
    from jsonschema import Draft202012Validator, FormatChecker
    Draft202012Validator(json.loads((ROOT/'Nautobot/schemas/workload-execution.schema.json').read_text()), format_checker=FormatChecker()).validate(execution)
    if execution['stage'] != 'workload_qualification' or execution['execution_authorized'] is not True: raise ValueError('inactive')
    if execution['baseline_review']['passed'] is not True or execution['baseline_review']['boot_id'] != execution['boot_id']: raise ValueError('baseline')
    if set(execution['baseline_review']['services']) != {'postgresql', 'redis', 'web', 'worker', 'scheduler'}: raise ValueError('baseline_services')
    if execution['backup']['authorized'] is not True: raise ValueError('backup_not_authorized')
    if not re.fullmatch(r'/tmp/nautobot-workload\.[0-9a-f]{32}', execution['root']): raise ValueError('operation_path')
    # Every owner helper must be frozen; executable code outside the bundle is not accepted.
    backup = execution['backup']
    if backup['argv'][:1] != ['/usr/bin/python3'] or len(backup['argv']) < 2: raise ValueError('backup_entrypoint')
    script = Path(backup['argv'][1])
    if script.parent != Path(execution['root']) or script.name != 'application-backup.py' or script.name not in files: raise ValueError('backup_not_frozen')
    if Path(backup['receipt']) != Path(execution['root'])/'application-backup-result.json': raise ValueError('backup_receipt_path')
    if hashlib.sha256((ROOT/'restic/scripts/application-backup.py').read_bytes()).hexdigest() != files['application-backup.py']: raise ValueError('backup_source_identity')
    if backup['argv'] != ['/usr/bin/python3', str(script), '--root', execution['root']]: raise ValueError('backup_arguments')
    import importlib.util
    producer_spec = importlib.util.spec_from_file_location('backup_producer', ROOT/'restic/scripts/application-backup.py')
    producer = importlib.util.module_from_spec(producer_spec); producer_spec.loader.exec_module(producer)
    backup_contract = json.loads((bundle/'application-backup.json').read_text())
    producer.validate(backup_contract)
    if backup_contract['operation_id'] != execution['operation_id']: raise ValueError('backup_operation_identity')
    source_policy = json.loads((bundle/'backup-sources.json').read_text())
    if source_policy.get('consistency') != 'quiet_pilot_empty_media' or source_policy.get('quiet_window_confirmed') is not True:
        raise ValueError('backup_consistency')
    prefix = ['/usr/bin/python3', execution['root']+'/workload_capture.py', '--root', execution['root']]
    for section, capture in backup_contract['captures'].items():
        if capture['argv'] != prefix + [section]: raise ValueError('backup_capture_arguments')
    if backup_contract['dump_validator'] != prefix + ['validate_dump']: raise ValueError('backup_validator_arguments')
    from jsonschema import validate
    import yaml
    contract = json.loads((bundle/'contract.json').read_text())
    validate(contract, json.loads((ROOT/'Nautobot/schemas/workload-test.schema.json').read_text()))
    import importlib.util
    spec = importlib.util.spec_from_file_location('generator', ROOT/'Nautobot/ansible/scripts/make-workload-fixture.py')
    generator = importlib.util.module_from_spec(spec); spec.loader.exec_module(generator)
    if json.loads((bundle/'dataset.json').read_text()) != generator.dataset(contract): raise ValueError('fixture_mismatch')
    return manifest, execution


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--approve', required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--backup-secrets', type=Path, required=True, help='Protected separately resolved credential directory; never frozen')
    args = parser.parse_args()
    manifest, execution = verify(args.bundle, args.approve)
    import stat
    for p, mode in [(args.backup_secrets, 0o700), *((args.backup_secrets/n, 0o600) for n in ('repository', 'password', 'credentials.json'))]:
        info=p.lstat()
        if p.is_symlink() or any(parent.is_symlink() for parent in p.parents) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != mode or not (stat.S_ISDIR(info.st_mode) if mode == 0o700 else stat.S_ISREG(info.st_mode)): raise ValueError('backup_secret_metadata')
    args.evidence.mkdir(mode=0o700, parents=False, exist_ok=False)
    artifacts = [{'name': n, 'source': str((args.bundle/n).resolve()), 'sha256': sha} for n, sha in manifest['files'].items() if n != 'run-workload.yaml']
    extra = {'ansible_host': '10.1.2.170', 'workload_bundle_verified': True, 'workload_baseline_verified': True,
             'workload_execution': execution, 'workload_root': execution['root'],
             'workload_backup_secrets': str(args.backup_secrets.resolve()), 'workload_artifacts': artifacts, 'workload_local_evidence': str(args.evidence.resolve()),
             'workload_job_artifacts': [a for a in artifacts if a['name'] in ('workload_adapter.py', 'workload_jobs.py')]}
    inputs = args.evidence/'ansible-inputs.json'; inputs.write_text(json.dumps(extra)); inputs.chmod(0o600)
    environment = {k: v for k, v in os.environ.items() if k in ('PATH', 'HOME', 'USER', 'LOGNAME', 'SSH_AUTH_SOCK', 'LANG', 'LC_ALL')}
    environment['ANSIBLE_CONFIG'] = str(ROOT/'Nautobot/ansible/ansible.cfg')
    result = subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
        'ansible-playbook','--limit','j2-svpi4mf','--user','ama','-i',str(ROOT/'inventory/prod/hosts.yaml'),str(args.bundle/'run-workload.yaml'),
        '--extra-vars','@'+str(inputs)],cwd=ROOT,env=environment,timeout=11100)
    raise SystemExit(result.returncode)

if __name__=='__main__':main()
