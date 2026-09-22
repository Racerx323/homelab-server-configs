#!/usr/bin/env python3
"""Deterministic local Quadlet renderer; never contacts Podman or a host."""
import argparse
import importlib.util
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

import yaml
from jinja2 import Environment, FileSystemLoader, StrictUndefined

ROOT = Path(__file__).resolve().parents[3]
TEMPLATES = ROOT / 'Nautobot/ansible/templates/runtime'
SERVICES = {'postgresql', 'redis', 'migration', 'web', 'worker', 'scheduler'}
DESTINATIONS = {'postgresql_data': '/var/lib/postgresql/data', 'redis_data': '/data', 'nautobot_media': '/opt/nautobot/media'}


def render(desired, inputs, initialization=False, continuation=None):
    if continuation is not None and (not initialization or not re.fullmatch('[0-9a-f]{64}', continuation)):
        raise ValueError('continuation_token')
    spec = importlib.util.spec_from_file_location('contracts', Path(__file__).with_name('validate-contracts.py'))
    contracts = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(contracts)
    contracts.validate(desired)
    if set(inputs) != {'custom_image', 'recovery_host'}:
        raise ValueError('require only custom_image and approved recovery_host')
    if not re.fullmatch(r'[a-z0-9][a-z0-9./:_-]*@sha256:[a-f0-9]{64}', inputs['custom_image']):
        raise ValueError('custom image must be an immutable reference')
    if not re.fullmatch(r'[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?', inputs['recovery_host']):
        raise ValueError('recovery host must be a reviewed DNS name or IPv4 address')
    if set(desired['services']) != SERVICES:
        raise ValueError('unreviewed service set')
    if desired['runtime']['privilege'] != 'rootless' or desired['runtime']['systemd_scope'] != 'user':
        raise ValueError('rootless user runtime required')
    import copy
    desired = copy.deepcopy(desired)
    if initialization:
        desired['services']['migration']['memory_limit_mib'] = 1536
        desired['services']['migration']['volumes'] = []
    env = Environment(loader=FileSystemLoader(TEMPLATES), undefined=StrictUndefined,
                      trim_blocks=True, lstrip_blocks=True, keep_trailing_newline=True)
    artifacts = {'nautobot-private.network': env.get_template('network.j2').render(network=desired['runtime']['network'])}
    for name in desired['volumes']:
        if name not in DESTINATIONS:
            raise ValueError('unreviewed volume')
        artifacts[f'nautobot-{name}.volume'] = env.get_template('volume.j2').render(name=name)
    for name, service in desired['services'].items():
        image = inputs['custom_image'] if service['image'] == 'custom_nautobot' else desired['images'][service['image']]['reference']
        if not re.fullmatch(r'[a-z0-9][a-z0-9./:_-]*@sha256:[a-f0-9]{64}', image):
            raise ValueError('mutable service image')
        if name != 'web' and service.get('published_endpoints'):
            raise ValueError('only web may publish ports')
        for endpoint in service.get('published_endpoints', []):
            if (endpoint['address'], endpoint['family'], endpoint['port']) not in {
                ('127.0.0.1', 'ipv4', 8080), ('10.1.2.170', 'ipv4', 8080), ('fd36:5aa8:6971:1::170', 'ipv6', 8080)}:
                raise ValueError('unreviewed backend binding')
        commands = {'migration': '/run/initialize-application.py' if initialization else ' '.join(desired['services']['migration']['command'][1:]),
                    'web': 'start --http 0.0.0.0:8080',
                    'worker': 'celery worker --loglevel INFO --concurrency ' + str(desired['services']['worker']['concurrency']),
                    'scheduler': 'celery beat --loglevel INFO'}
        artifacts[f'nautobot-{name}.container'] = env.get_template('container.j2').render(
            name=name, service=service, image=image, command=commands.get(name, ''), initialization=initialization, continuation=continuation,
            dependencies=['nautobot-' + dep + '.service' for dep in service.get('depends_on', [])],
            volumes=[{'name': v, 'destination': DESTINATIONS[v]} for v in service.get('volumes', [])])
    # Non-secret review contract; actual protected configuration is provided separately.
    contract = {'custom_image': inputs['custom_image'], 'recovery_host': inputs['recovery_host'],
                'allowed_hosts': list(dict.fromkeys(desired['application']['settings']['allowed_hosts'] + [inputs['recovery_host']])),
                'csrf_trusted_origins': desired['application']['settings']['csrf_trusted_origins'],
                'secure_proxy_ssl_header': desired['application']['settings']['secure_proxy_ssl_header'],
                'redis_memory_policy': desired['services']['redis']['memory_policy'],
                'redis_persistence': desired['services']['redis']['persistence'],
                'execution_authorized': False}
    artifacts['configuration-contract.json'] = json.dumps(contract, sort_keys=True, indent=2) + '\n'
    if initialization:
        names = {'nautobot-private.network', 'nautobot-postgresql_data.volume', 'nautobot-redis_data.volume',
                 'nautobot-postgresql.container', 'nautobot-redis.container', 'nautobot-migration.container'}
        return {k: v for k, v in artifacts.items() if k in names}
    return artifacts



