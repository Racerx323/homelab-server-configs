#!/usr/bin/env python3
"""Primary-first entrypoint regression in a disposable, offline container.

Reuse the serialized SSH/filesystem adapter, with native Caddy reloads and HTTPS
requests. Network identities and systemd/lsyncd scheduling are isolated substitutes;
real publishers, finalizers and accepted reconciler produce all release effects.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import re
import shlex
import tempfile

sys.dont_write_bytecode = True
SOURCE = Path(__file__).resolve()
REPO = SOURCE.parents[2]
spec = importlib.util.spec_from_file_location('release_fixture', SOURCE.with_name('certificate-release-regression.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
BASE_SWITCH = release.switch
CASES = ['publisher-boundaries', 'success', 'primary-reload', 'primary-http', 'secondary-drift', 'secondary-http', 'timeout', 'recovery-failure', 'exposure-tamper', 'webmin-source']
EXPECTED_STATUS = dict(zip(CASES, [0, 0, 1, 22, 2, 2, 2, 125, 2, 0]))
TRIALS = {'trial-success': 0, 'trial-timeout': 1, 'trial-lost-reply': 1, 'trial-secondary-timeout': 1, 'trial-recovery-failure': 125, 'trial-incomplete': 125}
CASES += list(TRIALS)
EXPECTED_STATUS.update(TRIALS)
GRAPH_FILES = [
    'Caddy/scripts/' + name for name in ['publish-release-v2.sh',
    'apply-serving-health-deployment.sh', 'run-serving-health-deployment-outer.sh']]
GRAPH_FILES += ['Caddy/tests/' + name for name in ['application-onboarding-regression.py',
    'application-onboarding-regression.sh', 'certificate-release-regression.py',
    'run-application-qualification.py', 'deployable-successor-policy.sh']]
GRAPH_FILES += ['Caddy/manifests/' + name for name in ['serving-health-operation.yaml',
    'certificate-release-inputs.tsv', 'deployable-successor.tsv',
    'deployable-successor-coverage.tsv', 'current-live-state.tsv',
    'serving-health-production.tsv', 'accepted-live-artifacts.tsv', 'production-artifacts.tsv']]
GRAPH_FILES += ['../homelab-monitoring-observability/uptime-kuma/proposals/20-uptime-kuma.caddy',
                'Webmin/proposals/30-webmin-j2-svpi3bmf.caddy']


def source_graph():
    paths = set(GRAPH_FILES)
    recipe = dict(line.split('\t') for line in (REPO/'Caddy/manifests/certificate-release-inputs.tsv').read_text().splitlines()[1:])
    if recipe.get('release_kind') == 'application':
        paths.add('../' + recipe['application_fragment_source'])
    return {name: release.digest(REPO/name) for name in sorted(paths)}


def coverage_rows():
    for case in CASES:
        phase = ('pre-mutation' if case == 'publisher-boundaries' else
                 'pre-exposure' if case == 'exposure-tamper' else
                 'convergence' if case.startswith('secondary-') or case == 'timeout' else
                 'accepted-path' if case in ('success', 'webmin-source') else 'recovery')
        entrypoint = 'outer' if case in ['publisher-boundaries', 'timeout'] else 'transaction'
        expectation = 'reach' if case == 'publisher-boundaries' else 'accept' if EXPECTED_STATUS[case] == 0 else 'reject'
        yield ['application-' + case, phase, entrypoint, expectation,
               'decisions/application-' + case + '.tsv', 'raw/application-' + case + '.json']


def definition_check():
    operation = (REPO/'Caddy/manifests/serving-health-operation.yaml').read_text()
    entries = re.findall(r'^([a-z0-9_]+): (\S+)$', operation, re.M)
    fields = dict(entries)
    assert len(fields) == len(entries), 'duplicate operation field'
    assert fields['transaction_sha256'] == release.digest(REPO/fields['transaction'])
    if fields.get('status') == 'inactive':
        assert fields['action'] == 'none'
        return
    assert fields['status'] == 'defined-unexecuted' and fields['scope'] == 'application-onboarding'
    for key, path in [('state_contract_sha256', fields['state_contract']),
                      ('production_contract_sha256', fields['production_contract']),
                      ('certificate_inputs_sha256', 'Caddy/manifests/certificate-release-inputs.tsv'),
                      ('coverage_sha256', 'Caddy/manifests/deployable-successor-coverage.tsv'),
                      ('regression_sha256', 'Caddy/tests/application-onboarding-regression.sh'),
                      ('fixture_sha256', 'Caddy/tests/application-onboarding-regression.py'),
                      ('qualification_launcher_sha256', 'Caddy/tests/run-application-qualification.py'),
                      ('authorization_policy_sha256', 'Caddy/tests/deployable-successor-policy.sh')]:
        assert fields[key] == release.digest(REPO/path), key
    assert 'readonly certificate_inputs_sha256=' + fields['certificate_inputs_sha256'] in (REPO/fields['transaction']).read_text()
    recipe_entries = [line.split('\t') for line in (REPO/fields['certificate_inputs']).read_text().splitlines()[1:]]
    recipe = dict(recipe_entries)
    assert len(recipe) == len(recipe_entries)
    assert recipe['release_kind'] == 'application'
    if 'application_trial_seconds' in recipe:
        assert recipe['application_trial_seconds'] == '660'
    if 'application_diagnostic_seconds' in recipe:
        assert recipe.get('application_trial_seconds') == '660' and recipe['application_diagnostic_seconds'] == '240'
    assert recipe['publisher_candidate_sha256'] == release.digest(REPO/'Caddy/scripts/publish-release-v2.sh')
    assert recipe['reconciler_installed_sha256'] == release.accepted_hash('protocol_v2_reconciler')
    assert recipe['finalizer_sha256'] == release.accepted_hash('protocol_v2_finalizer')
    source = recipe['application_fragment_source']
    assert re.fullmatch(r'homelab-[a-z0-9-]+/(?:[A-Za-z0-9_-]+/)+[2-7][0-9]-[a-z0-9-]+\.caddy', source)
    path = REPO.parent/source
    assert path.resolve() == path and path.name == recipe['application_fragment_name']
    assert recipe['application_fragment_sha256'] == release.digest(path)
    assert recipe['baseline_revision'] == recipe['tls_source_revision']
    assert recipe['baseline_manifest_sha256'] == recipe['tls_source_manifest_sha256']
    assert re.fullmatch(r'[a-z0-9-]+\.local\.theama\.co', recipe['application_fqdn'])
    assert re.fullmatch(r'[A-Za-z0-9_./-]*', recipe['application_probe_path'])
    assert '..' not in recipe['application_probe_path'].split('/')
    assert re.fullmatch(r'[234][0-9]{2}', recipe['application_http_status'])
    actual = [line.split('\t') for line in (REPO/'Caddy/manifests/deployable-successor-coverage.tsv').read_text().splitlines()[1:]]
    assert actual == list(coverage_rows()), 'primary-first coverage contract'


def probe_diagnostic_tests():
    """Check the real shell probe's evidence/exit contract, not host capacity."""
    source = (REPO/'Caddy/scripts/apply-serving-health-deployment.sh').read_text()
    functions = '\n'.join(re.search(r'^'+name+r'\(\) \{\n.*?^\}', source, re.M|re.S)[0]
                          for name in ('capture_command', 'application_failure_journal', 'application_routes'))
    with tempfile.TemporaryDirectory(prefix='caddy-probe-contract-') as name:
        root = Path(name)
        journal = root/'journal'
        journal.write_text("#!/bin/sh\nprintf '%s\\n' " + shlex.quote(json.dumps({'__REALTIME_TIMESTAMP': '1234', 'MESSAGE': 'timeout password=PRIVATE cookie=PRIVATE'})) + '\n')
        journal.chmod(0o700)
        curl = root/'curl'
        for code, status in [(0, '200'), (28, '000'), (22, '503')]:
            evidence = root/str(code); evidence.mkdir()
            curl.write_text("#!/bin/sh\nprintf '%s\\n' " + shlex.quote(status) + ' ' +
                            shlex.quote('connect=0.01 tls=0.02 first_byte=0 total=5 remote_ip=10.1.0.53 remote_port=443') + '\nexit '+str(code)+'\n')
            curl.chmod(0o700)
            script = functions + '\n' + """
set -Eeuo pipefail
umask 077
evidence_root=$1; journalctl_command=$2; export CADDY_SERVING_HEALTH_CURL_COMMAND=$3
node_role=node-a
certificate_setting() { case "$1" in application_fqdn) echo webmin.example;; application_probe_path) echo session_login.cgi;; application_http_status) echo 200;; esac; }
require_equal() { [[ "$2" = "$3" ]]; }
certificate_serving_check() { :; }
application_routes
"""
            result = subprocess.run(['bash', '-c', script, 'probe', str(evidence), str(journal), str(curl)], capture_output=True, text=True)
            assert result.returncode == code, result.stderr
            assert (evidence/'application-node-ipv4.stdout').read_text() == status+'\n'
            assert 'total=5' in (evidence/'application-node-ipv4.timing.tsv').read_text()
            if code:
                retained = (evidence/'application-node-ipv4-journal.stdout').read_text()
                assert json.loads(retained) == [{'epoch_us':'1234','category':'timeout'}]
                assert 'PRIVATE' not in ''.join(p.read_text() for p in evidence.iterdir())
                assert not (evidence/'application-node-ipv6.stdout').exists()
        # Diagnostic failure must not replace the original failure or prevent recovery.
        journal.write_text('#!/bin/sh\nexit 1\n')
        unavailable = root/'unavailable'; unavailable.mkdir()
        result = subprocess.run(['bash', '-c', script, 'probe', str(unavailable), str(journal), str(curl)], capture_output=True, text=True)
        assert result.returncode == 22
        assert (unavailable/'application-node-ipv4-journal.status').read_text() != '0\n'
        token = 'a'*32
        message = {'diagnostic_id': token, 'status': 200, 'duration': .4,
                   'upstream_host': '10.1.3.75:10000', 'upstream_duration_ms': '390',
                   'upstream_latency_ms': '380', 'request': {'headers': {'Cookie': 'PRIVATE'}},
                   'resp_headers': {'Set-Cookie': 'PRIVATE'}}
        journal.write_text("#!/bin/sh\nprintf '%s\\n' " + shlex.quote(json.dumps(
            {'__REALTIME_TIMESTAMP': '1234', 'MESSAGE': json.dumps(message)})) + '\n')
        run = subprocess.run(['bash', '-c', functions + '\njournalctl_command=$1; application_failure_journal 1 "$2"',
                              'journal', str(journal), token], capture_output=True, text=True)
        assert run.returncode == 0, run.stderr
        record = json.loads(run.stdout)[0]
        assert record['request_id'] == token and record['upstream_duration_ms'] == 390
        assert record['upstream_latency_ms'] == 380 and record['status'] == 200
        assert 'PRIVATE' not in run.stdout and 'request' not in record and 'resp_headers' not in record
        mismatch = subprocess.run(['bash', '-c', functions + '\njournalctl_command=$1; application_failure_journal 1 "$2"',
                                   'journal', str(journal), 'b'*32], capture_output=True, text=True)
        assert json.loads(mismatch.stdout) == [{'epoch_us': '1234', 'category': 'other'}]
    print('application_probe_diagnostic_contract=true')


