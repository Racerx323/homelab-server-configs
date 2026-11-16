#!/usr/bin/env python3
"""Offline native recovery test using a dummy HTTP service, never a capacity test."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

spec = importlib.util.spec_from_file_location('recovery', '/source/recover-proxy.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


def call(*args):
    row = subprocess.run(args, check=False, capture_output=True, text=True, timeout=40)
    if row.returncode:
        # This isolated stand-in contains no credentials or private application data.
        Path('/evidence/native-failure.json').write_text(json.dumps({
            'command': args, 'exit': row.returncode,
            'stderr': row.stderr[:2048], 'stdout': row.stdout[:2048]}) + '\n')
        raise RuntimeError('native_fixture_command_failed')
    return row.stdout


def main():
    os.umask(0o077)
    assert Path('/run/.containerenv').exists()
    assert {v['ifname'] for v in json.loads(call('ip', '-j', 'link'))} == {'lo'}
    call('systemctl', 'stop', 'webmin.service')
    # A tiny stand-in isolates systemd/timer/nft/backup ordering from Webmin load.
    Path('/tmp/dummy-webmin.py').write_text('''import http.server, socket, threading, pathlib
class V6(http.server.HTTPServer):
    address_family = socket.AF_INET6
    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        super().server_bind()
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers()
    def log_message(self, *args): pass
wide = pathlib.Path('/etc/webmin/miniserv.conf').read_text().find('redirect_ssl=1') >= 0
a = http.server.HTTPServer(('0.0.0.0' if wide else '127.0.0.1', 10000), Handler)
b = V6(('::' if wide else '::1', 10000), Handler)
threading.Thread(target=a.serve_forever, daemon=True).start()
b.serve_forever()
''')
    Path('/usr/lib/systemd/system/webmin.service').write_text('''[Unit]
Description=Offline recovery-contract stand-in
[Service]
Type=simple
ExecStart=/usr/bin/python3 /tmp/dummy-webmin.py
TimeoutStopSec=20
[Install]
WantedBy=multi-user.target
''')
    fixture_preserved = ('/usr/lib/systemd/system/webmin.service',
                         '/etc/systemd/system/webmin.service.d/10-fleet-foundation.conf',
                         '/etc/systemd/system/webmin.service.d/60-startup-authority.conf',
                         '/etc/webmin/system-status/config')
    for name in r.CONFIGS + fixture_preserved[1:]:
        p = Path(name); p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text('# offline baseline\n'); p.chmod(0o600 if '/webmin/' in name else 0o644)
    for name in r.ADDED:
        Path(name).unlink(missing_ok=True)
    call('systemctl', 'daemon-reload')
    call('systemctl', 'enable', '--now', 'webmin.service')
    time.sleep(1)
    r.loopback()
    work = Path('/run/webmin-proxy-trial/nativefixture')
    work.mkdir(parents=True, mode=0o700)
    binding = {'hostname': r.socket.gethostname(), 'controls': r.controls(),
               'files': {name: r.identity(Path(name)) for name in r.CONFIGS + fixture_preserved}}
    r.save(work / 'binding.json', binding)
    call('python3', '/source/recover-proxy.py', 'snapshot', '--work-directory', str(work),
         '--binding', str(work / 'binding.json'))
    call('nft', 'add', 'table', 'inet', 'unrelated_sentinel')
    for name in ['recover-proxy.py', 'configure-miniserv.py', 'ingress.nft',
                 'webmin-firewall.service', '30-proxy-ingress.conf',
                 'miniserv.json', 'webmin.json']:
        (work / name).write_bytes((Path('/source') / name).read_bytes())
        (work / name).chmod(0o600)
    commands = json.loads(Path('/source/native-commands.json').read_text())
    for action in ('timer', 'apply'):
        argv = [arg.replace('{{ proxy_trial.work_directory }}', str(work))
                for arg in commands[action]]
        if action == 'timer':
            argv = [arg.replace('--on-active=1800s', '--on-active=30s') for arg in argv]
        call(*argv)
    time.sleep(1)
    assert '0.0.0.0:10000' in r.listeners()
    assert json.loads((work / 'state.json').read_text())['phase'] == 'applied'
    # No controller restore call: systemd alone must reach terminal recovery.
    deadline = time.monotonic() + 55
    while json.loads((work / 'state.json').read_text())['phase'] != 'restored':
        if time.monotonic() >= deadline:
            raise RuntimeError('native_timer_recovery_not_completed')
        time.sleep(1)
    r.loopback()
    r.unchanged(binding['files'])
    assert not any(Path(p).exists() for p in r.ADDED)
    call('nft', 'list', 'table', 'inet', 'unrelated_sentinel')
    tables = json.loads(call('nft', '-j', 'list', 'tables'))['nftables']
    assert not any(v.get('table', {}).get('name') == 'webmin' for v in tables)
    late = subprocess.run(['python3', '/source/recover-proxy.py', 'apply',
                           '--work-directory', str(work)], capture_output=True, text=True, timeout=10)
    assert late.returncode == 1
    assert json.loads(late.stdout)['reason'] == 'apply_state_mismatch'
    r.loopback()
    r.unchanged(binding['files'])
    result = {'passed': True, 'native_timer_recovery': True, 'unrelated_table_preserved': True,
              'late_apply_rejected': True,
              'workload': 'dummy loopback HTTP service', 'capacity_acceptance': False,
              'actual_webmin_browser_acceptance': False}
    Path('/evidence/native-state.json').write_bytes((work / 'state.json').read_bytes())
    Path('/evidence/native-recovery.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        diagnostics = {}
        state = Path('/run/webmin-proxy-trial/nativefixture/state.json')
        if state.exists():
            diagnostics['state'] = json.loads(state.read_text())
        try:
            diagnostics['controls'] = r.controls()
        except Exception as error:
            diagnostics['control_error'] = type(error).__name__
        row = subprocess.run(['journalctl', '-u', 'webmin-proxy-recovery.service',
                              '--no-pager', '-n', '20'], capture_output=True, text=True, timeout=10)
        diagnostics['recovery_journal'] = row.stdout[:8192]
        Path('/evidence/failure-diagnostics.json').write_text(json.dumps(diagnostics, indent=2) + '\n')
        raise
