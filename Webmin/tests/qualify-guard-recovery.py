#!/usr/bin/env python3
"""Verify boot persistence, then ordered loopback recovery in the offline fixture."""
import hashlib
import http.client
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


def run(*args, check=True):
    return subprocess.run(args, capture_output=True, text=True, timeout=30, check=check)


def probe(host):
    conn = http.client.HTTPConnection(host, 10000, timeout=10)
    try:
        conn.request('GET', '/session_login.cgi')
        response = conn.getresponse()
        response.read(1048576)
        assert response.status == 200
    finally:
        conn.close()


def main():
    os.umask(0o077)
    assert Path('/run/.containerenv').is_file()
    assert {row['ifname'] for row in json.loads(run('ip', '-j', 'link').stdout)} == {'lo'}
    result = {'passed': False, 'checks': []}
    stage = 'post-container-restart'
    try:
        for unit in ['webmin-firewall.service', 'webmin.service']:
            assert run('systemctl', 'is-enabled', unit).stdout.strip() == 'enabled'
            assert run('systemctl', 'is-active', unit).stdout.strip() == 'active'
        run('nft', 'list', 'table', 'inet', 'webmin')
        result['checks'].append('container-restart-restores-guard-and-webmin')
        # The restart intentionally clears transient namespace rules. Add a fresh unrelated control.
        run('nft', 'add', 'table', 'inet', 'webmin_recovery_sentinel')
        stage = 'stop-before-restore'
        run('systemctl', 'stop', 'webmin.service', 'webmin-fixture-caddy.service')
        assert run('systemctl', 'show', 'webmin.service', '-p', 'MainPID', '--value').stdout.strip() == '0'
        stage = 'restore-baseline'
        for name in ['miniserv.conf', 'config']:
            source = Path('/evidence/baseline/loopback-' + name)
            destination = Path('/etc/webmin/' + name)
            shutil.copy2(source, destination)
            assert hashlib.sha256(source.read_bytes()).digest() == hashlib.sha256(destination.read_bytes()).digest()
        Path('/etc/systemd/system/webmin.service.d/30-proxy-ingress.conf').unlink()
        run('systemctl', 'disable', 'webmin-firewall.service')
        run('systemctl', 'daemon-reload')
        run('systemctl', 'reset-failed', 'webmin.service')
        run('systemctl', 'start', 'webmin.service')
        stage = 'loopback-before-guard-removal'
        deadline = time.monotonic() + 20
        while True:
            try:
                probe('127.0.0.1')
                probe('::1')
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.25)
        rows = run('ss', '-H', '-lnt').stdout.splitlines()
        listeners = {row.split()[3] for row in rows if row.split()[3].endswith(':10000')}
        assert listeners == {'127.0.0.1:10000', '[::1]:10000'}, listeners
        result['checks'].append('exact-loopback-config-http-and-listeners-before-guard-removal')
        run('systemctl', 'stop', 'webmin-firewall.service')
        run('nft', 'list', 'table', 'inet', 'webmin')
        run('nft', 'delete', 'table', 'inet', 'webmin')
        assert run('nft', 'list', 'table', 'inet', 'webmin', check=False).returncode != 0
        run('nft', 'list', 'table', 'inet', 'webmin_recovery_sentinel')
        assert run('systemctl', 'is-active', 'webmin.service').stdout.strip() == 'active'
        result['checks'].append('remove-only-owned-guard-preserve-service-and-unrelated-table')
        result['passed'] = True
    except Exception as error:
        result.update(failure_stage=stage, error_class=type(error).__name__)
        raise
    finally:
        Path('/evidence/guard-recovery.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result))


if __name__ == '__main__':
    main()
