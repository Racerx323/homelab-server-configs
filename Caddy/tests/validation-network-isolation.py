#!/usr/bin/env python3
"""Native containment/permission check inside the existing offline image only.

Exit 2 retains partial results when root network isolation is unavailable. Never
add container capabilities or substitute a user namespace to turn that into a pass.
This is not a target-capacity test or qualification of installed owner callers.
"""
import http.server
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time


def caller_contracts():
    """Exercise extracted caller boundaries, without namespaces or live services."""
    scripts = Path(__file__).resolve().parents[1] / 'scripts'
    installed = '/usr/local/libexec/validate-caddy-isolated.sh'
    results = []
    with tempfile.TemporaryDirectory(prefix='caddy-caller-contract.') as directory:
        root = Path(directory)
        release = root / 'release with spaces'
        release.mkdir()
        helper = root / 'validator'
        helper.write_text('''#!/bin/bash
printf '%s\\n' "$#" "$1" "$CADDY_CONFIG_ROOT" "$NODE_FQDN" "$NODE_IPV4" "$NODE_IPV6" >"$RECEIPT"
printf 'bounded test failure\\n' >&2
exit "$TEST_STATUS"
''')
        helper.chmod(0o700)
        for filename, label, variable in [
            ('publish-release-v2.sh', 'source_caddy_configuration_valid', 'source_dir'),
            ('reconcile-release-v2.sh', 'caddy_configuration_valid', 'candidate'),
            ('finalize-incoming-release-v2.sh', None, 'validation_release_path'),
        ]:
            source = (scripts / filename).read_text()
            assert source.count(installed) == 1
            assert 'caddy validate --config' not in source
            if label:
                require = 'require_check() {' + source.split('require_check() {', 1)[1].split('\n}', 1)[0] + '\n}\n'
                start = source.index('require_check ' + label + ' \\\n')
                end = source.index('\n', source.index(installed, start))
                block = require + source[start:end] + '\n'
            else:
                block = 'validate_caddy_configuration() {' + source.split('validate_caddy_configuration() {', 1)[1].split('\n}', 1)[0] + '\n}\nvalidate_caddy_configuration "$validation_release_path"\n'
            # Only the fixed helper location is mapped to a private stand-in.
            # The real env invocation, caller check/function and cleanup execute.
            for status in (0, 23, 124, None):
                receipt = root / 'receipt'
                receipt.unlink(missing_ok=True)
                selected = helper if status is not None else root / 'missing-validator'
                env = dict(os.environ, **{variable: str(release)},
                           NODE_FQDN='test.invalid', NODE_IPV4='192.0.2.1',
                           NODE_IPV6='2001:db8::1', RECEIPT=str(receipt),
                           TEST_STATUS=str(status), TMPDIR=str(root))
                result = subprocess.run(
                    ['/bin/bash', '-c', 'set -Eeuo pipefail\n' + block.replace(installed, str(selected))],
                    env=env, capture_output=True, text=True, timeout=3)
                expected = (0 if status == 0 else 1) if label else (127 if status is None else status)
                assert result.returncode == expected, (filename, status, result.stderr)
                if status is not None:
                    assert receipt.read_text().splitlines() == [
                        '1', str(release / 'Caddyfile'), str(release),
                        'test.invalid', '192.0.2.1', '2001:db8::1']
                else:
                    assert not receipt.exists()
                assert not list(root.glob('caddy-finalize-validate.*'))
                results.append({'caller': filename, 'validator_status': status,
                                'caller_status': result.returncode})
    print(json.dumps({'caller_contracts': results, 'target_contact': False}))
    return 0


def command(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, timeout=15, **kwargs)


