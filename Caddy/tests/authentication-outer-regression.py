#!/usr/bin/env python3
"""Full neutral outer stage with real Caddy/HTTP and causal external-system models."""
import hashlib
import http.server
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'tests' / filename)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def run(*args, **kwargs):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed ({result.returncode}): {result.stderr.decode()[-2000:]}')
    return result


def projection(work, role):
    selected = Path('/etc/caddy/current') if role == 'node-b' else work / 'node-a/etc/caddy/current'
    fragment = (selected / 'conf.d/10-pihole-admin.caddy').read_text().split('\npihole-admin.local.theama.co {')[0]
    port = 2021 if role == 'node-b' else 2020
    fqdn, suffix = ('pihole00', '54') if role == 'node-b' else ('pihole0', '53')
    text = f'{{\n admin 127.0.0.1:{port}\n auto_https off\n}}\n'
    text += f'(local_tls) {{\n tls {selected}/tls/fullchain.pem {selected}/tls/privkey.pem\n}}\n' + fragment
    text += f'\nhttps://{fqdn}.local.theama.co {{\n bind 10.1.0.{suffix} fd36:5aa8:6971:1::{suffix}\n import pihole_ui\n}}\n'
    if role == 'node-a':
        text += '\nhttps://pihole-admin.local.theama.co {\n bind 10.1.0.56 fd36:5aa8:6971:1::56\n import pihole_ui\n}\n'
        text += '\nhttps://proxy.local.theama.co {\n bind 10.1.0.56 fd36:5aa8:6971:1::56\n import local_tls\n respond 204\n}\n'
    path = work / f'{role}.caddy'
    path.write_text(text)
    return path, port