def budget_contract_tests():
    """Real timeout/process groups and OpenSSH-style remote shell serialization."""
    source = (REPO/'Caddy/scripts/run-serving-health-deployment-outer.sh').read_text()
    functions = '\n'.join(re.search(r'^'+name+r'\(\) \{\n.*?^\}', source, re.M|re.S)[0]
                          for name in ('application_budget_seconds', 'application_budget_copy', 'ssh_stream'))
    with tempfile.TemporaryDirectory(prefix='caddy-budget-contract-') as name:
        root = Path(name); ssh = root/'ssh'; program = root/'remote'
        ssh.write_text("#!/usr/bin/python3\nimport os,sys\ncommand=sys.argv[-1]\nassert command.startswith('cd / && sudo -n /usr/bin/timeout --signal=TERM --kill-after=5 ')\nassert '/bin/bash -s --' in command\nos.execv('/bin/bash',['bash','-c',command.replace('sudo -n ','',1)])\n")
        ssh.chmod(0o700)
        prelude = functions + "\nset -Eeuo pipefail\nssh_command=$1; program=$2\napplication_forward_deadline=$(awk '{printf \"%.0f\\n\", $1+22}' /proc/uptime)\napplication_recovery_deadline=$((application_forward_deadline+600))\n"
        program.write_text('printf \"%s\\n\" \"$1\"\n')
        run = subprocess.run(['bash', '-c', prelude+'ssh_stream fixture "$program" "argument with spaces"', 'budget', str(ssh), str(program)], capture_output=True, text=True, timeout=15)
        assert run.returncode == 0 and run.stdout.strip() == 'argument with spaces', run.stderr
        program.write_text('sleep 30\n')
        run = subprocess.run(['bash', '-c', prelude+'ssh_stream fixture "$program" test', 'budget', str(ssh), str(program)], capture_output=True, text=True, timeout=15)
        assert run.returncode == 124, (run.returncode, run.stderr)
        # Expired forward phase cannot execute, but reserve is not consumed/reset.
        script = prelude + "application_forward_deadline=1\nset +e\napplication_budget_seconds 90\nstatus=$?\nset -e\n[[ $status = 124 ]]\napplication_budget_phase=recovery\n[[ $(application_budget_seconds 170) = 170 ]]\n"
        run = subprocess.run(['bash', '-c', script, 'budget', str(ssh), str(program)], capture_output=True, text=True, timeout=5)
        assert run.returncode == 0, run.stderr
        script += "application_recovery_deadline=1\napplication_budget_seconds 90\n"
        run = subprocess.run(['bash', '-c', script, 'budget', str(ssh), str(program)], capture_output=True, text=True, timeout=5)
        assert run.returncode == 124, run.stderr
        run = subprocess.run(['bash', '-c', prelude+'application_budget_copy sleep 30', 'budget', str(ssh), str(program)], capture_output=True, text=True, timeout=15)
        assert run.returncode == 124, run.stderr
    print('application_diagnostic_budget_contract=true')


