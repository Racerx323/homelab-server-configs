#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly inspector="$caddy_root/scripts/inspect-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh"
readonly runner="$caddy_root/scripts/run-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh"
readonly installer="$caddy_root/scripts/install-node-b-stderr-safe-finalizer-action17u.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_directory/run-source-test-in-context.sh"
readonly inspector_sha256=38df35f89dc5732320e84ef9ec90ff8b0d5d1cee72d342b025c743c74a0d4210
readonly runner_sha256=facbaeda449522296cb90febf8fc0cbe4472129a35f960f9415e5aa5fb248ea2
readonly expected_manifest_sha256=a992c2ff9bdfde76770ddae910dedfc2a8bbdf6ad25de909ec5cbeacda31d70b
readonly observed_manifest_sha256=8b7ee379963bec0932dece5b11dd602efba33fe5d76a6e281c4db0c93b60dfbf

report_error() {
    local error_line=$1
    local error_status=$2
    printf 'action_17u_a_regression_failure_line=%s\n' "$error_line" >&2
    printf 'action_17u_a_regression_failure_status=%s\n' "$error_status" >&2
}
trap 'report_error "$LINENO" "$?"' ERR

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

write_fixture() {
    local fixture_path=$1
    local fixture_mode=$2
    local label value count=0 failed=0 first=none
    local state_hash=1111111111111111111111111111111111111111111111111111111111111111
    {
        while IFS= read -r label; do
            value=true
            if [[ "$fixture_mode" = mismatch &&
                ("$label" = backup_manifest_hash_exact || "$label" = backup_manifest_action_exact) ]]; then
                value=false
                failed=$((failed + 1))
                [[ "$first" != none ]] || first=$label
            fi
            printf 'action_17u_a_assertion_%s=%s\n' "$label" "$value"
            count=$((count + 1))
        done < <("$inspector" --expected-checks)
        printf '%s\n' \
            "action_17u_a_assertion_count=$count" \
            "action_17u_a_failed_assertion_count=$failed" \
            "action_17u_a_first_failure=$first" \
            action_17u_a_value_finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d \
            action_17u_a_value_backup_path=/var/backups/caddy-ha/action17u-node-b-stderr-safe-finalizer.N9uEhC \
            "action_17u_a_value_expected_backup_manifest_sha256=$expected_manifest_sha256" \
            "action_17u_a_value_observed_backup_manifest_sha256=$([[ "$fixture_mode" = mismatch ]] && printf %s "$observed_manifest_sha256" || printf %s "$expected_manifest_sha256")" \
            action_17u_a_value_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e \
            action_17u_a_value_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8 \
            "action_17u_a_value_before_state_sha256=$state_hash" \
            "action_17u_a_value_after_state_sha256=$state_hash" \
            action_17u_a_finalizer_invoked=false action_17u_a_release_mutated=false \
            action_17u_a_marker_mutated=false action_17u_a_service_mutations=false \
            action_17u_a_lsyncd_reconciliation_activation=false \
            action_17u_a_filesystem_mutations=false action_17u_a_persistent_mutations=false
        [[ "$fixture_mode" != valid ]] || printf 'action_17u_a_node_b_read_only_postinstall_complete=true\n'
    } >"$fixture_path"
}

write_fake_ssh() {
    local fake_path=$1
    # Variables are confined to the intercepted regression subprocess.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"$ACTION17U_A_CAPTURED_INSPECTOR"' \
        'printf "%s\n" "$*" >"$ACTION17U_A_ARGUMENTS"' \
        'cat "$ACTION17U_A_FIXTURE"' \
        'exit "$ACTION17U_A_STATUS"' >"$fake_path"
    chmod 0755 "$fake_path"
}

run_case() {
    local case_runner=$1
    local case_root=$2
    local suffix=$3
    local fixture=$4
    local status=$5
    if ACTION17U_A_CAPTURED_INSPECTOR="$case_root/$suffix.inspector" \
        ACTION17U_A_ARGUMENTS="$case_root/$suffix.arguments" \
        ACTION17U_A_FIXTURE="$fixture" ACTION17U_A_STATUS="$status" \
        "$case_runner" >"$case_root/$suffix.out" 2>"$case_root/$suffix.err"; then
        observed_status=0
    else
        observed_status=$?
    fi
}