def command():
    """Only model external commands; never implement a transaction mode."""
    work = Path(os.environ['CADDY_AUTH_STAGE_FIXTURE'])
    name, args = Path(sys.argv[0]).name, sys.argv[1:]
    role = os.environ.get('AUTH_RELEASE_ROLE', 'node-b')
    with (work / 'external-calls.jsonl').open('a') as stream:
        stream.write(json.dumps({'role': role, 'command': name, 'args': args}) + '\n')
    if name == 'sudo':
        assert args.pop(0) == '-n'
        os.execvp(args[0], args)
    if name == 'scp':
        assert args[:2] == ['-p', '--'] and args[3].startswith(('fixture-node-a:', 'fixture-node-b:'))
        shutil.copy2(args[2], args[3].split(':', 1)[1])
        return 0
    if name == 'ssh':
        assert args[0] in ('fixture-node-a', 'fixture-node-b') and len(args) == 2
        role = args[0].removeprefix('fixture-')
        env = dict(os.environ, AUTH_RELEASE_ROLE=role, PATH=f'{work / "bin"}:/usr/sbin:/usr/bin:/sbin:/bin',
                   CADDY_SERVING_HEALTH_TARGET_ROOT=str(work / 'node-a') if role == 'node-a' else '',
                   CADDY_SERVING_HEALTH_OUTGOING_ROOT='/var/lib/caddy-sync/outbound' if role == 'node-a' else '/var/lib/caddy-sync/node-b-outbound')
        scenario = os.environ.get('AUTH_OUTER_SCENARIO', 'success')
        if (scenario == 'interrupt-helper' and ' auth-helper-install ' in args[1]) or scenario == 'evidence-failure' or (scenario == 'publish-reply-failure' and ' auth-release-publish ' in args[1]) or (scenario == 'reordered-evidence' and ' sampler-stop ' in args[1] and role == 'node-b'):
            program = sys.stdin.buffer.read()
            result = subprocess.run(['/bin/bash', '-c', args[1]], input=program, env=env)
            if result.returncode == 0 and scenario == 'reordered-evidence' and not (work / 'reordered-injected').exists():
                evidence = Path(shlex.split(args[1])[-1])
                records = evidence / 'availability.tsv'
                rows = records.read_text().splitlines(keepends=True)
                assert len(rows) > 9
                rows[1], rows[2] = rows[2], rows[1]
                records.write_text(''.join(rows))  # Corrupt actual producer output, never fabricate successful observations.
                (work / 'reordered-injected').touch()
            if result.returncode == 0 and scenario == 'publish-reply-failure':
                deadline = time.monotonic() + 45
                while not (work / 'reconcile.status').exists() and time.monotonic() < deadline:
                    time.sleep(0.2)
                return 7
            if result.returncode == 0 and scenario == 'interrupt-helper':
                os.kill(os.getppid(), signal.SIGTERM)
            if result.returncode == 0 and scenario == 'evidence-failure' and len(shlex.split(args[1])) == 9 and b'base64 -w 0' in program:
                return 7  # Lost readback reply, after executing the real producer.
            return result.returncode
        os.execve('/bin/bash', ['/bin/bash', '-c', args[1]], env)
    if name == 'doppler':
        validator = module('login', '../scripts/validate-pihole-authentication.py')
        assert tuple(args) == validator.DOPPLER_COMMAND[1:]
        print('fixture-wrong' if os.environ.get('AUTH_OUTER_SCENARIO') in ('login-failure', 'restore-failure') else 'fixture-correct', end='')
        return 0
    if name == 'systemctl':
        action, unit = args[0], args[-1]
        state = work / f'{role}-{unit}.state'
        current = state.read_text().strip() if state.exists() else 'active'
        if action == 'is-enabled':
            if '--quiet' not in args:
                print('masked' if unit in ('caddy-api.service', 'lsyncd.service') else 'enabled')
            return 0
        if action == 'is-active':
            if '--quiet' not in args:
                print(current)
            return 0 if current == 'active' else 3
        if action in ('start', 'stop'):
            state.write_text('active' if action == 'start' else 'inactive')
            return 0
        if action == 'reload':
            assert unit == 'caddy.service'
            if os.environ.get('AUTH_OUTER_SCENARIO') == 'reconcile-failure' and Path('/etc/caddy/current').resolve().name != 'fixture-baseline':
                return 1
            if os.environ.get('AUTH_OUTER_SCENARIO') == 'restore-failure' and Path('/etc/caddy/current').resolve().name == 'fixture-baseline':
                return 1  # Caddy rejects the requested rollback reload; running config remains candidate.
            path, port = projection(work, role)
            result = subprocess.run(['caddy', 'reload', '--address', f'127.0.0.1:{port}', '--adapter', 'caddyfile', '--config', str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return result.returncode
        raise AssertionError(args)
    if name == 'busctl':
        assert args[0] == 'get-property' and args[-1] == 'State'
        print('s "Master"' if role == 'node-a' else 's "Backup"')
        return 0
    if name == 'ip':
        if 'monitor' in args:
            # Kernel address events are observed in the isolated namespace.
            os.execv('/usr/sbin/ip', ['/usr/sbin/ip', '-o', 'monitor', 'address', 'dev', 'lo'])
        assert args == ['-o', 'address', 'show', 'dev', 'eth0']
        if role == 'node-a':
            for suffix in ('55', '56'):
                print(f'1: eth0 inet 10.1.0.{suffix}/22 scope global')
                print(f'1: eth0 inet6 fd36:5aa8:6971:1::{suffix}/128 scope global')
        return 0
    if name == 'dig':
        assert args[1:4] == ['-p', '53', 'pihole.local.theama.co']
        if os.environ.get('AUTH_OUTER_SCENARIO') == 'dns-failure' and Path('/etc/caddy/current').resolve().name != 'fixture-baseline':
            return 1
        # DNS is an unavailable external system; queries depend on modeled service state.
        for service in ('pihole-FTL.service', 'unbound.service'):
            state = work / f'node-a-{service}.state'
            if state.exists() and state.read_text().strip() != 'active':
                return 1
        print('10.1.0.55' if args[4] == 'A' else 'fd36:5aa8:6971:1::55')
        return 0
    if name == 'journalctl':
        path = work / f'{role}.journal'
        records = path.read_text().splitlines() if path.exists() else []
        if '--show-cursor' in args:
            print(f'-- cursor: fixture-{len(records)}')
        else:
            cursor = args[args.index('--after-cursor') + 1]
            assert cursor.startswith('fixture-')
            for row in records[int(cursor.removeprefix('fixture-')):]:
                print(row)
        return 0
    raise AssertionError(name)


def verify_calls(call_path, evidence, scenario):
    calls = [json.loads(line) for line in call_path.read_text().splitlines()]
    phases = []
    for index, call in enumerate(calls):
        if call['command'] == 'ssh':
            parts = shlex.split(call['args'][1])
            if len(parts) >= 12:
                assert parts[:8] == ['cd', '/', '&&', 'sudo', '-n', '/bin/bash', '-s', '--']
                phases.append((parts[8], parts[9], index))
    def position(mode, role):
        positions = [i for m, r, i in phases if (m, r) == (mode, role)]
        assert len(positions) == 1, (scenario, mode, role, positions)
        return positions[0]
    assert position('auth-release-preflight', 'node-b') < position('auth-release-preflight', 'node-a')
    assert position('auth-release-prepare', 'node-a') < position('auth-helper-install', 'node-b')
    if scenario == 'interrupt-helper':
        assert not any(mode == 'auth-release-publish' for mode, _, _ in phases)
        assert not (evidence / 'auth-login.stdout').exists()
        return
    assert position('auth-helper-install', 'node-b') < position('auth-release-publish', 'node-a')
    assert position('auth-release-publish', 'node-a') < position('auth-release-discover', 'node-a')
    if scenario != 'publish-reply-failure':
        position('auth-release-wait', 'node-b')
    login = evidence / 'auth-login.stdout'
    if scenario in ('publish-reply-failure', 'reconcile-failure'):
        assert not login.exists()
    else:
        provider_calls = [i for i, c in enumerate(calls) if c['command'] == 'doppler']
        assert len(provider_calls) == 1 and provider_calls[0] > position('auth-release-wait', 'node-b')
        rows = [json.loads(line) for line in login.read_text().splitlines() if line.startswith('{')]
        posts = [(r['family'], r['status']) for r in rows if r['method'] == 'POST']
        if scenario in ('login-failure', 'restore-failure'):
            assert posts == [(4, 200), (4, 200)], posts
        else:
            assert posts == [(4, 200), (4, 302), (4, 200), (4, 302), (6, 200), (6, 302), (6, 200), (6, 302)], posts
            assert 'pihole_authentication_http_acceptance=true' in login.read_text()
            position('auth-release-accept', 'node-b')
    if scenario in ('success', 'evidence-failure'):
        assert not any(mode in ('auth-release-withdraw', 'auth-release-rollback', 'auth-helper-rollback') for mode, _, _ in phases)
    else:
        quiesce = position('auth-release-quiesce', 'node-b')
        withdraw = position('auth-release-withdraw', 'node-a')
        restore = position('auth-release-rollback', 'node-b')
        assert quiesce < withdraw < restore
        if scenario != 'restore-failure':
            assert restore < position('auth-helper-rollback', 'node-b') < position('auth-release-resume', 'node-b') < position('auth-release-resume', 'node-a')


def stage(work, baseline, node_a, environment):
    policy = module('auth_policy', 'authentication-deployment-policy.py')
    qualified_graph = policy.graph()
    scenario = os.environ.get('AUTH_OUTER_SCENARIO', 'success')
    assert scenario in ('success', 'login-failure', 'restore-failure', 'interrupt-helper', 'evidence-failure', 'dns-failure', 'publish-reply-failure', 'reconcile-failure', 'reordered-evidence')
    print(f'outer_fixture_begin={scenario}', flush=True)
    for suffix in ('53', '54', '55', '56'):
        run('/usr/sbin/ip', 'address', 'add', f'10.1.0.{suffix}/32', 'dev', 'lo')
        run('/usr/sbin/ip', '-6', 'address', 'add', f'fd36:5aa8:6971:1::{suffix}/128', 'dev', 'lo')
    bins = work / 'bin'
    bins.mkdir()
    for name in ('ssh', 'scp', 'sudo', 'systemctl', 'busctl', 'ip', 'dig', 'journalctl'):
        (bins / name).symlink_to(Path(__file__).resolve())
    Path('/usr/bin/systemctl').unlink()
    Path('/usr/bin/systemctl').symlink_to(Path(__file__).resolve())
    provider = Path('/usr/bin/doppler')
    assert not provider.exists()
    provider.symlink_to(Path(__file__).resolve())
    env = dict(environment, CADDY_AUTH_STAGE_FIXTURE=str(work),
               PATH=f'{bins}:/usr/sbin:/usr/bin:/sbin:/bin', AUTH_RELEASE_ROLE='node-b',
               CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND='/usr/bin/systemctl',
               CADDY_SERVING_HEALTH_BUSCTL_COMMAND=str(bins / 'busctl'), CADDY_SERVING_HEALTH_IP_COMMAND=str(bins / 'ip'),
               CADDY_SERVING_HEALTH_DNS_DIG_COMMAND=str(bins / 'dig'), CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=str(bins / 'journalctl'),
               CADDY_SERVING_HEALTH_OWNERSHIP_STABLE_SAMPLES='1', CADDY_SERVING_HEALTH_OWNERSHIP_ATTEMPTS='1',
               SSL_CERT_FILE=str(baseline / 'tls/fullchain.pem'), CURL_CA_BUNDLE=str(baseline / 'tls/fullchain.pem'),
               NO_PROXY='*', no_proxy='*')
    fixture = module('backend', 'authentication-resilience-integration.py')
    class Server(http.server.ThreadingHTTPServer):
        def handle_error(self, request, client_address):
            if isinstance(sys.exc_info()[1], (BrokenPipeError, ConnectionResetError)):
                return  # A Caddy health-check client may close before the empty redirect body.
            super().handle_error(request, client_address)
    backend = Server(('127.0.0.1', 8080), fixture.Backend)
    backend.daemon_threads = True
    threading.Thread(target=backend.serve_forever, daemon=True).start()
    processes, threads, errors = [], [], []
    stop = threading.Event()
    try:
        for role in ('node-a', 'node-b'):
            path, _ = projection(work, role)
            output = (work / f'{role}-caddy.log').open('wb')
            processes.append(subprocess.Popen(['caddy', 'run', '--adapter', 'caddyfile', '--config', str(path)], env=env, stdout=output, stderr=output))
            output.close()
        time.sleep(2)
        assert all(p.poll() is None for p in processes)
        def monitor():
            try:
                while not stop.is_set():
                    for role, suffix, host in [('node-a', '53', 'pihole0'), ('node-b', '54', 'pihole00')]:
                        node_env = work / f'{role}.env'
                        node_env.write_text(f'NODE_FQDN={host}.local.theama.co\nNODE_IPV4=10.1.0.{suffix}\nNODE_IPV6=fd36:5aa8:6971:1::{suffix}\n')
                        for kind in ('state', 'runtime'):
                            (work / f'{role}-{kind}').mkdir(mode=0o700, exist_ok=True)
                        monitor_env = dict(env, AUTH_RELEASE_ROLE=role,
                                           PIHOLE_WEB_HEALTH_ENVIRONMENT_FILE=str(node_env),
                                           PIHOLE_WEB_HEALTH_STATE_DIRECTORY=str(work / f'{role}-state'),
                                           PIHOLE_WEB_HEALTH_RUNTIME_DIRECTORY=str(work / f'{role}-runtime'))
                        helper = Path('/usr/local/libexec/check-pihole-web-health.sh') if role == 'node-b' else work / 'baseline-monitor'
                        result = subprocess.run(['/bin/bash', str(helper)], env=monitor_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
                        with (work / f'{role}.journal').open('a') as log:
                            for line in result.stdout.decode().splitlines():
                                log.write(json.dumps({'_SYSTEMD_UNIT': 'caddy-pihole-web-health.service', 'PRIORITY': '6' if result.returncode == 0 else '3', 'MESSAGE': line}) + '\n')
                    stop.wait(2)
            except Exception as error:
                errors.append(str(error))
        shutil.copyfile('/usr/local/libexec/check-pihole-web-health.sh', work / 'baseline-monitor')
        def transfer():
            handled = set()
            # Model the accepted lsyncd delay: publication renames staging into
            # the immutable revision before the next settled transfer batch.
            assert 'delay = 5,' in (ROOT / 'configs/lsyncd/caddy-node-a.lua').read_text()
            inventory, changed_at = (), time.monotonic()
            try:
                while not stop.is_set():
                    children = tuple(sorted(Path('/var/lib/caddy-sync/outbound').iterdir()))
                    if children != inventory:
                        inventory, changed_at = children, time.monotonic()
                    if time.monotonic() - changed_at < 5:
                        stop.wait(0.2)
                        continue
                    for child in children:
                        if child.name in handled or not (child / '.finalize-request').exists():
                            continue
                        handled.add(child.name)
                        incoming = Path('/var/lib/caddy-sync/incoming/node-a') / child.name
                        shutil.copytree(child, incoming)
                        run('chown', '-R', 'caddy-sync:caddy-sync', str(incoming))
                        run('runuser', '-u', 'caddy-sync', '--', 'env', 'XDG_DATA_HOME=/var/lib/caddy-sync/validation-data', 'XDG_CONFIG_HOME=/var/lib/caddy-sync/validation-config', '/bin/bash', '/usr/local/libexec/finalize-incoming-release-v2.sh', '--source-role', 'node-a', env=env)
                        reconciled = subprocess.run(['/bin/bash', '/usr/local/libexec/reconcile-release.sh'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                        (work / 'reconcile.status').write_text(str(reconciled.returncode) + '\n')
                        if reconciled.returncode != (1 if scenario == 'reconcile-failure' else 0):
                            raise RuntimeError('unexpected reconciler status')
                    stop.wait(0.2)
            except Exception as error:
                errors.append(str(error))
        for fn in (monitor, transfer):
            thread = threading.Thread(target=fn, daemon=True)
            thread.start()
            threads.append(thread)
        result = subprocess.run(['/bin/bash', str(ROOT / 'scripts/run-serving-health-deployment-outer.sh'), '--production-path-test'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=240)
        # Freeze background producers before hashing and copying their evidence.
        stop.set()
        for thread in threads:
            thread.join(timeout=20)
            assert not thread.is_alive(), 'external fixture producer did not stop'
        (work / 'outer.stdout').write_bytes(result.stdout)
        (work / 'outer.stderr').write_bytes(result.stderr)
        print(result.stdout.decode(), end='', flush=True)
        expected_status = 0 if scenario == 'success' else 1 if scenario in ('login-failure', 'dns-failure', 'publish-reply-failure', 'reconcile-failure', 'reordered-evidence') else 125
        if result.returncode != expected_status or errors:
            print(result.stderr.decode()[-4000:], file=sys.stderr)
            for root_line in result.stdout.decode().splitlines():
                if root_line.startswith('evidence_directory='):
                    failed_root = Path(root_line.split('=', 1)[1])
                    for status in sorted(failed_root.glob('*.status')):
                        if status.read_text().strip() != '0':
                            print(f'failed_phase={status.name} status={status.read_text().strip()}', file=sys.stderr)
                            for suffix in ('.stdout', '.stderr'):
                                output = status.with_suffix(suffix)
                                if output.exists():
                                    print(output.read_text()[-2000:], file=sys.stderr)
            raise AssertionError(f'outer status={result.returncode}; external errors={errors}; fixture={work}')
        root_line = next(line for line in result.stdout.decode().splitlines() if line.startswith('evidence_directory='))
        producer_root = Path(root_line.split('=', 1)[1])
        verify_calls(work / 'external-calls.jsonl', producer_root, scenario)
        calls = [json.loads(line) for line in (work / 'external-calls.jsonl').read_text().splitlines()]
        for call in calls:
            if call['command'] == 'ssh':
                parts = shlex.split(call['args'][1])
                if len(parts) >= 12 and parts[8] == 'sampler-start':
                    for pid_name in ('availability.pid', 'vip-address-monitor.pid'):
                        pid_file = Path(parts[11]) / pid_name
                        assert pid_file.is_file()
                        pid = pid_file.read_text().strip()
                        assert pid.isdecimal() and not Path('/proc', pid).exists(), ('observer residue', pid)
        for process in Path('/proc').iterdir():
            if process.name.isdecimal():
                try:
                    command_line = (process / 'cmdline').read_bytes().replace(b'\0', b' ')
                except OSError:
                    continue
                assert b'/usr/sbin/ip -o monitor address dev lo' not in command_line, 'kernel monitor residue'

        assert (node_a / 'etc/caddy/current').resolve() == baseline
        selected = Path('/etc/caddy/current').resolve()
        publications = list(Path('/var/lib/caddy-sync/outbound').iterdir())
        monitor_hash = hashlib.sha256(Path('/usr/local/libexec/check-pihole-web-health.sh').read_bytes()).hexdigest()
        if scenario in ('success', 'evidence-failure'):
            assert selected != baseline and [p.name for p in publications] == [selected.name]
            assert monitor_hash == '0aa489aaaeee7e32635a63e99bbfb5750dd591f5142969c5cdc0274613b985ab'
        elif scenario in ('login-failure', 'dns-failure', 'publish-reply-failure', 'reconcile-failure', 'reordered-evidence'):
            assert selected == baseline and not publications
            assert monitor_hash == '803f6d510302fe5ad3ee7b59eeff1f719a4b2ea091c6c908054b0eecffce5d51'
        else:
            assert selected == baseline and not publications
            assert monitor_hash == '0aa489aaaeee7e32635a63e99bbfb5750dd591f5142969c5cdc0274613b985ab'
        if expected_status == 125:
            assert b'authentication_node_b_accepted=' not in result.stdout
            assert b'baseline_restoration=complete' not in result.stdout
        # Keep independently observed state and actual producer status together.
        decision = {'scenario': scenario, 'expected_status': expected_status, 'observed_status': result.returncode,
                    'node_a_revision': (node_a / 'etc/caddy/current').resolve().name,
                    'node_b_revision': selected.name, 'node_b_monitor_sha256': monitor_hash,
                    'publications': [p.name for p in publications],
                    'observer_residue': 0,
                    'graph': qualified_graph,
                    'external_calls_sha256': hashlib.sha256((work / 'external-calls.jsonl').read_bytes()).hexdigest()}
        retained = os.environ.get('AUTH_OUTER_EVIDENCE_ROOT')
        if retained:
            target = Path(retained)
            assert target == Path('/evidence') and not target.is_symlink() and target.stat().st_mode & 0o777 == 0o700
            target = target / scenario
            target.mkdir(mode=0o700)
            root_line = next(line for line in result.stdout.decode().splitlines() if line.startswith('evidence_directory='))
            producer_root = Path(root_line.split('=', 1)[1])
            assert str(producer_root).startswith('/tmp/caddy-serving-health-outer-test.')
            for source_file in [work / 'external-calls.jsonl', work / 'outer.stdout', work / 'outer.stderr', *producer_root.iterdir()]:
                if source_file.is_file() and source_file.suffix in ('.jsonl', '.stdout', '.stderr', '.status', '.tsv'):
                    assert not source_file.is_symlink() and source_file.stat().st_size <= 1048576
                    shutil.copyfile(source_file, target / source_file.name)
                    (target / source_file.name).chmod(0o600)
            assert policy.graph() == qualified_graph, 'qualification inputs changed during execution'
            (target / 'outer.status').write_text(str(result.returncode) + '\n')
            (target / 'outer.status').chmod(0o600)
            (target / 'decision.json').write_text(json.dumps(decision, sort_keys=True) + '\n')
            (target / 'decision.json').chmod(0o600)
        if retained:
            policy.export_case(target, scenario)
        print('outer_decision=' + json.dumps(decision, sort_keys=True), flush=True)
        print(f'outer_{scenario}_independent_state_verified=true', flush=True)
    finally:
        stop.set()
        for thread in threads:
            thread.join(timeout=20)
        backend.shutdown()
        backend.server_close()
        for process in processes:
            process.terminate()
            process.wait(timeout=10)
        provider.unlink(missing_ok=True)
        for suffix in ('53', '54', '55', '56'):
            run('/usr/sbin/ip', 'address', 'del', f'10.1.0.{suffix}/32', 'dev', 'lo')
            run('/usr/sbin/ip', '-6', 'address', 'del', f'fd36:5aa8:6971:1::{suffix}/128', 'dev', 'lo')
        # Retain bounded fixture diagnostics in the disposable container output.
        if errors:
            print('fixture_errors=' + repr(errors), file=sys.stderr)


if __name__ == '__main__':
    if Path(sys.argv[0]).name in ('ssh', 'scp', 'sudo', 'systemctl', 'busctl', 'ip', 'dig', 'journalctl', 'doppler'):
        sys.exit(command())
    assert Path('/run/.containerenv').exists() and os.geteuid() == 0 and os.environ.get('CADDY_VALIDATION_CONTAINER') == '1'
    module('release', 'authentication-release-regression.py').main(stage)
