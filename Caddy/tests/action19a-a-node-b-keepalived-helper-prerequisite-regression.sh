#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19a_a_regression
readonly inspector_sha256=162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f
readonly runner_sha256=d0f6cc13e4de61dd9105ee4db3afd8f4caead3485d119b6c1e59e488219c4801
readonly expected_assertion_count=61

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly inspector="$caddy_root/scripts/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly runner="$caddy_root/scripts/run-node-b-keepalived-helper-prerequisite-action19a-a.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly source_context_policy="$test_directory/run-source-test-in-context.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

require_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf '%s_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}

static_read_only_policy() {
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
        "$inspector" "$runner"; then
        return 1
    fi
    if grep -Eq \
        '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)|ip[[:space:]].*address[[:space:]]+(add|del|replace)' \
        "$inspector" "$runner"; then
        return 1
    fi
    grep -Fq "printf '%s_helper_execution=false" "$inspector" || return 1
    grep -Fq "printf '%s_filesystem_mutations=false" "$inspector" ||
        return 1
    grep -Fq "printf '%s_service_mutations=false" "$inspector" || return 1
    grep -Fq "printf '%s_vrrp_mutations=false" "$inspector" || return 1
    grep -Fq "printf '%s_vip_mutations=false" "$inspector" || return 1
    grep -Fq "printf '%s_persistent_mutations=false" "$inspector" ||
        return 1
    grep -Fq "'cd / && sudo -n /bin/bash -s --'" "$runner" || return 1
    # Literal production-source assertion.
    # shellcheck disable=SC2016
    grep -Fq 'HostKeyAlias=$expected_host_alias' "$runner" || return 1
    ! grep -Fq 'IdentitiesOnly=yes' "$runner"
}

production_label_alignment() {
    local expected_path
    local label_root

    label_root=$(mktemp -d /tmp/caddy-action19a-a-source-labels.XXXXXX) ||
        return 1
    expected_path=$label_root/expected
    "$inspector" --expected-assertions >"$expected_path" || {
        rm -rf -- "$label_root"
        return 1
    }
    if [[ "$(wc -l <"$expected_path")" -ne "$expected_assertion_count" ||
    "$(sort -u "$expected_path" | wc -l)" -ne "$expected_assertion_count" ]]; then
        rm -rf -- "$label_root"
        return 1
    fi
    # Literal production-source assertions.
    # shellcheck disable=SC2016
    for required_source in \
        'record_command identity_root ' \
        'record_command health_state_absent ' \
        'record_command notification_state_supported ' \
        'validate_exact_helper "$expected_certificate_sha256" certificate_helper' \
        'validate_exact_helper "$expected_sync_failure_sha256" sync_failure_helper' \
        'validate_exact_helper "$expected_reconcile_sha256" reconcile_helper' \
        'validate_exact_helper "$expected_sync_health_sha256" sync_health_helper' \
        'record_command action19a_backup_count_zero ' \
        'record_command state_unchanged '; do
        grep -Fq "$required_source" "$inspector" || {
            rm -rf -- "$label_root"
            return 1
        }
    done
    rm -rf -- "$label_root"
}

write_fixture() {
    local fixture_path=$1
    local fixture_assertion

    {
        while IFS= read -r fixture_assertion; do
            printf 'action_19a_a_assertion_%s=true\n' "$fixture_assertion"
        done < <("$inspector" --expected-assertions)
        printf '%s\n' \
            action_19a_a_value_health_state=absent \
            action_19a_a_value_health_observed_sha256=absent \
            action_19a_a_value_notification_state=absent \
            action_19a_a_value_notification_observed_sha256=absent \
            action_19a_a_value_action19a_backup_count=0 \
            action_19a_a_value_action19a_run_stage_count=0 \
            action_19a_a_value_action19a_tmp_stage_count=0 \
            action_19a_a_value_action19a_install_stage_count=0 \
            action_19a_a_value_dns_ipv4_vip_count=0 \
            action_19a_a_value_dns_ipv6_vip_count=0 \
            action_19a_a_value_before_state_sha256=1111111111111111111111111111111111111111111111111111111111111111 \
            action_19a_a_value_after_state_sha256=1111111111111111111111111111111111111111111111111111111111111111 \
            action_19a_a_assertion_count=61 \
            action_19a_a_failed_assertion_count=0 \
            action_19a_a_first_failure=none \
            action_19a_a_helper_execution=false \
            action_19a_a_filesystem_mutations=false \
            action_19a_a_service_mutations=false \
            action_19a_a_vrrp_mutations=false \
            action_19a_a_vip_mutations=false \
            action_19a_a_persistent_mutations=false \
            action_19a_a_remote_complete=true
    } >"$fixture_path"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # The interceptor captures the exact streamed production inspector and
    # emits only the selected bounded fixture.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"$ACTION19AA_CAPTURED_INSPECTOR"' \
        'printf "%s\n" "$@" >"$ACTION19AA_SSH_ARGUMENTS"' \
        'cat "$ACTION19AA_FIXTURE"' \
        'exit "${ACTION19AA_STATUS:-0}"' >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

run_case() {
    local case_fixture=$1
    local case_name=$2
    local case_root=$3
    local expected_status=$4
    local observed_status=0

    (
        cd "$repository_root"
        CADDY_ACTION19AA_INTERCEPTED_TEST=1 \
            CADDY_ACTION19AA_SSH_BINARY="$case_root/fake-ssh" \
            ACTION19AA_CAPTURED_INSPECTOR="$case_root/$case_name.inspector" \
            ACTION19AA_SSH_ARGUMENTS="$case_root/$case_name.arguments" \
            ACTION19AA_FIXTURE="$case_fixture" \
            ACTION19AA_STATUS="$expected_status" \
            "$runner"
    ) >"$case_root/$case_name.stdout" \
        2>"$case_root/$case_name.stderr" || observed_status=$?
    printf '%s\n' "$observed_status"
}

require_gate inspector_hash_exact test "$(file_hash "$inspector")" = \
    "$inspector_sha256"
require_gate runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
require_gate syntax bash -n "$inspector" "$runner"
require_gate shellcheck shellcheck "$inspector" "$runner"
require_gate collision_policy "$collision_checker" "$inspector" "$runner"
require_gate inspector_self_test "$inspector" --self-test
require_gate runner_self_test "$runner" --self-test
require_gate runner_contract_test "$runner" --contract-test
require_gate runner_source_context "$source_context_policy" --runner "$runner"
require_gate production_label_alignment production_label_alignment
require_gate static_read_only_policy static_read_only_policy

regression_root=$(mktemp -d /tmp/caddy-action19a-a-regression.XXXXXX)
readonly regression_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$regression_root"
}
trap cleanup EXIT
write_fake_ssh "$regression_root/fake-ssh"
write_fixture "$regression_root/valid.fixture"