run_production_regression() {
    local case_root=$1
    local case_runner
    local fake_bin="$case_root/bin"
    case_runner="$case_root/Caddy/scripts/$(basename "$runner")"
    install -d -m 0700 "$fake_bin" "$case_root/Caddy/scripts" "$case_root/Caddy/tests"
    cp -- "$runner" "$inspector" "$case_root/Caddy/scripts/"
    cp -- "$collision_checker" "$case_root/Caddy/tests/"
    chmod 0755 "$case_root/Caddy/scripts/"* "$case_root/Caddy/tests/"*
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$fake_bin:/usr/bin:/bin|" "$case_runner"
    write_fake_ssh "$fake_bin/ssh"
    write_fixture "$case_root/valid.fixture" valid
    write_fixture "$case_root/mismatch.fixture" mismatch

    run_case "$case_runner" "$case_root" valid "$case_root/valid.fixture" 0
    [[ "$observed_status" -eq 0 ]]
    grep -Fxq action_17u_a_runner_acceptance=true "$case_root/valid.out"
    grep -Fq 'cd / && sudo -n /bin/bash -s --' "$case_root/valid.arguments"
    run_case "$case_runner" "$case_root" mismatch "$case_root/mismatch.fixture" 1
    [[ "$observed_status" -eq 1 ]]
    grep -Fxq action_17u_a_runner_acceptance=semantic_mismatch "$case_root/mismatch.out"
    cp -- "$case_root/valid.fixture" "$case_root/duplicate.fixture"
    printf 'action_17u_a_assertion_identity_root=true\n' >>"$case_root/duplicate.fixture"
    run_case "$case_runner" "$case_root" duplicate "$case_root/duplicate.fixture" 0
    printf 'action_17u_a_regression_duplicate_status=%s\n' "$observed_status"
    [[ "$observed_status" -eq 97 ]]
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$runner_sha256" =~ ^[0-9a-f]{64}$ ]]
    printf 'action_17u_a_regression_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(file_hash "$inspector")" = "$inspector_sha256" ]]
[[ "$(file_hash "$runner")" = "$runner_sha256" ]]
bash -n "$inspector" "$runner" "$0"
shellcheck "$inspector" "$runner" "$0"
"$collision_checker" "$inspector" "$runner" "$0" >/dev/null
"$inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$source_context_policy" --runner "$runner" >/dev/null
[[ "$("$inspector" --expected-checks | wc -l)" -eq 71 ]]
[[ "$("$inspector" --expected-checks | sort -u | wc -l)" -eq 71 ]]

# The variable reference is required as literal production source text.
# shellcheck disable=SC2016
grep -Fq 'grep -Fxq action=17u "$backup_manifest"' "$inspector"
grep -Fq "expected_backup_manifest_sha256=$expected_manifest_sha256" "$inspector"
grep -Fq "printf 'action=17t" "$installer"
if grep -Eq 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' "$inspector"; then
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' "$inspector"; then
    exit 1
fi

regression_root=$(mktemp -d /tmp/caddy-action17u-a-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
    printf 'action_17u_a_production_runner_behavior=skipped_host_authoritative\n'
else
    run_production_regression "$regression_root/production"
    printf 'action_17u_a_production_runner_behavior=workstation_validated\n'
fi

printf 'action_17u_a_expected_provenance_action=17u\n'
printf 'action_17u_a_defined_installer_provenance_action=17t\n'
printf 'action_17u_a_false_negative_valid_success_accepted=true\n'
printf 'action_17u_a_false_negative_semantic_mismatch_preserved=true\n'
printf 'action_17u_a_false_positive_duplicate_rejected=true\n'
printf 'action_17u_a_production_path_network_contact=false\n'
printf 'action_17u_a_node_b_postinstall_regression_complete=true\n'
