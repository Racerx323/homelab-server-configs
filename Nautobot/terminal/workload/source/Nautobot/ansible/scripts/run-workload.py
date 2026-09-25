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
from contextlib import contextmanager

ROOT = Path(__file__).resolve().parents[3]
REQUIRED = {'execution.json', 'contract.json', 'dataset.json', 'workload_adapter.py',
            'workload_jobs.py', 'workload_control.py', 'workload_session.py', 'workload_sampler.py', 'run-workload.yaml', 'workload_capture.py', 'backup-sources.json', 'desired-state.yaml', 'requirements.lock', 'qualified-image.json', 'application-backup.py', 'application-backup.json'}
DATA_FILES = {'desired-state.yaml': 'Nautobot/manifests/desired-state.yaml',
              'requirements.lock': 'Nautobot/container/requirements.lock',
              'qualified-image.json': 'Nautobot/manifests/qualified-image.json'}
SOURCE_FILES = ('Nautobot/docs/OPERATIONS.md', 'restic/docs/RESTIC_ARCHITECTURE.md','Nautobot/manifests/operation.yaml', 'Nautobot/schemas/workload-operation.schema.json', 'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md', 'Nautobot/manifests/accepted-live-state.yaml', 'Nautobot/manifests/workload-capture-result.json', 'Nautobot/manifests/restic-initialization-result.json','Nautobot/ansible/scripts/run-restic-repository-preflight.py','Nautobot/container/requirements.lock', 'Nautobot/manifests/qualified-image.json', 'restic/scripts/application-backup.py', 'Nautobot/ansible/scripts/run-workload.py', 'Nautobot/ansible/ansible.cfg', 'Nautobot/schemas/workload-test.schema.json', 'Nautobot/schemas/workload-execution.schema.json',
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
    if execution.get('resume'):
        if execution['resume']['source_operation'] == execution['operation_id']: raise ValueError('retained_source_operation')
        if 'retained-ownership.json' not in files or files['retained-ownership.json'] != execution['resume']['ownership_sha256']:
            raise ValueError('retained_ownership_identity')
        ownership = json.loads((bundle/'retained-ownership.json').read_text())
        if ownership.get('fixture_sha256') != hashlib.sha256(generator.canonical(generator.dataset(contract))).hexdigest():
            raise ValueError('retained_fixture_identity')
        adapter_spec = importlib.util.spec_from_file_location('retained_adapter', ROOT/'Nautobot/ansible/scripts/workload_adapter.py')
        adapter = importlib.util.module_from_spec(adapter_spec); adapter_spec.loader.exec_module(adapter)
        if (set(ownership) != {'schema_version','fixture_sha256','objects'} or ownership['schema_version'] != 1
                or set(ownership['objects']) != {n['key'] for n in adapter.plan(generator.dataset(contract))}):
            raise ValueError('retained_ownership_shape')
        import uuid
        for identity in ownership['objects'].values(): uuid.UUID(identity)
        if len(set(execution['resume']['registration'].values())) != 3: raise ValueError('retained_registration_identity')
    elif 'retained-ownership.json' in files:
        raise ValueError('unreviewed_retained_ownership')
    verify_operation(execution, load_operation())
    return manifest, execution


def load_operation():
    import yaml
    return yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())


def verify_operation(execution, operation):
    from jsonschema import Draft202012Validator, FormatChecker
    from jsonschema import RefResolver
    schemas = ROOT/'Nautobot/schemas'
    schema = json.loads((schemas/'workload-operation.schema.json').read_text())
    resolver = RefResolver(base_uri=schemas.as_uri()+'/', referrer=schema)
    Draft202012Validator(schema, resolver=resolver, format_checker=FormatChecker()).validate(operation)
    active = operation['operation']
    if active['state'] != 'definition' or active['authorization_ready'] is not True: raise ValueError('operation_inactive')
    if operation['execution'] != execution or active['id'] != execution['operation_id']: raise ValueError('operation_execution_mismatch')
    if operation['plan_sha256'] != hashlib.sha256((ROOT/'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md').read_bytes()).hexdigest(): raise ValueError('plan_drift')


@contextmanager
def resolved_credentials(bundle, evidence, reader=None):
    """Use the existing bounded Doppler reader; cleanup is independent per file."""
    if reader is None:
        import importlib.util
        spec = importlib.util.spec_from_file_location('restic_secrets', ROOT/'Nautobot/ansible/scripts/run-restic-repository-preflight.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        reader = module.read_secret
    directory = Path(tempfile.mkdtemp(prefix='nautobot-workload-secrets.'))
    values = []
    cleanup = {}
    try:
        for config, name in (
            ('prd_restic', 'NAUTOBOT_RESTIC_REPOSITORY_PASSWORD'),
            ('prd_b2', 'NAUTOBOT_RESTIC_B2_APPLICATION_KEY_ID'),
            ('prd_b2', 'NAUTOBOT_RESTIC_B2_APPLICATION_KEY'),
        ):
            values.append(reader('homelab-dev', config, name))
        repository = json.loads((bundle/'application-backup.json').read_text())['repository_url']
        payloads = {'repository': repository.encode(), 'password': values[0],
                    'credentials.json': json.dumps({'id': values[1].decode(), 'key': values[2].decode()}).encode()}
        for name, value in payloads.items():
            fd = os.open(directory/name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, 'wb') as stream: stream.write(value)
        del payloads
        yield directory
    finally:
        for value in values: value[:] = b'\0' * len(value)
        for name in ('password', 'credentials.json', 'repository'):
            try:
                (directory/name).unlink(missing_ok=True)
                cleanup[name] = not (directory/name).exists()
            except OSError: cleanup[name] = False
        try: directory.rmdir()
        except OSError: cleanup['directory'] = False
        else: cleanup['directory'] = True
        if evidence.is_dir():
            path = evidence/'controller-credential-cleanup.json'
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, 'w') as stream: json.dump(cleanup, stream)
        if not all(cleanup.values()): raise ValueError('controller_credential_cleanup_incomplete')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--approve', required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    credentials = parser.add_mutually_exclusive_group(required=True)
    credentials.add_argument('--backup-secrets', type=Path, help='Protected separately resolved credential directory; caller owns cleanup')
    credentials.add_argument('--resolve-doppler', action='store_true', help='Resolve the approved references transiently and remove controller copies')
    args = parser.parse_args()
    manifest, execution = verify(args.bundle, args.approve)
    if args.resolve_doppler:
        with resolved_credentials(args.bundle, args.evidence) as directory:
            args.backup_secrets = directory
            return execute(args, manifest, execution)
    return execute(args, manifest, execution)


def execute(args, manifest, execution):
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
        '--extra-vars','@'+str(inputs)],cwd=ROOT,env=environment,timeout=11700)
    raise SystemExit(result.returncode)

if __name__=='__main__':main()
