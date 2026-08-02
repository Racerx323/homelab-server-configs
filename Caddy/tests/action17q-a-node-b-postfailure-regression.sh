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
readonly inspector="$caddy_root/scripts/inspect-node-b-protocol-v2-postfailure-action17q-a.sh"
readonly runner="$caddy_root/scripts/run-node-b-protocol-v2-postfailure-action17q-a.sh"
readonly collision_checker="$caddy_root/tests/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$caddy_root/tests/run-source-test-in-context.sh"
readonly inspector_sha256=5296b318426ee38a32a1f75c133ad20ad34f70bd0027712f104876e122ba146c
readonly runner_sha256=2e207fdfbb62543890195dfb1c5f4fab515c6dca9eccbe8093df038bc2503043
readonly -a expected_assertions=(
    identity_root
    working_directory_root
    hostname_node_b
    architecture_arm64
    reconcile_path_property_query_status_zero
    reconcile_path_property_query_stderr_empty
    reconcile_path_property_count_positive
    reconcile_path_property_names_hash_format
    reconcile_path_load_state_loaded
    reconcile_path_active_state_inactive
    reconcile_path_sub_state_dead
    reconcile_path_unit_file_state_disabled
    reconcile_path_fragment_path_exact
    reconcile_path_mainpid_presence_boolean
    reconcile_path_nrestarts_presence_boolean
    receiver_v1_regular
    receiver_v1_not_symlink
    receiver_v1_hash_exact
    receiver_v2_absent
    receiver_v2_not_symlink
    finalizer_v2_absent
    finalizer_v2_not_symlink
    authorized_keys_regular
    authorized_keys_not_symlink
    authorized_keys_metadata
    authorized_keys_hash_exact
    retained_release_directory
    retained_release_not_symlink
    retained_release_metadata
    retained_complete_absent
    retained_complete_not_symlink
    retained_pending_absent
    retained_pending_not_symlink
    retained_finalize_request_absent
    retained_finalize_request_not_symlink
    retained_payload_hash_exact
    retained_manifest_hash_exact
    retained_not_writable_by_sync
    current_link_exact
    current_target_exact
    caddy_active
    lighttpd_active
    lsyncd_inactive
    lsyncd_masked
    caddy_lsyncd_inactive
    caddy_lsyncd_disabled
    reconcile_path_inactive
    reconcile_service_inactive
    lsyncd_configuration_absent
    lsyncd_configuration_not_symlink
    action17q_backup_count_zero
    action17q_stage_count_zero
    before_state_status_zero
    before_state_stderr_empty
    before_state_hash_format
    after_state_status_zero
    after_state_stderr_empty
    after_state_hash_format
    state_unchanged
    conclusion_supported
    assertion_count_nonnegative
)

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

assert_hash() {
    local expected_hash=$1
    local source_path=$2

    [[ "$(file_hash "$source_path")" == "$expected_hash" ]]
}

# The static policy intentionally matches literal production shell source.
# shellcheck disable=SC2016
assert_static_policy() {
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
        "$inspector" "$runner"; then
        printf 'Action 17q-a contains a service mutation.\n' >&2
        return 1
    fi
    if grep -Eq \
        '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)' \
        "$inspector" "$runner"; then
        printf 'Action 17q-a contains a transfer command.\n' >&2
        return 1
    fi
    if grep -Eq \
        'ACTION17QA_(FIXTURE|CAPTURED|SSH_ARGUMENTS|STATUS)' "$runner"; then
        printf 'Production Action 17q-a runner contains a fixture bypass.\n' >&2
        return 1
    fi
    grep -Fq \
        'systemctl show "$reconcile_path_unit" --all --no-pager' \
        "$inspector"
    grep -Fq 'property_present MainPID "$property_output"' "$inspector"
    grep -Fq 'property_present NRestarts "$property_output"' "$inspector"
    grep -Fq 'stable_state_snapshot >"$before_state"' "$inspector"
    grep -Fq 'stable_state_snapshot >"$after_state"' "$inspector"
    grep -Fq \
        'test "$after_state_sha256" = "$before_state_sha256"' \
        "$inspector"
    grep -Fq \
        'action_17q_a_helper_execution=false' "$inspector"
    grep -Fq \
        'action_17q_a_persistent_mutations=false' "$inspector"
    grep -Fq \
        "'cd / && sudo -n /bin/bash -s --'" "$runner"
}

