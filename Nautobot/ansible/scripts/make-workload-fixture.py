#!/usr/bin/env python3
"""Create a deterministic synthetic pilot dataset; no Nautobot API access."""
import argparse
import hashlib
import json
from pathlib import Path


def dataset():
    return {
        'schema_version': 1,
        'namespace': 'pilot-synthetic',
        'locations': [{'key': f'pilot-location-{i:02}', 'description': 'Synthetic acceptance fixture'} for i in range(1, 11)],
        'devices': [
            {'key': f'pilot-device-{i:04}', 'location': f'pilot-location-{(i-1)//50+1:02}',
             'interfaces': [{'name': f'eth{j}', 'enabled': True} for j in range(4)]}
            for i in range(1, 501)
        ],
        'ip_assignments': [
            {'device': f'pilot-device-{i:04}', 'interface': 'eth0',
             'address': f'198.18.{(i-1)//250}.{(i-1)%250+1}/24'}
            for i in range(1, 501)
        ],
    }


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    payload=canonical(dataset())
    with args.output.open('xb') as out:out.write(payload)
    args.output.chmod(0o600)
    print(hashlib.sha256(payload).hexdigest())


if __name__=='__main__':main()