def monitor_contract_tests():
    """Exercise the actual observer and pair coordinator without live commands."""
    source = (REPO/'Caddy/scripts/apply-serving-health-deployment.sh').read_text()
    functions = '\n'.join(re.search(r'^'+name+r'\(\) \{\n.*?^\}', source, re.M|re.S)[0]
                          for name in ('capture_command', 'application_monitor_value', 'application_trial_monitor'))
    cases = ['success', 'failed', 'missing', 'stale', 'boot-change', 'restart', 'timer-off', 'late', 'command-error']
    with tempfile.TemporaryDirectory(prefix='caddy-monitor-contract-') as name:
        root = Path(name)
        ctl = root/'systemctl'
        ctl.write_text("""#!/usr/bin/env python3
import os,sys
case=os.environ['MONITOR_CASE']; unit=sys.argv[2]
if case=='command-error': sys.exit(1)
if sys.argv[1]=='is-active':
 print('inactive' if case=='timer-off' else 'active');sys.exit(3 if case=='timer-off' else 0)
if unit=='caddy-lsyncd.service':
 print('MainPID=99\\nNRestarts='+('1' if case=='restart' else '0')+'\\nActiveState=active\\nSubState=running');sys.exit()
start,end,iid='200','300','b'*32
if case in ('missing','stale'): start,end,iid='10','20','a'*32
if case=='late': end='150000101'
print('InvocationID='+iid+'\\nExecMainStartTimestampMonotonic='+start+'\\nExecMainExitTimestampMonotonic='+end)
print('Result='+('exit-code' if case=='failed' else 'success'))
print('ExecMainStatus='+('1' if case=='failed' else '0')+'\\nActiveState='+('failed' if case=='failed' else 'inactive'))
""")
        ctl.chmod(0o700)
        for case in cases:
            evidence=root/case; evidence.mkdir()
            for file, value in {'application-trial-resumed.tsv':'resumed', 'application-monitor-resume-us.tsv':'100',
                                'application-trial-boot.tsv':'boot', 'application-monitor-before.stdout':'InvocationID='+('a'*32)+'\nExecMainExitTimestampMonotonic=20',
                                'application-monitor-sender-before.stdout':'MainPID=99\nNRestarts=0'}.items():
                (evidence/file).write_text(value+'\n')
            script=functions+"""
set -Eeuo pipefail
evidence_root=$1; systemctl_command=$2; sleep_command=false
require_equal() { [[ "$2" = "$3" ]] || { printf '%s expected=%s observed=%s\n' "$1" "$2" "$3" >&2; return 1; }; }
cat() { if [[ "$1" = /proc/sys/kernel/random/boot_id ]]; then [[ "$MONITOR_CASE" != boot-change ]] && echo boot || echo changed; else command cat "$@"; fi; }
awk() { if [[ "${*: -1}" = /proc/uptime ]]; then echo 150000101; else command awk "$@"; fi; }
application_trial_monitor
"""
            result=subprocess.run(['bash','-c',script,'monitor',str(evidence),str(ctl)],env=dict(os.environ,MONITOR_CASE=case),capture_output=True,text=True)
            assert (result.returncode==0)==(case=='success'), (case,result.stderr)
            assert (evidence/'application-trial-monitor.tsv').read_text()==('passed\n' if case=='success' else 'pending\n')
        outer=(REPO/'Caddy/scripts/run-serving-health-deployment-outer.sh').read_text()
        pair=re.search(r'^application_trial_recover_pair\(\) \{\n.*?^\}',outer,re.M|re.S)[0]
        # Explicit command recording proves an observation failure does not recontain/restart.
        script=pair+"""
set -Eeuo pipefail
node_a_host=a; node_b_host=b; node_a_payload=pa; node_b_payload=pb; node_a_evidence=ea; node_b_evidence=eb
remote_transaction() { echo "$1" >>"$CALL_LOG"; [[ "$1" != application-monitor-b ]]; }
readback() { echo "$1" >>"$CALL_LOG"; }
application_trial_recover_pair candidate
"""
        calls=root/'calls'
        result=subprocess.run(['bash','-c',script],env=dict(os.environ,CALL_LOG=str(calls)),capture_output=True,text=True)
        assert result.returncode==125,result.stderr
        values=calls.read_text().splitlines()
        assert values[-4:]==['application-monitor-b','application-monitor-a','application-restored-a','application-restored-b']
        assert values.count('application-contain-a')==values.count('application-contain-b')==1
        assert values.index('application-resume-a')<values.index('application-monitor-b')
        assert 'restoration=passed monitor_acceptance=incomplete' in result.stderr
    print('application_trial_monitor_contract=true')


def payload_tests():
    """Execute the actual builder with local files; no SSH or target fixtures."""
    outer = (REPO/'Caddy/scripts/run-serving-health-deployment-outer.sh').read_text()
    functions = '\n'.join(re.search(r'^' + name + r'\(\) \{\n.*?^\}', outer, re.M | re.S)[0]
                          for name in ('regular_file', 'application_payload_fragment'))
    with tempfile.TemporaryDirectory(prefix='caddy-fragment-') as temporary:
        root = Path(temporary)
        stage = root/'payload'
        (stage/'manifests').mkdir(parents=True)
        workspace = root/'workspace'
        for source in ('homelab-monitoring-observability/uptime-kuma/proposals/20-uptime-kuma.caddy',
                       'homelab-server-configs/Webmin/proposals/30-webmin-j2-svpi3bmf.caddy'):
            target = workspace/source
            target.parent.mkdir(parents=True)
            target.write_bytes((REPO.parent/source).read_bytes())
            recipe = root/'inputs.tsv'
            fields = dict(application_fragment_source=source, application_fragment_name=target.name,
                          application_fragment_sha256=release.digest(target))
            def run(overrides=None, duplicate=False):
                values = fields | (overrides or {})
                recipe.write_text('key\tvalue\n' + ''.join(k+'\t'+v+'\n' for k,v in values.items()) +
                                  ('application_fragment_source\t'+source+'\n' if duplicate else ''))
                output = stage/'manifests/application.caddy'
                output.unlink(missing_ok=True)
                script = functions + '\nworkspace_root=$1; payload_stage=$2; application_payload_fragment "$3"\n'
                result = subprocess.run(['/bin/bash', '-euc', script, 'payload-test', str(workspace), str(stage), str(recipe)],
                                        capture_output=True, timeout=10)
                return result.returncode, output
            status, output = run()
            assert status == 0 and output.read_bytes() == target.read_bytes()
            assert output.stat().st_mode & 0o777 == 0o600
            for overrides in ({'application_fragment_sha256': '0'*64},
                              {'application_fragment_source': '../'+source},
                              {'application_fragment_source': source.replace('/proposals/', '/proposals/../proposals/')},
                              {'application_fragment_name': '20-other.caddy'},
                              {'application_fragment_source': source.replace(target.name, '90-default.caddy'),
                               'application_fragment_name': '90-default.caddy'}):
                status, output = run(overrides)
                assert status != 0 and not output.exists(), overrides
            assert run(duplicate=True)[0] != 0
            saved = target.with_suffix('.saved'); target.rename(saved); target.symlink_to(saved)
            assert run()[0] != 0
            target.unlink(); saved.rename(target)
            saved_directory = target.parent.with_name('saved-directory')
            target.parent.rename(saved_directory); target.parent.symlink_to(saved_directory)
            assert run()[0] != 0
        print('application payload: both owners, exact identity, mode and unsafe-input rejection passed')


