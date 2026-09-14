#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=deployable_successor_policy_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly policy=$test_directory/deployable-successor-policy.sh
root=$(mktemp -d /tmp/caddy-successor-regression.XXXXXX)
readonly root
trap 'rm -rf -- "$root"' EXIT INT TERM

check() {
    local label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$label" >&2
    return 1
}

run_fixture() {
    CADDY_DEPLOYABLE_SUCCESSOR_TEST_MODE=1 \
        CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT=$root \
        /bin/bash "$policy" --check >/dev/null 2>&1
}

fixture_rejected() {
    ! run_fixture
}

install -d -m 0700 "$root/Caddy/manifests" "$root/Caddy/scripts"
install -m 0600 \
    "$repository_root/Caddy/manifests/accepted-live-artifacts.tsv" \
    "$repository_root/Caddy/manifests/current-live-state.tsv" \
    "$repository_root/Caddy/manifests/production-artifacts.tsv" \
    "$repository_root/Caddy/manifests/runtime-production.tsv" \
    "$root/Caddy/manifests/"
install -m 0700 \
    "$repository_root/Caddy/scripts/apply-serving-health-deployment.sh" \
    "$repository_root/Caddy/scripts/run-serving-health-deployment-outer.sh" \
    "$root/Caddy/scripts/"
awk '/^scope:/ { exit } { print }' "$repository_root/Caddy/manifests/serving-health-operation.yaml" |
    sed -e 's/^action:.*/action: none/' -e 's/^status:.*/status: inactive/' >"$root/inactive-operation.yaml"
printf 'live_execution: no-operation-defined\n' >>"$root/inactive-operation.yaml"
install -m 0600 "$root/inactive-operation.yaml" "$root/Caddy/manifests/serving-health-operation.yaml"
inactive_hash=$(sha256sum "$root/inactive-operation.yaml" | awk '{print $1}')
sed -i "s/^readonly operation_sha256=.*/readonly operation_sha256=$inactive_hash/" "$root/Caddy/scripts/run-serving-health-deployment-outer.sh"
install -m 0700 "$root/Caddy/scripts/run-serving-health-deployment-outer.sh" "$root/inactive-outer.sh"

printf '%s\n' \
    $'scenario\tphase\tentrypoint\texpectation\tdecision-evidence\traw-evidence' \
    >"$root/Caddy/manifests/deployable-successor-coverage.tsv"
state_hash=$(sha256sum "$root/Caddy/manifests/current-live-state.tsv" | awk '{ print $1 }')
readonly state_hash
printf '%s\n' \
    $'schema_version\tstatus\taction\toperation_spec\ttransaction\touter_runner\tstate_contract\tstate_sha256\tcoverage\tregression' \
    "2"$'\t'"none"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"Caddy/manifests/current-live-state.tsv"$'\t'"$state_hash"$'\t'"Caddy/manifests/deployable-successor-coverage.tsv"$'\t'"-" \
    >"$root/Caddy/manifests/deployable-successor.tsv"

check clean_registry_accepts run_fixture || exit 1

sed -i 's/^action: none$/action: stale/' \
    "$root/Caddy/manifests/serving-health-operation.yaml"
check inactive_operation_rejected fixture_rejected || exit 1
install -m 0600 "$root/inactive-operation.yaml" \
    "$root/Caddy/manifests/serving-health-operation.yaml"

sed -i 's/^readonly operation_sha256=/readonly operation_sha256=0/' \
    "$root/Caddy/scripts/run-serving-health-deployment-outer.sh"
check inactive_operation_pin_rejected fixture_rejected || exit 1
install -m 0700 "$root/inactive-outer.sh" \
    "$root/Caddy/scripts/run-serving-health-deployment-outer.sh"

sed -i '2s/^2/1/' "$root/Caddy/manifests/deployable-successor.tsv"
check obsolete_schema_rejected fixture_rejected || exit 1
sed -i '2s/^1/2/' "$root/Caddy/manifests/deployable-successor.tsv"

