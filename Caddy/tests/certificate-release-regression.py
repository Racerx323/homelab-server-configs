#!/usr/bin/env python3
"""Execute the real certificate outer/transaction path in a disposable container.

The transport substitute switches node filesystems and serializes OpenSSH's
remote shell command. Publication causally transfers a real publisher payload;
the real finalizer, reconciler, OpenSSL and expiry checker process that payload.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import shlex
import re

REPO = Path(__file__).resolve().parents[2]
SCENARIOS = ['success', 'namespace-absent', 'worker-failure', 'primary-worker-failure',
             'readback-failure', 'standby-readback-failure', 'reload-failure', 'rollback-failure', 'ownership-transition', 'stale-baseline', 'baseline-extra',
             'namespace-symlink', 'namespace-mode', 'namespace-owner',
             'namespace-nonempty', 'namespace-file']
GRAPH_FILES = ['Caddy/scripts/apply-serving-health-deployment.sh',
               'Caddy/scripts/run-serving-health-deployment-outer.sh',
               'Caddy/scripts/publish-release-v2.sh',
               'Caddy/scripts/check-certificate-expiry.sh',
               'Caddy/scripts/finalize-incoming-release-v2.sh',
               'Caddy/scripts/reconcile-release-v2.sh',
               'Caddy/manifests/certificate-release-inputs.tsv',
               'Caddy/manifests/serving-health-operation.yaml',
               'Caddy/manifests/deployable-successor-coverage.tsv',
               'Caddy/tests/certificate-release-regression.py',
               'Caddy/tests/certificate-release-regression.sh',
               'Caddy/tests/run-focused-container.sh', 'Caddy/tests/focused-validation.yaml', 'Caddy/tests/deployable-successor-policy.sh']
GRAPH_FILES += ['Caddy/manifests/current-live-state.tsv', 'Caddy/manifests/serving-health-production.tsv', 'Caddy/systemd/caddy-cert-expiry.service', 'Caddy/systemd/caddy-sync-reconcile.service']
GRAPH_FILES += sorted(str(p.relative_to(REPO)) for p in (REPO/'Caddy/configs/caddy').rglob('*') if p.is_file())
VIEWS = {"caddy": Path("/etc/caddy"), "sync": Path("/var/lib/caddy-sync"),
         "libexec": Path("/usr/local/libexec")}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def health_response(release):
    """Read the response from the selected production fragment, not the probe."""
    text = (release/'conf.d/10-pihole-admin.caddy').read_text()
    matches = re.findall(r'@caddy_health\s+path\s+/healthz\s+handle\s+@caddy_health\s*\{\s*respond\s+(\d{3})\s*\}', text)
    assert len(matches) == 1, 'Ambiguous or unsupported health endpoint contract'
    return matches[0]


def require_container():
    assert os.geteuid() == 0 and os.environ.get("CADDY_VALIDATION_CONTAINER") == "1"
    assert Path("/run/.containerenv").is_file()


def fixture_root():
    return Path(os.environ["CERT_FIXTURE_ROOT"])


def active_role():
    return (fixture_root() / "active").read_text().strip()


def state(role=None):
    return json.loads((fixture_root() / "nodes" / (role or active_role()) / "state.json").read_text())


def save(value, role=None):
    (fixture_root() / "nodes" / (role or active_role()) / "state.json").write_text(json.dumps(value))


def event(text):
    value = state()
    value["journal"].append(text)
    save(value)


def move_tree(source, destination):
    # Evidence is a bind mount, while each simulated node runs on the container
    # filesystem. Preserve uid/gid and symlinks when crossing that boundary.
    run(['cp', '-a', str(source), str(destination)])
    shutil.rmtree(source)


def switch(role):
    root = fixture_root()
    previous = (root / "active").read_text().strip() if (root / "active").exists() else ""
    if previous == role:
        return
    for name, path in VIEWS.items():
        if path.exists():
            move_tree(path, root / "nodes" / previous / name)
        path.parent.mkdir(parents=True, exist_ok=True)
        move_tree(root / "nodes" / role / name, path)
    (root / "active").write_text(role)
    suffix = "0" if role == "node-a" else "00"
    ip = "53" if role == "node-a" else "54"
    Path("/etc/default/caddy-ha").write_text(
        f"NODE_FQDN=pihole{suffix}.local.theama.co\nNODE_IPV4=10.1.0.{ip}\n"
        f"NODE_IPV6=fd36:5aa8:6971:1::{ip}\n")


def transfer_publication():
    assert active_role() == "node-a"
    children = [p for p in Path('/var/lib/caddy-sync/outbound').iterdir() if p.name != 'baseline']
    if not children or not state()["lsyncd"]:
        return
    assert len(children) == 1
    revision = children[0].name
    transport = fixture_root() / 'transport'
    shutil.copytree(children[0], transport)
    switch('node-b')
    run(['install', '-d', '-o', 'caddy-sync', '-g', 'caddy-sync', '-m', '0750', '/var/lib/caddy-sync/incoming/node-a'])
    destination = Path('/var/lib/caddy-sync/incoming/node-a') / revision
    shutil.copytree(transport, destination)
    run(['chown', '-R', 'caddy-sync:caddy-sync', str(destination)])
    with (fixture_root() / 'transport.log').open('a') as output:
        run(['/usr/sbin/runuser', '-u', 'caddy-sync', '--', '/usr/local/libexec/finalize-incoming-release-v2.sh', '--source-role', 'node-a'], stdout=output, stderr=output)
        run(['/bin/bash', '/usr/local/libexec/reconcile-release.sh'], stdout=output, stderr=output)
    shutil.rmtree(transport)
    switch('node-a')


def adapter(name, args):
    require_container()
    if name == 'ssh':
        options = []
        while args and args[0] == '-o':
            options.append(args[1])
            args = args[2:]
        assert options == ['BatchMode=yes', 'ConnectTimeout=10', 'ServerAliveInterval=5', 'ServerAliveCountMax=3']
        role = 'node-a' if args[0].endswith('.53') else 'node-b'
        switch(role)
        body = sys.stdin.buffer.read()
        command = ' '.join(args[1:])
        with (fixture_root() / 'ssh.jsonl').open('a') as log:
            log.write(json.dumps({'role': role, 'command': command, 'options': options,
                                  'stdin_sha256': hashlib.sha256(body).hexdigest()}) + '\n')
        result = subprocess.run(['/bin/bash', '-c', command], input=body, stdout=subprocess.PIPE)
        observed = state()
        corrupt = (((os.environ.get('CERT_CASE') == 'readback-failure' and role == 'node-a') or (os.environ.get('CERT_CASE') == 'standby-readback-failure' and role == 'node-b'))
                   and observed['checker_runs'] == 1 and not observed.get('readback_faulted')
                   and b'file=%s bytes=%s' in body)
        if corrupt:
            observed['readback_faulted'] = True
            save(observed)
            sys.stdout.buffer.write(b'corrupt readback\n')
        else:
            sys.stdout.buffer.write(result.stdout)
        if ' certificate-publish ' in command:
            transfer_publication()
        return result.returncode
    if name == 'scp':
        source, destination = args[-2:]
        shutil.copy2(source, destination.split(':', 1)[1])
        return 0
    if name == 'curl':
        assert '--resolve' in args and '--fail' in args and '-k' not in args
        endpoint = args[args.index('--resolve') + 1]
        role = 'node-b' if endpoint.startswith('pihole00.') else 'node-a'
        root = fixture_root()
        active = (root/'active').read_text().strip() if (root/'active').exists() else ''
        view = Path('/etc/caddy') if active == role else root/'nodes'/role/'caddy'
        selected = Path(os.readlink(view/'current')).name
        assert (view/'releases'/selected/'Caddyfile').is_file()
        assert (view/'releases'/selected/'tls/fullchain.pem').is_file()
        assert args[-1].endswith('/healthz')
        print(health_response(view/'releases'/selected))
        return 0
    value = state()
    role = active_role()
    if name == 'systemctl':
        event('systemctl ' + ' '.join(args))
        value = state()
        action = args[0]
        unit = next((a for a in args[1:] if a.endswith(('.service', '.path', '.timer'))), '')
        if action == 'is-active':
            for item in args[1:]:
                if item == 'caddy-lsyncd.service' and not value['lsyncd']:
                    return 3
            return 0
        if action == 'show':
            if unit == 'caddy-cert-expiry.service':
                print('Result=' + value['cert_result'])
                print('ExecMainStatus=' + str(value['cert_status']))
            elif 'KillMode' in args:
                print('control-group')
            elif 'MainPID' in args:
                print(100 if value['lsyncd'] else 0)
            return 0
        if unit == 'caddy-lsyncd.service':
            value['lsyncd'] = action == 'start'
            save(value)
            return 0
        if action == 'start' and unit == 'caddy-cert-expiry.service':
            result = subprocess.run(['/bin/bash', '/usr/local/libexec/check-certificate-expiry.sh'], capture_output=True, text=True)
            fail = (os.environ.get('CERT_CASE') in ['worker-failure', 'rollback-failure'] and role == 'node-b') or (os.environ.get('CERT_CASE') == 'primary-worker-failure' and role == 'node-a')
            rc = 1 if fail else result.returncode
            value['cert_status'] = rc
            value['cert_result'] = 'exit-code' if rc else 'success'
            value['checker_runs'] += 1
            value['journal'].append('certificate-worker exit=' + str(rc))
            save(value)
            return rc
        if action == 'start' and unit == 'caddy-sync-reconcile.service':
            return subprocess.run(['/bin/bash', '/usr/local/libexec/reconcile-release.sh']).returncode
        if action == 'reload' and unit == 'caddy.service':
            value['reloads'] += 1
            if os.environ.get('CERT_CASE') == 'ownership-transition' and role == 'node-a' and value['reloads'] == 1:
                value['journal'].extend(['Entering BACKUP STATE', 'Entering MASTER STATE'])
            save(value)
            if (os.environ.get('CERT_CASE') == 'reload-failure' and role == 'node-a' and value['reloads'] == 1) or (os.environ.get('CERT_CASE') == 'rollback-failure' and role == 'node-b' and value['reloads'] == 2):
                return 1
            return 0
        if action == 'stop' and unit == 'caddy-sync-reconcile.service':
            return 0
        raise AssertionError(args)
    if name == 'journalctl':
        if '--show-cursor' in args:
            print('-- cursor: ' + str(len(value['journal'])))
        else:
            cursor = int(args[args.index('--after-cursor') + 1])
            print('\n'.join(value['journal'][cursor:]))
        return 0
    if name == 'busctl':
        print('(us) 2 "Master"' if role == 'node-a' else '(us) 1 "Backup"')
        return 0
    if name == 'ip':
        if role == 'node-a':
            for cidr in ['10.1.0.55/22', '10.1.0.56/22', 'fd36:5aa8:6971:1::55/128', 'fd36:5aa8:6971:1::56/128']:
                print('1: eth0 inet ' + cidr + ' scope global')
        return 0
    raise AssertionError(name)


def manifest(path, revision, parent):
    (path / 'release-manifest.json').write_text(json.dumps(dict(revision=revision, parent_revision=parent, source_node='node-a', created_at='fixture')))
    files = sorted(p for p in path.rglob('*') if p.is_file() and p.name != 'manifest.sha256')
    (path / 'manifest.sha256').write_text(''.join(digest(p) + '  ./' + str(p.relative_to(path)) + '\n' for p in files))


def setup(root):
    os.environ['CERT_FIXTURE_ROOT'] = str(root)
    run(['groupadd', '-f', 'caddy-sync'])
    run(['groupadd', '-f', 'caddy-tls'])
    if subprocess.run(['id', 'caddy-sync'], capture_output=True).returncode:
        run(['useradd', '--system', '--gid', 'caddy-sync', 'caddy-sync'])
    run(['install', '-d', '-o', 'caddy-sync', '-g', 'caddy-sync', '/home/caddy-sync'])
    for path in VIEWS.values():
        if path.exists():
            shutil.rmtree(path)
    bin_dir = root / 'bin'
    bin_dir.mkdir()
    for name in ['ssh', 'scp', 'systemctl', 'journalctl', 'busctl', 'ip', 'curl']:
        script = bin_dir / name
        script.write_text('#!/bin/bash\nexec /usr/bin/python3 ' + str(Path(__file__).resolve()) + ' --adapter ' + name + ' "$@"\n')
        script.chmod(0o755)
    # The real reconciler dispatches its runtime service command by PATH.
    shutil.copy2(bin_dir / 'systemctl', '/usr/bin/systemctl')
    Path('/usr/bin/sudo').write_text('#!/bin/bash\n[[ "${1:-}" != -n ]] || shift\nexec "$@"\n')
    Path('/usr/bin/sudo').chmod(0o755)
    cert = root / 'cert'
    cert.mkdir()
    run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '365', '-subj', '/CN=*.local.theama.co', '-keyout', str(cert / 'privkey.pem'), '-out', str(cert / 'fullchain.pem')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for name in ['leaf.pem', 'intermediates.pem']:
        shutil.copy2(cert / 'fullchain.pem', cert / name)
    (cert / 'certificate-manifest.json').write_text('{}\n')
    hashes = {}
    for role in ['node-a', 'node-b']:
        node = root / 'nodes' / role
        releases = node / 'caddy/releases'
        releases.mkdir(parents=True)
        for revision in ['tls-source', 'baseline']:
            release = releases / revision
            shutil.copytree(REPO / 'Caddy/configs/caddy', release)
            shutil.copytree(cert, release / 'tls')
            if revision == 'baseline':
                for name in ['leaf.pem', 'intermediates.pem', 'certificate-manifest.json']:
                    (release / 'tls' / name).unlink()
            manifest(release, revision, '' if revision == 'tls-source' else 'tls-source')
            hashes[revision] = digest(release / 'manifest.sha256')
        (node / 'caddy/current').symlink_to('/etc/caddy/releases/baseline')
        for namespace in ['outbound', 'incoming/node-a', 'quarantine']:
            (node / 'sync' / namespace).mkdir(parents=True, exist_ok=True)
        run(['chown', '-R', 'caddy-sync:caddy-sync', str(node / 'sync')])
        for directory in [node/'sync', *[p for p in (node/'sync').rglob('*') if p.is_dir()]]:
            directory.chmod(0o750)
        if role == 'node-a':
            shutil.copytree(releases / 'baseline', node / 'sync/outbound/baseline')
        (node / 'libexec').mkdir()
        (node / 'libexec').chmod(0o755)
        for source, target in [('check-certificate-expiry.sh', 'check-certificate-expiry.sh'), ('finalize-incoming-release-v2.sh', 'finalize-incoming-release-v2.sh'), ('reconcile-release-v2.sh', 'reconcile-release.sh')]:
            shutil.copy2(REPO / 'Caddy/scripts' / source, node / 'libexec' / target)
        # A distinct baseline publisher makes installation and restoration observable.
        baseline_publisher = node / 'libexec/publish-release-v2.sh'
        baseline_publisher.write_text('#!/bin/bash\nexit 73\n')
        baseline_publisher.chmod(0o755)
        (node / 'state.json').write_text(json.dumps(dict(lsyncd=True, cert_result='exit-code', cert_status=1, checker_runs=0, reloads=0, journal=[])))
    recipe = root / 'inputs.tsv'
    values = dict(baseline_revision='baseline', baseline_manifest_sha256=hashes['baseline'], tls_source_revision='tls-source', tls_source_manifest_sha256=hashes['tls-source'], publisher_baseline_sha256=digest(root / 'nodes/node-a/libexec/publish-release-v2.sh'), publisher_candidate_sha256=digest(REPO / 'Caddy/scripts/publish-release-v2.sh'), checker_sha256=digest(REPO / 'Caddy/scripts/check-certificate-expiry.sh'))
    values.update(finalizer_sha256=digest(REPO/'Caddy/scripts/finalize-incoming-release-v2.sh'), reconciler_sha256=digest(REPO/'Caddy/scripts/reconcile-release-v2.sh'), checker_unit_sha256=digest(REPO/'Caddy/systemd/caddy-cert-expiry.service'), reconcile_unit_sha256=digest(REPO/'Caddy/systemd/caddy-sync-reconcile.service'))
    for unit in ['caddy-cert-expiry.service', 'caddy-sync-reconcile.service']:
        shutil.copy2(REPO/'Caddy/systemd'/unit, Path('/etc/systemd/system')/unit)
    recipe.write_text('key\tvalue\n' + ''.join(k+'\t'+v+'\n' for k,v in values.items()))
    env = os.environ.copy()
    env.update(CADDY_CERTIFICATE_TEST_SCOPE='1', CADDY_CERTIFICATE_FIXTURE_EXECUTE='1', CADDY_CERTIFICATE_TEST_INPUTS=str(recipe), CADDY_CERTIFICATE_TEST_INPUTS_SHA256=digest(recipe), CADDY_CERTIFICATE_TEST_SSH=str(bin_dir/'ssh'), CADDY_CERTIFICATE_TEST_SCP=str(bin_dir/'scp'), CADDY_SERVING_HEALTH_PRODUCTION_PATH_TEST='1', CADDY_SERVING_HEALTH_TEST_EXPECTED_SYNC_METADATA='caddy-sync:caddy-sync:750', CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND=str(bin_dir/'systemctl'), CADDY_SERVING_HEALTH_JOURNALCTL_COMMAND=str(bin_dir/'journalctl'), CADDY_SERVING_HEALTH_BUSCTL_COMMAND=str(bin_dir/'busctl'), CADDY_SERVING_HEALTH_IP_COMMAND=str(bin_dir/'ip'), CADDY_SERVING_HEALTH_CURL_COMMAND=str(bin_dir/'curl'), CADDY_SERVING_HEALTH_SLEEP_COMMAND='/bin/true', CADDY_SERVING_HEALTH_OWNERSHIP_SAMPLE_DELAY='0')
    return env


def suite():
    definition_check()
    require_container()
    os.environ["PATH"] = "/usr/sbin:/usr/bin:/sbin:/bin"
    evidence = Path(os.environ.get('CADDY_PRODUCTION_PATH_EVIDENCE_ROOT', str(Path(os.environ.get('CADDY_FOCUSED_EVIDENCE_ROOT', '/evidence')) / 'certificate-release')))
    evidence.mkdir(exist_ok=True, mode=0o700)
    qualification_graph = {name: digest(REPO/name) for name in GRAPH_FILES}
    for scenario in SCENARIOS:
        root = evidence / scenario
        root.mkdir(mode=0o700)
        env = setup(root)
        env['CERT_CASE'] = scenario
        namespace = root / 'nodes/node-b/sync/outbound'
        if scenario == 'namespace-absent':
            namespace.rmdir()
        elif scenario == 'namespace-symlink':
            namespace.rmdir()
            (root / 'foreign-empty').mkdir()
            namespace.symlink_to(root / 'foreign-empty', target_is_directory=True)
        elif scenario == 'namespace-mode':
            namespace.chmod(0o777)
        elif scenario == 'namespace-owner':
            run(['chown', 'root:root', str(namespace)])
        elif scenario == 'namespace-nonempty':
            (namespace / 'unexpected').write_text('fixture')
        elif scenario == 'namespace-file':
            namespace.rmdir()
            namespace.write_text('fixture')
        elif scenario == 'stale-baseline':
            (root / 'nodes/node-b/caddy/releases/baseline/Caddyfile').write_text('unexpected drift')
        elif scenario == 'baseline-extra':
            (root / 'nodes/node-b/caddy/releases/baseline/unmanifested').write_text('unexpected file')
        accepted_case = scenario in ['success', 'namespace-absent']
        preflight_rejection = scenario in ['stale-baseline', 'baseline-extra', 'namespace-symlink', 'namespace-mode', 'namespace-owner', 'namespace-nonempty', 'namespace-file']
        before_runners = set(Path('/tmp').glob('caddy-serving-health-outer-test.*'))
        with (root/'outer.stdout').open('w') as out, (root/'outer.stderr').open('w') as err:
            result = subprocess.run(['/bin/bash', str(REPO/'Caddy/scripts/run-serving-health-deployment-outer.sh'), '--production-path-test'], env=env, stdout=out, stderr=err)
        for runner in set(Path('/tmp').glob('caddy-serving-health-outer-test.*')) - before_runners:
            shutil.copytree(runner, root/'runner-evidence')
        expected_status = 0 if accepted_case else (125 if scenario == 'rollback-failure' else 1)
        if result.returncode != expected_status:
            print('Certificate scenario failed:', scenario, 'status', result.returncode, 'evidence', root, file=sys.stderr)
            raise SystemExit(1)
        observations = {}
        for role in ['node-a', 'node-b']:
            switch(role)
            selected = os.readlink('/etc/caddy/current')
            observed = state()
            assert observed['lsyncd'] == (not (scenario == 'rollback-failure' and role == 'node-a'))
            observations[role] = {'selection': selected, 'publisher_sha256': digest('/usr/local/libexec/publish-release-v2.sh'), **observed}
            if accepted_case:
                assert selected != '/etc/caddy/releases/baseline'
                assert Path('/etc/caddy/current/tls/leaf.pem').is_file()
                assert observed['cert_status'] == 0 and observed['checker_runs'] == 1
                assert digest('/usr/local/libexec/publish-release-v2.sh') == digest(REPO/'Caddy/scripts/publish-release-v2.sh')
            else:
                assert selected == '/etc/caddy/releases/baseline'
                if scenario == 'rollback-failure' and role == 'node-b':
                    assert digest('/usr/local/libexec/publish-release-v2.sh') == digest(REPO/'Caddy/scripts/publish-release-v2.sh')
                else:
                    assert Path('/usr/local/libexec/publish-release-v2.sh').read_text().endswith('exit 73\n')
        calls = [json.loads(line) for line in (root/'ssh.jsonl').read_text().splitlines()]
        transaction_calls = [c for c in calls if c['stdin_sha256'] == digest(REPO/'Caddy/scripts/apply-serving-health-deployment.sh')]
        assert transaction_calls
        commands = [c['command'] for c in transaction_calls]
        b_accept = next((i for i,c in enumerate(commands) if ' certificate-accept node-b ' in c), None)
        if accepted_case:
            a_promote = next(i for i,c in enumerate(commands) if ' certificate-promote node-a ' in c)
            a_install = next(i for i,c in enumerate(commands) if ' certificate-install-publisher node-a ' in c)
            assert b_accept < a_install < a_promote
        elif preflight_rejection:
            assert not any(' certificate-install-publisher ' in c or ' certificate-publish ' in c for c in commands)
            assert all(item['checker_runs'] == 0 and item['reloads'] == 0 for item in observations.values())
        else:
            if scenario in ['worker-failure', 'standby-readback-failure']:
                assert not any(' certificate-promote node-a ' in c for c in commands)
            contain = next(i for i,c in enumerate(commands) if ' certificate-contain-publication ' in c)
            restore_a = next(i for i,c in enumerate(commands) if ' certificate-rollback node-a ' in c)
            restore_b = next(i for i,c in enumerate(commands) if ' certificate-rollback node-b ' in c)
            assert contain < restore_a < restore_b
        for call in calls:
            for token in shlex.split(call['command']):
                if token.startswith('/tmp/caddy-serving-health-') and scenario != 'rollback-failure':
                    assert not Path(token).exists(), token
        (root / 'observations.json').write_text(json.dumps({'scenario': scenario, 'status': result.returncode, 'nodes': observations, 'transaction_commands': transaction_calls, 'residue_absent': scenario != 'rollback-failure'}, indent=2)+'\n')
        print('certificate_release_scenario=' + scenario + ':passed', flush=True)
        # Retain both actual node filesystems before leaving this scenario.
        last_role = active_role()
        for name, path in VIEWS.items():
            move_tree(path, root / 'nodes' / last_role / name)
        (root / 'active').unlink()
        run(['chown', '-R', 'root:root', str(root)])
        for item in root.rglob('*'):
            if not item.is_symlink():
                item.chmod(0o700 if item.is_dir() else 0o600)
    for directory in ['decisions', 'raw']:
        (evidence/directory).mkdir(mode=0o700)
    preflight_runner = evidence/'success/runner-evidence'
    preflight = {name: int((preflight_runner/(name+'.status')).read_text()) for name in [
        'node-a-upload-prepare', 'node-b-upload-prepare', 'node-a-upload-accept',
        'node-b-upload-accept', 'certificate-preflight-a', 'certificate-preflight-b']}
    assert all(status == 0 for status in preflight.values())
    preflight['payload_sha256'] = digest(preflight_runner/'serving-health-payload.tar')
    (evidence/'raw/certificate-preflight.json').write_text(json.dumps(preflight, indent=2)+'\n')
    for line in (REPO/'Caddy/manifests/deployable-successor-coverage.tsv').read_text().splitlines()[1:]:
        name, phase, entrypoint, expectation, decision_name, raw_name = line.split('\t')
        assert name.startswith('certificate-')
        if name == 'certificate-preflight':
            status, expected, observed_label = 0, 'prepared-and-preflighted', 'prepared-and-preflighted'
        else:
            scenario = name.removeprefix('certificate-')
            source = evidence/scenario/'observations.json'
            shutil.copyfile(source, evidence/raw_name)
            record = json.loads(source.read_text())
            status = record['status']
            expected = 'accepted' if expectation == 'accept' else 'rejected'
            selected = [node['selection'] for node in record['nodes'].values()]
            observed_label = 'baseline' if all(value == '/etc/caddy/releases/baseline' for value in selected) else 'accepted'
        (evidence/decision_name).write_text('scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n'+
            '\t'.join([name, expectation, str(status), expected, observed_label, digest(evidence/raw_name)])+'\n')
        (evidence/decision_name).chmod(0o600)
        (evidence/raw_name).chmod(0o600)
    assert qualification_graph == {name: digest(REPO/name) for name in GRAPH_FILES}, 'source changed during qualification'
    (evidence / 'qualification-summary.json').write_text(json.dumps({
        'source_graph': qualification_graph,
        'scenarios': {name: {'observations_sha256': digest(evidence/name/'observations.json'),
                             'ssh_sha256': digest(evidence/name/'ssh.jsonl')} for name in SCENARIOS}
    }, indent=2)+'\n')
    print('certificate_release_regression_complete=true')


def definition_check():
    assert health_response(REPO/'Caddy/configs/caddy') == '204'
    import re
    operation_text = (REPO/'Caddy/manifests/serving-health-operation.yaml').read_text()
    fields = dict(re.findall(r'^([a-z0-9_]+): (\S+)$', operation_text, re.M))
    assert fields.get('scope') == 'certificate-release-repair', 'A defined certificate-repair operation is required'
    assert fields['state_contract_sha256'] == digest(REPO/fields['state_contract'])
    assert fields['production_contract_sha256'] == digest(REPO/fields['production_contract'])
    assert fields['status'] == 'defined-unexecuted'
    assert fields['certificate_inputs'] == 'Caddy/manifests/certificate-release-inputs.tsv'
    assert fields['certificate_inputs_sha256'] == digest(REPO/fields['certificate_inputs'])
    assert fields['coverage_sha256'] == digest(REPO/'Caddy/manifests/deployable-successor-coverage.tsv')
    assert fields['regression_sha256'] == digest(REPO/'Caddy/tests/certificate-release-regression.sh')
    assert fields['fixture_sha256'] == digest(Path(__file__))
    assert fields['transaction_sha256'] == digest(REPO/'Caddy/scripts/apply-serving-health-deployment.sh')
    transaction = (REPO/'Caddy/scripts/apply-serving-health-deployment.sh').read_text()
    assert 'readonly certificate_inputs_sha256=' + fields['certificate_inputs_sha256'] in transaction
    recipe = dict(line.split('\t') for line in (REPO/fields['certificate_inputs']).read_text().splitlines()[1:])
    assert recipe['publisher_candidate_sha256'] == digest(REPO/'Caddy/scripts/publish-release-v2.sh')
    assert recipe['checker_sha256'] == digest(REPO/'Caddy/scripts/check-certificate-expiry.sh')


def decode_stream(path):
    import base64
    import re
    lines = path.read_text().splitlines()
    assert len(lines) % 2 == 0 and path.stat().st_size <= 1048576
    records = {}
    for index in range(0, len(lines), 2):
        match = re.fullmatch(r'file=([a-zA-Z0-9._-]+) bytes=([0-9]+) sha256=([a-f0-9]{64})', lines[index])
        assert match
        name, size, sha = match.groups()
        assert name not in records
        body = base64.b64decode(lines[index+1], validate=True)
        assert len(body) == int(size) and hashlib.sha256(body).hexdigest() == sha
        records[name] = body.decode('utf-8')
    return records


def verify_evidence(evidence):
    definition_check()
    assert evidence.is_dir() and not evidence.is_symlink()
    summary = json.loads((evidence/'qualification-summary.json').read_text())
    assert summary['source_graph'] == {name: digest(REPO/name) for name in GRAPH_FILES}
    assert set(summary['scenarios']) == set(SCENARIOS)
    tx_sha = digest(REPO/'Caddy/scripts/apply-serving-health-deployment.sh')
    for scenario in SCENARIOS:
        root = evidence/scenario
        assert digest(root/'observations.json') == summary['scenarios'][scenario]['observations_sha256']
        assert digest(root/'ssh.jsonl') == summary['scenarios'][scenario]['ssh_sha256']
        observed = json.loads((root/'observations.json').read_text())
        calls = [json.loads(line) for line in (root/'ssh.jsonl').read_text().splitlines()]
        assert all(call['options'] == ['BatchMode=yes', 'ConnectTimeout=10', 'ServerAliveInterval=5', 'ServerAliveCountMax=3'] for call in calls)
        tx = [call for call in calls if call['stdin_sha256'] == tx_sha]
        assert tx == observed['transaction_commands']
        commands = [call['command'] for call in tx]
        assert all(command.startswith('cd / && sudo -n /bin/bash -s -- certificate-') for command in commands)
        accepted = scenario in ['success', 'namespace-absent']
        assert observed['status'] == (0 if accepted else (125 if scenario == 'rollback-failure' else 1))
        runner = root/'runner-evidence'
        for role in ['node-a', 'node-b']:
            node = root/'nodes'/role
            selected = os.readlink(node/'caddy/current')
            assert selected == observed['nodes'][role]['selection']
            assert digest(node/'libexec/publish-release-v2.sh') == observed['nodes'][role]['publisher_sha256']
            assert json.loads((node/'state.json').read_text())['lsyncd'] == (not (scenario == 'rollback-failure' and role == 'node-a'))
            if accepted:
                assert selected.startswith('/etc/caddy/releases/') and not selected.endswith('/baseline')
                candidate = node/'caddy/releases'/Path(selected).name
                baseline = node/'caddy/releases/baseline'
                for name in ['fullchain.pem', 'privkey.pem']:
                    assert (candidate/'tls'/name).read_bytes() == (baseline/'tls'/name).read_bytes()
                for name in ['leaf.pem', 'intermediates.pem', 'certificate-manifest.json']:
                    assert (candidate/'tls'/name).read_bytes() == (root/'cert'/name).read_bytes()
                assert digest(node/'libexec/publish-release-v2.sh') == digest(REPO/'Caddy/scripts/publish-release-v2.sh')
                records = decode_stream(runner/f'certificate-result-{role[-1]}-readback.stdout')
                assert records['certificate-checker-start.status'] == '0\n'
                assert records['certificate-checker-result.status'] == '0\n'
                assert set(records['certificate-checker-result.stdout'].splitlines()) == {'Result=success', 'ExecMainStatus=0'}
                assert records['certificate-checker-journal.stdout'].strip()
                for family in [4, 6]:
                    assert records[f'certificate-serving-ipv{family}.stdout'] == health_response(candidate) + '\n'
                    assert records[f'certificate-serving-ipv{family}.status'] == '0\n'
            else:
                assert selected == '/etc/caddy/releases/baseline'
                if scenario == 'rollback-failure' and role == 'node-b':
                    assert digest(node/'libexec/publish-release-v2.sh') == digest(REPO/'Caddy/scripts/publish-release-v2.sh')
                else:
                    assert (node/'libexec/publish-release-v2.sh').read_text() == '#!/bin/bash\nexit 73\n'
        if accepted:
            b_accept = next(i for i,c in enumerate(commands) if ' certificate-accept node-b ' in c)
            a_install = next(i for i,c in enumerate(commands) if ' certificate-install-publisher node-a ' in c)
            a_promote = next(i for i,c in enumerate(commands) if ' certificate-promote node-a ' in c)
            assert b_accept < a_install < a_promote
            assert (runner/'certificate-standby-b-readback.status').read_text() == '0\n'
            a = decode_stream(runner/'certificate-result-a-readback.stdout')
            b = decode_stream(runner/'certificate-result-b-readback.stdout')
            assert a['certificate-manifest.tsv'] == b['certificate-manifest.tsv']
        elif scenario in ['worker-failure', 'primary-worker-failure', 'readback-failure', 'standby-readback-failure', 'ownership-transition', 'reload-failure', 'rollback-failure']:
            contain = next(i for i,c in enumerate(commands) if ' certificate-contain-publication ' in c)
            a_restore = next(i for i,c in enumerate(commands) if ' certificate-rollback node-a ' in c)
            b_restore = next(i for i,c in enumerate(commands) if ' certificate-rollback node-b ' in c)
            assert contain < a_restore < b_restore
            if scenario in ['worker-failure', 'standby-readback-failure']:
                assert not any(' certificate-promote node-a ' in c for c in commands)
            for role in ['a', 'b']:
                if scenario == 'rollback-failure' and role == 'b':
                    assert (runner/'certificate-rollback-b.status').read_text() != '0\n'
                    continue
                assert (runner/f'certificate-rollback-{role}.status').read_text() == '0\n'
                if scenario == 'rollback-failure':
                    continue
                records = decode_stream(runner/f'certificate-rollback-{role}-readback.stdout')
                assert records['certificate-rollback-selection.stdout'] == '/etc/caddy/releases/baseline\n'
        else:
            assert not any(' certificate-install-publisher ' in c or ' certificate-publish ' in c for c in commands)
            assert all(item['reloads'] == 0 and item['checker_runs'] == 0 for item in observed['nodes'].values())
        # These are command results from the real disposition entrypoint, not
        # a fixture-generated success marker.
        for role in ['a', 'b']:
            if scenario == 'rollback-failure':
                assert not (runner/f'node-{role}-disposition.status').exists()
                assert not (runner/'certificate-resume-a.status').exists()
            else:
                assert (runner/f'node-{role}-disposition.status').read_text() == '0\n'
    print('certificate_release_qualification_verified=true')


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == '--adapter':
        raise SystemExit(adapter(sys.argv[2], sys.argv[3:]))
    if sys.argv[1:] == ['--definition-check']:
        definition_check()
    elif len(sys.argv) == 3 and sys.argv[1] == '--verify-evidence':
        verify_evidence(Path(sys.argv[2]))
    else:
        suite()
