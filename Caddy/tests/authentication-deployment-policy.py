#!/usr/bin/env python3
"""Bind the primary activation operation to current sources and causal container evidence."""
import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
MANIFEST = 'Caddy/manifests/authentication-deployment-inputs.tsv'
OUTER = 'Caddy/scripts/run-serving-health-deployment-outer.sh'
OPERATION = 'Caddy/manifests/serving-health-operation.yaml'
TRANSACTION = 'Caddy/scripts/apply-serving-health-deployment.sh'
COVERAGE = 'Caddy/manifests/deployable-successor-coverage.tsv'
CASES = {'preflight-ipv6': 1, 'preflight-tls': 1, 'preflight-http': 1,
         'preflight-baseline-changed': 1, 'preflight-baseline-missing': 1, 'preflight-baseline-extra': 1,
         'preflight-service': 1, 'preflight-publication': 1, 'preflight-interrupt': 125, 'success': 0, 'login-failure': 1, 'shared-login-failure': 1, 'restore-failure': 125,
         'interrupt-helper': 125, 'evidence-failure': 125, 'dns-failure': 1,
         'activate-reply-failure': 1, 'reconcile-failure': 1, 'reordered-evidence': 1}
BASELINE_MONITOR = '803f6d510302fe5ad3ee7b59eeff1f719a4b2ea091c6c908054b0eecffce5d51'
CANDIDATE_MONITOR = '0aa489aaaeee7e32635a63e99bbfb5750dd591f5142969c5cdc0274613b985ab'
HEADER = ['scenario', 'phase', 'entrypoint', 'expectation', 'decision-evidence', 'raw-evidence']
# Distinct transaction decisions retain the real phase status and streams.
PHASES = {'authentication-mutation': ('success', 'auth-helper-install', 0),
          'authentication-acceptance': ('success', 'auth-candidate-accept-node-a', 0),
          'authentication-rollback-failure': ('restore-failure', 'auth-restore-release', 125)}


def read(path, mode=None, limit=1048576):
    info = path.lstat()
    assert stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_size <= limit, path
    assert path.resolve() == path.absolute(), path
    if mode is not None:
        assert stat.S_IMODE(info.st_mode) == mode and info.st_uid == os.getuid(), path
    data = path.read_bytes()
    assert not re.search(rb'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', data), path
    return data


def digest(data):
    return hashlib.sha256(data).hexdigest()


def graph():
    manifest = read(ROOT / MANIFEST).decode()
    rows = list(csv.reader(manifest.splitlines(), delimiter='\t'))
    assert rows.pop(0) == ['sha256', 'path']
    hashes = {MANIFEST: digest(manifest.encode())}
    for row in rows:
        assert len(row) == 2
        sha, name = row
        assert re.fullmatch(r'[0-9a-f]{64}', sha) and re.fullmatch(r'Caddy/[A-Za-z0-9_./-]+', name)
        assert name not in hashes and '..' not in Path(name).parts
        assert digest(read(ROOT / name)) == sha, f'input drift: {name}'
        hashes[name] = sha
    outer = read(ROOT / OUTER).decode()
    assert f'readonly authentication_policy_inputs_sha256={hashes[MANIFEST]}\n' in outer
    for name, variable in ((TRANSACTION, 'transaction'), (OPERATION, 'operation')):
        sha = digest(read(ROOT / name))
        assert f'readonly {variable}_sha256={sha}\n' in outer
        hashes[name] = sha
    hashes[OUTER] = digest(outer.encode())
    catalog = outer.split("cat <<'INPUTS'\n", 1)[1].split('\nINPUTS', 1)[0]
    for row in catalog.splitlines():
        sha, name = row.split()
        assert digest(read(ROOT / name)) == sha
        hashes[name] = sha
    return hashes


def coverage_rows():
    rows = []
    for scenario, status in CASES.items():
        name = 'authentication-' + scenario
        rows.append([name, 'pre-mutation' if scenario.startswith('preflight-') else 'accepted-path', 'outer', 'accept' if status == 0 else 'reject',
                     f'decisions/{name}.tsv', f'raw/{name}.json'])
    for name, (_, _, status) in PHASES.items():
        rows.append([name, 'accepted-path', 'transaction', 'accept' if status == 0 else 'reject',
                     f'decisions/{name}.tsv', f'raw/{name}.json'])
    return rows


def definition():
    result = graph()
    operation = read(ROOT / OPERATION).decode()
    for text in ('scope: pihole-authentication-node-a', 'status: defined-unexecuted',
                 '  success: both-nodes-fixed-node-a-and-shared-login-accepted',
                 '  standby: preserve-accepted-release-and-monitor',
                 '  workstation_connectivity: verified-node-a-and-shared-ipv4-ipv6-before-upload',
                 '  project: homelab-dev', '  config: prd_caddy', '  key: PIHOLE_NODE_B_WEB_PASSWORD'):
        assert text + '\n' in operation, text
    assert list(csv.reader(read(ROOT / COVERAGE).decode().splitlines(), delimiter='\t')) == [HEADER, *coverage_rows()]
    return result