sed -i '2s/\tnone\t-\t-/\tdefined\t35ag\tCaddy\/manifests\/action35ag.yaml/' \
    "$root/Caddy/manifests/deployable-successor.tsv"
check action_numbered_spec_rejected fixture_rejected || exit 1

check neutral_transaction_required \
    grep -Fq 'Caddy/scripts/apply-serving-health-deployment.sh' "$policy" || exit 1
check neutral_outer_required \
    grep -Fq 'Caddy/scripts/run-serving-health-deployment-outer.sh' "$policy" || exit 1
check operation_hash_required grep -Fq 'readonly operation_sha256=' "$policy" || exit 1
check state_equivalence_contract_required \
    grep -Fq 'protocol-namespace-state-equivalence' "$policy" || exit 1
check protected_empty_state_required \
    grep -Fq 'protected-empty-directory' "$policy" || exit 1
check proportional_coverage \
    grep -Fq 'Extra bounded evidence is allowed' "$policy" || exit 1
forbidden_generator=successor_regression_write_entrypoint
check fabricated_entrypoint_absent \
    test -z "$(grep -F "$forbidden_generator()" "$0" || :)" || exit 1
check neutral_real_entrypoint_policy \
    grep -Fq 'successor_policy_neutral_entrypoints_are_real' "$policy" || exit 1
check fabricated_availability_policy \
    grep -Fq 'availability\.tsv' "$policy" || exit 1
check fabricated_journal_policy \
    grep -Fq 'exercise_.*_journal\.stdout' "$policy" || exit 1
# shellcheck disable=SC2016
check mode_dispatch_policy \
    grep -Fq 'case "$mode" in' "$policy" || exit 1

# Exercise the authentication graph checker against actual copied input bytes.
if awk -F '\t' 'NR==2 {exit($2 != "defined")}' "$repository_root/Caddy/manifests/deployable-successor.tsv" &&
    grep -Fxq 'scope: pihole-authentication-node-b' "$repository_root/Caddy/manifests/serving-health-operation.yaml"; then
    python3 - "$repository_root" "$root" <<'PYTEST'
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
repo, temp = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location('policy', repo / 'Caddy/tests/authentication-deployment-policy.py')
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)
fixture = temp / 'authentication-graph'
for name in policy.graph():
    target = fixture / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(repo / name, target)
