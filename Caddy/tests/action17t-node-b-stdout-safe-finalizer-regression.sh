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
readonly renderer="$caddy_root/scripts/render-node-b-stdout-safe-finalizer-action17t.sh"
readonly installer="$caddy_root/scripts/install-node-b-stdout-safe-finalizer-action17t.sh"
readonly runner="$caddy_root/scripts/run-node-b-stdout-safe-finalizer-install-action17t.sh"
readonly old_finalizer="$caddy_root/scripts/finalize-incoming-release-v2.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_directory/run-source-test-in-context.sh"
readonly old_finalizer_sha256=a49dadcaa611e641a100e6a4f2b1836fcf9a790876f437ee02e37003d78ef30c
readonly new_finalizer_sha256=e5ec5aab0f57b9ea68c41f122de282c1d156a6747f9f74dd1f22200079c097e4
readonly historical_action17s_sha256=325a8fff552646073768a619f5ee793423494d7258c8503624f1b44be0a0e5d8
readonly historical_action17s_a_inspector_sha256=adae35e14b9639c0cfb66ddac33e93e71489c4a06bdca3e10376248c54543da1
readonly empty_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

report_regression_error() {
    local error_line=$1
    local error_status=$2

    printf 'action_17t_regression_failure_line=%s\n' "$error_line" >&2
    printf 'action_17t_regression_failure_status=%s\n' "$error_status" >&2
}
trap 'report_regression_error "$LINENO" "$?"' ERR

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
    local fixture_count

    fixture_count=$("$installer" --expected-checks | wc -l)
    {
        while IFS= read -r fixture_label; do
            printf 'action_17t_assertion_%s=true\n' "$fixture_label"
        done < <("$installer" --expected-checks)
        printf '%s\n' \
            "action_17t_assertion_count=$fixture_count" \
            action_17t_failed_assertion_count=0 \
            action_17t_first_failure=none \
            action_17t_preflight_complete=true \
            action_17t_mutation_started=true \
            action_17t_value_install_stdout_bytes=0 \
            action_17t_value_install_stdout_lines=0 \
            "action_17t_value_install_stdout_sha256=$empty_sha256" \
            action_17t_value_install_stdout_classification=empty \
            action_17t_install_stdout_raw_emitted=false \
            action_17t_value_install_stderr_bytes=0 \
            action_17t_value_install_stderr_lines=0 \
            "action_17t_value_install_stderr_sha256=$empty_sha256" \
            action_17t_value_install_stderr_classification=empty \
            action_17t_install_stderr_raw_emitted=false \
            "action_17t_value_old_finalizer_sha256=$old_finalizer_sha256" \
            "action_17t_value_new_finalizer_sha256=$new_finalizer_sha256" \
            action_17t_value_revision=action17p-node-a-to-node-b-bootstrap \
            action_17t_value_backup_path=/var/backups/caddy-ha/action17t-node-b-stdout-safe-finalizer.ABC123 \
            action_17t_finalizer_invoked=false \
            action_17t_release_mutated=false \
            action_17t_marker_mutated=false \
            action_17t_lsyncd_reconciliation_activation=false \
            action_17t_service_mutations=false \
            action_17t_persistent_mutation_scope=stdout_safe_finalizer,rollback_backup \
            action_17t_node_b_stdout_safe_finalizer_install_complete=true
    } >"$fixture_path"
}

