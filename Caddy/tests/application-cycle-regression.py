#!/usr/bin/env python3
"""Exercise the real transaction's cycle gate against disposable native systemd."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

REPO = Path(__file__).resolve().parents[2]


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=20)


def main():
    assert os.geteuid() == 0 and Path('/run/.containerenv').is_file()
    assert os.environ.get('CADDY_VALIDATION_CONTAINER') == '1'
    assert Path('/proc/1/comm').read_text().strip() == 'systemd'
    root = Path('/tmp/caddy-serving-health-native-cycles')
    root.mkdir(mode=0o700)
    payload = root / 'payload'
    evidence = root / 'evidence'
    (payload / 'manifests').mkdir(parents=True)
    evidence.mkdir()
    publisher = payload / 'repositories/homelab-server-configs/Caddy/scripts/publish-release-v2.sh'
    publisher.parent.mkdir(parents=True)
    shutil.copyfile(REPO / 'Caddy/scripts/publish-release-v2.sh', publisher)
    fragment = payload / 'manifests/application.caddy'
    shutil.copyfile(REPO.parent / 'homelab-monitoring-observability/uptime-kuma/proposals/20-uptime-kuma.caddy', fragment)
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    (payload / 'operator').mkdir()
    for name in ['private-proxy-login.py', 'verify-proxy-login.cjs']:
        shutil.copyfile(REPO.parent/'homelab-monitoring-observability/uptime-kuma/scripts'/name, payload/'operator'/name)
    recipe = payload / 'manifests/certificate-release-inputs.tsv'
    values = dict(release_kind='application', baseline_revision='baseline', tls_source_revision='baseline',
                  baseline_manifest_sha256='a'*64, tls_source_manifest_sha256='a'*64,
                  publisher_candidate_sha256=digest(publisher), publisher_baseline_sha256=digest(publisher),
                  application_fragment_name='20-uptime-kuma.caddy', application_fragment_sha256=digest(fragment),
                  application_operator_sha256=digest(payload/'operator/private-proxy-login.py'),
                  application_client_sha256=digest(payload/'operator/verify-proxy-login.cjs'))
    recipe.write_text('key\tvalue\n' + ''.join(f'{key}\t{value}\n' for key, value in values.items()))
    units = ['caddy-pihole-web-health', 'caddy-sync-health']
    for unit in units:
        service = Path('/etc/systemd/system') / (unit + '.service')
        timer = service.with_suffix('.timer')
        assert not service.exists() and not timer.exists()
        service.write_text('[Service]\nType=oneshot\nExecStart=/bin/true\n')
        timer.write_text('[Timer]\nOnActiveSec=1s\nOnUnitInactiveSec=2s\nAccuracySec=50ms\n')
    run('systemctl', 'daemon-reload')
    run('systemctl', 'start', *(u + '.timer' for u in units))
    env = os.environ.copy()
    env['CADDY_CERTIFICATE_TEST_INPUTS_SHA256'] = digest(recipe)
    command = ['bash', str(REPO / 'Caddy/scripts/apply-serving-health-deployment.sh'),
               'certificate-application-cycles', 'node-a', str(payload), str(evidence)]
    started = time.monotonic()
    with Path('/qual/cycles.stdout').open('w') as out, Path('/qual/cycles.stderr').open('w') as err:
        completed = subprocess.run(command, env=env, stdout=out, stderr=err, timeout=380)
    elapsed = time.monotonic() - started
    assert completed.returncode == 0 and elapsed >= 65
    rows = [line.split('\t') for line in (evidence / 'application-cycles.tsv').read_text().splitlines()]
    for unit in units:
        observed = [row for row in rows if row[0] == unit + '.service']
        assert len(observed) >= 2
        starts = [int(row[1]) for row in observed]
        assert starts == sorted(set(starts))
        assert all(int(row[2]) >= int(row[1]) for row in observed)
    shutil.copyfile(evidence / 'application-cycles.tsv', '/qual/cycles.tsv')
    run('systemctl', 'stop', *(u + '.timer' for u in units))
    service = Path('/etc/systemd/system/caddy-sync-health.service')
    service.write_text('[Service]\nType=oneshot\nExecStart=/bin/false\n')
    run('systemctl', 'daemon-reload')
    subprocess.run(['systemctl', 'start', 'caddy-sync-health.service'], capture_output=True, timeout=20)
    failed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=20)
    assert failed.returncode != 0
    Path('/qual/result.json').write_text(json.dumps({'successful_cycles': rows, 'elapsed': elapsed,
        'success_status': completed.returncode, 'failed_unit_rejected': failed.returncode,
        'transaction_sha256': digest(REPO / 'Caddy/scripts/apply-serving-health-deployment.sh')}, indent=2)+'\n')


if __name__ == '__main__':
    main()
