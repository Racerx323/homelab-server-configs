#!/usr/bin/env python3
"""Isolated real publisher/finalizer/reconciler and transaction release tests."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TX = ROOT / 'scripts/apply-serving-health-deployment.sh'


def run(*args, **kwargs):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    assert result.returncode == 0, str(args) + ': ' + result.stderr.decode()[-2000:]
    return result


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(outer_stage=None):
    assert Path('/run/.containerenv').exists() and os.geteuid() == 0
    assert os.environ.get('CADDY_VALIDATION_CONTAINER') == '1'
    os.environ['PATH'] = '/usr/sbin:/usr/bin:/sbin:/bin'
    with tempfile.TemporaryDirectory(prefix='caddy-serving-health-release-test.') as directory:
        work = Path(directory)
        for group in ('caddy-sync', 'caddy-tls'):
            if subprocess.run(['getent', 'group', group], stdout=subprocess.DEVNULL).returncode:
                run('groupadd', '--system', group)
        if subprocess.run(['id', 'caddy-sync'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
            run('useradd', '--system', '--gid', 'caddy-sync', '--groups', 'caddy-tls', '--no-create-home', 'caddy-sync')
        else:
            run('usermod', '-a', '-G', 'caddy-tls', 'caddy-sync')
        managed = [Path('/etc/caddy'), Path('/var/lib/caddy-sync'), Path('/etc/default/caddy-ha'), Path('/usr/bin/systemctl'), Path('/usr/local/libexec/check-pihole-web-health.sh')] + [
            Path('/usr/local/libexec') / name for name in ('publish-release-v2.sh', 'finalize-incoming-release-v2.sh', 'reconcile-release.sh')]
        # All replacements are inside this disposable, network-disabled container.
        saved = []
        try:
            for index, path in enumerate(managed):
                if path.exists():
                    backup = work / f'original-{index}'
                    shutil.move(str(path), backup)
                    saved.append((path, backup))
            Path('/usr/bin/systemctl').write_text('''#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\\n' "$*" >>"$AUTH_RELEASE_TEST_ROOT/systemctl.calls"
case "$1" in
 reload)
   if [[ -e "$AUTH_RELEASE_TEST_ROOT/fail-reload" ]]; then
     rm "$AUTH_RELEASE_TEST_ROOT/fail-reload"
     exit 1
   fi
   printf 'success\\n' >>"$AUTH_RELEASE_TEST_ROOT/reloads"
   ;;
 stop) printf 'inactive\\n' >"$AUTH_RELEASE_TEST_ROOT/$2.state" ;;
 start) printf 'active\\n' >"$AUTH_RELEASE_TEST_ROOT/$2.state" ;;
 is-enabled)
   unit=${!#}; state=enabled
   case "$unit" in caddy-api.service|lsyncd.service) state=masked ;; esac
   if [[ "${2:-}" != --quiet ]]; then printf '%s\\n' "$state"; fi
   ;;
 is-active)
   unit=${!#}; state=active
   [[ ! -f "$AUTH_RELEASE_TEST_ROOT/$unit.state" ]] || state=$(cat "$AUTH_RELEASE_TEST_ROOT/$unit.state")
   if [[ "${2:-}" != --quiet ]]; then printf '%s\\n' "$state"; fi
   [[ "$state" = active ]] || exit 3
   ;;
 *) exit 64 ;;
esac
''')
            Path('/usr/bin/systemctl').chmod(0o755)
            bus = work / 'busctl'
            bus.write_text("""#!/bin/bash