write_rollback_fixture() {
    local fixture_path=$1
    local fixture_label

    {
        printf '%s\n' \
            action_17t_rollback_started=true \
            action_17t_value_rollback_install_stdout_bytes=0 \
            action_17t_value_rollback_install_stdout_lines=0 \
            "action_17t_value_rollback_install_stdout_sha256=$empty_sha256" \
            action_17t_value_rollback_install_stdout_classification=empty \
            action_17t_rollback_install_stdout_raw_emitted=false \
            action_17t_value_rollback_install_stderr_bytes=0 \
            action_17t_value_rollback_install_stderr_lines=0 \
            "action_17t_value_rollback_install_stderr_sha256=$empty_sha256" \
            action_17t_value_rollback_install_stderr_classification=empty \
            action_17t_rollback_install_stderr_raw_emitted=false
        while IFS= read -r fixture_label; do
            printf 'action_17t_rollback_assertion_%s=true\n' "$fixture_label"
        done < <("$installer" --expected-rollback-checks)
        printf 'action_17t_rollback_complete=true\n'
    } >"$fixture_path"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # These variables exist only in the intercepted regression subprocess.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"$ACTION17T_CAPTURED_BUNDLE"' \
        'printf "%s\n" "$*" >"$ACTION17T_SSH_ARGUMENTS"' \
        'cat "$ACTION17T_FIXTURE_OUTPUT"' \
        'cat "$ACTION17T_FIXTURE_ERROR" >&2' \
        'exit "$ACTION17T_STATUS"' >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

run_case() {
    local case_error=$1
    local case_output=$2
    local case_root=$3
    local case_runner=$4
    local case_status=$5
    local case_suffix=$6

    if ACTION17T_CAPTURED_BUNDLE="$case_root/$case_suffix.bundle" \
        ACTION17T_SSH_ARGUMENTS="$case_root/$case_suffix.arguments" \
        ACTION17T_FIXTURE_OUTPUT="$case_output" \
        ACTION17T_FIXTURE_ERROR="$case_error" \
        ACTION17T_STATUS="$case_status" \
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
    local rollback_error
    local rollback_output
    local valid_output

    case_root=$(mktemp -d /tmp/caddy-action17t-regression.XXXXXX)
    trap 'rm -rf -- "$case_root"' RETURN
    case_bin="$case_root/bin"
    install -d -m 0700 \
        "$case_bin" "$case_root/Caddy/scripts" "$case_root/Caddy/tests"
    cp -- "$renderer" "$installer" "$runner" "$old_finalizer" \
        "$case_root/Caddy/scripts/"
    cp -- "$collision_checker" "$case_root/Caddy/tests/"
    chmod 0755 "$case_root/Caddy/scripts/"* \
        "$case_root/Caddy/tests/check-shell-readonly-local-collisions.sh"
    case_runner="$case_root/Caddy/scripts/run-node-b-stdout-safe-finalizer-install-action17t.sh"
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$case_bin:/usr/bin:/bin|" "$case_runner"
    write_fake_ssh "$case_bin/ssh"

    valid_output="$case_root/valid.fixture"
    empty_error="$case_root/empty.err"
    : >"$empty_error"
    write_success_fixture "$valid_output"
    run_case "$empty_error" "$valid_output" "$case_root" "$case_runner" 0 valid
    [[ "$observed_status" -eq 0 ]]
    grep -Fxq action_17t_runner_acceptance=true "$case_root/valid.out"
    grep -Fxq action_17t_remote_stdout_raw_emitted=false "$case_root/valid.out"
    grep -Fxq action_17t_remote_stderr_classification=empty "$case_root/valid.out"
    grep -Fq 'cd / && sudo -n /bin/bash -s --' "$case_root/valid.arguments"
    grep -Fq pi@10.1.0.54 "$case_root/valid.arguments"
    grep -Fq 'install-node-b-stdout-safe-finalizer-action17t.sh' \
        "$case_root/valid.bundle"

    printf 'action_17t_finalizer_invoked=true\n' >>"$valid_output"
    run_case "$empty_error" "$valid_output" "$case_root" "$case_runner" 0 contradiction
    [[ "$observed_status" -eq 97 ]]
    grep -Fq 'success transcript contract failed' "$case_root/contradiction.err"

    write_success_fixture "$valid_output"
    sed -i '/value_install_stdout_sha256=/d' "$valid_output"
    run_case "$empty_error" "$valid_output" "$case_root" "$case_runner" 0 missing
    printf 'action_17t_regression_value_missing_metadata_status=%s\n' \
        "$observed_status"
    [[ "$observed_status" -eq 97 ]]

    rollback_output="$case_root/rollback.out.fixture"
    rollback_error="$case_root/rollback.err.fixture"
    printf '%s\n' \
        action_17t_preflight_complete=true \
        action_17t_mutation_started=true >"$rollback_output"
    write_rollback_fixture "$rollback_error"
    run_case "$rollback_error" "$rollback_output" "$case_root" "$case_runner" 1 rollback
    [[ "$observed_status" -eq 1 ]]
    grep -Fxq action_17t_runner_acceptance=false "$case_root/rollback.out"

    sed -i '/rollback_complete=true/d' "$rollback_error"
    run_case "$rollback_error" "$rollback_output" "$case_root" "$case_runner" 1 incomplete
    [[ "$observed_status" -eq 97 ]]
    grep -Fq 'rollback evidence is incomplete' "$case_root/incomplete.err"

    printf '%s\n' \
        action_17t_false_negative_valid_success_accepted=true \
        action_17t_false_negative_complete_rollback_preserved=true \
        action_17t_false_positive_contradiction_rejected=true \
        action_17t_false_positive_missing_stream_metadata_rejected=true \
        action_17t_false_positive_incomplete_rollback_rejected=true \
        action_17t_production_path_network_contact=false
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$old_finalizer_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$new_finalizer_sha256" =~ ^[0-9a-f]{64}$ ]]
        printf 'action_17t_regression_self_test_complete=true\n'
        exit 0
        ;;
    "") ;;
    *)
        printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