def verify_qualified_inputs(inputs, qualified, accepted):
    """Bind operator rendering to archived image evidence, not a plausible digest."""
    if inputs['custom_image'] != qualified['reference']:
        raise ValueError('runtime_image_not_qualified')
    if qualified['reference'] != 'localhost/nautobot-homelab@'+qualified['manifest_digest']:
        raise ValueError('qualified_reference_mismatch')
    if inputs['recovery_host'] != accepted['dual_stack_identity']['fqdn']:
        raise ValueError('recovery_identity_mismatch')
    if qualified['runtime_accepted'] or qualified['runtime_store_loaded']:
        raise ValueError('unexpected_runtime_acceptance')
    git=lambda *args: subprocess.check_output(['git','-C',str(ROOT),*args],timeout=15)
    tag=qualified['terminal_tag']
    if git('cat-file','-t',tag).strip()!=b'tag' or git('rev-parse',tag+'^{}').decode().strip()!=qualified['terminal_commit']:
        raise ValueError('image_archive_identity')
    raw=git('show',tag+':Nautobot/manifests/image-qualification-result.json')
    if hashlib.sha256(raw).hexdigest()!=qualified['terminal_evidence_sha256']:
        raise ValueError('image_archive_hash')
    result=json.loads(raw)
    for key in ['image_id','archive_sha256']:
        if result[key]!=qualified[key]:raise ValueError('image_artifact_mismatch')
    if result['oci_manifest_digest']!=qualified['manifest_digest'] or result['outcome']!='bounded_static_image_qualification_passed':
        raise ValueError('image_not_qualified')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--initialization-only', action='store_true')
    parser.add_argument('--inputs', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    desired = ROOT / 'Nautobot/manifests/desired-state.yaml'
    subprocess.run(['check-jsonschema', '--schemafile', str(ROOT / 'Nautobot/schemas/desired-state.schema.json'), str(desired)], check=True)
    inputs=json.loads(args.inputs.read_text())
    verify_qualified_inputs(inputs, json.loads((ROOT/'Nautobot/manifests/qualified-image.json').read_text()),
                            yaml.safe_load((ROOT/'Nautobot/manifests/accepted-live-state.yaml').read_text()))
    files = render(yaml.safe_load(desired.read_text()), inputs, args.initialization_only)
    args.output.mkdir(mode=0o700)  # Refuse existing destination and never overwrite evidence.
    for name, content in files.items():
        path = args.output / name
        path.write_text(content)
        path.chmod(0o600)
    (args.output / 'rendered-sha256.json').write_text(json.dumps({name: hashlib.sha256(value.encode()).hexdigest() for name, value in files.items()}, sort_keys=True, indent=2)+'\n')
    print(f'Rendered {len(files)} files; no deployment authorized.')


if __name__ == '__main__':
    main()
