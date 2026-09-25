#!/usr/bin/env python3
"""Resource-limited, no published ports, disposable PostgreSQL comparison tests."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time
import uuid


def run(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, timeout=360, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--postgres-image', required=True)
    parser.add_argument('--app-image', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    for value in (args.postgres_image, args.app_image):
        if not re.fullmatch(r'(sha256:)?[0-9a-f]{64}', value):
            raise ValueError('immutable_image_id_required')
    args.output.mkdir(mode=0o700, exist_ok=False)
    prefix = 'nautobot-logical-' + uuid.uuid4().hex[:12]
    network = prefix + '-net'
    names = []
    created = False
    try:
        run(['podman', 'network', 'create', '--internal', network], check=True)
        created = True
        name = prefix + '-db'
        names.append(name)
        run(['podman', 'run', '-d', '--name', name, '--network', network, '--network-alias', 'postgresql',
             '--memory', '768m', '--cpus', '2', '--tmpfs', '/var/lib/postgresql/data:rw,size=512m',
             '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', args.postgres_image], check=True)
        for _ in range(60):
            if run(['podman', 'exec', name, 'pg_isready', '-U', 'postgres']).returncode == 0:
                break
            time.sleep(1)
        else:
            raise RuntimeError('postgres_readiness')
        version = run(['podman', 'exec', name, 'postgres', '--version'], check=True).stdout.strip()
        app = prefix + '-test'
        names.append(app)
        component = Path(__file__).resolve().parents[1]
        result = run(['podman', 'run', '--name', app, '--network', network, '--memory', '768m', '--cpus', '2',
                      '-e', 'LOGICAL_TEST_DATABASE=disposable', '-e', 'PYTHONDONTWRITEBYTECODE=1',
                      '-v', str(component) + ':/work:ro', '--entrypoint', 'python3', args.app_image,
                      '/work/tests/test_logical_database.py'])
        (args.output / 'tests.txt').write_text(result.stdout + result.stderr)
        (args.output / 'result.json').write_text(json.dumps({'exit_status': result.returncode, 'version': version,
                'images': [args.postgres_image, args.app_image], 'target_architecture_qualified': False}, indent=2))
        if result.returncode:
            raise RuntimeError('qualification_failed')
    finally:
        cleanup = {name: run(['podman', 'rm', '-f', '--volumes', name]).returncode == 0 for name in reversed(names)}
        if created:
            cleanup[network] = run(['podman', 'network', 'rm', network]).returncode == 0
        (args.output / 'cleanup.json').write_text(json.dumps(cleanup, indent=2))
        if not all(cleanup.values()):
            raise RuntimeError('cleanup_incomplete')


if __name__ == '__main__':
    main()