def read_evidence(path, limit=1048576):
    assert path.is_file() and not path.is_symlink(), str(path)
    assert not any(parent.is_symlink() for parent in path.parents), str(path)
    data = path.read_bytes()
    assert len(data) <= limit and not re.search(rb'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', data), str(path)
    return data.decode('utf-8')


def case_observation(root, case):
    """Derive acceptance again from retained producers, not the suite's pass label."""
    evidence_hashes = {}
    def read(relative):
        text = read_evidence(root/relative)
        evidence_hashes[relative] = release.digest(root/relative)
        return text
    if case == 'publisher-boundaries':
        record = json.loads(read('publisher.json'))
        assert record['prepared_status'] == record['legacy_status'] == 0
        assert record['early_exposure_status'] != 0 and 'primary_selected' in record['early_exposure_stderr']
        for label, status in [('prepare', 0), ('early-expose', record['early_exposure_status']), ('legacy', 0)]:
            assert int(read('publisher-' + label + '.status')) == status
            read('publisher-' + label + '.stdout'); read('publisher-' + label + '.stderr')
        assert record['primary_selection'] == '/etc/caddy/releases/baseline'
        return {'case': case, 'status': 0, 'expected': 'unexposed-until-primary',
                'observed': 'unexposed-until-primary', 'evidence': evidence_hashes}
    observed = json.loads(read('observed.json'))
    assert observed['scenario'] == case and observed['status'] == EXPECTED_STATUS[case]
    assert int(read('outer.status')) == EXPECTED_STATUS[case]
    read('outer.stdout'); read('outer.stderr')
    calls = [json.loads(line) for line in read('ssh.jsonl').splitlines()]
    tx_hash = release.digest(REPO/'Caddy/scripts/apply-serving-health-deployment.sh')
    commands = [shlex.split(c['command']) for c in calls if c['stdin_sha256'] == tx_hash]
    modes = [next(t for t in c if t.startswith('application-')) for c in commands]
    if case in TRIALS:
        assert modes[:2] == ['application-trial-admit', 'application-trial-admit']
        assert modes.index('application-primary') < modes.index('application-expose')
        assert modes.count('application-trial-contain') == 2
        assert modes.index('application-trial-quiesce') > modes.index('application-trial-contain')
        assert int(read('outer.status')) == TRIALS[case]
        for role in ['node-a', 'node-b']:
            node = root/'nodes'/role
            selected = Path(os.readlink(node/'caddy/current')).name
            state = json.loads(read(f'nodes/{role}/state.json'))
            assert state['checker_runs'] == 0
            if TRIALS[case] != 125:
                assert selected == 'baseline' and state['lsyncd'] and state['reconcile_path']
                assert not list((node/'sync/incoming/node-a').iterdir())
                expected_out = ['baseline'] if role == 'node-a' else []
                assert sorted(p.name for p in (node/'sync/outbound').iterdir()) == expected_out if (node/'sync/outbound').exists() else not expected_out
                label = 'a' if role == 'node-a' else 'b'
                stream = root/f'runner-evidence/application-restored-{label}-readback.stdout'
                records = release.decode_stream(stream); read(str(stream.relative_to(root)))
                assert records['application-trial-restored.tsv'] == 'restored\n'
                assert records['application-trial-resumed.tsv'] == 'resumed\n'
                assert records['application-trial-monitor.tsv'] == 'passed\n'
                assert records['application-trial-outbound.tsv'] == records['application-trial-outbound-after.tsv'] == records['application-trial-resume-inventory.tsv']
            else:
                assert not state['lsyncd'] and not state['reconcile_path']
        if case == 'trial-success':
            assert int(read('late-expose.status')) != 0
            read('late-expose.stderr')
        if TRIALS[case] != 125:
            restore_commands = [c for c in commands if 'application-trial-restore' in c]
            assert 'node-b' in restore_commands[0] and 'node-a' in restore_commands[1]
        return {'case': case, 'status': TRIALS[case], 'expected': 'contained' if TRIALS[case] == 125 else 'restored',
                'observed': 'contained' if TRIALS[case] == 125 else 'restored', 'evidence': evidence_hashes}
    assert modes and modes[0] == 'application-primary'
    assert not any('certificate-' in ' '.join(c) for c in commands)
    runner = root/'runner-evidence'
    primary_status = int(read('runner-evidence/application-primary-a.status'))
    assert primary_status == (EXPECTED_STATUS[case] if case in ['primary-reload', 'primary-http', 'recovery-failure'] else 0)
    assert int(read('runner-evidence/application-primary-a-readback.status')) == 0
    primary = release.decode_stream(runner/'application-primary-a-readback.stdout')
    read('runner-evidence/application-primary-a-readback.stdout')
    if primary_status == 0:
        for family in [4, 6]:
            assert primary[f'application-node-ipv{family}.status'] == '0\n'
            assert primary[f'application-node-ipv{family}.stdout'] == '200\n'
            assert primary[f'certificate-serving-ipv{family}.stdout'] == '204\n'
        assert modes.index('application-primary') < modes.index('application-secondary-ready')
    if case in ['primary-reload', 'primary-http', 'recovery-failure', 'exposure-tamper']:
        assert not (root/'exposure.json').exists()
        if primary_status: assert modes == ['application-primary']
    else:
        exposure = json.loads(read('exposure.json'))
        assert exposure['primary'] == '/etc/caddy/releases/' + exposure['revision']
        assert modes.index('application-secondary-ready') < modes.index('application-expose') < modes.index('application-secondary')
        assert exposure['revision'] == primary['application-target.tsv'].strip()
        assert exposure['manifest'] == primary['application-manifest.tsv'].strip()
    for role in ['node-a', 'node-b']:
        node = root/'nodes'/role/'caddy'
        selection = os.readlink(node/'current')
        selected = Path(selection).name
        assert selection == '/etc/caddy/releases/' + selected
        assert observed['nodes'][role]['selection'] == selected
        expected = ('drift' if role == 'node-b' and case == 'secondary-drift' else
                    'baseline' if case in ['primary-reload', 'primary-http', 'recovery-failure', 'exposure-tamper'] or
                    role == 'node-b' and case in ['timeout', 'secondary-http'] else None)
        if expected: assert selected == expected
        else: assert selected not in ['baseline', 'drift']
        state = json.loads(read('nodes/' + role + '/state.json'))
        assert state['checker_runs'] == observed['nodes'][role]['checker_runs'] == 0
        assert state['reloads'] == observed['nodes'][role]['reloads']
        if selected not in ['baseline', 'drift']:
            release_root = node/'releases'/selected
            manifest = read('nodes/' + role + '/caddy/releases/' + selected + '/manifest.sha256')
            for line in manifest.splitlines():
                sha, relative = line.split('  ', 1)
                assert relative.startswith('./') and '..' not in Path(relative).parts
                file = release_root/relative
                assert file.is_file() and not file.is_symlink() and release.digest(file) == sha
            for name in ['fullchain.pem', 'privkey.pem']:
                assert (release_root/'tls'/name).read_bytes() == (node/'releases/baseline/tls'/name).read_bytes()
    if case in ('success', 'webmin-source'):
        assert modes == ['application-primary', 'application-secondary-ready', 'application-expose',
                         'application-secondary', 'application-final', 'application-final', 'application-shared']
        assert observed['nodes']['node-a']['selection'] == observed['nodes']['node-b']['selection']
        for label in ['application-ready-b', 'application-expose-a', 'application-secondary-b',
                      'application-final-a', 'application-final-b', 'application-shared-a']:
            assert int(read('runner-evidence/' + label + '.status')) == 0
        for role in ['a', 'b']:
            stream = runner/f'application-result-{role}-readback.stdout'
            records = release.decode_stream(stream); read(str(stream.relative_to(root)))
            for family in [4, 6]:
                assert records[f'application-node-ipv{family}.stdout'] == '200\n'
                if role == 'a': assert records[f'application-shared-ipv{family}.stdout'] == '200\n'
            assert records['application-manifest.tsv'] == primary['application-manifest.tsv']
    if case in ['primary-reload', 'primary-http']:
        assert primary['application-recovery.tsv'] == 'restored\n'
        assert primary['application-restore-reload.status'] == '0\n'
    if case in ['secondary-drift', 'secondary-http', 'timeout']:
        assert int(read('runner-evidence/application-secondary-b.status')) != 0
    if case == 'exposure-tamper':
        assert int(read('runner-evidence/application-expose-a.status')) != 0
    cleanup = json.loads(read('cleanup.json'))
    assert cleanup['staging_retained'] == (case == 'recovery-failure')
    if case != 'recovery-failure':
        for role in ['a', 'b']:
            assert int(read(f'runner-evidence/node-{role}-disposition.status')) == 0
    return {'case': case, 'status': EXPECTED_STATUS[case], 'expected': 'verified-' + case,
            'observed': 'verified-' + case, 'evidence': evidence_hashes}


