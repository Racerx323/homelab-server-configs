#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=$(cd -- "$test_directory/.." && pwd)
readonly caddy_root
readonly derivation="$caddy_root/scripts/derive-node-b-postmigration-acceptance-action17v.sh"
readonly derivation_sha256=46adf7d35a306ddb13e68087db9f5191140b78418f0f65a2182f3ebc848c7afd
readonly expected_inspector_sha256=216ee51b429048b0304e76d0b75402f4306470d012f170debb1352951efd5910
readonly expected_runner_sha256=cb85c0c63faba81db701f6d02be092df3150dd38a3b926bc785c0b067f54ebad
readonly expected_marker_backup_path=/var/backups/caddy-ha/action17s-retry2-node-b-marker-migration.K3K5zO
readonly expected_marker_before_snapshot_sha256=3df6a1b8ff8adf6e8ce30762b86bc9e25b2fc072ba4458fdc889e631892796a4

cleanup_directory=

unexpected_failure() {
    local failure_status=$1
    local failure_line=$2

    trap - ERR
    printf 'action_17v_regression_assertion_unexpected_failure=false\n' >&2
    printf 'action_17v_regression_value_failure_line=%s\n' "$failure_line" >&2
    printf 'action_17v_regression_value_failure_status=%s\n' "$failure_status" >&2
    exit "$failure_status"
}

trap 'unexpected_failure "$?" "$LINENO"' ERR

cleanup_test_directory() {
    local cleanup_status=$?

    trap - EXIT
    if [[ -n "$cleanup_directory" && -d "$cleanup_directory" ]]; then
        rm -rf -- "$cleanup_directory"
    fi
    exit "$cleanup_status"
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

render_tree() {
    local render_root=$1
    local render_scripts="$render_root/Caddy/scripts"
    local render_tests="$render_root/Caddy/tests"

    install -d -m 0700 "$render_scripts" "$render_tests"
    "$derivation" --render-inspector \
        >"$render_scripts/inspect-node-b-postmigration-acceptance-action17v.sh"
    "$derivation" --render-runner \
        >"$render_scripts/run-node-b-postmigration-acceptance-action17v.sh"
    install -m 0755 -- "$test_directory/check-shell-readonly-local-collisions.sh" \
        "$render_tests/check-shell-readonly-local-collisions.sh"
    chmod 0755 "$render_scripts/"*
    [[ "$(file_hash "$render_scripts/inspect-node-b-postmigration-acceptance-action17v.sh")" == "$expected_inspector_sha256" ]]
    [[ "$(file_hash "$render_scripts/run-node-b-postmigration-acceptance-action17v.sh")" == "$expected_runner_sha256" ]]
}

assert_static_read_only_policy() {
    local inspector=$1

    # The dollar-prefixed paths are matched as literal production source.
    # shellcheck disable=SC2016
    grep -Fq 'record_command request_regular test -f "$release/.finalize-request"' "$inspector"
    # shellcheck disable=SC2016
    grep -Fq 'record_command complete_regular test -f "$release/.complete"' "$inspector"
    # shellcheck disable=SC2016
    grep -Fq 'record_command pending_absent test ! -e "$release/.complete.pending"' "$inspector"
    grep -Fq 'record_command marker_backup_snapshot_hash_exact' "$inspector"
    grep -Fq 'record_command marker_backup_hash_record_content_exact' "$inspector"
    grep -Fq 'record_command marker_transaction_stage_count_zero' "$inspector"
    grep -Fq "printf '%s_finalizer_invoked=false" "$inspector"
    grep -Fq "printf '%s_marker_mutated=false" "$inspector"
    if grep -Fq -- '--source-role node-a' "$inspector"; then
        printf 'Action 17v inspector could invoke the finalizer.\n' >&2
        return 1
    fi
    if grep -Eq 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' "$inspector"; then
        printf 'Action 17v inspector contains a service mutation.\n' >&2
        return 1
    fi
    if grep -Eq '(^|[[:space:]])(touch|install)[[:space:]].*[.]complete|(^|[[:space:]])rm[[:space:]].*[.](complete|finalize-request)' "$inspector"; then
        printf 'Action 17v inspector contains a marker mutation.\n' >&2
        return 1
    fi
}

write_fake_ssh() {
    local fake_ssh=$1

    # Variables are evaluated only by the intercepted production process.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"$ACTION17V_STDIN"' \
        'printf "%s\n" "$@" >"$ACTION17V_ARGUMENTS"' \
        '[[ "$(sha256sum "$ACTION17V_STDIN" | awk '\''{ print $1 }'\'')" == "$ACTION17V_INSPECTOR_HASH" ]]' \
        'cat -- "$ACTION17V_STDOUT"' \
        'cat -- "$ACTION17V_STDERR" >&2' \
        'exit "$ACTION17V_STATUS"' >"$fake_ssh"
    chmod 0755 "$fake_ssh"
}