assert_hash "$old_finalizer_sha256" "$old_finalizer"
assert_hash "$historical_action17s_sha256" \
    "$caddy_root/scripts/migrate-node-b-retained-release-marker-action17s.sh"
assert_hash "$historical_action17s_a_inspector_sha256" \
    "$caddy_root/scripts/inspect-node-b-action17s-rollback-output-action17s-a.sh"
printf 'action_17t_regression_assertion_historical_artifacts_immutable=true\n'

regression_root=$(mktemp -d /tmp/caddy-action17t-render.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
"$renderer" --input "$old_finalizer" --output "$regression_root/finalizer"
assert_hash "$new_finalizer_sha256" "$regression_root/finalizer"
diff_output="$regression_root/finalizer.diff"
diff -u "$old_finalizer" "$regression_root/finalizer" >"$diff_output" || true
[[ "$(grep -Ec '^[-+]        --adapter caddyfile' "$diff_output")" -eq 2 ]]
[[ "$(grep -Ec '^[-+][^-+]' "$diff_output")" -eq 2 ]]
printf 'action_17t_regression_assertion_exact_one_line_transform=true\n'

bash -n "$renderer" "$installer" "$runner" "$0"
shellcheck "$renderer" "$installer" "$runner" "$0"
"$collision_checker" "$renderer" "$installer" "$runner" "$0" >/dev/null
"$renderer" --self-test >/dev/null
"$installer" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$source_context_policy" --runner "$runner" >/dev/null
printf 'action_17t_regression_assertion_shell_contracts=true\n'

grep -Fq '>/dev/null' "$renderer"
grep -Fq 'finalizer_invoked=false' "$installer"
grep -Fq 'release_mutated=false' "$installer"
grep -Fq 'marker_mutated=false' "$installer"
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$renderer" "$installer" "$runner"; then
    printf 'Action 17t contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq 'ACTION17T_(FIXTURE|STATUS|CAPTURED)' "$runner"; then
    printf 'Production Action 17t runner contains a fixture bypass.\n' >&2
    exit 1
fi
printf 'action_17t_regression_assertion_static_scope=true\n'

run_production_path_regression
printf 'action_17t_regression_complete=true\n'