def write_qualification(evidence, graph):
    assert graph == source_graph(), 'source changed during qualification'
    for directory in ['raw', 'decisions']:
        (evidence/directory).mkdir(mode=0o700)
    for row in coverage_rows():
        case = row[0].removeprefix('application-')
        raw = evidence/row[5]
        raw.write_text(json.dumps(case_observation(evidence/case, case), sort_keys=True, indent=2)+'\n')
        raw.chmod(0o600)
        record = json.loads(raw.read_text())
        decision = evidence/row[4]
        decision.write_text('scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n' +
            '\t'.join([row[0], row[3], str(record['status']), record['expected'], record['observed'], release.digest(raw)])+'\n')
        decision.chmod(0o600)
    (evidence/'qualification-summary.json').write_text(json.dumps({'source_graph': graph, 'cases': CASES}, indent=2)+'\n')


def verify_evidence(evidence):
    definition_check()
    assert evidence.is_dir() and not evidence.is_symlink()
    summary = json.loads(read_evidence(evidence/'qualification-summary.json'))
    assert summary == {'source_graph': source_graph(), 'cases': CASES}, 'stale or incomplete graph'
    for row in coverage_rows():
        case = row[0].removeprefix('application-')
        actual = case_observation(evidence/case, case)
        raw = evidence/row[5]
        assert json.loads(read_evidence(raw)) == actual, 'raw observation mismatch: ' + case
        expected = [row[0], row[3], str(actual['status']), actual['expected'], actual['observed'], release.digest(raw)]
        lines = read_evidence(evidence/row[4]).splitlines()
        assert len(lines) == 2 and lines[1].split('\t') == expected, 'decision mismatch: ' + case


def verification_tests(evidence):
    verify_evidence(evidence)
    defined = 'status: defined-unexecuted\n' in (REPO/'Caddy/manifests/serving-health-operation.yaml').read_text()
    def check(path):
        try:
            verify_evidence(path)
            accepted = True
        except (AssertionError, ValueError, KeyError, OSError):
            accepted = False
        if defined:
            env = dict(os.environ, CADDY_APPLICATION_QUALIFICATION_ROOT=str(path))
            result = subprocess.run(['/bin/bash', str(REPO/'Caddy/tests/deployable-successor-policy.sh'),
                                     '--authorization-ready'], env=env, capture_output=True)
            assert (result.returncode == 0) == accepted, 'policy/verifier disagreement'
        return accepted
    assert check(evidence)
    with tempfile.TemporaryDirectory(prefix='caddy-application-evidence-negative-') as temporary:
        trial = Path(temporary)/'evidence'
        shutil.copytree(evidence, trial, symlinks=True)
        mutations = [
            ('stale-graph', 'qualification-summary.json', lambda data: data.replace(b'"source_graph":', b'"stale_source_graph":')),
            ('wrong-command-status', 'success/outer.status', lambda data: b'1\n'),
            ('wrong-phase-status', 'success/runner-evidence/application-final-a.status', lambda data: b'1\n'),
            ('forged-observation', 'raw/application-success.json', lambda data: data.replace(b'"status": 0', b'"status": 1')),
            ('missing-command', 'success/ssh.jsonl', lambda data: b'\n'.join(line for line in data.splitlines() if b' application-expose ' not in line)+b'\n'),
            ('missing-decision', 'decisions/application-timeout.tsv', lambda data: b''),
        ]
        for name, relative, mutate in mutations:
            path = trial/relative; original = path.read_bytes()
            try:
                path.write_bytes(mutate(original))
                assert not check(trial), name
            finally:
                path.write_bytes(original)
            print('application_evidence_reject=' + name)
        path = trial/'success/outer.status'; original = path.read_bytes()
        path.unlink(); path.symlink_to(evidence/'success/outer.status')
        assert not check(trial), 'symlinked evidence'
        path.unlink(); path.write_bytes(original)
        print('application_evidence_reject=symlinked-evidence')
        directory = trial/'raw'; saved = trial/'raw-saved'
        directory.rename(saved); directory.symlink_to(saved, target_is_directory=True)
        assert not check(trial), 'symlinked evidence directory'
        directory.unlink(); saved.rename(directory)
        print('application_evidence_reject=symlinked-directory')
        path = trial/'success/runner-evidence/application-primary-a-readback.stdout'
        original = path.read_bytes(); path.unlink()
        assert not check(trial), 'missing causal readback'
        path.write_bytes(original)
        print('application_evidence_reject=missing-readback')
        assert check(trial), 'restored control'


