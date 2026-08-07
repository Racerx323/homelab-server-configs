#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20n_a_retry_regression
readonly expected_check_count=68
readonly expected_line_count=84
readonly fixture_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-node-a-keepalived-dbus-main-postinstall-action20n-a-retry.sh
readonly outer=$caddy_root/scripts/run-node-a-keepalived-dbus-main-postinstall-action20n-a-retry-outer.sh
readonly historical_inspector=$caddy_root/scripts/inspect-node-a-keepalived-dbus-main-postinstall-action20n-a.sh
readonly historical_inspector_sha256=6130fd3716cdc81a3ee08eebd1499a6d18a99664ae5eb48e906074ba834773ec
readonly collision_checker=$test_directory/check-shell-readonly-local-collisions-v2.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

record_gate() {
    local action20na_retry_regression_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20na_retry_regression_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20na_retry_regression_gate_label" >&2
    return 1
}
write_expected_inspector() {
    local action20na_retry_regression_expected=$1

    sed 's/action20n-node-a-dbus-main\.wHwzci/action20n-node-a-dbus-main.s8Qkep/' \
        "$historical_inspector" >"$action20na_retry_regression_expected" || return 1
}
write_valid_transcript() {
    local action20na_retry_regression_output=$1
    local action20na_retry_regression_label

    : >"$action20na_retry_regression_output" || return 1
    while IFS= read -r action20na_retry_regression_label; do
        printf 'action_20n_a_check_%s=true\n' "$action20na_retry_regression_label" \
            >>"$action20na_retry_regression_output" || return 1
    done < <(/bin/bash "$inspector" --expected-checks)
    printf '%s\n' \
        'action_20n_a_value_expected_check_count=68' \
        'action_20n_a_value_backup_path=/var/backups/caddy-ha/action20n-node-a-dbus-main.s8Qkep' \
        'action_20n_a_value_main_sha256=8fc9dcf8e079b7131f86a58038ae5543804a5158a02d53a4614452de212ce47c' \
        'action_20n_a_value_backup_main_sha256=357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2' \
        "action_20n_a_value_before_state_sha256=$fixture_state_sha256" \
        "action_20n_a_value_after_state_sha256=$fixture_state_sha256" \
        'action_20n_a_check_count=68' \
        'action_20n_a_failed_check_count=0' \
        'action_20n_a_first_failure=none' \
        'action_20n_a_helper_execution=false' \
        'action_20n_a_filesystem_mutations=false' \
        'action_20n_a_service_mutations=false' \
        'action_20n_a_vrrp_mutations=false' \
        'action_20n_a_vip_mutations=false' \
        'action_20n_a_node_b_contacted=false' \
        'action_20n_a_remote_complete=true' >>"$action20na_retry_regression_output"
}
write_mock_ssh() {
    local action20na_retry_regression_mock=$1

    # The mock intentionally ignores SSH options and consumes the production stdin.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        '[[ "${!#}" = "cd / && sudo -n /bin/bash -s --" ]] || exit 71' \
        'cat >/dev/null' \
        'cat "$ACTION20NA_MOCK_STDOUT"' \
        'cat "$ACTION20NA_MOCK_STDERR" >&2' \
        'exit "$ACTION20NA_MOCK_STATUS"' >"$action20na_retry_regression_mock" || return 1
    chmod 0755 "$action20na_retry_regression_mock"
}
run_case() (
    local action20na_retry_regression_case_root=$1
    local action20na_retry_regression_transcript=$2
    local action20na_retry_regression_remote_status=$3
    local action20na_retry_regression_expected_status=$4
    local action20na_retry_regression_stderr_content=${5:-}
    local action20na_retry_regression_mock=$action20na_retry_regression_case_root/mock-ssh
    local action20na_retry_regression_mock_stderr=$action20na_retry_regression_case_root/mock.stderr
    local action20na_retry_regression_outer_stdout=$action20na_retry_regression_case_root/outer.stdout
    local action20na_retry_regression_outer_stderr=$action20na_retry_regression_case_root/outer.stderr
    local action20na_retry_regression_observed_status=0

    install -d -m 0700 "$action20na_retry_regression_case_root" || return 1
    write_mock_ssh "$action20na_retry_regression_mock" || return 1
    printf '%s' "$action20na_retry_regression_stderr_content" >"$action20na_retry_regression_mock_stderr" || return 1
    CADDY_ACTION20NA_TEST_MODE=1 \
        CADDY_ACTION20NA_SSH_BINARY=$action20na_retry_regression_mock \
        ACTION20NA_MOCK_STDOUT=$action20na_retry_regression_transcript \
        ACTION20NA_MOCK_STDERR=$action20na_retry_regression_mock_stderr \
        ACTION20NA_MOCK_STATUS=$action20na_retry_regression_remote_status \
        /bin/bash "$outer" --test-transport \
        >"$action20na_retry_regression_outer_stdout" 2>"$action20na_retry_regression_outer_stderr" ||
        action20na_retry_regression_observed_status=$?
    [[ "$action20na_retry_regression_observed_status" -eq "$action20na_retry_regression_expected_status" ]] || return 1
    if [[ "$action20na_retry_regression_expected_status" -eq 0 ]]; then
        grep -Fqx action_20n_a_retry_outer_complete=true "$action20na_retry_regression_outer_stdout" || return 1
        [[ ! -s "$action20na_retry_regression_outer_stderr" ]] || return 1
    fi
)
run_regression() (
    local action20na_retry_regression_root
    local action20na_retry_regression_valid
    local action20na_retry_regression_case
    local action20na_retry_regression_collision_fixture
    local action20na_retry_regression_collision_status=0
    local action20na_retry_regression_expected_inspector
    local action20na_retry_regression_stale_inspector

    action20na_retry_regression_root=$(mktemp -d /tmp/caddy-action20n-a-retry-regression.XXXXXX) || return 1
    trap 'rm -rf -- "$action20na_retry_regression_root"' EXIT
    action20na_retry_regression_valid=$action20na_retry_regression_root/valid.transcript
    action20na_retry_regression_expected_inspector=$action20na_retry_regression_root/expected-inspector.sh
    action20na_retry_regression_stale_inspector=$action20na_retry_regression_root/stale-inspector.sh
    record_gate historical_inspector_hash test \
        "$(file_hash "$historical_inspector")" = "$historical_inspector_sha256" || return 1
    write_expected_inspector "$action20na_retry_regression_expected_inspector" || return 1
    record_gate inspector_exact_one_line_delta cmp -s \
        "$action20na_retry_regression_expected_inspector" "$inspector" || return 1
    record_gate production_correct_suffix_once test \
        "$(grep -Fxc 'readonly backup_directory=/var/backups/caddy-ha/action20n-node-a-dbus-main.s8Qkep' "$inspector" || true)" -eq 1 || return 1
    record_gate production_stale_suffix_absent test \
        "$(grep -Fc 'action20n-node-a-dbus-main.wHwzci' "$inspector" || true)" -eq 0 || return 1
    sed 's/action20n-node-a-dbus-main\.s8Qkep/action20n-node-a-dbus-main.wHwzci/' \
        "$inspector" >"$action20na_retry_regression_stale_inspector" || return 1
    record_gate stale_fixture_correct_suffix_absent test \
        "$(grep -Fc 'action20n-node-a-dbus-main.s8Qkep' "$action20na_retry_regression_stale_inspector" || true)" -eq 0 || return 1
    record_gate stale_fixture_stale_suffix_once test \
        "$(grep -Fxc 'readonly backup_directory=/var/backups/caddy-ha/action20n-node-a-dbus-main.wHwzci' "$action20na_retry_regression_stale_inspector" || true)" -eq 1 || return 1
    write_valid_transcript "$action20na_retry_regression_valid" || return 1
    record_gate expected_check_count test \
        "$(/bin/bash "$inspector" --expected-checks | awk 'END { print NR }')" -eq "$expected_check_count" || return 1
    record_gate valid_transcript_line_count test \
        "$(awk 'END { print NR }' "$action20na_retry_regression_valid")" -eq "$expected_line_count" || return 1
    record_gate valid_production_path run_case \
        "$action20na_retry_regression_root/valid" "$action20na_retry_regression_valid" 0 0 || return 1

    for action20na_retry_regression_case in false missing duplicate reordered changed_state; do
        cp -- "$action20na_retry_regression_valid" \
            "$action20na_retry_regression_root/$action20na_retry_regression_case.transcript" || return 1
    done
    sed -i 's/action_20n_a_check_main_hash_exact=true/action_20n_a_check_main_hash_exact=false/' \
        "$action20na_retry_regression_root/false.transcript" || return 1
    sed -i '/action_20n_a_check_main_hash_exact=true/d' \
        "$action20na_retry_regression_root/missing.transcript" || return 1
    printf '%s\n' action_20n_a_check_main_hash_exact=true \
        >>"$action20na_retry_regression_root/duplicate.transcript" || return 1
    awk 'NR == 1 { first=$0; next } NR == 2 { print; print first; next } { print }' \
        "$action20na_retry_regression_valid" >"$action20na_retry_regression_root/reordered.tmp" || return 1
    mv "$action20na_retry_regression_root/reordered.tmp" \
        "$action20na_retry_regression_root/reordered.transcript" || return 1
    sed -i "s/action_20n_a_value_after_state_sha256=$fixture_state_sha256/action_20n_a_value_after_state_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/" \
        "$action20na_retry_regression_root/changed_state.transcript" || return 1
    for action20na_retry_regression_case in false missing duplicate reordered changed_state; do
        record_gate "${action20na_retry_regression_case}_rejected" run_case \
            "$action20na_retry_regression_root/$action20na_retry_regression_case" \
            "$action20na_retry_regression_root/$action20na_retry_regression_case.transcript" 0 97 || return 1
    done
    record_gate stderr_rejected run_case "$action20na_retry_regression_root/stderr" \
        "$action20na_retry_regression_valid" 0 97 'bounded-safe-error' || return 1
    record_gate nonzero_status_preserved run_case "$action20na_retry_regression_root/status" \
        "$action20na_retry_regression_valid" 7 7 || return 1

    action20na_retry_regression_collision_fixture=$action20na_retry_regression_root/collision.sh
    # The fixture intentionally contains a literal dynamic-scope collision.
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'readonly action20na_collision=value' \
        'collision() {' '    local action20na_collision=other' \
        '    printf '\''%s\n'\'' "$action20na_collision"' '}' \
        >"$action20na_retry_regression_collision_fixture" || return 1
    /bin/bash "$collision_checker" "$action20na_retry_regression_collision_fixture" \
        >/dev/null 2>&1 || action20na_retry_regression_collision_status=$?
    record_gate dynamic_scope_collision_rejected test \
        "$action20na_retry_regression_collision_status" -eq 1 || return 1
    record_gate collision_policy_clean /bin/bash "$collision_checker" \
        "$inspector" "$outer" "$0" || return 1
    printf '%s_false_negative_valid_production_transcript_accepted=true\n' "$prefix"
    printf '%s_false_positive_invalid_transcripts_rejected=true\n' "$prefix"
    printf '%s_false_negative_nonzero_status_preserved=true\n' "$prefix"
    printf '%s_node_a_contacted=false\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_action_executed=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
)

run_regression
