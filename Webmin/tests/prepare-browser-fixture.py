#!/usr/bin/env python3
"""Configure only the task-owned, network-none container for native browser tests."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=30, **kwargs).stdout


def main():
    os.umask(0o077)
    assert Path('/run/.containerenv').is_file()
    assert {r['ifname'] for r in json.loads(run('/usr/sbin/ip', '-j', 'link'))} == {'lo'}
    paired = sys.argv[1:] == ['--paired']
    assert not sys.argv[1:] or paired
    if paired:
        run('ip', '-6', 'addr', 'add', 'fd00::2/128', 'dev', 'lo', 'nodad')
    root = Path('/work/Webmin')
    foundation = Path('/evidence/foundation-dropin.conf')
    binding = json.loads(Path('/evidence/owner-binding.json').read_text())
    assert not foundation.is_symlink() and foundation.is_file()
    assert hashlib.sha256(foundation.read_bytes()).hexdigest() == binding['dropin_sha256']
    spec = importlib.util.spec_from_file_location('editor', root / 'scripts/configure-miniserv.py')
    editor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(editor)
    spec = importlib.util.spec_from_file_location('profile', root / 'scripts/render-proxy-profile.py')
    profile = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(profile)
    run('systemctl', 'stop', 'webmin.service')
    baseline = Path('/evidence/baseline')
    baseline.mkdir(exist_ok=False)
    for name in ['miniserv.conf', 'config']:
        shutil.copy2('/etc/webmin/' + name, baseline / name)
    password = secrets.token_urlsafe(24)
    hashed = run('openssl', 'passwd', '-6', '-stdin', input=password).strip()
    Path('/etc/webmin/miniserv.users').write_text('fixture:' + hashed + '\n')
    Path('/etc/webmin/webmin.acl').write_text('fixture: webmin system-status xterm\n')
    run('useradd', '--create-home', '--shell', '/bin/bash', 'fixture')
    Path('/etc/webmin/xterm/fixture.acl').write_text('user=fixture\nsudoenforce=1\n')
    Path('/evidence/login.json').write_text(json.dumps({'username': 'fixture', 'password': password}))
    mini = Path('/etc/webmin/miniserv.conf')
    editor.configure(mini, {'port': '10000', 'ssl': '0', 'bind': '127.0.0.1', 'sockets': '::1:10000',
                           'ipv6': '1', 'allow': '127.0.0.1 ::1', 'deny': '', 'allowusers': 'fixture',
                           'sudo': '0', 'pam': '', 'localauth': '', 'session': '1', 'listen': '',
                           'ssl_redirect': '0', 'syslog': '0'})
    webmin = Path('/etc/webmin/config')
    editor.configure(webmin, {'referer': '0', 'referers_none': '1', 'webprefix': ''})
    system = Path('/etc/webmin/system-status/config')
    editor.configure(system, {'collect_pkgs': '0'})
    # Preserve a real loopback baseline for the recovery test, distinct from image defaults.
    for name in ['miniserv.conf', 'config']:
        shutil.copy2('/etc/webmin/' + name, baseline / ('loopback-' + name))
    review = json.loads((root / 'configs/hosts/example-proxy.json').read_text())
    review['browser_hostname'] = 'webmin-host.example.test'
    review['backend_addresses'] = ['127.0.0.1', '::1']
    review['proxy_sources'] = ['127.0.0.1', '::1']
    review['miniserv']['allowusers'] = 'fixture'
    policy = profile.policies(review)
    editor.configure(mini, policy['miniserv'])
    editor.configure(webmin, policy['webmin'])
    Path('/etc/webmin/ingress.nft').write_text(profile.ingress(review))
    shutil.copy2(root / 'systemd/webmin-firewall.service', '/etc/systemd/system/webmin-firewall.service')
    drop = Path('/etc/systemd/system/webmin.service.d')
    drop.mkdir(exist_ok=True)
    shutil.copy2(root / 'systemd/webmin.service.d/30-proxy-ingress.conf', drop / '30-proxy-ingress.conf')
    # Reuse the package's real unit producer, not a hand-written substitute.
    shutil.copy2(foundation, drop / '10-fleet-foundation.conf')
    (drop / '10-fleet-foundation.conf').chmod(0o644)
    run('/usr/bin/perl', '/usr/share/webmin/init/updateboot.pl', 'webmin',
        cwd='/usr/share/webmin/init',
        env={**os.environ, 'WEBMIN_LIBDIR': '/usr/share/webmin', 'WEBMIN_CONFIG': '/etc/webmin'})
    props = run('systemctl', 'show', 'webmin.service',
                '--property=Type,FragmentPath,DropInPaths,MemoryHigh,MemoryMax,MemorySwapMax,TasksMax,CPUQuotaPerSecUSec,KillMode,OOMPolicy,TimeoutStartUSec,TimeoutStopUSec,Restart,RestartUSec,StartLimitIntervalUSec,StartLimitBurst')
    Path('/evidence/effective-unit.txt').write_text(props)
    expected = ['Type=simple', 'MemoryHigh=134217728', 'MemoryMax=201326592',
                'MemorySwapMax=0', 'TasksMax=128', 'CPUQuotaPerSecUSec=1s',
                'KillMode=control-group', 'OOMPolicy=stop', 'TimeoutStartUSec=1min',
                'TimeoutStopUSec=20s', 'Restart=on-failure', 'RestartUSec=2s',
                'StartLimitIntervalUSec=5min', 'StartLimitBurst=3']
    assert set(expected) <= set(props.splitlines()), 'effective_fixture_controls_mismatch'
    unit_path = Path(next(line.split('=', 1)[1] for line in props.splitlines() if line.startswith('FragmentPath=')))
    shutil.copy2(unit_path, '/evidence/generated-webmin.service')
    Path('/etc/webmin/.installation-accepted').touch()
    run('systemctl', 'daemon-reload')
    run('systemctl', 'enable', 'webmin-firewall.service', 'webmin.service')
    run('systemctl', 'start', 'webmin.service')
    tls = Path('/evidence/tls')
    tls.mkdir()
    run('openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2',
        '-subj', '/CN=Webmin fixture CA', '-keyout', str(tls/'ca.key'), '-out', str(tls/'ca.crt'))
    run('openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=webmin-host.example.test',
        '-keyout', str(tls/'server.key'), '-out', str(tls/'server.csr'))
    (tls/'extensions').write_text('subjectAltName=DNS:webmin-host.example.test\nextendedKeyUsage=serverAuth\n')
    run('openssl', 'x509', '-req', '-in', str(tls/'server.csr'), '-CA', str(tls/'ca.crt'),
        '-CAkey', str(tls/'ca.key'), '-CAcreateserial', '-days', '2', '-extfile', str(tls/'extensions'),
        '-out', str(tls/'server.crt'))
    nss = Path('/root/.pki/nssdb')
    nss.mkdir(parents=True, exist_ok=True)
    run('certutil', '-N', '--empty-password', '-d', 'sql:' + str(nss))
    run('certutil', '-A', '-n', 'Webmin fixture CA', '-t', 'C,,', '-i', str(tls/'ca.crt'), '-d', 'sql:' + str(nss))
    fragment = (root / 'proposals/30-webmin-example.caddy').read_text()
    fragment = fragment.replace('webmin-example.local.theama.co', 'webmin-host.example.test')
    fragment = fragment.replace('10.1.0.56 fd36:5aa8:6971:1::56 {$NODE_IPV4} {$NODE_IPV6}', '127.0.0.1 ::1')
    fragment = fragment.replace('10.1.0.0/22 fd36:5aa8:6971:1::/64', '127.0.0.1/32 ::1/128')
    fragment = fragment.replace('192.0.2.75:10000', '127.0.0.1:10000').replace('[2001:db8::75]:10000', '[::1]:10000')
    fragment = fragment.replace('import local_tls', 'tls /evidence/tls/server.crt /evidence/tls/server.key')
    nodes = {'a': '127.0.0.1 ::1', 'b': '127.0.0.2 fd00::2'} if paired else {'a': '127.0.0.1 ::1'}
    units = []
    for node, addresses in nodes.items():
        text = fragment.replace('bind 127.0.0.1 ::1', 'bind ' + addresses)
        # Permit only this isolated namespace's loopback clients.
        text = text.replace('127.0.0.1/32 ::1/128', '127.0.0.0/8 ::1/128 fd00::2/128')
        config = Path('/evidence') / ('Caddyfile-' + node if paired else 'Caddyfile')
        config.write_text('{\n admin off\n auto_https disable_redirects\n}\n' + text)
        run('/usr/bin/caddy', 'validate', '--config', str(config), '--adapter', 'caddyfile')
        if paired:
            # Force each upstream family independently in the browser path matrix.
            family_address = '127.0.0.1:10000' if node == 'a' else '[::1]:10000'
            forced = config.with_name(config.name + '-forced')
            forced.write_text(config.read_text().replace('reverse_proxy 127.0.0.1:10000 [::1]:10000',
                                                        'reverse_proxy ' + family_address))
            run('/usr/bin/caddy', 'validate', '--config', str(forced), '--adapter', 'caddyfile')
            shutil.copy2(config, config.with_name(config.name + '-paired'))
            shutil.copy2(forced, config)
        unit = 'webmin-fixture-caddy' + ('-' + node if paired else '') + '.service'
        Path('/etc/systemd/system', unit).write_text('[Unit]\nAfter=webmin.service\n[Service]\n'
            + 'ExecStart=/usr/bin/caddy run --config ' + str(config) + ' --adapter caddyfile\n'
            + '[Install]\nWantedBy=multi-user.target\n')
        units.append(unit)
    with Path('/etc/hosts').open('a') as stream:
        stream.write('\n127.0.0.1 webmin-host.example.test\n::1 webmin-host.example.test\n')
    run('systemctl', 'daemon-reload')
    run('systemctl', 'enable', '--now', *units)
    Path('/evidence/fixture-mode.json').write_text(json.dumps({'paired': paired, 'units': units,
        'frontends': nodes, 'forced_upstreams': {'a': 'ipv4', 'b': 'ipv6'} if paired else {}}))
    print(json.dumps({'prepared': True, 'network': 'none', 'synthetic_credentials': True,
                      'native_webmin_unit': 'package updateboot.pl producer plus exact owner foundation drop-in; installed target identity still unverified'}))


if __name__ == '__main__':
    main()