write_fixture() {
    local fixture_destination=$1
    local fixture_assertion

    {
        for fixture_assertion in "${expected_assertions[@]}"; do
            printf 'action_17q_a_assertion_%s=true\n' "$fixture_assertion"
        done
        printf '%s\n' \
            action_17q_a_value_reconcile_path_property_count=190 \
            action_17q_a_value_reconcile_path_property_names_sha256=1111111111111111111111111111111111111111111111111111111111111111 \
            action_17q_a_value_reconcile_path_load_state=loaded \
            action_17q_a_value_reconcile_path_active_state=inactive \
            action_17q_a_value_reconcile_path_sub_state=dead \
            action_17q_a_value_reconcile_path_unit_file_state=disabled \
            action_17q_a_value_reconcile_path_fragment_path=/etc/systemd/system/caddy-sync-reconcile.path \
            action_17q_a_value_reconcile_path_mainpid_present=false \
            action_17q_a_value_reconcile_path_nrestarts_present=false \
            action_17q_a_value_action17q_backup_count=0 \
            action_17q_a_value_action17q_stage_count=0 \
            action_17q_a_value_before_state_sha256=2222222222222222222222222222222222222222222222222222222222222222 \
            action_17q_a_value_after_state_sha256=2222222222222222222222222222222222222222222222222222222222222222 \
            action_17q_a_value_conclusion=path_omits_mainpid_and_nrestarts \
            "action_17q_a_assertion_count=${#expected_assertions[@]}" \
            action_17q_a_failed_assertion_count=0 \
            action_17q_a_first_failure=none \
            action_17q_a_helper_execution=false \
            action_17q_a_release_mutation=false \
            action_17q_a_authorization_mutation=false \
            action_17q_a_lsyncd_reconciliation_activation=false \
            action_17q_a_service_mutations=false \
            action_17q_a_persistent_mutations=false \
            action_17q_a_remote_complete=true
    } >"$fixture_destination"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # These variables exist only in the intercepted regression subprocess.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"$ACTION17QA_CAPTURED_INSPECTOR"' \
        'printf "%s\n" "$*" >"$ACTION17QA_SSH_ARGUMENTS"' \
        'cat "$ACTION17QA_FIXTURE"' \
        'exit "${ACTION17QA_STATUS:-0}"' \
        >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

run_case() {
    local case_fixture=$1
    local case_root=$2
    local case_status=$3
    local case_suffix=$4
    local case_runner=$5

    set +e
    ACTION17QA_CAPTURED_INSPECTOR="$case_root/$case_suffix.inspector" \
        ACTION17QA_SSH_ARGUMENTS="$case_root/$case_suffix.arguments" \
        ACTION17QA_FIXTURE="$case_fixture" \
        ACTION17QA_STATUS="$case_status" \
        "$case_runner" >"$case_root/$case_suffix.out" \
        2>"$case_root/$case_suffix.err"
    observed_status=$?
    set -e
}

run_production_path_regression() {
    local case_bin
    local case_root
    local case_runner
    local valid_fixture
    local mismatch_fixture
    local malformed_fixture

    case_root=$(mktemp -d /tmp/caddy-action17q-a-regression.XXXXXX)
    trap 'rm -rf -- "$case_root"' RETURN
    case_bin="$case_root/bin"
    install -d -m 0700 "$case_bin" "$case_root/Caddy/scripts" \
        "$case_root/Caddy/tests"
    cp -- "$inspector" "$runner" "$collision_checker" \
        "$case_root/Caddy/scripts/"
    mv -- \
        "$case_root/Caddy/scripts/check-shell-readonly-local-collisions.sh" \
        "$case_root/Caddy/tests/check-shell-readonly-local-collisions.sh"
    case_runner="$case_root/Caddy/scripts/run-node-b-protocol-v2-postfailure-action17q-a.sh"
    write_fake_ssh "$case_bin/ssh"
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$case_bin:/usr/bin:/bin|" \
        "$case_runner"
    chmod 0755 \
        "$case_runner" \
        "$case_root/Caddy/scripts/inspect-node-b-protocol-v2-postfailure-action17q-a.sh" \
        "$case_root/Caddy/tests/check-shell-readonly-local-collisions.sh"

    valid_fixture="$case_root/valid.fixture"
    write_fixture "$valid_fixture"
    run_case "$valid_fixture" "$case_root" 0 valid "$case_runner"
    [[ "$observed_status" -eq 0 ]]
    [[ ! -s "$case_root/valid.err" ]]
    grep -Fxq action_17q_a_runner_contract_valid=true \
        "$case_root/valid.out"
    grep -Fxq action_17q_a_runner_acceptance=true \
        "$case_root/valid.out"
    grep -Fxq action_17q_a_workstation_cleanup_complete=true \
        "$case_root/valid.out"
    cmp -s "$inspector" "$case_root/valid.inspector"
    grep -Fq 'pi@10.1.0.54' "$case_root/valid.arguments"
    grep -Fq 'HostKeyAlias=pihole00.local.theama.co' \
        "$case_root/valid.arguments"
    grep -Fq 'cd / && sudo -n /bin/bash -s --' \
        "$case_root/valid.arguments"

    mismatch_fixture="$case_root/mismatch.fixture"
    sed \
        -e 's/action_17q_a_assertion_state_unchanged=true/action_17q_a_assertion_state_unchanged=false/' \
        -e 's/action_17q_a_failed_assertion_count=0/action_17q_a_failed_assertion_count=1/' \
        -e 's/action_17q_a_first_failure=none/action_17q_a_first_failure=state_unchanged/' \
        "$valid_fixture" >"$mismatch_fixture"
    run_case "$mismatch_fixture" "$case_root" 1 mismatch "$case_runner"
    [[ "$observed_status" -eq 1 ]]
    [[ ! -s "$case_root/mismatch.err" ]]
    grep -Fxq action_17q_a_runner_contract_valid=true \
        "$case_root/mismatch.out"
    grep -Fxq action_17q_a_runner_acceptance=false \
        "$case_root/mismatch.out"

    malformed_fixture="$case_root/malformed.fixture"
    sed \
        's/action_17q_a_value_reconcile_path_mainpid_present=false/action_17q_a_value_reconcile_path_mainpid_present=true/' \
        "$valid_fixture" >"$malformed_fixture"
    run_case "$malformed_fixture" "$case_root" 0 malformed "$case_runner"
    [[ "$observed_status" -eq 97 ]]
    grep -Fq 'Action 17q-a transcript contract failed.' \
        "$case_root/malformed.err"

    cp -- "$valid_fixture" "$case_root/duplicate.fixture"
    printf 'action_17q_a_assertion_state_unchanged=true\n' \
        >>"$case_root/duplicate.fixture"
    run_case \
        "$case_root/duplicate.fixture" "$case_root" 0 duplicate "$case_runner"
    [[ "$observed_status" -eq 97 ]]

    sed \
        's/action_17q_a_value_after_state_sha256=2222222222222222222222222222222222222222222222222222222222222222/action_17q_a_value_after_state_sha256=3333333333333333333333333333333333333333333333333333333333333333/' \
        "$valid_fixture" >"$case_root/drift.fixture"
    run_case "$case_root/drift.fixture" "$case_root" 0 drift "$case_runner"
    [[ "$observed_status" -eq 97 ]]

    printf 'action_17q_a_false_negative_valid_evidence_accepted=true\n'
    printf 'action_17q_a_false_negative_semantic_mismatch_preserved=true\n'
    printf 'action_17q_a_false_positive_contradiction_rejected=true\n'
    printf 'action_17q_a_false_positive_duplicate_rejected=true\n'
    printf 'action_17q_a_false_positive_state_drift_rejected=true\n'
    printf 'action_17q_a_production_path_network_contact=false\n'
}

if [[ "${1:-}" != --self-test || $# -ne 1 ]]; then
    printf 'Usage: %s --self-test\n' "${0##*/}" >&2
    exit 2
fi

assert_hash "$inspector_sha256" "$inspector"
assert_hash "$runner_sha256" "$runner"
bash -n "$inspector" "$runner"
shellcheck "$inspector" "$runner"
"$collision_checker" "$inspector" "$runner" >/dev/null
"$inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$source_context_policy" --runner "$runner" >/dev/null
assert_static_policy
if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
    [[ "$caddy_root" == /workspace/homelab-server-configs/Caddy ]]
    printf 'action_17q_a_container_projection_validated=true\n'
else
    run_production_path_regression
fi

printf 'action_17q_a_node_b_postfailure_regression_complete=true\n'
