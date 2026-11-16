#!/usr/bin/env python3
"""Offline native miniserv qualification; run inside a network-disabled container."""
import argparse
import hashlib
import http.client
import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def probe(host, port, source=None):
    conn = http.client.HTTPConnection(host, port, timeout=3,
                                      source_address=(source, 0) if source else None)
    try:
        conn.request('GET', '/protected', headers={'Host': 'webmin-host.example.test'})
        response = conn.getresponse()
        response.read(65536)
        return response.status, response.getheader('Location')
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--webmin-root', type=Path, required=True)
    args = parser.parse_args()
    scripts = Path(__file__).parents[1] / 'scripts'
    profile = load(scripts / 'render-proxy-profile.py', 'profile')
    editor = load(scripts / 'configure-miniserv.py', 'editor')
    with tempfile.TemporaryDirectory(prefix='webmin-proxy-native-') as directory:
        root = Path(directory)
        with socket.socket() as allocator:
            allocator.bind(('127.0.0.1', 0))
            port = allocator.getsockname()[1]
        review = {'browser_hostname': 'webmin-host.example.test',
                  'backend_addresses': ['127.0.0.2'], 'proxy_sources': ['127.0.0.2'],
                  'backend_transport': 'http',
                  'miniserv': {'ssl': '0', 'session': '1', 'localauth': '',
                               'port': str(port), 'allow': '127.0.0.1 ::1'},
                  'webmin': {'referers': 'existing.example.test'}}
        policy = profile.policies(review)
        (root / 'users').write_text('fixture:!\n')
        (root / 'www/protected').mkdir(parents=True)
        (root / 'www/protected/index.html').write_text('private fixture')
        settings = {**review['miniserv'], 'root': str(root / 'www'),
                    'pidfile': str(root / 'pid'), 'logfile': str(root / 'access'),
                    'errorlog': str(root / 'error'), 'userfile': str(root / 'users'),
                    'log': '0', 'syslog': '0', 'pam': '', 'preload': '',
                    'sessiondb': str(root / 'sessiondb'), 'nofork': '1',
                    'redirect': '/protected=/protected/'}
        config = root / 'miniserv.conf'
        config.write_text(''.join(f'{k}={v}\n' for k, v in settings.items()))
        editor.configure(config, policy['miniserv'])
        with (root / 'process.log').open('wb') as log:
            process = subprocess.Popen(['/usr/bin/perl', str(args.webmin_root / 'miniserv.pl'),
                                        '--nofork', str(config)], stdout=log, stderr=log,
                                       start_new_session=True)
            try:
                deadline = time.monotonic() + 12
                while True:
                    try:
                        ipv4 = probe('127.0.0.1', port)
                        break
                    except OSError:
                        if process.poll() is not None or time.monotonic() >= deadline:
                            raise RuntimeError('native_startup_failed')
                        time.sleep(0.1)
                ipv6 = probe('::1', port)
                selected = probe('127.0.0.2', port, '127.0.0.2')
                denied = probe('127.0.0.2', port, '127.0.0.3')
                for family, result in [('ipv4', ipv4), ('ipv6', ipv6), ('selected', selected)]:
                    assert result[0] == 302, (family, result)
                    assert result[1] == 'https://webmin-host.example.test/protected/', (family, result)
                    assert ':443' not in result[1] and str(port) not in result[1], (family, result)
                assert denied[0] == 403, ('denied', denied)
                print(json.dumps({'passed': True, 'dual_stack_canonical_redirect': True,
                                  'selected_listener': True, 'unlisted_source_denied': True,
                                  'login_tested': False, 'tls_tested': False,
                                  'source_sha256': {name: hashlib.sha256((args.webmin_root / name).read_bytes()).hexdigest()
                                                    for name in ('miniserv.pl', 'miniserv-lib.pl')}}))
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)


if __name__ == '__main__':
    main()
