#!/usr/bin/env python3
"""Native application fixture for the existing release outer/transaction.

Transport/node views reuse certificate-release-regression. Actual Kuma, Caddy,
TLS, client and native systemd oneshots produce application observations. The
Podman adapter executes the unchanged Node client in this already isolated
container; it never generates login results or receipts.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pty
import secrets
import select
import shutil
import subprocess
import sys
import threading
import time

REPO = Path(__file__).resolve().parents[2]
NATIVE = Path('/tmp/application-native')
SYSTEMCTL = '/usr/bin/systemctl.native'
JOURNALCTL = '/usr/bin/journalctl'
SOURCE = Path(__file__).resolve()
APP = REPO.parent / 'homelab-monitoring-observability/uptime-kuma'
UNITS = ['caddy-pihole-web-health.service', 'caddy-sync-health.service']
SCENARIOS = ['success', 'operator-rejection', 'http-failure', 'journal-failure', 'cycle-failure', 'readback-failure']
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('release_fixture', SOURCE.with_name('certificate-release-regression.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, timeout=30, **kwargs)


def native_control(*args):
    return run([SYSTEMCTL, *args])


def proxy_reload():
    selected = Path('/etc/caddy/current')
    fragment = selected / 'conf.d/20-uptime-kuma.caddy'
    if not fragment.exists():
        subprocess.run([SYSTEMCTL, 'stop', 'kuma-qualification-proxy.service'], capture_output=True, timeout=30)
        return
    # Exact selected fragment; only the surrounding synthetic TLS snippet differs.
    cert = Path(os.environ['CERT_FIXTURE_ROOT']) / 'cert'
    content = '{\n admin localhost:2019\n auto_https disable_redirects\n}\n'
    content += f'(local_tls) {{\n tls {cert}/fullchain.pem {cert}/privkey.pem\n}}\n'
    content += fragment.read_text()
    (NATIVE/'Caddyfile').write_text(content)
    if subprocess.run([SYSTEMCTL, 'is-active', '--quiet', 'kuma-qualification-proxy.service']).returncode:
        native_control('start', 'kuma-qualification-proxy.service')
    else:
        run(['/usr/bin/caddy', 'reload', '--config', str(NATIVE/'Caddyfile')])
    native_control('start', *(unit.replace('.service', '.timer') for unit in UNITS))


def adapter(name, args):
    release.require_container()
    if name == 'podman':
        if args[:3] == ['container', 'exists', args[-1]]:
            return 1  # run uses exec; there is no detached container/process.
        assert args[:7] == ['run', '--rm', '--pull', 'never', '--network', 'host', '--name']
        assert args[-2:] == ['/work/verify-proxy-login.cjs', '--production']
        assert '--read-only' in args and '--cap-drop' in args and '--security-opt' in args
        assert args[-3] == '1bf189bcd6286c24facc94dcd12565b09e1cf0bdd523d3dc8852f6646be49c29'
        mount = args[args.index('-v')+1]
        assert mount.endswith(':/work:ro')
        client = Path(mount[:-9])/'verify-proxy-login.cjs'
        assert client.read_bytes() == (APP/'scripts/verify-proxy-login.cjs').read_bytes()
        # Synthetic CA is an explicit fixture trust input, not disabled verification.
        env = dict(os.environ, NODE_EXTRA_CA_CERTS=str(Path(os.environ['CERT_FIXTURE_ROOT'])/'cert/fullchain.pem'))
        result = subprocess.run(['/usr/local/bin/node', str(client), '--production'], env=env, input=sys.stdin.buffer.read(), capture_output=True, timeout=160)
        root = Path(os.environ['CERT_FIXTURE_ROOT'])
        (root/'native-client.status').write_text(str(result.returncode)+'\n')
        (root/'native-client.stderr').write_bytes(result.stderr)
        sys.stdout.buffer.write(result.stdout)
        sys.stderr.buffer.write(result.stderr)
        return result.returncode
    if name == 'systemctl' and any(unit in args for unit in UNITS) and args[0] == 'show':
        return subprocess.run([SYSTEMCTL, *args]).returncode
    if name == 'curl' and args[-1] == 'https://uptime.local.theama.co/dashboard':
        cert = Path(os.environ['CERT_FIXTURE_ROOT'])/'cert/fullchain.pem'
        return subprocess.run(['/usr/bin/curl', '--cacert', str(cert), *args]).returncode
    if name == 'journalctl' and '--grep' in args:
        cursors = json.loads((Path(os.environ['CERT_FIXTURE_ROOT'])/'native-cursors.json').read_text())
        cursor = cursors[release.active_role()+':'+args[args.index('--after-cursor')+1]]
        command = [JOURNALCTL, '-u', 'kuma-qualification-proxy.service', '--after-cursor', cursor,
                   '--grep', args[args.index('--grep')+1], '--quiet', '--no-pager', '--no-tail']
        result = subprocess.run(command, capture_output=True)
        root = Path(os.environ['CERT_FIXTURE_ROOT'])
        with (root/'native-journal-queries.jsonl').open('a') as log:
            log.write(json.dumps(dict(command=command, status=result.returncode,
                                      stdout=result.stdout.decode(), stderr=result.stderr.decode()))+'\n')
        sys.stdout.buffer.write(result.stdout)
        sys.stderr.buffer.write(result.stderr)
        return result.returncode
    if name == 'journalctl' and '--show-cursor' in args:
        output = run([JOURNALCTL, '--show-cursor', '-n', '0'], text=True).stdout
        path = Path(os.environ['CERT_FIXTURE_ROOT'])/'native-cursors.json'
        cursors = json.loads(path.read_text()) if path.exists() else {}
        key = release.active_role()+':'+str(len(release.state()['journal']))
        cursors.setdefault(key, output.split('-- cursor: ')[1].strip())
        path.write_text(json.dumps(cursors))
    if name == 'systemctl' and args == ['reload', 'caddy.service']:
        proxy_reload()
    return release.adapter(name, args)


def initialize(credentials):
    assert Path('/proc/1/comm').read_text().strip() == 'systemd'
    assert Path('/run/.containerenv').exists()
    NATIVE.mkdir(mode=0o700)
    shutil.copy2('/usr/bin/systemctl', SYSTEMCTL)
    native_control('stop', 'caddy.service')
    for address in ['10.1.0.56/32', 'fd36:5aa8:6971:1::56/128',
                    '10.1.3.75/32', 'fd36:5aa8:6971:1::75/128']:
        run(['/usr/sbin/ip', 'address', 'add', address, 'dev', 'lo', 'nodad'])
    Path('/app/data').mkdir(exist_ok=True)
    units = Path('/etc/systemd/system')
    (units/'kuma-qualification.service').write_text('[Service]\nWorkingDirectory=/app\nEnvironment=UPTIME_KUMA_DB_TYPE=sqlite\nExecStart=/usr/local/bin/node /app/server/server.js\n')
    (units/'kuma-qualification-proxy.service').write_text(f'[Service]\nExecStart=/usr/bin/caddy run --config {NATIVE}/Caddyfile\n')
    for unit in UNITS:
        (units/unit).write_text('[Service]\nType=oneshot\nExecStart=/bin/true\n')
        (units/unit.replace('.service','.timer')).write_text('[Timer]\nOnActiveSec=1s\nOnUnitInactiveSec=2s\nAccuracySec=100ms\n')
    native_control('daemon-reload')
    native_control('start', 'kuma-qualification.service')
    deadline = time.monotonic()+90
    while subprocess.run(['/usr/bin/curl','--silent','--fail','--max-time','2','-o','/dev/null','http://127.0.0.1:3001/dashboard']).returncode:
        assert time.monotonic() < deadline
        time.sleep(2)
    bootstrap = "const io=require('/app/node_modules/socket.io-client').io;const c=JSON.parse(require('fs').readFileSync(0,'utf8'));const s=io('http://127.0.0.1:3001');setTimeout(()=>process.exit(1),10000);s.on('setup',()=>s.emit('setup',c.username,c.password,r=>process.exit(r.ok?0:1)));"
    run(['/usr/local/bin/node','-e',bootstrap], input=json.dumps(credentials).encode())


def private_operator(helper, window, credentials):
    # Input goes only to a private PTY; discard prompt bytes instead of logging them.
    pid, descriptor = pty.fork()
    if pid == 0:
        os.execv('/usr/bin/python3', ['python3', str(helper), json.loads(window.read_text())['operation'], str(window.parent/'operator-receipt.json')])
    pending = b''
    sent = set()
    deadline = time.monotonic()+200
    try:
        while time.monotonic() < deadline:
            if select.select([descriptor], [], [], 1)[0]:
                try:
                    data = os.read(descriptor, 8192)
                except OSError:
                    break
                if not data:
                    break
                pending = (pending+data)[-8192:]
                for marker,key in [(b'Kuma username:', 'username'), (b'Kuma password (never retained):', 'password')]:
                    if marker in pending and key not in sent:
                        os.write(descriptor, credentials[key].encode()+b'\n')
                        sent.add(key)
        else:
            os.kill(pid, 9)
        _, status = os.waitpid(pid, 0)
        return os.waitstatus_to_exitcode(status)
    finally:
        os.close(descriptor)


def operator_thread(outer, before, credentials, scenario, observations):
    deadline = time.monotonic()+180
    while outer.poll() is None and time.monotonic() < deadline:
        roots = set(Path('/tmp').glob('caddy-serving-health-outer-test.*'))-before
        windows = [p/'operator-window.json' for p in roots if (p/'operator-window.json').exists()]
        if windows:
            window = windows[0]
            if scenario == 'journal-failure':
                run(['/usr/sbin/ip','-6','address','del','fd36:5aa8:6971:1::75/128','dev','lo'])
                def restore():
                    time.sleep(40)
                    run(['/usr/sbin/ip','-6','address','add','fd36:5aa8:6971:1::75/128','dev','lo','nodad'])
                restorer = threading.Thread(target=restore)
                restorer.start()
            supplied = dict(credentials)
            if scenario == 'operator-rejection':
                supplied['username'] = 'unknown-fixture-user'
            observations['helper_status'] = private_operator(window.parent/'payload/operator/private-proxy-login.py', window, supplied)
            if scenario == 'journal-failure':
                restorer.join()
            if scenario == 'http-failure':
                native_control('stop', 'kuma-qualification.service')
            if scenario == 'cycle-failure':
                native_control('stop', 'caddy-sync-health.timer')
                Path('/etc/systemd/system/caddy-sync-health.service').write_text('[Service]\nType=oneshot\nExecStart=/bin/false\n')
                native_control('daemon-reload')
                subprocess.run([SYSTEMCTL,'start','caddy-sync-health.service'],capture_output=True,timeout=20)
            return
        time.sleep(.2)
    observations['operator_not_reached'] = True


def main():
    release.require_container()
    credentials = dict(username='local-qualification', password=secrets.token_urlsafe(32))
    initialize(credentials)
    evidence = Path('/qual/application')
    evidence.mkdir(mode=0o700)
    graph_files = release.GRAPH_FILES + ['Caddy/tests/application-onboarding-regression.py','Caddy/tests/Containerfile.application','Caddy/tests/run-application-qualification.py']
    graph = {p:release.digest(REPO/p) for p in graph_files}
    selected_scenarios = [os.environ['CADDY_APPLICATION_SCENARIO']] if os.environ.get('CADDY_APPLICATION_SCENARIO') else SCENARIOS
    assert set(selected_scenarios) <= set(SCENARIOS)
    for scenario in selected_scenarios:
        root = evidence/scenario
        root.mkdir(mode=0o700)
        os.environ['CERT_APPLICATION'] = '1'
        env = release.setup(root)
        env['CADDY_CERTIFICATE_TEST_SCOPE'] = 'application'
        env['CERT_CASE'] = 'application-readback-failure' if scenario == 'readback-failure' else 'success'
        os.environ.update(CERT_FIXTURE_ROOT=str(root), CERT_CASE=env['CERT_CASE'])
        for name in ['systemctl','journalctl','curl']:
            script = root/'bin'/name
            script.write_text(f'#!/bin/bash\nexec /usr/bin/python3 {SOURCE} --adapter {name} "$@"\n')
        shutil.copyfile(root/'bin/systemctl','/usr/bin/systemctl')
        Path('/usr/bin/podman').write_text(f'#!/bin/bash\nexec /usr/bin/python3 {SOURCE} --adapter podman "$@"\n')
        Path('/usr/bin/podman').chmod(0o755)
        # Baseline health state is a fixture input; monitor-cycle timestamps are native.
        Path('/var/lib/caddy-pihole-web-health').mkdir(exist_ok=True)
        Path('/var/lib/caddy-pihole-web-health/state').write_text('state=healthy\n')
        before = set(Path('/tmp').glob('caddy-serving-health-outer-test.*'))
        observation = {}
        with (root/'outer.stdout').open('w') as out, (root/'outer.stderr').open('w') as err:
            outer = subprocess.Popen(['/bin/bash',str(REPO/'Caddy/scripts/run-serving-health-deployment-outer.sh'),'--production-path-test'],env=env,stdout=out,stderr=err)
            thread = threading.Thread(target=operator_thread,args=(outer,before,credentials,scenario,observation))
            thread.start()
            try:
                status = outer.wait(timeout=900)
            finally:
                if outer.poll() is None:
                    outer.kill()
                    outer.wait()
            thread.join(timeout=210)
            assert not thread.is_alive()
        for runner in set(Path('/tmp').glob('caddy-serving-health-outer-test.*'))-before:
            shutil.copytree(runner, root/'runner-evidence')
        observation['outer_status'] = status
        expected = 0 if scenario == 'success' else 1
        (root/'observations.json').write_text(json.dumps(observation,indent=2)+'\n')
        assert status == expected, (scenario,status,root)
        assert observation.get('helper_status') == (1 if scenario == 'operator-rejection' else 0), observation
        observation['nodes'] = {}
        for role in ['node-a','node-b']:
            release.switch(role)
            selected = os.readlink('/etc/caddy/current')
            assert (selected == '/etc/caddy/releases/baseline') == (scenario != 'success')
            assert release.state()['lsyncd']
            observation['nodes'][role] = dict(selection=selected, publisher_sha256=release.digest('/usr/local/libexec/publish-release-v2.sh'), lsyncd=True)
        calls = [json.loads(line) for line in (root/'ssh.jsonl').read_text().splitlines()]
        commands = [row['command'] for row in calls]
        if scenario != 'success':
            assert next(i for i,c in enumerate(commands) if ' certificate-rollback node-a ' in c) < next(i for i,c in enumerate(commands) if ' certificate-rollback node-b ' in c)
        for letter in ['a','b']:
            assert (root/f'runner-evidence/node-{letter}-disposition.status').read_text().strip() == '0'
        (root/'observations.json').write_text(json.dumps(observation,indent=2)+'\n')
        # Retain the last node view before teardown; no external resources exist.
        for name,path in release.VIEWS.items():
            release.move_tree(path,root/'nodes'/release.active_role()/name)
        (root/'active').unlink()
        native_control('stop','kuma-qualification-proxy.service',*(u.replace('.service','.timer') for u in UNITS))
        Path('/etc/systemd/system/caddy-sync-health.service').write_text('[Service]\nType=oneshot\nExecStart=/bin/true\n')
        native_control('daemon-reload')
        native_control('reset-failed')
        native_control('start','kuma-qualification.service')
        print('application_scenario='+scenario+':passed',flush=True)
    assert graph == {p:release.digest(REPO/p) for p in graph_files}
    (evidence/'qualification-summary.json').write_text(json.dumps(dict(source_graph=graph,scenarios=selected_scenarios,scope='isolated native application; simulated transport/node views; real helper receipt'),indent=2)+'\n')


def verify_evidence(evidence):
    summary = json.loads((evidence/'qualification-summary.json').read_text())
    assert summary['scenarios'] == SCENARIOS
    assert summary['source_graph'] == {name:release.digest(REPO/name) for name in summary['source_graph']}
    assert set(summary['source_graph']) == set(release.GRAPH_FILES + [
        'Caddy/tests/application-onboarding-regression.py','Caddy/tests/Containerfile.application',
        'Caddy/tests/run-application-qualification.py'])
    for scenario in SCENARIOS:
        root=evidence/scenario; runner=root/'runner-evidence'
        observed=json.loads((root/'observations.json').read_text())
        assert observed['outer_status']==(0 if scenario=='success' else 1)
        receipt=json.loads((runner/'operator-receipt.json').read_text())
        assert receipt['client_sha256']==release.digest(APP/'scripts/verify-proxy-login.cjs')
        assert observed['helper_status']==(1 if scenario=='operator-rejection' else 0)
        assert receipt['status']==('failed' if scenario=='operator-rejection' else 'passed')
        assert (root/'native-client.status').read_text().strip()==('1' if scenario=='operator-rejection' else '0')
        assert json.loads((runner/'operator-window.json').read_text())['status']=='closed'
        calls=[json.loads(line) for line in (root/'ssh.jsonl').read_text().splitlines()]
        commands=[c['command'] for c in calls if c['stdin_sha256']==release.digest(REPO/'Caddy/scripts/apply-serving-health-deployment.sh')]
        assert commands
        assert next(i for i,c in enumerate(commands) if ' certificate-accept node-b ' in c)<next(i for i,c in enumerate(commands) if ' certificate-promote node-a ' in c)
        if scenario!='success':
            assert next(i for i,c in enumerate(commands) if ' certificate-contain-publication ' in c)<next(i for i,c in enumerate(commands) if ' certificate-rollback node-a ' in c)<next(i for i,c in enumerate(commands) if ' certificate-rollback node-b ' in c)
        for role in ['node-a','node-b']:
            node=root/'nodes'/role; selected=os.readlink(node/'caddy/current')
            assert selected==observed['nodes'][role]['selection']
            assert (selected=='/etc/caddy/releases/baseline')==(scenario!='success')
            assert release.digest(node/'libexec/publish-release-v2.sh')==release.digest(REPO/'Caddy/scripts/publish-release-v2.sh')
            assert json.loads((node/'state.json').read_text())['lsyncd']
            letter=role[-1]
            assert (runner/f'node-{letter}-disposition.status').read_text().strip()=='0'
            if scenario=='success':
                records=release.decode_stream(runner/f'application-result-{letter}-readback.stdout')
                assert (runner/f'application-observe-{letter}.status').read_text().strip()=='0'
                http=[list(map(int,line.split('\t'))) for line in records['application-http.tsv'].splitlines()]
                for family in (4,6):
                    times=[row[0] for row in http if row[1]==family]
                    assert len(times)>=2 and times[-1]-times[0]>=65
                assert all(row[2]==200 for row in http)
                cycles=[line.split('\t') for line in records['application-cycles.tsv'].splitlines()]
                for unit in UNITS:
                    rows=[list(map(int,row[1:])) for row in cycles if row[0]==unit]
                    assert len(rows)>=2 and [v[0] for v in rows]==sorted(set(v[0] for v in rows))
                    assert all(v[1]>=v[0]>0 for v in rows)
                assert not any(word in records['application-health-journal.stdout'].lower() for word in ['failed','unhealthy','error'])
        if scenario in ('http-failure','journal-failure','cycle-failure'):
            assert (runner/'application-observe-b.status').read_text().strip()!='0'
        if scenario == 'journal-failure':
            queries = [json.loads(line) for line in (root/'native-journal-queries.jsonl').read_text().splitlines()]
            assert any(q['status']==0 and 'health_checker.active' in q['stdout'] and
                       'HTTP request failed' in q['stdout'] and q['command'][-1]=='--no-tail' for q in queries)
    print('application_qualification_verified=true')


if __name__ == '__main__':
    if len(sys.argv)>2 and sys.argv[1]=='--adapter':
        raise SystemExit(adapter(sys.argv[2],sys.argv[3:]))
    if len(sys.argv)==3 and sys.argv[1]=='--verify-evidence':
        verify_evidence(Path(sys.argv[2]))
    else:
        main()