def native_reload():
    env = dict(os.environ)
    env.update(line.split('=', 1) for line in Path('/etc/default/caddy-ha').read_text().splitlines())
    env['CADDY_CONFIG_ROOT'] = '/etc/caddy/current'
    return subprocess.run(['/usr/bin/caddy', 'reload', '--config', '/etc/caddy/current/Caddyfile'], env=env, capture_output=True).returncode


def switch(role):
    previous = release.active_role() if (release.fixture_root()/'active').exists() else None
    BASE_SWITCH(role)
    if previous != role and (release.fixture_root()/'native-started').exists():
        assert native_reload() == 0


release.switch = switch


def transfer():
    root = release.fixture_root()
    children = [p for p in Path('/var/lib/caddy-sync/outbound').iterdir() if p.name != 'baseline']
    assert len(children) == 1
    child = children[0]
    # This assertion independently catches publication before primary activation.
    assert os.readlink('/etc/caddy/current') == '/etc/caddy/releases/' + child.name
    assert json.loads((child/'release-manifest.json').read_text())['parent_revision'] == 'baseline'
    (root/'exposure.json').write_text(json.dumps({'revision': child.name, 'manifest': release.digest(child/'manifest.sha256'), 'primary': os.readlink('/etc/caddy/current')}))
    if os.environ['PRIMARY_CASE'] in ('timeout', 'trial-secondary-timeout'):
        return
    stage = root/'transport'
    subprocess.run(['cp', '-a', str(child), str(stage)], check=True)
    switch('node-b')
    if os.environ['PRIMARY_CASE'] == 'secondary-drift':
        base = Path('/etc/caddy/releases/baseline')
        shutil.copytree(base, base.with_name('drift'))
        release.manifest(base.with_name('drift'), 'drift', 'baseline')
        Path('/etc/caddy/current').unlink()
        Path('/etc/caddy/current').symlink_to('/etc/caddy/releases/drift')
        assert native_reload() == 0
    dest = Path('/var/lib/caddy-sync/incoming/node-a')/child.name
    subprocess.run(['cp', '-a', str(stage), str(dest)], check=True)
    subprocess.run(['chown', '-R', 'caddy-sync:caddy-sync', str(dest)], check=True)
    if os.environ['PRIMARY_CASE'] == 'trial-incomplete':
        (dest/'manifest.sha256').unlink()
        switch('node-a')
        return
    with (root/'transport.log').open('w') as log:
        finalized = subprocess.run(['/usr/sbin/runuser', '-u', 'caddy-sync', '--', '/usr/local/libexec/finalize-incoming-release-v2.sh', '--source-role', 'node-a'], stdout=log, stderr=log)
        reconciled = subprocess.run(['/bin/bash', '/usr/local/libexec/reconcile-release.sh'], stdout=log, stderr=log) if finalized.returncode == 0 else finalized
    (root/'transport.status').write_text(str(reconciled.returncode))
    switch('node-a')


def adapter(name, args):
    release.require_container()
    scenario = os.environ['PRIMARY_CASE']
    if name == 'ssh':
        command = ' '.join(args)
        rc = release.adapter(name, args)
        if ' application-primary ' in command:
            # At the actual return boundary no transport-visible child may exist.
            assert sorted(p.name for p in Path('/var/lib/caddy-sync/outbound').iterdir()) == ['baseline']
        if scenario == 'trial-success' and ' application-trial-restore node-a ' in command and rc == 0:
            words = shlex.split(command)
            index = words.index('application-trial-restore')
            arguments = words[index + 1:index + 5]
            late = subprocess.run(['/bin/bash', str(REPO/'Caddy/scripts/apply-serving-health-deployment.sh'),
                                   'application-expose', *arguments], capture_output=True, text=True)
            root = release.fixture_root()
            (root/'late-expose.status').write_text(str(late.returncode)+'\n')
            (root/'late-expose.stderr').write_text(late.stderr)
            assert late.returncode != 0
            assert not (Path('/var/lib/caddy-sync/outbound')/arguments[-1]).exists()
        if ' application-expose ' in command and rc == 0:
            transfer()
            if scenario == 'trial-lost-reply':
                return 255
        return rc
    if name == 'systemctl' and args[0] in ('start', 'stop') and 'caddy-sync-reconcile.path' in args:
        value = release.state()
        value['reconcile_path'] = args[0] == 'start'
        if 'caddy-lsyncd.service' in args:
            value['lsyncd'] = args[0] == 'start'
        release.save(value)
        release.event('systemctl ' + ' '.join(args))
        return 0
    if name == 'systemctl' and args == ['is-active', 'caddy-sync-health.timer']:
        print('active')
        return 0
    if name == 'systemctl' and args[:2] == ['show', 'caddy-sync-health.service']:
        now = int(time.monotonic()*1_000_000)
        fields = dict(InvocationID=hashlib.sha256(str(now).encode()).hexdigest()[:32],
                      ExecMainStartTimestampMonotonic=now-1000, ExecMainExitTimestampMonotonic=now,
                      Result='success', ExecMainStatus=0, ActiveState='inactive')
        wanted = next(a.split('=',1)[1].split(',') for a in args if a.startswith('--property='))
        print('\n'.join(k+'='+str(fields[k]) for k in wanted))
        return 0
    if name == 'systemctl' and args[:2] == ['show', 'caddy-sync-reconcile.service']:
        print(0)
        return 0
    if name == 'systemctl' and args[:2] == ['show', 'caddy-lsyncd.service'] and any(a.startswith('--property=') for a in args):
        fields = dict(MainPID=123, NRestarts=0, ActiveState='active', SubState='running')
        wanted = next(a.split('=',1)[1].split(',') for a in args if a.startswith('--property='))
        print('\n'.join(k+'='+str(fields[k]) for k in wanted))
        return 0
    if name == 'systemctl' and args == ['reload', 'caddy.service']:
        state = release.state()
        state['reloads'] += 1
        release.save(state)
        selected = Path(os.readlink('/etc/caddy/current')).name
        if release.active_role() == 'node-a' and scenario in ['primary-reload', 'recovery-failure']:
            if selected != 'baseline' or scenario == 'recovery-failure':
                return 1
        if scenario == 'trial-recovery-failure' and release.active_role() == 'node-b' and selected == 'baseline':
            return 1
        return native_reload()
    if name == 'curl':
        # Use the requested real family, destination, SNI, trust and selected route.
        assert '--resolve' in args and '-k' not in args
        env = dict(os.environ)
        selected = Path(os.readlink('/etc/caddy/current')).name
        endpoint = args[-1]
        marker = release.fixture_root()/'backend-fail'
        should_fail = selected != 'baseline' and endpoint.endswith('/dashboard') and (
            scenario == 'primary-http' and release.active_role() == 'node-a' or
            scenario == 'secondary-http' and release.active_role() == 'node-b')
        if should_fail:
            marker.touch()
        else:
            marker.unlink(missing_ok=True)
        rc = subprocess.run(['/usr/bin/curl', '--cacert', str(release.fixture_root()/'cert/fullchain.pem'), *args], env=env).returncode
        if scenario == 'exposure-tamper' and endpoint.endswith('/dashboard') and selected != 'baseline':
            prepared = Path('/var/lib/caddy-sync/prepared')/selected
            if prepared.exists():
                (prepared/'conf.d/20-uptime-kuma.caddy').write_text('tampered\n')
        return rc
    return release.adapter(name, args)


