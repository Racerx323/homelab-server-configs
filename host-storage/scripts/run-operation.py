#!/usr/bin/env python3
"""Bind one Ansible operation to exact local inputs and protected evidence."""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import signal
import subprocess
import sys

import jsonschema
import yaml

COMPONENT = Path(__file__).resolve().parents[1]
REPO = COMPONENT.parent


def read_yaml(path):
    return yaml.safe_load(path.read_text())


def bundle(operation, host_path):
    paths = sorted(p for p in COMPONENT.rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    paths += [host_path, REPO / 'inventory/prod/hosts.yaml', REPO / 'tests/repository/run-with-ansible-local-temp.sh']
    entries = {}
    for path in paths:
        if path.is_symlink():
            raise ValueError('Symlink input rejected')
        entries[str(path.relative_to(REPO))] = hashlib.sha256(path.read_bytes()).hexdigest()
    entries['operation'] = hashlib.sha256(json.dumps(operation, sort_keys=True).encode()).hexdigest()
    return hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest(), entries


def prepare(operation):
    jsonschema.validate(operation, json.loads((COMPONENT / 'schemas/operation.schema.json').read_text()))
    host_path = REPO / 'inventory/prod/hosts' / (operation['host'] + '.yaml')
    def members(group):
        names = set(group.get('hosts', {}))
        for child in group.get('children', {}).values():
            names.update(members(child))
        return names
    if operation['host'] not in members(read_yaml(REPO / 'inventory/prod/hosts.yaml')['all']):
        raise ValueError('Host is not an inventory member')
    host = read_yaml(host_path)
    selected = host['storage']['root']['transport_profile']
    if not re.fullmatch(r'[a-z0-9-]+', selected):
        raise ValueError('Unsafe profile identifier')
    profile = read_yaml(COMPONENT / 'profiles' / (selected + '.yaml'))
    if profile['id'] != selected or host['hardware']['platform'] != profile['platform']:
        raise ValueError('Inventory/profile mismatch')
    adapter = host['storage']['root']['adapter']
    if adapter['manufacturer'] != profile['adapter_manufacturer'] or adapter['model'] != profile['adapter_model']:
        raise ValueError('Inventory adapter does not match profile')
    if profile['quirk_flag'] != 'u' or profile['expected_driver'] != 'usb-storage':
        raise ValueError('Unsupported profile implementation')
    if host['storage']['root']['transport'] != 'usb_storage' or host['storage']['root']['uas_disabled'] is not True:
        raise ValueError('Inventory transport assertions conflict with profile')
    if not re.fullmatch(r'[0-9a-f]{4}:[0-9a-f]{4}', profile['bridge']):
        raise ValueError('Invalid bridge identifier')
    if profile['boot_file'] != '/boot/firmware/cmdline.txt':
        raise ValueError('Unsupported boot-file backend')
    return host_path, host, profile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--operation', type=Path, required=True)
    parser.add_argument('--stage', choices=['bundle', 'preflight', 'apply', 'validate', 'rollback'], required=True)
    parser.add_argument('--evidence', type=Path)
    parser.add_argument('--approved-bundle')
    args = parser.parse_args()
    operation = json.loads(args.operation.read_text())
    host_path, host, profile = prepare(operation)
    bundle_hash, inputs = bundle(operation, host_path)
    if args.stage == 'bundle':
        print(json.dumps({'sha256': bundle_hash, 'inputs': inputs}, indent=2))
        return
    if args.stage != 'preflight' and args.approved_bundle != bundle_hash:
        raise ValueError('Reviewed bundle digest is required for this stage')
    if args.stage in ('apply', 'rollback'):
        required = 'authorize_' + args.stage
        if not operation[required]:
            raise ValueError('Operation does not authorize ' + args.stage)
    if not args.evidence or not args.evidence.is_absolute():
        raise ValueError('Explicit absolute evidence directory required')
    evidence = args.evidence
    if evidence.is_symlink() or any(p.is_symlink() for p in evidence.parents):
        raise ValueError('Evidence symlink rejected')
    if evidence.is_relative_to(REPO) or evidence.parent.stat().st_uid != os.getuid() or evidence.parent.stat().st_mode & 0o077:
        raise ValueError('Evidence needs a private owned parent outside the repository')
    evidence.mkdir(mode=0o700, parents=False, exist_ok=False)
    os.umask(0o077)
    (evidence / 'bundle.json').write_text(json.dumps({'sha256': bundle_hash, 'inputs': inputs}, indent=2))
    (evidence / 'operation.json').write_text(json.dumps(operation, indent=2))
    # Execute a verified snapshot, not files that may change after review.
    snapshot = evidence / 'source'
    for relative, expected in inputs.items():
        if relative == 'operation':
            continue
        source = REPO / relative
        data = source.read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError('Bundle input changed while preparing execution')
        destination = snapshot / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    snapshot_host = read_yaml(snapshot / host_path.relative_to(REPO))
    snapshot_profile = read_yaml(snapshot / 'host-storage/profiles' / (host['storage']['root']['transport_profile'] + '.yaml'))
    if snapshot_host != host or snapshot_profile != profile:
        raise ValueError('Inventory or profile changed after validation')
    inventory = {'all': {'hosts': {operation['host']: {
        'ansible_host': operation['address'], 'ansible_user': operation['user'],
        'ansible_python_interpreter': '/usr/bin/python3',
        'ansible_ssh_common_args': '-o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15',
    }}}}
    (evidence / 'inventory.json').write_text(json.dumps(inventory))
    variables = {'storage_profile': profile, 'storage_host': host,
                 'storage_operation': operation, 'storage_evidence': str(evidence)}
    (evidence / 'vars.json').write_text(json.dumps(variables))
    config = evidence / 'ansible.cfg'
    config.write_text('[defaults]\nhost_key_checking = True\nretry_files_enabled = False\n[inventory]\nenable_plugins = yaml\n')
    # An isolated explicit configuration avoids inherited project callbacks or inventory.
    env = {k: v for k, v in os.environ.items() if not k.startswith('ANSIBLE_')}
    env['ANSIBLE_CONFIG'] = str(config)
    command = ['/bin/bash', str(snapshot / 'tests/repository/run-with-ansible-local-temp.sh'),
               'ansible-playbook', '-i', str(evidence / 'inventory.json'),
               str(snapshot / 'host-storage/ansible/playbooks' / (args.stage + '.yaml')),
               '--extra-vars', '@' + str(evidence / 'vars.json')]
    # Each run is bounded; retain failures as evidence without declaring acceptance.
    with (evidence / 'stdout.txt').open('w') as out, (evidence / 'stderr.txt').open('w') as err:
        try:
            def limit_output():
                resource.setrlimit(resource.RLIMIT_FSIZE, (8 * 1024 * 1024, 8 * 1024 * 1024))
            process = subprocess.Popen(command, env=env, stdout=out, stderr=err,
                                       start_new_session=True, preexec_fn=limit_output)
            status = process.wait(timeout=900)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            status = 124
    (evidence / 'status.json').write_text(json.dumps({'exit_status': status, 'stage': args.stage,
        'acceptance': 'operator_review_required', 'manual_intervention_required': bool(status and args.stage in ('apply', 'rollback'))}))
    if args.stage == 'preflight' and status == 0:
        import base64
        observed = json.loads((evidence / 'preflight-observed.json').read_text())
        before = base64.b64decode(observed['original_b64']).decode()
        after = base64.b64decode(observed['proposed_b64']).decode()
        (evidence / 'boot-format.json').write_text(json.dumps({
            'original_bytes': len(before.encode('ascii')), 'proposed_bytes': len(after.encode('ascii')),
            'original_final_newline': before.endswith('\n'), 'proposed_final_newline': after.endswith('\n')}))
        (evidence / 'boot.diff').write_text(''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile=profile['boot_file'], tofile=profile['boot_file'])))
        operation.update(expected_boot_sha256=observed['boot_sha256'], expected_boot_id=observed['boot_id'],
                         expected_root_uuid=observed['root_uuid'], proposed_boot_sha256=observed['proposed_sha256'],
                         expect_new_boot=observed['reboot_required'])
        (evidence / 'proposed-operation.json').write_text(json.dumps(operation, indent=2))
    print(json.dumps({'stage': args.stage, 'exit_status': status, 'evidence': str(evidence)}))
    if status:
        raise SystemExit(status)


if __name__ == '__main__':
    main()