make_fixture() {
    local inspector=$1
    local fixture=$2
    local fixture_count=0
    local fixture_label
    local fixture_state=1111111111111111111111111111111111111111111111111111111111111111

    {
        while IFS= read -r fixture_label; do
            printf 'action_17v_assertion_%s=true\n' "$fixture_label"
            fixture_count=$((fixture_count + 1))
        done < <("$inspector" --expected-checks)
        printf '%s\n' \
            "action_17v_assertion_count=$fixture_count" \
            action_17v_failed_assertion_count=0 \
            action_17v_first_failure=none \
            action_17v_value_finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d \
            action_17v_value_backup_path=/var/backups/caddy-ha/action17u-node-b-stderr-safe-finalizer.N9uEhC \
            action_17v_value_expected_backup_manifest_sha256=a992c2ff9bdfde76770ddae910dedfc2a8bbdf6ad25de909ec5cbeacda31d70b \
            action_17v_value_observed_backup_manifest_sha256=a992c2ff9bdfde76770ddae910dedfc2a8bbdf6ad25de909ec5cbeacda31d70b \
            action_17v_value_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e \
            action_17v_value_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8 \
            "action_17v_value_marker_backup_path=$expected_marker_backup_path" \
            "action_17v_value_marker_before_snapshot_sha256=$expected_marker_before_snapshot_sha256" \
            "action_17v_value_before_state_sha256=$fixture_state" \
            "action_17v_value_after_state_sha256=$fixture_state" \
            action_17v_finalizer_invoked=false \
            action_17v_release_mutated=false \
            action_17v_marker_mutated=false \
            action_17v_service_mutations=false \
            action_17v_lsyncd_reconciliation_activation=false \
            action_17v_filesystem_mutations=false \
            action_17v_persistent_mutations=false \
            action_17v_node_b_read_only_postmigration_complete=true
    } >"$fixture"
}

run_case() {
    local case_error=$1
    local case_fixture=$2
    local case_name=$3
    local case_root=$4
    local case_runner=$5
    local case_status=$6

    observed_status=0
    (
        cd /home/aaron/code/homelab-server-configs
        ACTION17V_ARGUMENTS="$case_root/$case_name.arguments" \
            ACTION17V_INSPECTOR_HASH="$expected_inspector_sha256" \
            ACTION17V_STATUS="$case_status" \
            ACTION17V_STDERR="$case_error" \
            ACTION17V_STDIN="$case_root/$case_name.stdin" \
            ACTION17V_STDOUT="$case_fixture" \
            "$case_runner"
    ) >"$case_root/$case_name.outer" 2>"$case_root/$case_name.error" || observed_status=$?
}