if [[ "$AUTH_RELEASE_ROLE" = node-a ]]; then echo 's "Master"'; else echo 's "Backup"'; fi
""")
            bus.chmod(0o755)
            addresses = work / 'ip'
            addresses.write_text('#!/bin/bash\nif [[ "$AUTH_RELEASE_ROLE" = node-a ]]; then\n'
                                 + 'echo "1: eth0 inet 10.1.0.55/22 scope global"\n'
                                 + 'echo "1: eth0 inet 10.1.0.56/22 scope global"\n'
                                 + 'echo "1: eth0 inet6 fd36:5aa8:6971:1::55/128 scope global"\n'
                                 + 'echo "1: eth0 inet6 fd36:5aa8:6971:1::56/128 scope global"\nfi\n')
            addresses.chmod(0o755)
            monitor = Path('/usr/local/libexec/check-pihole-web-health.sh')
            run('install', '-d', '-m', '0755', str(monitor.parent))
            monitor.write_bytes(run('git', '-c', f'safe.directory={ROOT.parent}', '-C', str(ROOT.parent),
                                    'cat-file', 'blob', 'aec92d5c0a99d7ee8154f32193a3e3d321af616c').stdout)
            monitor.chmod(0o755)
            assert digest(monitor) == '803f6d510302fe5ad3ee7b59eeff1f719a4b2ea091c6c908054b0eecffce5d51'
            source = work / 'payload/repositories/homelab-server-configs/Caddy'
            shutil.copytree(ROOT / 'configs/caddy', source / 'configs/caddy')
            (source / 'scripts').mkdir()
            (source / 'manifests').mkdir()
            for name in ('prepare-pihole-auth-release.sh', 'check-pihole-web-health.sh'):
                shutil.copyfile(ROOT / 'scripts' / name, source / 'scripts' / name)
            shutil.copyfile(ROOT / 'manifests/caddy-release-source.tsv', source / 'manifests/caddy-release-source.tsv')
            manifests = work / 'payload/manifests'
            manifests.mkdir()
            shutil.copyfile(ROOT / 'manifests/serving-health-quarantine-baseline.tsv', manifests / 'serving-health-quarantine-baseline.tsv')
            (manifests / 'serving-health-production.tsv').write_text(
                'homelab-server-configs\tCaddy/scripts/check-pihole-web-health.sh\t/usr/local/libexec/check-pihole-web-health.sh\t0755\t'
                + digest(source / 'scripts/check-pihole-web-health.sh') + '\tproduction-current\n')
            baseline = Path('/etc/caddy/releases/fixture-baseline')
            shutil.copytree(ROOT / 'configs/caddy', baseline)
            (baseline / 'tls').mkdir()
            run('openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                '-subj', '/CN=*.local.theama.co', '-addext', 'subjectAltName=DNS:pihole0.local.theama.co,DNS:pihole00.local.theama.co,DNS:pihole-admin.local.theama.co,DNS:proxy.local.theama.co', '-keyout', str(baseline / 'tls/privkey.pem'), '-out', str(baseline / 'tls/fullchain.pem'))
            (baseline / 'release-manifest.json').write_text(json.dumps({'revision': baseline.name, 'parent_revision': 'fixture-parent', 'source_node': 'node-a'}))
            files = sorted(p for p in baseline.rglob('*') if p.is_file())
            (baseline / 'manifest.sha256').write_text(''.join(f'{digest(p)}  ./{p.relative_to(baseline)}\n' for p in files))
            (manifests / 'current-live-state.tsv').write_text(''.join(
                f'1\t{role}\trelease\tfixture,revision={baseline.name},parent=fixture-parent,source=node-a,payload-manifest-sha256={digest(baseline / "manifest.sha256")}\tfixture\n'
                for role in ('node-a', 'node-b')))
            run('chown', '-R', 'root:caddy-tls', str(baseline))
            for p in baseline.rglob('*'):
                p.chmod(0o550 if p.is_dir() else 0o440)
            baseline.chmod(0o550)
            current = Path('/etc/caddy/current')
            current.symlink_to(baseline)
            node_a = work / 'node-a'
            (node_a / 'etc/caddy').mkdir(parents=True)
            (node_a / 'etc/caddy/current').symlink_to(baseline)
            for runtime_name in ('publish-release-v2.sh', 'finalize-incoming-release-v2.sh', 'reconcile-release.sh'):
                installed = Path('/usr/local/libexec') / runtime_name
                if runtime_name == 'reconcile-release.sh':
                    # Accepted runtime blob; this is not an archived transaction or test.
                    installed.write_bytes(run('git', '-c', f'safe.directory={ROOT.parent}', '-C', str(ROOT.parent),
                                              'cat-file', 'blob', 'bde0839cf64b5ae86be2027fe6ac8b82aeb14960').stdout)
                    assert digest(installed) == 'e777c2fe6932090d717b5ac9e50ef706d6b90c753293ad7eec4e396f2f6ea073'
                else:
                    shutil.copyfile(ROOT / 'scripts' / runtime_name, installed)
                installed.chmod(0o755)
                peer_installed = node_a / 'usr/local/libexec' / runtime_name
                peer_installed.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(installed, peer_installed)
                peer_installed.chmod(0o755)
            sync = Path('/var/lib/caddy-sync')
            for name in ('outbound', 'incoming', 'incoming/node-a', 'quarantine', 'validation-data', 'validation-config'):
                run('install', '-d', '-o', 'caddy-sync', '-g', 'caddy-sync', '-m', '0750', str(sync / name))
            environment = dict(os.environ, CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST='1',
                               CADDY_SERVING_HEALTH_TEST_EXPECTED_SYNC_METADATA='caddy-sync:caddy-sync:750',
                               CADDY_SERVING_HEALTH_PUBLISHER_COMMAND=str(ROOT / 'scripts/publish-release-v2.sh'),
                               AUTH_RELEASE_TEST_ROOT=str(work))
            Path('/etc/default/caddy-ha').write_text('NODE_FQDN=pihole00.local.theama.co\nNODE_IPV4=10.1.0.54\nNODE_IPV6=fd36:5aa8:6971:1::54\n')
            if outer_stage is not None:
                outer_stage(work, baseline, node_a, environment)
                return
            for scenario in ('success', 'prepared-tamper', 'publish-empty-failure', 'publish-reply-failure', 'reload-failure', 'rollback-reload-failure', 'retain-success'):
                for state in work.glob('*.state'):
                    state.unlink()
                evidence = {}
                for role in ('node-a', 'node-b'):
                    evidence[role] = work / f'{scenario}-{role}'
                    evidence[role].mkdir(mode=0o700)
                producer = str(ROOT / 'scripts/publish-release-v2.sh')
                if scenario == 'publish-empty-failure':
                    producer = '/usr/bin/false'
                elif scenario == 'publish-reply-failure':
                    wrapper = work / 'publisher-failed-reply.sh'
                    wrapper.write_text('#!/usr/bin/env bash\nset -Eeuo pipefail\n/bin/bash '
                                       + shlex.quote(producer) + ' "$@"\nexit 7\n')
                    wrapper.chmod(0o755)
                    producer = str(wrapper)
                def transaction(mode, role, *extra, expected=0):
                    env = dict(environment, CADDY_SERVING_HEALTH_TARGET_ROOT=str(node_a) if role == 'node-a' else '', CADDY_SERVING_HEALTH_PUBLISHER_COMMAND=producer,
                               CADDY_SERVING_HEALTH_OUTGOING_ROOT=str(sync / 'outbound') if role == 'node-a' else str(sync / 'node-b-outbound'),
                               CADDY_SERVING_HEALTH_BUSCTL_COMMAND=str(bus), CADDY_SERVING_HEALTH_IP_COMMAND=str(addresses),
                               CADDY_SERVING_HEALTH_OWNERSHIP_STABLE_SAMPLES='1', CADDY_SERVING_HEALTH_OWNERSHIP_ATTEMPTS='1',
                               AUTH_RELEASE_ROLE=role)
                    result = subprocess.run(['/bin/bash', str(TX), mode, role, str(work / 'payload'), str(evidence[role]), *extra],
                                            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=70)
                    if result.returncode != expected:
                        raise AssertionError(f'{scenario}/{mode}: expected {expected}, got {result.returncode}; ' + result.stderr.decode()[-2000:])
                    return result
                transaction('auth-release-prepare', 'node-a')
                if scenario == 'prepared-tamper':
                    candidate_file = evidence['node-a'] / 'auth-release-source/Caddyfile'
                    candidate_file.write_text(candidate_file.read_text() + '\n# out-of-scope change\n')
                    transaction('auth-release-publish', 'node-a', expected=1)
                    assert not list((sync / 'outbound').iterdir())
                    assert not (evidence['node-a'] / 'auth-publish.intent').exists()
                    print('prepared_tamper_rejected_before_publication=true', flush=True)
                    continue
                if scenario == 'publish-empty-failure':
                    (sync / 'outbound').rmdir()
                    transaction('auth-release-publish', 'node-a', expected=1)
                    result = transaction('auth-release-discover', 'node-a')
                    assert b'authentication_release_publication=absent' in result.stdout
                    assert current.resolve() == baseline
                    run('install', '-d', '-o', 'caddy-sync', '-g', 'caddy-sync', '-m', '0750', str(sync / 'outbound'))
                    print('empty_publication_failure_proved_without_rollback=true', flush=True)
                    continue
                if scenario == 'publish-reply-failure':
                    transaction('auth-release-publish', 'node-a', expected=7)
                    result = transaction('auth-release-discover', 'node-a')
                else:
                    result = transaction('auth-release-publish', 'node-a')
                revision = result.stdout.decode().strip().split('authentication_release_revision=')[-1]
                published = sync / 'outbound' / revision
                assert published.is_dir() and (published / '.finalize-request').is_file()
                assert current.resolve() == baseline
                transaction('record-target', 'node-b', revision)
                # Model only lsyncd's transfer; execute the actual receiver and reconciler.
                incoming = sync / 'incoming/node-a' / revision
                shutil.copytree(published, incoming)
                run('chown', '-R', 'caddy-sync:caddy-sync', str(incoming))
                run('runuser', '-u', 'caddy-sync', '--', 'env', 'XDG_DATA_HOME=/var/lib/caddy-sync/validation-data', 'XDG_CONFIG_HOME=/var/lib/caddy-sync/validation-config', '/bin/bash', str(ROOT / 'scripts/finalize-incoming-release-v2.sh'), '--source-role', 'node-a', env=environment)
                if scenario == 'reload-failure':
                    (work / 'fail-reload').touch()
                reconciled = subprocess.run(['/bin/bash', '/usr/local/libexec/reconcile-release.sh'], env=environment,
                                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45)
                assert reconciled.returncode == (1 if scenario == 'reload-failure' else 0), reconciled.stderr.decode()[-2000:]
                if scenario != 'reload-failure':
                    transaction('auth-release-wait', 'node-b')
                    assert current.resolve().name == revision
                else:
                    assert current.resolve() == baseline
                if scenario == 'retain-success':
                    transaction('auth-helper-preflight', 'node-b')
                    transaction('auth-helper-install', 'node-b')
                    calls_before = (work / 'systemctl.calls').read_text()
                    transaction('auth-release-accept', 'node-b')
                    transaction('auth-release-accept', 'node-a')
                    assert current.resolve().name == revision
                    assert (node_a / 'etc/caddy/current').resolve() == baseline
                    assert published.is_dir() and not incoming.exists()
                    assert digest(monitor) == digest(source / 'scripts/check-pihole-web-health.sh')
                    calls_after = (work / 'systemctl.calls').read_text()[len(calls_before):]
                    assert not any(line.startswith(('reload ', 'stop ', 'start ')) for line in calls_after.splitlines())
                    # Each required application service must reject acceptance when inactive.
                    for unit in ('caddy.service', 'lighttpd.service', 'pihole-FTL.service', 'unbound.service'):
                        state = work / f'{unit}.state'
                        state.write_text('inactive\n')
                        transaction('auth-release-accept', 'node-b', expected=1)
                        assert current.resolve().name == revision and published.is_dir()
                        state.unlink()
                    unexpected = sync / 'incoming/node-b'
                    run('install', '-d', '-o', 'caddy-sync', '-g', 'caddy-sync', '-m', '0750', str(unexpected))
                    transaction('auth-release-accept', 'node-b')
                    (unexpected / 'unexpected').touch()
                    transaction('auth-release-accept', 'node-b', expected=1)
                    assert current.resolve().name == revision and published.is_dir()
                    print('accepted_node_b_candidate_and_node_a_publication_retained=true', flush=True)
                    continue
                transaction('auth-release-quiesce', 'node-b')
                transaction('auth-release-withdraw', 'node-a')
                if scenario == 'rollback-reload-failure':
                    (work / 'fail-reload').touch()
                    transaction('auth-release-rollback', 'node-b', expected=125)
                    assert (baseline.parent / revision).exists()
                transaction('auth-release-rollback', 'node-b')
                assert current.resolve() == baseline
                assert not published.exists() and not incoming.exists() and not (baseline.parent / revision).exists()
                assert (node_a / 'etc/caddy/current').resolve() == baseline
                print(f'{scenario}_publication_reconciliation_rollback=true', flush=True)
        finally:
            for path in managed:
                if path.is_dir() and not path.is_symlink():
                    shutil.rmtree(path)
                elif path.exists() or path.is_symlink():
                    path.unlink()
            for path, backup in saved:
                shutil.move(str(backup), path)


if __name__ == '__main__':
    main()
