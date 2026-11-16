#!/usr/bin/env python3
"""Check/apply/reapply the Webmin guard only in a disposable network-none container."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=10).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--review', type=Path, required=True)
    args = parser.parse_args()
    if not Path('/run/.containerenv').is_file():
        raise RuntimeError('podman_container_required')
    links = json.loads(run('/usr/sbin/ip', '-j', 'link'))
    if {x['ifname'] for x in links} != {'lo'}:
        raise RuntimeError('network_none_required')
    spec = importlib.util.spec_from_file_location('profile', Path(__file__).parents[1] / 'scripts/render-proxy-profile.py')
    profile = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(profile)
    nft = '/usr/sbin/nft'
    existing = json.loads(run(nft, '-j', 'list', 'tables'))['nftables']
    if any(x.get('table', {}).get('name') in ('webmin', 'qualification_preserved') for x in existing):
        raise RuntimeError('test_tables_must_be_absent')
    sentinel_created = False
    guard_created = False
    with tempfile.TemporaryDirectory(prefix='webmin-ingress-') as directory:
        candidate = Path(directory) / 'webmin.nft'
        candidate.write_text(profile.ingress(json.loads(args.review.read_text())))
        try:
            run(nft, 'add', 'table', 'inet', 'qualification_preserved')
            sentinel_created = True
            before = run(nft, '-j', 'list', 'table', 'inet', 'qualification_preserved')
            run(nft, '--check', '-f', str(candidate))
            run(nft, '-f', str(candidate))
            guard_created = True
            first = json.loads(run(nft, '-j', 'list', 'table', 'inet', 'webmin'))
            run(nft, '-f', str(candidate))
            second = json.loads(run(nft, '-j', 'list', 'table', 'inet', 'webmin'))
            def semantic(value):
                if isinstance(value, dict):
                    return {k: semantic(v) for k, v in value.items() if k not in ('handle', 'metainfo')}
                if isinstance(value, list):
                    return [semantic(v) for v in value]
                return value
            assert semantic(first) == semantic(second), 'reapply_changed_semantics'
            assert before == run(nft, '-j', 'list', 'table', 'inet', 'qualification_preserved'), 'unrelated_table_changed'
            print(json.dumps({'passed': True, 'native_check': True, 'native_apply_reapply': True,
                              'unrelated_table_preserved': True, 'packet_paths_tested': False}))
        finally:
            if guard_created:
                run(nft, 'delete', 'table', 'inet', 'webmin')
            if sentinel_created:
                run(nft, 'delete', 'table', 'inet', 'qualification_preserved')


if __name__ == '__main__':
    main()