production_test() {
    local duplicate_evidence
    local fake_bin
    local inspector
    local runner

    cleanup_directory=$(mktemp -d /tmp/caddy-action17v-regression.XXXXXX)
    trap cleanup_test_directory EXIT
    fake_bin="$cleanup_directory/bin"
    install -d -m 0700 "$fake_bin"
    render_tree "$cleanup_directory/production"
    inspector="$cleanup_directory/production/Caddy/scripts/inspect-node-b-postmigration-acceptance-action17v.sh"
    runner="$cleanup_directory/production/Caddy/scripts/run-node-b-postmigration-acceptance-action17v.sh"
    assert_static_read_only_policy "$inspector"
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$fake_bin:/usr/bin:/bin|" "$runner"
    write_fake_ssh "$fake_bin/ssh"
    make_fixture "$inspector" "$cleanup_directory/valid"
    : >"$cleanup_directory/empty"

    run_case "$cleanup_directory/empty" "$cleanup_directory/valid" valid \
        "$cleanup_directory" "$runner" 0
    [[ "$observed_status" -eq 0 ]]
    grep -Fxq action_17v_runner_acceptance=true "$cleanup_directory/valid.outer"
    grep -Fxq action_17v_assertion_complete_regular=true "$cleanup_directory/valid.outer"
    grep -Fxq action_17v_assertion_marker_backup_snapshot_hash_exact=true "$cleanup_directory/valid.outer"
    grep -Fq 'cd / && sudo -n /bin/bash -s --' "$cleanup_directory/valid.arguments"
    [[ "$(file_hash "$cleanup_directory/valid.stdin")" == "$expected_inspector_sha256" ]]

    sed 's/action_17v_assertion_complete_metadata=true/action_17v_assertion_complete_metadata=false/; s/action_17v_failed_assertion_count=0/action_17v_failed_assertion_count=1/; s/action_17v_first_failure=none/action_17v_first_failure=complete_metadata/; /action_17v_node_b_read_only_postmigration_complete=true/d' \
        "$cleanup_directory/valid" >"$cleanup_directory/mismatch"
    run_case "$cleanup_directory/empty" "$cleanup_directory/mismatch" mismatch \
        "$cleanup_directory" "$runner" 1
    [[ "$observed_status" -eq 1 ]]
    grep -Fxq action_17v_runner_acceptance=semantic_mismatch \
        "$cleanup_directory/mismatch.outer"

    cp -- "$cleanup_directory/valid" "$cleanup_directory/duplicate"
    printf 'action_17v_assertion_identity_root=true\n' >>"$cleanup_directory/duplicate"
    run_case "$cleanup_directory/empty" "$cleanup_directory/duplicate" duplicate \
        "$cleanup_directory" "$runner" 0
    [[ "$observed_status" -eq 97 ]]
    grep -Fxq action_17v_runner_acceptance=false "$cleanup_directory/duplicate.error"
    duplicate_evidence=$(sed -n 's/^action_17v_evidence_retained=//p' \
        "$cleanup_directory/duplicate.error")
    [[ "$duplicate_evidence" == /tmp/caddy-action17v-runner.* ]]
    [[ -d "$duplicate_evidence" && ! -L "$duplicate_evidence" ]]
    [[ "$(stat -c '%U:%G:%a' "$duplicate_evidence")" == aaron:aaron:700 ]]
    rm -rf -- "$duplicate_evidence"

    [[ -z "$(find /tmp -mindepth 1 -maxdepth 1 -type d -name 'caddy-action17v-runner.*' -print -quit)" ]]
    printf 'action_17v_false_negative_valid_postmigration_accepted=true\n'
    printf 'action_17v_false_negative_semantic_mismatch_preserved=true\n'
    printf 'action_17v_false_positive_duplicate_evidence_rejected=true\n'
    printf 'action_17v_marker_specific_production_path_validated=true\n'
    printf 'action_17v_production_path_network_contact=false\n'
    rm -rf -- "$cleanup_directory"
    cleanup_directory=
    trap - EXIT
}

container_projection_test() {
    local inspector
    local runner

    cleanup_directory=$(mktemp -d /tmp/caddy-action17v-container.XXXXXX)
    trap cleanup_test_directory EXIT
    render_tree "$cleanup_directory/production"
    inspector="$cleanup_directory/production/Caddy/scripts/inspect-node-b-postmigration-acceptance-action17v.sh"
    runner="$cleanup_directory/production/Caddy/scripts/run-node-b-postmigration-acceptance-action17v.sh"
    [[ "$("$inspector" --expected-checks | wc -l)" -eq 89 ]]
    [[ "$("$inspector" --expected-checks | LC_ALL=C sort -u | wc -l)" -eq 89 ]]
    assert_static_read_only_policy "$inspector"
    "$inspector" --self-test >/dev/null
    "$runner" --contract-test >/dev/null
    printf 'action_17v_container_projection_validated=true\n'
    printf 'action_17v_container_network_contact=false\n'
    rm -rf -- "$cleanup_directory"
    cleanup_directory=
    trap - EXIT
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        [[ "$(file_hash "$derivation")" == "$derivation_sha256" ]]
        bash -n "$derivation"
        printf 'action_17v_regression_self_test_complete=true\n'
        ;;
    --production-test | "")
        [[ $# -le 1 ]]
        [[ "$(file_hash "$derivation")" == "$derivation_sha256" ]]
        if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
            container_projection_test
        else
            production_test
        fi
        ;;
    *)
        printf 'Usage: %s [--self-test|--production-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac
