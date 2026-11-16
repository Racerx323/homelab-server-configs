#!/usr/bin/env python3
"""Native systemd/nft lifecycle checks in the owned network-none fixture only."""
import hashlib
import json
import os
from pathlib import Path
import subprocess


def run(*args, check=True):
    return subprocess.run(args, capture_output=True, text=True, timeout=30, check=check)


def main():
    os.umask(0o077)
    assert Path('/run/.containerenv').is_file()
    assert {row['ifname'] for row in json.loads(run('ip', '-j', 'link').stdout)} == {'lo'}
    result = {'passed': False, 'checks': []}
    stage = 'initial-state'
    rule = Path('/etc/webmin/ingress.nft')
    good = rule.read_bytes()
    sentinel = 'webmin_fixture_sentinel'
    try:
        run('nft', 'add', 'table', 'inet', sentinel)
        for unit in ['webmin-firewall.service', 'webmin.service']:
            assert run('systemctl', 'is-active', unit).stdout.strip() == 'active'
            assert run('systemctl', 'is-enabled', unit).stdout.strip() == 'enabled'
        stage = 'guard-stop'
        run('systemctl', 'stop', 'webmin-firewall.service')
        assert run('systemctl', 'is-active', 'webmin.service', check=False).stdout.strip() in {'inactive', 'failed'}
        assert run('systemctl', 'show', 'webmin.service', '-p', 'MainPID', '--value').stdout.strip() == '0'
        original = run('nft', 'list', 'table', 'inet', 'webmin').stdout
        result['checks'].append('guard-stop-stops-webmin-and-retains-rules')
        stage = 'invalid-start'
        rule.write_text('invalid nft syntax\n')
        assert run('systemctl', 'start', 'webmin.service', check=False).returncode != 0
        assert run('systemctl', 'is-active', 'webmin.service', check=False).stdout.strip() != 'active'
        assert run('nft', 'list', 'table', 'inet', 'webmin').stdout == original
        result['checks'].append('invalid-guard-blocks-start-preserves-table')
        stage = 'restart'
        rule.write_bytes(good)
        run('systemctl', 'reset-failed', 'webmin-firewall.service', 'webmin.service')
        run('systemctl', 'start', 'webmin.service')
        assert run('systemctl', 'is-active', 'webmin.service').stdout.strip() == 'active'
        stage = 'invalid-reload'
        rule.write_text('invalid nft syntax\n')
        assert run('systemctl', 'reload', 'webmin-firewall.service', check=False).returncode != 0
        assert run('nft', 'list', 'table', 'inet', 'webmin').stdout == original
        result['checks'].append('invalid-reload-retains-table')
        rule.write_bytes(good)
        run('systemctl', 'reload', 'webmin-firewall.service')
        stage = 'service-start-reasserts-table'
        run('systemctl', 'stop', 'webmin.service')
        run('nft', 'delete', 'table', 'inet', 'webmin')
        run('systemctl', 'start', 'webmin.service')
        run('nft', 'list', 'table', 'inet', 'webmin')
        result['checks'].append('service-start-reasserts-guard')
        run('nft', 'list', 'table', 'inet', sentinel)
        result['checks'].append('unrelated-table-preserved')
        result['rule_sha256'] = hashlib.sha256(good).hexdigest()
        result['passed'] = True
    except Exception as error:
        result.update(failure_stage=stage, error_class=type(error).__name__)
        raise
    finally:
        rule.write_bytes(good)
        Path('/evidence/guard-lifecycle.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result))


if __name__ == '__main__':
    main()