def main():
    assert os.geteuid() == 0 and os.environ.get('CADDY_VALIDATION_CONTAINER') == '1'
    assert Path('/run/.containerenv').is_file()
    # This test may modify only disposable container accounts and temporary files.
    command(['groupadd', '--system', 'caddy-tls']).check_returncode()
    command(['useradd', '--system', '--user-group', '-G', 'caddy-tls', 'caddy-sync']).check_returncode()
    helper = Path(__file__).resolve().parents[1] / 'scripts/validate-caddy-isolated.sh'
    calls = []

    class Endpoint(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            calls.append(self.server.address_family)
            self.send_response(200)
            self.end_headers()

        def log_message(self, *_args):
            pass

    class IPv6Server(http.server.ThreadingHTTPServer):
        address_family = socket.AF_INET6

    servers = [http.server.ThreadingHTTPServer(('127.0.0.1', 0), Endpoint),
               IPv6Server(('::1', 0), Endpoint)]
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    report = {'caddy': command(['/usr/bin/caddy', 'version']).stdout.strip()}
    try:
        with tempfile.TemporaryDirectory(prefix='caddy-validation-isolation.') as directory:
            root = Path(directory)
            root.chmod(0o755)
            cert, key, config = (root / name for name in ('cert.pem', 'key.pem', 'Caddyfile'))
            command(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                     '-keyout', str(key), '-out', str(cert), '-days', '1',
                     '-subj', '/CN=localhost']).check_returncode()
            command(['chgrp', 'caddy-tls', str(key)]).check_returncode()
            key.chmod(0o640)
            config.write_text('''{
    admin off
    auto_https off
}
https://localhost:19443 {
    tls %s %s
    reverse_proxy 127.0.0.1:%d [::1]:%d {
        health_uri /health
        health_interval 100ms
        health_timeout 100ms
    }
}
''' % (cert, key, servers[0].server_port, servers[1].server_port))
            config.chmod(0o644)
            unprivileged = ['/usr/sbin/runuser', '-u', 'caddy-sync', '--',
                            '/usr/bin/setpriv', '--no-new-privs']
            validator = unprivileged + ['/bin/bash', str(helper), str(config)]
            valid = command(validator)
            assert valid.returncode == 0, valid.stderr
            report['caddy_sync_group_tls_no_new_privs'] = 'passed'
            assert calls == [], calls
            report['validation_external_ipv4_ipv6_requests'] = len(calls)
            key.chmod(0o600)
            denied = command(validator)
            assert denied.returncode != 0 and 'permission denied' in denied.stderr
            key.chmod(0o640)
            original = config.read_text()
            config.write_text(original.replace('health_uri /health', 'invalid_proxy_option'))
            assert command(validator).returncode != 0
            config.write_text(original)
            original_key = key.read_bytes()
            key.write_text('invalid TLS key\n')
            assert command(validator).returncode != 0
            key.write_bytes(original_key)
            report['unreadable_tls_bad_tls_bad_config_rejected'] = True
            assert calls == [], calls

            # Root's real reconciler must read files owned by the receiver.
            command(['chown', 'caddy-sync:caddy-sync', str(config)]).check_returncode()
            config.chmod(0o640)
            root_remapped = command(['/usr/bin/unshare', '--user', '--map-current-user', '--net',
                                     '/usr/bin/test', '-r', str(config)])
            assert root_remapped.returncode == 1, root_remapped.stderr
            assert not root_remapped.stderr, root_remapped.stderr
            report['root_user_namespace_loses_receiver_read_access'] = True
            root_result = command(['/usr/bin/setpriv', '--no-new-privs',
                                   '/bin/bash', str(helper), str(config)])
            report['root_validator_status'] = root_result.returncode
            if root_result.returncode:
                assert 'unshare failed: Operation not permitted' in root_result.stderr, root_result.stderr
                report['root_success_qualification'] = 'blocked: network namespace denied'
                report['root_failure_closed'] = True
            else:
                report['root_success_qualification'] = 'passed'
            assert calls == [], calls
            runtime = subprocess.Popen(unprivileged + ['/usr/bin/caddy', 'run', '--config', str(config),
                                                       '--adapter', 'caddyfile'],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                       start_new_session=True)
            try:
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline and set(calls) != {socket.AF_INET, socket.AF_INET6}:
                    assert runtime.poll() is None, 'runtime exited before health checks'
                    time.sleep(0.05)
                assert set(calls) == {socket.AF_INET, socket.AF_INET6}, calls
                report['unchanged_runtime_health_both_families'] = 'passed'
            finally:
                os.killpg(runtime.pid, signal.SIGTERM)
                try:
                    runtime.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(runtime.pid, signal.SIGKILL)
                    runtime.wait(timeout=3)
            report['runtime_cleanup'] = 'passed'
            print(json.dumps(report, sort_keys=True))
            return 2 if root_result.returncode else 0
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    raise SystemExit(caller_contracts() if sys.argv[1:] == ['--caller-contracts'] else main())
