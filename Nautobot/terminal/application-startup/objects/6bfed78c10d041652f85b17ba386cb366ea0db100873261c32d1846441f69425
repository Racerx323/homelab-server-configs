#!/usr/bin/env python3
"""Execute frozen, bounded startup checks; retain decisions, never raw output."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import time
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('bounded', Path(__file__).with_name('run-restic-repository-preflight.py'))
bounded = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bounded)
FAILURE_CODES = frozenset(['boot', 'bootstrap_secret', 'cgroup_path', 'command_or_output_boundary', 'container_state', 'credential_metadata', 'cursor_unavailable', 'effective_memory', 'http', 'image', 'invocation', 'kernel_message', 'memory_config', 'mode', 'native_failure', 'native_receipt_count', 'native_receipt_shape', 'network', 'observation_short', 'oom', 'pid', 'private_ports', 'process_changed', 'root_required', 'runtime_probe_failed', 'service_state', 'static_type', 'storage_event', 'swap', 'unexpected_runtime_failure', 'unprivileged_readonly'])
GROUPS = {
    'native_configuration_and_migrations', 'health_and_static_http',
    'administrator_login_logout', 'allowed_denied_dual_stack_access',
    'worker_scheduler_and_representative_job', 'resource_and_secret_boundaries',
    'cleanup_and_storage_observation',
}


def validate(contract):
    if set(contract) != {'schema_version', 'checks'} or contract['schema_version'] != 1:
        raise ValueError('contract_shape')
    checks = contract['checks']
    if not isinstance(checks, list) or not 7 <= len(checks) <= 64:
        raise ValueError('check_count')
    names = set()
    groups = set()
    total = 0
    for check in checks:
        if set(check) != {'id', 'group', 'argv', 'timeout_seconds', 'expected'}:
            raise ValueError('check_shape')
        name = check['id']
        if not isinstance(name, str) or not re.fullmatch('[a-z][a-z0-9_]{0,79}', name) or name in names:
            raise ValueError('check_identity')
        names.add(name)
        if check['group'] not in GROUPS:
            raise ValueError('check_group')
        groups.add(check['group'])
        argv = check['argv']
        if (not isinstance(argv, list) or not argv or len(argv) > 64
                or not all(isinstance(x, str) and x and len(x) <= 4096 and not any(ord(c) < 32 for c in x) for x in argv)
                or not argv[0].startswith('/')):
            raise ValueError('check_command')
        timeout = check['timeout_seconds']
        if type(timeout) is not int or not 1 <= timeout <= 300:
            raise ValueError('check_timeout')
        total += timeout
        expected = check['expected']
        if (not isinstance(expected, dict) or not expected
                or not all(isinstance(k, str) and re.fullmatch('[a-z][a-z0-9_]*', k) for k in expected)
                or any(not isinstance(v, (str, int, bool)) or len(str(v)) > 256 for v in expected.values())):
            raise ValueError('check_expectations')
    if groups != GROUPS or total > 1200:
        raise ValueError('coverage_or_deadline')
    return checks


def run(argv, timeout):
    bounded.COMMAND_TIMEOUT_SECONDS = timeout
    return bounded.drain_process(tuple(argv), bounded.minimal_environment())


def collect(contract, runner=run):
    checks = validate(contract)  # Validate everything before the first command.
    result = {'schema_version': 1, 'accepted': False, 'checks': []}
    for check in checks:
        started = time.monotonic()
        row = {'id': check['id'], 'group': check['group'], 'passed': False}
        try:
            rc, out, err, truncated = runner(check['argv'], check['timeout_seconds'])
            row.update(exit_status=rc, output_truncated=bool(truncated))
            if rc != 0 or truncated or len(out) > 65536 or len(err) > 65536:
                raise ValueError('command_failed_or_output_limit')
            # One JSON object only. Each field is produced by a live probe, not
            # supplied via Ansible extra-vars or a previous evidence file.
            observed = json.loads(out)
            if not isinstance(observed, dict):
                raise ValueError('invalid_receipt')
            if observed.get('error_class') in FAILURE_CODES:
                row['error_class'] = observed['error_class']
            row['matches'] = {key: type(observed.get(key)) is type(value) and observed.get(key) == value
                              for key, value in check['expected'].items()}
            row['passed'] = all(row['matches'].values())
        except Exception:
            row['error'] = 'probe_failed'
        row['duration_seconds'] = round(time.monotonic() - started, 3)
        result['checks'].append(row)
        if not row['passed']:
            return result  # Stop further probes; Ansible owns service recovery.
    result['accepted'] = True
    return result


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('contract', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = collect(json.loads(args.contract.read_text()))
    # Refuse reuse of a previous acceptance result.
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2)
    return 0 if result['accepted'] else 69


if __name__ == '__main__':
    raise SystemExit(main())