checker = fixture / 'Caddy/tests/authentication-deployment-policy.py'
def status():
    return subprocess.run([sys.executable, str(checker), '--graph-check'],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
assert status() == 0
for name in ('Caddy/manifests/deployable-successor-coverage.tsv',
             'Caddy/manifests/serving-health-operation.yaml',
             'Caddy/scripts/apply-serving-health-deployment.sh',
             'Caddy/scripts/validate-pihole-authentication.py'):
    path = fixture / name
    original = path.read_bytes()
    path.write_bytes(original + b'\n# unqualified change\n')
    assert status() != 0, name
    path.write_bytes(original)
path = fixture / 'Caddy/scripts/check-pihole-web-health.sh'
original = path.read_bytes()
path.unlink()
assert status() != 0
path.symlink_to(repo / 'Caddy/scripts/check-pihole-web-health.sh')
assert status() != 0
path.unlink()
path.write_bytes(original)
link = temp / 'hardlinked-input'
os.link(path, link)
assert status() != 0
link.unlink()
assert status() == 0
print('authentication_graph_seven_adjacent_input_changes_rejected=true')
PYTEST
fi

if [[ -n "${CADDY_AUTH_QUALIFICATION_EVIDENCE:-}" ]]; then
    python3 - "$repository_root" "$root" "$CADDY_AUTH_QUALIFICATION_EVIDENCE" <<'PYTEST'
import hashlib
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
repo, temp, original = map(Path, sys.argv[1:])
fixture = temp / 'qualification'
checker = repo / 'Caddy/tests/authentication-deployment-policy.py'
def status():
    return subprocess.run([sys.executable, str(checker), '--evidence-check', str(fixture)],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
for case in ('unchanged', 'missing', 'unsafe-mode', 'symlink', 'changed-stream', 'stale-graph', 'rehashed-duplicate-command'):
    shutil.copytree(original, fixture)
    path = fixture / 'success/outer.status'
    if case == 'missing':
        path.unlink()
    elif case == 'unsafe-mode':
        path.chmod(0o644)
    elif case == 'symlink':
        path.unlink()
        path.symlink_to(original / 'success/outer.status')
    elif case == 'changed-stream':
        path.write_text('125\n')
    elif case in ('stale-graph', 'rehashed-duplicate-command'):
        state_path = fixture / 'success/decision.json'
        state = json.loads(state_path.read_text())
        if case == 'stale-graph':
            state['graph']['Caddy/scripts/run-serving-health-deployment-outer.sh'] = '0' * 64
        else:
            calls = fixture / 'success/external-calls.jsonl'
            rows = calls.read_text().splitlines()
            duplicate = next(row for row in rows if json.loads(row)['command'] == 'ssh'
                             and shlex.split(json.loads(row)['args'][1])[8:10] == ['auth-release-accept', 'node-b'])
            calls.write_text('\n'.join([*rows, duplicate]) + '\n')
            state['external_calls_sha256'] = hashlib.sha256(calls.read_bytes()).hexdigest()
        state_path.write_text(json.dumps(state, sort_keys=True) + '\n')
        # Rehash the changed evidence too: causal verification, not merely the
        # raw hash comparison, must reject the modified command/state claim.
        files = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (fixture / 'success').iterdir()}
        for raw_path in (fixture / 'raw').iterdir():
            raw = json.loads(raw_path.read_text())
            if raw['case'] != 'success':
                continue
            raw.update(files=files, state=state)
            raw_path.write_text(json.dumps(raw, sort_keys=True) + '\n')
            decision = fixture / 'decisions' / (raw_path.stem + '.tsv')
            header, row = decision.read_text().splitlines()
            fields = row.split('\t')
            fields[-1] = hashlib.sha256(raw_path.read_bytes()).hexdigest()
            decision.write_text(header + '\n' + '\t'.join(fields) + '\n')
    assert (status() == 0) == (case == 'unchanged'), case
    shutil.rmtree(fixture)
print('authentication_evidence_six_adjacent_changes_rejected=true')
PYTEST
fi

if [[ -f "$repository_root/Caddy/manifests/serving-health-terminal-result.yaml" ]]; then
    install -m 0600 "$repository_root/Caddy/manifests/deployment-streams.tsv" \
        "$repository_root/Caddy/manifests/serving-health-terminal-result.yaml" \
        "$repository_root/Caddy/manifests/serving-health-operation.yaml" \
        "$repository_root/Caddy/manifests/deployable-successor.tsv" "$root/Caddy/manifests/"
    install -m 0700 "$repository_root/Caddy/scripts/run-serving-health-deployment-outer.sh" "$root/Caddy/scripts/"
    check retained_terminal_definition_accepts run_fixture || exit 1
    jq '.outer_sha256 = ("0" * 64)' "$root/Caddy/manifests/serving-health-terminal-result.yaml" >"$root/altered-terminal"
    mv "$root/altered-terminal" "$root/Caddy/manifests/serving-health-terminal-result.yaml"
    check terminal_identity_drift_rejected fixture_rejected || exit 1
    install -m 0600 "$repository_root/Caddy/manifests/serving-health-terminal-result.yaml" "$root/Caddy/manifests/"
    jq '.result = "accepted"' "$root/Caddy/manifests/serving-health-terminal-result.yaml" >"$root/altered-terminal"
    mv "$root/altered-terminal" "$root/Caddy/manifests/serving-health-terminal-result.yaml"
    check terminal_result_mismatch_rejected fixture_rejected || exit 1
fi

printf '%s_complete=true\n' "$prefix"