def export_case(case_root, scenario):
    """Called only after the fixture independently checks actual execution effects."""
    target = case_root.parent
    for dirname in ('decisions', 'raw'):
        (target / dirname).mkdir(mode=0o700, exist_ok=True)
    files = {p.name: digest(read(p, 0o600)) for p in case_root.iterdir() if p.is_file()}
    state = json.loads(read(case_root / 'decision.json', 0o600))
    for row in coverage_rows():
        name, _, entrypoint, expectation, decision_name, raw_name = row
        if entrypoint == 'outer':
            if name != 'authentication-' + scenario:
                continue
            status = int(read(case_root / 'outer.status', 0o600))
            expected = str(CASES[scenario])
        else:
            case, phase, expected_status = PHASES[name]
            if case != scenario:
                continue
            status = int(read(case_root / (phase + '.status'), 0o600))
            expected = str(expected_status)
            assert status == expected_status, (phase, status)
        raw = json.dumps({'case': scenario, 'files': files, 'state': state}, sort_keys=True) + '\n'
        (target / raw_name).write_text(raw)
        (target / raw_name).chmod(0o600)
        decision = 'scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n'
        decision += '\t'.join((name, expectation, str(status), expected, str(status), digest(raw.encode()))) + '\n'
        (target / decision_name).write_text(decision)
        (target / decision_name).chmod(0o600)


def evidence(directory):
    expected_graph = definition()
    base = Path(directory)
    assert base.is_absolute() and (str(base).startswith('/tmp/') or
                                   (base == Path('/evidence') and Path('/run/.containerenv').exists()
                                    and os.geteuid() == 0 and os.environ.get('CADDY_VALIDATION_CONTAINER') == '1'))
    for path in (base, base / 'decisions', base / 'raw'):
        assert path.resolve() == path and path.is_dir() and stat.S_IMODE(path.stat().st_mode) == 0o700
        assert path.stat().st_uid == os.getuid()
    spec = importlib.util.spec_from_file_location('outer_fixture', ROOT / 'Caddy/tests/authentication-outer-regression.py')
    fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture)
    for row in coverage_rows():
        name, _, entrypoint, expectation, decision_name, raw_name = row
        raw_bytes = read(base / raw_name, 0o600)
        raw = json.loads(raw_bytes)
        scenario = name.removeprefix('authentication-') if entrypoint == 'outer' else PHASES[name][0]
        assert raw['case'] == scenario
        case_root = base / scenario
        assert case_root.resolve() == case_root and stat.S_IMODE(case_root.stat().st_mode) == 0o700
        assert set(raw['files']) == {p.name for p in case_root.iterdir()}
        for filename, sha in raw['files'].items():
            assert Path(filename).name == filename
            assert digest(read(case_root / filename, 0o600)) == sha, filename
        state = json.loads(read(case_root / 'decision.json', 0o600))
        assert raw['state'] == state and state['graph'] == expected_graph, 'stale qualification graph'
        expected_status = CASES[scenario]
        assert state['expected_status'] == state['observed_status'] == expected_status
        assert int(read(case_root / 'outer.status', 0o600)) == expected_status
        assert state['observer_residue'] == 0
        assert re.fullmatch(r'[0-9]{8}T[0-9]{6}Z-[0-9a-f-]{36}', state['node_b_revision'])
        assert state['publications'] == [state['node_b_revision']]
        assert state['node_b_monitor_sha256'] == CANDIDATE_MONITOR
        retained = scenario in ('success', 'evidence-failure')
        restored = expected_status == 1 or scenario == 'preflight-interrupt'
        assert state['node_a_revision'] == (state['node_b_revision'] if retained else 'fixture-baseline')
        assert state['node_a_monitor_sha256'] == (BASELINE_MONITOR if restored else CANDIDATE_MONITOR)
        assert digest(read(case_root / 'external-calls.jsonl', 0o600)) == state['external_calls_sha256']
        fixture.verify_calls(case_root / 'external-calls.jsonl', case_root, scenario)
        phase_status = expected_status if entrypoint == 'outer' else int(read(case_root / (PHASES[name][1] + '.status'), 0o600))
        wanted = expected_status if entrypoint == 'outer' else PHASES[name][2]
        assert phase_status == wanted
        decision = list(csv.reader(read(base / decision_name, 0o600, 4096).decode().splitlines(), delimiter='\t'))
        assert decision == [['scenario', 'expectation', 'status', 'expected', 'observed', 'raw-sha256'],
                            [name, expectation, str(phase_status), str(wanted), str(phase_status), digest(raw_bytes)]]
    print('authentication_qualification_current_graph_and_causal_evidence=true')


if __name__ == '__main__':
    try:
        if sys.argv[1:] == ['--graph-check']:
            definition()
            print('authentication_deployment_graph_valid=true')
        elif len(sys.argv) == 3 and sys.argv[1] == '--evidence-check':
            evidence(sys.argv[2])
        else:
            raise ValueError('expected --graph-check or --evidence-check /tmp/EVIDENCE')
    except (AssertionError, OSError, ValueError, KeyError, IndexError) as error:
        print(f'authentication_deployment_policy_rejected: {error}', file=sys.stderr)
        sys.exit(1)
