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
readonly inspector="$caddy_root/scripts/inspect-node-b-stdout-safe-finalizer-postinstall-action17t-a.sh"
readonly runner="$caddy_root/scripts/run-node-b-stdout-safe-finalizer-postinstall-action17t-a.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_directory/run-source-test-in-context.sh"
readonly inspector_sha256=50cef92bc6b55b90275a819ee92d511df12132f2ad417c12d359d46f0f56919f
readonly runner_sha256=63125308950da76de2ab80bff2121d4e424105f718f431076ad7de67b293e944
readonly expected_finalizer_sha256=e5ec5aab0f57b9ea68c41f122de282c1d156a6747f9f74dd1f22200079c097e4
readonly expected_backup_manifest_sha256=1c77b0bbab0b9b6cc0cd134c6748553fd686e12e665cb7131552578a1182f15d
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

assert_hash() {
    local expected_hash=$1
    local hash_path=$2

    [[ "$(file_hash "$hash_path")" = "$expected_hash" ]]
}

write_success_fixture() {
    local fixture_path=$1
    local fixture_label
    local fixture_count=0
    local fixture_state_sha256=1111111111111111111111111111111111111111111111111111111111111111

    {
        while IFS= read -r fixture_label; do
            printf 'action_17t_a_assertion_%s=true\n' "$fixture_label"
            fixture_count=$((fixture_count + 1))
        done < <("$inspector" --expected-checks)
        printf '%s\n' \
            "action_17t_a_assertion_count=$fixture_count" \
            action_17t_a_failed_assertion_count=0 \
            action_17t_a_first_failure=none \
            "action_17t_a_value_finalizer_sha256=$expected_finalizer_sha256" \
            action_17t_a_value_backup_path=/var/backups/caddy-ha/action17t-node-b-stdout-safe-finalizer.Z6U7Yc \
            "action_17t_a_value_backup_manifest_sha256=$expected_backup_manifest_sha256" \
            "action_17t_a_value_payload_sha256=$expected_payload_sha256" \
            "action_17t_a_value_manifest_sha256=$expected_manifest_sha256" \
            "action_17t_a_value_before_state_sha256=$fixture_state_sha256" \
            "action_17t_a_value_after_state_sha256=$fixture_state_sha256" \
            action_17t_a_finalizer_invoked=false \
            action_17t_a_release_mutated=false \
            action_17t_a_marker_mutated=false \
            action_17t_a_service_mutations=false \
            action_17t_a_lsyncd_reconciliation_activation=false \
            action_17t_a_filesystem_mutations=false \
            action_17t_a_persistent_mutations=false \
            action_17t_a_node_b_read_only_postinstall_complete=true
    } >"$fixture_path"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # These variables exist only in the intercepted regression subprocess.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"$ACTION17T_A_CAPTURED_INSPECTOR"' \
        'printf "%s\n" "$*" >"$ACTION17T_A_SSH_ARGUMENTS"' \
        'cat "$ACTION17T_A_FIXTURE_OUTPUT"' \
        'cat "$ACTION17T_A_FIXTURE_ERROR" >&2' \
        'exit "$ACTION17T_A_STATUS"' >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

run_case() {
    local case_error=$1
    local case_output=$2
    local case_root=$3
    local case_runner=$4
    local case_status=$5
    local case_suffix=$6

    if ACTION17T_A_CAPTURED_INSPECTOR="$case_root/$case_suffix.inspector" \
        ACTION17T_A_SSH_ARGUMENTS="$case_root/$case_suffix.arguments" \
        ACTION17T_A_FIXTURE_OUTPUT="$case_output" \
        ACTION17T_A_FIXTURE_ERROR="$case_error" \
        ACTION17T_A_STATUS="$case_status" \
        "$case_runner" >"$case_root/$case_suffix.out" \
        2>"$case_root/$case_suffix.err"; then
        observed_status=0
    else
        observed_status=$?
    fi
}

run_production_path_regression() {
    local case_bin
    local case_root
    local case_runner
    local empty_error
    local valid_output

    case_root=$(mktemp -d /tmp/caddy-action17t-a-regression.XXXXXX)
    trap 'rm -rf -- "$case_root"' RETURN
    case_bin="$case_root/bin"
    install -d -m 0700 \
        "$case_bin" "$case_root/Caddy/scripts" "$case_root/Caddy/tests"
    cp -- "$inspector" "$runner" "$case_root/Caddy/scripts/"
    cp -- "$collision_checker" "$case_root/Caddy/tests/"
    chmod 0755 "$case_root/Caddy/scripts/"*.sh \
        "$case_root/Caddy/tests/check-shell-readonly-local-collisions.sh"
    case_runner="$case_root/Caddy/scripts/run-node-b-stdout-safe-finalizer-postinstall-action17t-a.sh"
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$case_bin:/usr/bin:/bin|" "$case_runner"
    write_fake_ssh "$case_bin/ssh"
    empty_error="$case_root/empty.err"
    valid_output="$case_root/valid.fixture"
    : >"$empty_error"
    write_success_fixture "$valid_output"

    run_case "$empty_error" "$valid_output" "$case_root" "$case_runner" 0 valid
    [[ "$observed_status" -eq 0 ]]
    grep -Fxq action_17t_a_runner_acceptance=true "$case_root/valid.out"
    grep -Fxq action_17t_a_remote_stdout_raw_emitted=false "$case_root/valid.out"
    grep -Fxq action_17t_a_remote_stderr_classification=empty "$case_root/valid.out"
    grep -Fq pi@10.1.0.54 "$case_root/valid.arguments"
    grep -Fq HostKeyAlias=pihole00.local.theama.co "$case_root/valid.arguments"
    grep -Fq 'cd / && sudo -n /bin/bash -s --' "$case_root/valid.arguments"
    cmp -s "$inspector" "$case_root/valid.inspector"

    sed -i '/assertion_complete_absent=/d' "$valid_output"
    run_case "$empty_error" "$valid_output" "$case_root" "$case_runner" 0 missing
    [[ "$observed_status" -eq 97 ]]
    grep -Fxq action_17t_a_runner_acceptance=false "$case_root/missing.err"

    write_success_fixture "$valid_output"
    printf 'action_17t_a_assertion_identity_root=true\n' >>"$valid_output"
    run_case "$empty_error" "$valid_output" "$case_root" "$case_runner" 0 duplicate
    [[ "$observed_status" -eq 97 ]]

    write_success_fixture "$valid_output"
    sed -i \
        's/action_17t_a_assertion_complete_absent=true/action_17t_a_assertion_complete_absent=false/; s/action_17t_a_failed_assertion_count=0/action_17t_a_failed_assertion_count=1/; s/action_17t_a_first_failure=none/action_17t_a_first_failure=complete_absent/; /node_b_read_only_postinstall_complete=true/d' \
        "$valid_output"
    run_case "$empty_error" "$valid_output" "$case_root" "$case_runner" 1 semantic
    [[ "$observed_status" -eq 1 ]]
    grep -Fxq action_17t_a_runner_acceptance=false "$case_root/semantic.out"

    printf 'DOPPLER_TOKEN=forbidden\n' >"$case_root/unsafe.err"
    write_success_fixture "$valid_output"
    run_case \
        "$case_root/unsafe.err" "$valid_output" "$case_root" "$case_runner" 255 unsafe
    [[ "$observed_status" -eq 97 ]]
    if grep -Fq forbidden "$case_root/unsafe.out" "$case_root/unsafe.err"; then
        printf 'Unsafe remote stderr was emitted.\n' >&2
        return 1
    fi

    printf '%s\n' \
        action_17t_a_false_negative_valid_success_accepted=true \
        action_17t_a_false_negative_semantic_mismatch_preserved=true \
        action_17t_a_false_positive_missing_assertion_rejected=true \
        action_17t_a_false_positive_duplicate_assertion_rejected=true \
        action_17t_a_false_positive_unsafe_stderr_suppressed=true \
        action_17t_a_production_path_network_contact=false
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$runner_sha256" =~ ^[0-9a-f]{64}$ ]]
        printf 'action_17t_a_regression_self_test_complete=true\n'
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

assert_hash "$inspector_sha256" "$inspector"
assert_hash "$runner_sha256" "$runner"
bash -n "$inspector" "$runner" "$0"
shellcheck "$inspector" "$runner" "$0"
"$collision_checker" "$inspector" "$runner" "$0" >/dev/null
"$inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$source_context_policy" --runner "$runner" >/dev/null
[[ "$("$inspector" --expected-checks | wc -l)" -eq 62 ]]
[[ "$("$inspector" --expected-checks | LC_ALL=C sort -u | wc -l)" -eq 62 ]]
printf 'action_17t_a_regression_assertion_shell_contracts=true\n'

mutation_command_count=$(grep -Ec \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$inspector" || true)
readonly mutation_command_count
[[ "$mutation_command_count" -eq 1 ]]
# The dollar-prefixed token is intentionally matched as literal source text.
# shellcheck disable=SC2016
grep -Fxq '    rm -rf -- "$work_directory"' "$inspector"
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$inspector" "$runner"; then
    printf 'Action 17t-a contains a service mutation.\n' >&2
    exit 1
fi
# The dollar-prefixed token is intentionally matched as literal source text.
# shellcheck disable=SC2016
if grep -Eq 'runuser[^\n]*finalizer|"\$finalizer"[[:space:]]+--source-role' \
    "$inspector"; then
    printf 'Action 17t-a can invoke the finalizer.\n' >&2
    exit 1
fi
if grep -Eq 'ACTION17T_A_(FIXTURE|STATUS|CAPTURED)' "$runner"; then
    printf 'Production Action 17t-a runner contains a fixture bypass.\n' >&2
    exit 1
fi
grep -Fq 'remote_stdout_bytes=%s' "$runner"
grep -Fq 'remote_stdout_lines=%s' "$runner"
grep -Fq 'remote_stdout_sha256=%s' "$runner"
grep -Fq 'remote_stdout_classification=%s' "$runner"
printf 'action_17t_a_regression_assertion_static_read_only_scope=true\n'

run_production_path_regression
printf 'action_17t_a_regression_complete=true\n'
