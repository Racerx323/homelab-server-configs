#!/usr/bin/env python3
"""Native isolated packet/counter correctness, never target capacity acceptance."""
import http.server
import importlib.util
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import threading

ROOT = Path(__file__).parents[1]


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=12)


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


def main():
    assert Path('/run/.containerenv').exists()
    assert {x['ifname'] for x in json.loads(run('ip', '-j', 'link').stdout)} == {'lo'}
    profile, probe = load('render-proxy-profile'), load('probe-proxy-path')
    review = json.loads((ROOT / 'configs/hosts/example-proxy.json').read_text())
    review.update(browser_hostname='webmin.example.test', backend_addresses=['192.0.2.75', 'fd00::75'],
                  proxy_sources=['192.0.2.53', '192.0.2.54', 'fd00::53', 'fd00::54'])
    servers = []; namespaces = []
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = b'<input name="pass">'; self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
        def log_message(self, *args): pass
    class V6(http.server.HTTPServer): address_family = socket.AF_INET6
    try:
        run('ip', 'link', 'add', 'wmbridge', 'type', 'bridge'); run('ip', 'link', 'set', 'wmbridge', 'up')
        run('ip', 'addr', 'add', '192.0.2.75/24', 'dev', 'wmbridge')
        run('ip', '-6', 'addr', 'add', 'fd00::75/64', 'dev', 'wmbridge', 'nodad')
        for name, number in [('wma', '53'), ('wmb', '54'), ('wmdeny', '99')]:
            run('ip', 'netns', 'add', name); namespaces.append(name)
            run('ip', 'link', 'add', name, 'type', 'veth', 'peer', 'name', name+'peer')
            run('ip', 'link', 'set', name+'peer', 'netns', name)
            run('ip', 'link', 'set', name, 'master', 'wmbridge'); run('ip', 'link', 'set', name, 'up')
            run('ip', '-n', name, 'link', 'set', 'lo', 'up'); run('ip', '-n', name, 'link', 'set', name+'peer', 'up')
            run('ip', '-n', name, 'addr', 'add', '192.0.2.'+number+'/24', 'dev', name+'peer')
            run('ip', '-n', name, '-6', 'addr', 'add', 'fd00::'+number+'/64', 'dev', name+'peer', 'nodad')
        for family, address in [(http.server.HTTPServer, '192.0.2.75'), (V6, 'fd00::75')]:
            server = family((address, 10000), Handler); servers.append(server)
            threading.Thread(target=server.serve_forever, daemon=True).start()
        with tempfile.TemporaryDirectory() as temporary:
            rules = Path(temporary) / 'guard.nft'; rules.write_text(profile.ingress(review))
            run('nft', '--check', '-f', str(rules)); run('nft', '-f', str(rules))
        evidence = []
        for node, suffix in [('wma', '53'), ('wmb', '54')]:
            for version, address, source in [(4, '192.0.2.75', '192.0.2.'+suffix), (6, 'fd00::75', 'fd00::'+suffix)]:
                before = probe.counters()
                result = run('ip', 'netns', 'exec', node, 'python3', str(ROOT / 'scripts/probe-proxy-path.py'),
                             '--address', address, '--hostname', 'webmin.example.test', '--source', source)
                row = json.loads(result.stdout); assert row['accepted'], row
                key = f'webmin-{version}-{source}-to-{address}'
                after = probe.counters(); assert after[key] > before[key]
                evidence.append({'client': row, 'counter_increase': after[key]-before[key]})
                rejected = run('ip', 'netns', 'exec', node, 'python3', str(ROOT / 'scripts/probe-proxy-path.py'),
                               '--address', address, '--hostname', 'webmin.example.test', '--source', '192.0.2.99' if version == 4 else 'fd00::99', check=False)
                failure = json.loads(rejected.stdout)
                assert rejected.returncode == 1 and failure['failure'] == 'route_selected_source_mismatch'
                assert failure['observed_route'] and failure['expected_source'] != source
        for version, address in [(4, '192.0.2.75'), (6, 'fd00::75')]:
            before = probe.counters()
            result = run('ip', 'netns', 'exec', 'wmdeny', 'python3', str(ROOT / 'scripts/probe-proxy-path.py'), '--deny', '--address', address)
            assert json.loads(result.stdout)['accepted']
            after = probe.counters(); assert after[f'webmin-denied-{version}'] > before[f'webmin-denied-{version}']
        print(json.dumps({'passed': True, 'paths': evidence, 'both_denied': True,
                          'browser_workload': False, 'target_capacity': 'not tested'}))
    finally:
        for server in servers: server.shutdown(); server.server_close()
        run('nft', 'delete', 'table', 'inet', 'webmin', check=False)
        for name in namespaces: run('ip', 'netns', 'del', name, check=False)
        run('ip', 'link', 'del', 'wmbridge', check=False)


if __name__ == '__main__': main()
