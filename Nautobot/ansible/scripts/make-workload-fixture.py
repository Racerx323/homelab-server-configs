#!/usr/bin/env python3
"""Create a deterministic synthetic pilot dataset; no Nautobot API access."""
import argparse
import hashlib
import json
import yaml
import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


def dataset(contract=None):
    if contract is None:
        contract = yaml.safe_load((ROOT / 'Nautobot/manifests/workload-test.yaml').read_text())
    spec = importlib.util.spec_from_file_location('contracts', Path(__file__).with_name('validate-contracts.py'))
    validator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    validator.validate(yaml.safe_load((ROOT / 'Nautobot/manifests/desired-state.yaml').read_text()), contract)
    f = contract['fixture']
    result = {
        'schema_version': 1,
        'namespace': f['namespace'],
        'locations': [{'key': f'pilot-location-{i:02}', 'description': 'Synthetic acceptance fixture'} for i in range(1, f['locations'] + 1)],
        'devices': [
            {'key': f'pilot-device-{i:04}', 'location': f'pilot-location-{(i-1)*f['locations']//f['devices']+1:02}',
             'interfaces': [{'name': f'eth{j}', 'enabled': True} for j in range(f['interfaces_per_device'])]}
            for i in range(1, f['devices'] + 1)
        ],
        'ip_assignments': [
            {'device': f'pilot-device-{(i-1) % f["devices"]+1:04}', 'interface': 'eth0',
             'address': f'198.18.{(i-1)//250}.{(i-1)%250+1}/24'}
            for i in range(1, f['ip_assignments'] + 1)
        ],
    }

    if f.get('dns_records', 0):
        result['dns_records'] = [
            {'name': f'host-{i:04}', 'address': result['ip_assignments'][(i-1) % f['ip_assignments']]['address']}
            for i in range(1, f['dns_records'] + 1)]
    if f.get('profile') == 'agreed_pilot':
        if (f['locations'], f['devices'], f['ip_assignments'], f['dns_records']) != (1, 200, 2000, 2000):
            raise ValueError('pilot_profile_counts')
        # Synthetic switch-like/host-like density, not discovered hardware models.
        for i, device in enumerate(result['devices']):
            count = 24 if i < 20 else 2 if i < 160 else 1
            device['interfaces'] = [{'name': f'eth{j}', 'enabled': True} for j in range(count)]
        interfaces = [(d['key'], n['name']) for d in result['devices'] for n in d['interfaces']]
        addresses = [f'198.18.{i//250}.{i%250+1}/24' for i in range(1200)]
        addresses += [f'2001:2::{i+1:x}/64' for i in range(800)]
        result['ip_assignments'] = [dict(device=interfaces[i % 800][0], interface=interfaces[i % 800][1], address=a)
                                    for i, a in enumerate(addresses)]
        records = [dict(type=t, name=f'host-{i+1:04}', address=addresses[offset+i])
                   for t, offset in [('A', 0), ('AAAA', 1200)] for i in range(800)]
        records += [dict(type='PTR', name=str(i+1), address=addresses[i], target=f'host-{i+1:04}.pilot-synthetic.invalid') for i in range(250)]
        records += [dict(type='CNAME', name=f'alias-{i+1:04}', target=f'host-{i+1:04}.pilot-synthetic.invalid') for i in range(100)]
        records += [dict(type='TXT', name=f'text-{i+1:04}', text=f'synthetic-pilot-{i+1:04}') for i in range(40)]
        records += [dict(type='SRV', name=f'_pilot{i+1:02}._tcp', target=f'host-{i+1:04}.pilot-synthetic.invalid',
                         priority=10, weight=5, port=443) for i in range(10)]
        result['dns_records'] = records
    return result


def expanded_contract():
    """Synthetic capacity profile; DNS mix/interface density are not inventory claims."""
    contract = yaml.safe_load((ROOT / 'Nautobot/manifests/workload-test.yaml').read_text())
    contract['fixture'].update(locations=1, devices=200, interfaces_per_device=4,
                               ip_assignments=2000, dns_records=2000)
    contract['audit_submission'] = 'single_batch'
    return contract


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def pilot_contract():
    contract = expanded_contract()
    contract['fixture']['profile'] = 'agreed_pilot'
    return contract


def main():
    parser=argparse.ArgumentParser()
    profile = parser.add_mutually_exclusive_group()
    profile.add_argument('--expanded', action='store_true')
    profile.add_argument('--pilot', action='store_true')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    payload=canonical(dataset(pilot_contract() if args.pilot else expanded_contract() if args.expanded else None))
    with args.output.open('xb') as out:out.write(payload)
    args.output.chmod(0o600)
    print(hashlib.sha256(payload).hexdigest())


if __name__=='__main__':main()
