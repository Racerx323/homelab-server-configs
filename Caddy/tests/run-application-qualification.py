#!/usr/bin/env python3
"""Run the primary-first fixture in an offline, disposable Podman container."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[2]


def main():
    os.umask(0o077)
    fixture = Path(os.environ['CADDY_ACCEPTED_RECONCILER_FIXTURE'])
    assert fixture.is_absolute() and fixture.is_file() and not fixture.is_symlink()
    assert ':' not in str(fixture) and '\n' not in str(fixture)
    evidence = Path(tempfile.mkdtemp(prefix='caddy-application-qualification-', dir='/tmp'))
    name = evidence.name
    image = 'localhost/caddy-auth-validation:latest'
    result = dict(status='failed', network='none', evidence=str(evidence))
    sources = [REPO/'Caddy/scripts'/name for name in ['publish-release-v2.sh', 'apply-serving-health-deployment.sh', 'run-serving-health-deployment-outer.sh']]
    sources += [Path(__file__), REPO/'Caddy/tests/application-onboarding-regression.py', REPO/'Caddy/tests/certificate-release-regression.py', REPO.parent/'homelab-monitoring-observability/uptime-kuma/proposals/20-uptime-kuma.caddy']
    result['inputs'] = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    result['accepted_reconciler_sha256'] = hashlib.sha256(fixture.read_bytes()).hexdigest()
    print(evidence, flush=True)
    try:
        result['image'] = subprocess.check_output(['podman', 'image', 'inspect', '--format', '{{.Id}}', image], text=True).strip()
        command = ['podman', 'run', '--rm', '--pull=never', '--name', name, '--network=none', '--cap-add=NET_ADMIN',
                   '--env', 'CADDY_VALIDATION_CONTAINER=1', '--env', 'CADDY_ACCEPTED_RECONCILER_FIXTURE=/accepted-reconciler.sh',
                   '--volume', str(REPO.parent)+':/workspace:ro', '--volume', str(evidence)+':/evidence',
                   '--volume', str(fixture)+':/accepted-reconciler.sh:ro', result['image'], '-lc',
                   'python3 /workspace/homelab-server-configs/Caddy/tests/application-onboarding-regression.py']
        with (evidence/'qualification.log').open('wb') as log:
            completed = subprocess.run(command, stdout=log, stderr=log, timeout=1800)
        result.update(exit=completed.returncode, status='passed' if completed.returncode == 0 else 'failed')
    finally:
        # Exact named test container only, including interrupted fixture runs.
        exists = subprocess.run(['podman', 'container', 'exists', name], capture_output=True).returncode
        if exists == 0:
            result['cleanup_status'] = subprocess.run(['podman', 'rm', '--force', name], capture_output=True).returncode
        else:
            result['cleanup_status'] = 0 if exists == 1 else exists
        if result['cleanup_status']:
            result['status'] = 'failed'
        (evidence/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    raise SystemExit(0 if result['status'] == 'passed' else 1)


if __name__ == '__main__':
    main()