def serve_backend(port, root):
    from http.server import BaseHTTPRequestHandler, HTTPServer
    import socket
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(503 if (root/'backend-fail').exists() else 200)
            self.end_headers()
            self.wfile.write(b'fixture application\n')
        def log_message(self, *args):
            pass
    class DualStackServer(HTTPServer):
        address_family = socket.AF_INET6
    DualStackServer(('::', port), Handler).serve_forever()


def suite():
    definition_check()
    graph = source_graph()
    release.require_container()
    evidence = Path('/evidence')
    evidence.mkdir(exist_ok=True)
    for address in ['10.1.0.53/32', '10.1.0.54/32', '10.1.0.56/32', '10.1.3.75/32', 'fd36:5aa8:6971:1::53/128', 'fd36:5aa8:6971:1::54/128', 'fd36:5aa8:6971:1::56/128', 'fd36:5aa8:6971:1::75/128']:
        subprocess.run(['ip', 'address', 'add', address, 'dev', 'lo'], check=True)
    for scenario in CASES:
        root = evidence/scenario
        root.mkdir(mode=0o700)
        os.environ.update(CERT_APPLICATION='1', PRIMARY_CASE=scenario)
        env = release.setup(root)
        # Route every substitute through this native-HTTP adapter.
        for script in (root/'bin').iterdir():
            script.write_text('#!/bin/bash\nexec /usr/bin/python3 '+str(SOURCE)+' --adapter '+script.name+' "$@"\n')
            script.chmod(0o755)
        shutil.copy2(root/'bin/systemctl', '/usr/bin/systemctl')
        # Keep real configuration parsing/reload while avoiding production's
        # graceful delay in each synthetic node-view switch.
        for role in ['node-a', 'node-b']:
            for rev in ['baseline', 'tls-source']:
                config = root/'nodes'/role/'caddy/releases'/rev/'Caddyfile'
                config.write_text(config.read_text().replace('grace_period 10s', 'grace_period 100ms').replace('shutdown_delay 5s', 'shutdown_delay 0s'))
                release.manifest(config.parent, rev, '' if rev == 'tls-source' else 'tls-source')
        recipe = root/'inputs.tsv'
        baseline_hash = release.digest(root/'nodes/node-a/caddy/releases/baseline/manifest.sha256')
        rows = dict(line.split('\t') for line in recipe.read_text().splitlines()[1:])
        rows.update(baseline_manifest_sha256=baseline_hash, tls_source_manifest_sha256=baseline_hash)
        recipe.write_text('key\tvalue\n'+''.join(k+'\t'+v+'\n' for k,v in rows.items()))
        host, probe = ('webmin-j2-svpi3bmf.local.theama.co', 'session_login.cgi') if scenario == 'webmin-source' or scenario in TRIALS else ('uptime.local.theama.co', 'dashboard')
        recipe.write_text(recipe.read_text()+f'application_fqdn\t{host}\napplication_probe_path\t{probe}\napplication_http_status\t200\n')
        if scenario in TRIALS:
            recipe.write_text(recipe.read_text()+'application_trial_seconds\t660\napplication_diagnostic_seconds\t240\n')
        env.update(CADDY_CERTIFICATE_TEST_SCOPE='application', CADDY_CERTIFICATE_TEST_INPUTS_SHA256=release.digest(recipe), PRIMARY_CASE=scenario)
        os.environ.update(env)
        switch('node-a')
        native_env = dict(env, CADDY_CONFIG_ROOT='/etc/caddy/current', NODE_FQDN='pihole0.local.theama.co', NODE_IPV4='10.1.0.53', NODE_IPV6='fd36:5aa8:6971:1::53')
        children = []
        with (root/'native.log').open('wb') as native_log:
            children.append(subprocess.Popen(['/usr/bin/caddy', 'run', '--config', '/etc/caddy/current/Caddyfile'], env=native_env, stdout=native_log, stderr=native_log))
            for port in ['3001', '8080', '10000']:
                children.append(subprocess.Popen([sys.executable, str(SOURCE), '--backend', port, str(root)], stdout=native_log, stderr=native_log))
            try:
                for _ in range(50):
                    if subprocess.run(['/usr/bin/curl', '--silent', '--fail', 'http://127.0.0.1:2019/config/'], capture_output=True).returncode == 0:
                        break
                    time.sleep(.1)
                else:
                    raise AssertionError('native Caddy startup')
                (root/'native-started').touch()
                if scenario == 'publisher-boundaries':
                    publisher = REPO/'Caddy/scripts/publish-release-v2.sh'
                    source = '/etc/caddy/releases/baseline'
                    prepared = subprocess.run(['/bin/bash', str(publisher), '--source', source, '--node-role', 'node-a', '--prepare-only'], env=env, capture_output=True, text=True)
                    assert prepared.returncode == 0, prepared.stderr
                    candidates = [p for p in Path('/var/lib/caddy-sync/prepared').iterdir() if p.is_dir()]
                    assert len(candidates) == 1
                    candidate = candidates[0]
                    rejected = subprocess.run(['/bin/bash', str(publisher), '--node-role', 'node-a', '--expose', candidate.name, '--manifest-sha256', release.digest(candidate/'manifest.sha256')], env=env, capture_output=True, text=True)
                    assert rejected.returncode != 0 and 'primary_selected' in rejected.stderr
                    assert sorted(p.name for p in Path('/var/lib/caddy-sync/outbound').iterdir()) == ['baseline']
                    legacy = subprocess.run(['/bin/bash', str(publisher), '--source', source, '--node-role', 'node-a'], env=env, capture_output=True, text=True)
                    assert legacy.returncode == 0, legacy.stderr
                    for label, process in [('prepare', prepared), ('early-expose', rejected), ('legacy', legacy)]:
                        (root/('publisher-' + label + '.status')).write_text(str(process.returncode)+'\n')
                        (root/('publisher-' + label + '.stdout')).write_text(process.stdout)
                        (root/('publisher-' + label + '.stderr')).write_text(process.stderr)
                    published = [p for p in Path('/var/lib/caddy-sync/outbound').iterdir() if p.name != 'baseline']
                    assert len(published) == 1 and not (published[0]/'.complete').exists()
                    assert os.readlink('/etc/caddy/current') == source
                    assert json.loads((published[0]/'release-manifest.json').read_text())['parent_revision'] == 'baseline'
                    (root/'publisher.json').write_text(json.dumps({'prepared_status':prepared.returncode, 'early_exposure_status':rejected.returncode, 'legacy_status':legacy.returncode, 'early_exposure_stderr':rejected.stderr, 'published_revision':published[0].name, 'primary_selection':os.readlink('/etc/caddy/current')}, indent=2)+'\n')
                    print(scenario+': passed', flush=True)
                    continue
                if scenario in TRIALS and scenario != 'trial-timeout':
                    children.append(subprocess.Popen([sys.executable, str(SOURCE), '--finish-trial'], stdout=native_log, stderr=native_log))
                outer = REPO/'Caddy/scripts/run-serving-health-deployment-outer.sh'
                with (root/'outer.stdout').open('wb') as stdout, (root/'outer.stderr').open('wb') as stderr:
                    result = subprocess.run(['/bin/bash', str(outer), '--production-path-test'], env=env, stdout=stdout, stderr=stderr, timeout=180)
                (root/'outer.status').write_text(str(result.returncode)+'\n')
                expected = EXPECTED_STATUS[scenario]
                calls = [json.loads(line) for line in (root/'ssh.jsonl').read_text().splitlines()]
                runner_roots = sorted(Path('/tmp').glob('caddy-serving-health-outer-test.*'), key=lambda p:p.stat().st_mtime)
                shutil.copytree(runner_roots[-1], root/'runner-evidence')
                assert result.returncode == expected, (scenario, result.returncode, (root/'outer.stderr').read_text())
                if expected == 125:
                    import shlex
                    remote_paths = [token for call in calls for token in shlex.split(call['command']) if token.startswith('/tmp/caddy-serving-health-')]
                    assert any(Path(token).exists() for token in remote_paths)
                else:
                    for call in calls:
                        import shlex
                        for token in shlex.split(call['command']):
                            if token.startswith('/tmp/caddy-serving-health-'):
                                assert not Path(token).exists(), token
                (root/'cleanup.json').write_text(json.dumps({'staging_retained': expected == 125})+'\n')
                observed = {}
                for role in ['node-a', 'node-b']:
                    switch(role)
                    selected = Path(os.readlink('/etc/caddy/current')).name
                    expected_selection = 'drift' if role == 'node-b' and scenario == 'secondary-drift' else 'baseline' if scenario in ['primary-reload', 'primary-http', 'recovery-failure', 'exposure-tamper'] or role == 'node-b' and scenario in ['timeout', 'secondary-http', 'exposure-tamper'] else None
                    if scenario in TRIALS:
                        expected_selection = 'baseline' if expected != 125 or scenario == 'trial-recovery-failure' and role == 'node-b' or scenario == 'trial-incomplete' and role == 'node-b' else None
                    if expected_selection:
                        assert selected == expected_selection, (scenario, role, selected)
                    else:
                        assert selected != 'baseline'
                        assert Path('/etc/caddy/current/tls/fullchain.pem').read_bytes() == Path('/etc/caddy/releases/baseline/tls/fullchain.pem').read_bytes()
                    state = release.state()
                    assert state['checker_runs'] == 0
                    observed[role] = dict(selection=selected, reloads=state['reloads'], checker_runs=state['checker_runs'])
                if scenario in ('success', 'webmin-source'):
                    assert observed['node-a']['selection'] == observed['node-b']['selection']
                if scenario in ['primary-reload', 'primary-http', 'recovery-failure', 'exposure-tamper']:
                    assert not (root/'exposure.json').exists()
                (root/'observed.json').write_text(json.dumps({'scenario':scenario, 'status':result.returncode, 'nodes':observed}, indent=2)+'\n')
                print(scenario+': passed', flush=True)
            finally:
                (root/'native-started').unlink(missing_ok=True)
                for child in children:
                    child.terminate()
                for child in children:
                    try:
                        child.wait(timeout=20)
                    except subprocess.TimeoutExpired:
                        child.kill(); child.wait()
                if (root/'active').exists():
                    role = release.active_role()
                    for name, path in release.VIEWS.items():
                        if path.exists():
                            release.move_tree(path, root/'nodes'/role/name)
                    (root/'active').unlink()
    write_qualification(evidence, graph)
    verify_evidence(evidence)