valid_status=$(run_case "$regression_root/valid.fixture" valid \
    "$regression_root" 0)
require_gate valid_status_zero test "$valid_status" -eq 0
require_gate valid_stderr_empty test ! -s "$regression_root/valid.stderr"
require_gate valid_accepted grep -Fxq \
    action_19a_a_runner_acceptance=accepted "$regression_root/valid.stdout"
require_gate streamed_inspector_exact cmp -s "$inspector" \
    "$regression_root/valid.inspector"
require_gate ssh_target_exact grep -Fxq pi@10.1.0.54 \
    "$regression_root/valid.arguments"
require_gate ssh_alias_exact grep -Fxq HostKeyAlias=pihole00.local.theama.co \
    "$regression_root/valid.arguments"
require_gate ssh_terminal_suppressed grep -Fxq -- -T \
    "$regression_root/valid.arguments"
require_gate ssh_remote_cwd_exact grep -Fxq \
    'cd / && sudo -n /bin/bash -s --' "$regression_root/valid.arguments"

sed \
    -e 's/action_19a_a_assertion_health_state_absent=true/action_19a_a_assertion_health_state_absent=false/' \
    -e 's/action_19a_a_failed_assertion_count=0/action_19a_a_failed_assertion_count=1/' \
    -e 's/action_19a_a_first_failure=none/action_19a_a_first_failure=health_state_absent/' \
    "$regression_root/valid.fixture" >"$regression_root/mismatch.fixture"
mismatch_status=$(run_case "$regression_root/mismatch.fixture" mismatch \
    "$regression_root" 1)
require_gate mismatch_status_one test "$mismatch_status" -eq 1
require_gate mismatch_contract_valid grep -Fxq \
    action_19a_a_runner_contract_valid=true \
    "$regression_root/mismatch.stdout"
require_gate mismatch_classified grep -Fxq \
    action_19a_a_runner_acceptance=semantic_mismatch \
    "$regression_root/mismatch.stdout"

cp -- "$regression_root/valid.fixture" "$regression_root/duplicate.fixture"
printf 'action_19a_a_assertion_health_state_absent=true\n' \
    >>"$regression_root/duplicate.fixture"
duplicate_status=$(run_case "$regression_root/duplicate.fixture" duplicate \
    "$regression_root" 0)
require_gate duplicate_rejected test "$duplicate_status" -eq 97

sed '/^action_19a_a_assertion_notification_state_supported=true$/d' \
    "$regression_root/valid.fixture" >"$regression_root/missing.fixture"
missing_status=$(run_case "$regression_root/missing.fixture" missing \
    "$regression_root" 0)
require_gate missing_rejected test "$missing_status" -eq 97

sed 's/action_19a_a_value_after_state_sha256=1111111111111111111111111111111111111111111111111111111111111111/action_19a_a_value_after_state_sha256=2222222222222222222222222222222222222222222222222222222222222222/' \
    "$regression_root/valid.fixture" >"$regression_root/drift.fixture"
drift_status=$(run_case "$regression_root/drift.fixture" drift \
    "$regression_root" 0)
require_gate state_drift_rejected test "$drift_status" -eq 97

printf '%s_false_negative_valid_evidence_accepted=true\n' "$prefix"
printf '%s_false_negative_semantic_mismatch_preserved=true\n' "$prefix"
printf '%s_false_positive_duplicate_assertion_rejected=true\n' "$prefix"
printf '%s_false_positive_missing_assertion_rejected=true\n' "$prefix"
printf '%s_false_positive_state_drift_rejected=true\n' "$prefix"
printf '%s_production_path_network_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