if __name__ == '__main__':
    if sys.argv[1:2] == ['--adapter']:
        raise SystemExit(adapter(sys.argv[2], sys.argv[3:]))
    elif sys.argv[1:] == ['--finish-trial']:
        # A separate parent produces only the finish signal after actual readiness.
        start = time.time()
        while time.time() - start < 120:
            for path in Path('/tmp').glob('caddy-serving-health-outer-test.*/application-trial-ready.tsv'):
                if path.stat().st_mtime >= start:
                    finish = path.with_name('application-trial-finish.tsv')
                    with finish.open('x') as stream:
                        os.chmod(finish, 0o600)
                        stream.write(path.read_text().strip()+'\tcomplete\n')
                    raise SystemExit(0)
            time.sleep(.05)
        raise SystemExit(1)
    elif sys.argv[1:2] == ['--backend']:
        serve_backend(int(sys.argv[2]), Path(sys.argv[3]))
    elif sys.argv[1:] == ['--payload-tests']:
        probe_diagnostic_tests()
        monitor_contract_tests()
        budget_contract_tests()
        payload_tests()
    elif sys.argv[1:] == ['--definition-check']:
        definition_check()
    elif sys.argv[1:2] == ['--verify-evidence'] and len(sys.argv) == 3:
        verify_evidence(Path(sys.argv[2]))
    elif sys.argv[1:2] == ['--verification-tests'] and len(sys.argv) == 3:
        verification_tests(Path(sys.argv[2]))
    else:
        assert not sys.argv[1:], 'unknown fixture arguments'
        suite()
