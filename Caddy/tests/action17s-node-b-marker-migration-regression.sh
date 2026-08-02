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
readonly transaction="$caddy_root/scripts/migrate-node-b-retained-release-marker-action17s.sh"
readonly runner="$caddy_root/scripts/run-node-b-retained-release-marker-migration-action17s.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_directory/run-source-test-in-context.sh"
readonly transaction_sha256=325a8fff552646073768a619f5ee793423494d7258c8503624f1b44be0a0e5d8
readonly runner_sha256=006b0d34480fe9cf3e0bec50649c2d8d59bf050821c1df8219d2193c7d403d20
readonly historical_node_a_inspector_sha256=ce7463c63883fc5973226d94332522326e88cc942d1d28f9ac9644e30803aa40
readonly historical_node_b_inspector_sha256=f9abd9952612f7855821c0d09a1de01c64fa540c1782aa24512cd035e7a1cdaf
readonly historical_runner_sha256=db59dcf4b0a52034639305e46bd6dc62f18ea3f4621013cfa53e6b0919ad2a5e
readonly historical_regression_sha256=7e35b48673215e12cd6f4e3bbed713832cb6945ed02a828f9f98b18f8284f41f
readonly expected_payload_sha256=3635265ef2ad9d6a0a88b9b972fa329d97655d3b4c9df56a1b491952bf1f8f6e
readonly expected_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

assert_hash() {
    local expected_hash=$1
    local hashed_path=$2

    [[ "$(file_hash "$hashed_path")" = "$expected_hash" ]]
}

assert_static_policy() {
    # The following checks intentionally match literal production shell source.
    # shellcheck disable=SC2016
    grep -Fq 'readonly release="$source_root/$revision"' "$transaction"
    # shellcheck disable=SC2016
    grep -Fq 'install -o caddy-sync -g caddy-sync -m 0440 /dev/null "$request_marker"' \
        "$transaction"
    # shellcheck disable=SC2016
    grep -Fq 'runuser -u caddy-sync -- "$finalizer" --source-role node-a' \
        "$transaction"
    # shellcheck disable=SC2016
    grep -Fq 'rm -f -- "$request_marker" "$pending_marker" "$complete_marker"' \
        "$transaction"
    # shellcheck disable=SC2016
    grep -Fq 'find "$release" -type d -exec chmod 0550 {} +' "$transaction"
    # shellcheck disable=SC2016
    grep -Fq 'find "$release" -type f -exec chmod 0440 {} +' "$transaction"
    grep -Fq 'action17s-node-b-marker-migration.XXXXXX' "$transaction"
    grep -Fq 'persistent_mutation_scope=finalize_request,complete,rollback_metadata' \
        "$transaction"
    grep -Fq "'cd / && sudo -n /bin/bash -s --'" "$runner"
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
        "$transaction" "$runner"; then
        printf 'Action 17s contains a service mutation.\n' >&2
        return 1
    fi
    if grep -Eq '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)' \
        "$transaction" "$runner"; then
        printf 'Action 17s contains a release transfer.\n' >&2
        return 1
    fi
    # shellcheck disable=SC2016
    if grep -Fq 'rm -rf -- "$release"' "$transaction"; then
        printf 'Action 17s rollback removes the retained release.\n' >&2
        return 1
    fi
    if grep -Eq 'ACTION17S_(FIXTURE|CAPTURED|SSH_ARGUMENTS|STATUS)' "$runner"; then
        printf 'Production Action 17s runner contains a fixture bypass.\n' >&2
        return 1
    fi
}

write_success_fixture() {
    local fixture_path=$1
    local fixture_label
    local fixture_count

    fixture_count=$("$transaction" --expected-checks | wc -l)
    {
        while IFS= read -r fixture_label; do
            printf 'action_17s_assertion_%s=true\n' "$fixture_label"
        done < <("$transaction" --expected-checks)
        printf '%s\n' \
            "action_17s_assertion_count=$fixture_count" \
            action_17s_failed_assertion_count=0 \
            action_17s_first_failure=none \
            action_17s_preflight_complete=true \
            action_17s_mutation_started=true \
            action_17s_value_revision=action17p-node-a-to-node-b-bootstrap \
            "action_17s_value_payload_sha256=$expected_payload_sha256" \
            "action_17s_value_manifest_sha256=$expected_manifest_sha256" \
            action_17s_value_before_snapshot_sha256=1111111111111111111111111111111111111111111111111111111111111111 \
            action_17s_value_backup_path=/var/backups/caddy-ha/action17s-node-b-marker-migration.ABC123 \
            action_17s_finalizer_invoked=true \
            action_17s_marker_migration=true \
            action_17s_payload_content_mutation=false \
            action_17s_lsyncd_reconciliation_activation=false \
            action_17s_caddy_selection_changed=false \
            action_17s_service_mutations=false \
            action_17s_persistent_mutation_scope=finalize_request,complete,rollback_metadata \
            action_17s_node_b_marker_migration_complete=true
    } >"$fixture_path"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # These variables exist only in the intercepted regression subprocess.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"$ACTION17S_CAPTURED_TRANSACTION"' \
        'printf "%s\n" "$*" >"$ACTION17S_SSH_ARGUMENTS"' \
        'cat "$ACTION17S_FIXTURE_OUTPUT"' \
        'cat "$ACTION17S_FIXTURE_ERROR" >&2' \
        'exit "$ACTION17S_STATUS"' >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

run_case() {
    local case_error=$1
    local case_output=$2
    local case_root=$3
    local case_runner=$4
    local case_status=$5
    local case_suffix=$6

    set +e
    ACTION17S_CAPTURED_TRANSACTION="$case_root/$case_suffix.transaction" \
        ACTION17S_SSH_ARGUMENTS="$case_root/$case_suffix.arguments" \
        ACTION17S_FIXTURE_OUTPUT="$case_output" \
        ACTION17S_FIXTURE_ERROR="$case_error" \
        ACTION17S_STATUS="$case_status" \
        "$case_runner" >"$case_root/$case_suffix.out" \
        2>"$case_root/$case_suffix.err"
    observed_status=$?
    set -e
}

run_production_path_regression() {
    local case_bin
    local case_root
    local case_runner
    local duplicate_fixture
    local empty_error
    local rollback_error
    local rollback_output
    local valid_fixture

    case_root=$(mktemp -d /tmp/caddy-action17s-regression.XXXXXX)
    trap 'rm -rf -- "$case_root"' RETURN
    case_bin="$case_root/bin"
    install -d -m 0700 \
        "$case_bin" "$case_root/Caddy/scripts" "$case_root/Caddy/tests"
    cp -- "$transaction" "$runner" "$case_root/Caddy/scripts/"
    cp -- "$collision_checker" "$case_root/Caddy/tests/"
    chmod 0755 "$case_root/Caddy/scripts/"*.sh \
        "$case_root/Caddy/tests/check-shell-readonly-local-collisions.sh"
    case_runner="$case_root/Caddy/scripts/run-node-b-retained-release-marker-migration-action17s.sh"
    sed -i "s|^PATH=/usr/bin:/bin$|PATH=$case_bin:/usr/bin:/bin|" "$case_runner"
    write_fake_ssh "$case_bin/ssh"

    valid_fixture="$case_root/valid.fixture"
    empty_error="$case_root/empty.err"
    : >"$empty_error"
    write_success_fixture "$valid_fixture"
    run_case "$empty_error" "$valid_fixture" "$case_root" "$case_runner" 0 valid
    [[ "$observed_status" -eq 0 ]]
    [[ ! -s "$case_root/valid.err" ]]
    grep -Fxq action_17s_runner_acceptance=true "$case_root/valid.out"
    grep -Fxq action_17s_workstation_cleanup_complete=true "$case_root/valid.out"
    cmp -s "$transaction" "$case_root/valid.transaction"
    grep -Fq pi@10.1.0.54 "$case_root/valid.arguments"
    grep -Fq HostKeyAlias=pihole00.local.theama.co \
        "$case_root/valid.arguments"
    grep -Fq 'cd / && sudo -n /bin/bash -s --' "$case_root/valid.arguments"

    duplicate_fixture="$case_root/duplicate.fixture"
    cp -- "$valid_fixture" "$duplicate_fixture"
    printf 'action_17s_assertion_identity_root=true\n' >>"$duplicate_fixture"
    run_case \
        "$empty_error" "$duplicate_fixture" "$case_root" "$case_runner" 0 duplicate
    [[ "$observed_status" -eq 97 ]]
    grep -Fq 'Action 17s success transcript contract failed.' \
        "$case_root/duplicate.err"

    rollback_output="$case_root/rollback.out.fixture"
    rollback_error="$case_root/rollback.err.fixture"
    printf '%s\n' \
        action_17s_preflight_complete=true \
        action_17s_mutation_started=true >"$rollback_output"
    {
        printf 'action_17s_rollback_started=true\n'
        while IFS= read -r rollback_fixture_label; do
            printf 'action_17s_rollback_assertion_%s=true\n' \
                "$rollback_fixture_label"
        done < <("$transaction" --expected-rollback-checks)
        printf 'action_17s_rollback_complete=true\n'
    } >"$rollback_error"
    run_case \
        "$rollback_error" "$rollback_output" "$case_root" "$case_runner" 1 rollback
    [[ "$observed_status" -eq 1 ]]
    grep -Fxq action_17s_runner_acceptance=false "$case_root/rollback.out"
    grep -Fxq action_17s_workstation_cleanup_complete=true \
        "$case_root/rollback.out"

    sed -i '/rollback_complete/d' "$rollback_error"
    run_case \
        "$rollback_error" "$rollback_output" "$case_root" "$case_runner" 1 incomplete
    [[ "$observed_status" -eq 97 ]]
    grep -Fq 'Action 17s rollback evidence is incomplete.' \
        "$case_root/incomplete.err"

    printf '%s\n' \
        action_17s_false_negative_valid_success_accepted=true \
        action_17s_false_negative_complete_rollback_preserved=true \
        action_17s_false_positive_duplicate_assertion_rejected=true \
        action_17s_false_positive_incomplete_rollback_rejected=true \
        action_17s_production_path_network_contact=false
}

assert_hash "$transaction_sha256" "$transaction"
assert_hash "$runner_sha256" "$runner"
assert_hash "$historical_node_a_inspector_sha256" \
    "$caddy_root/scripts/inspect-node-a-protocol-v2-readiness-action17r-c.sh"
assert_hash "$historical_node_b_inspector_sha256" \
    "$caddy_root/scripts/inspect-node-b-protocol-v2-readiness-action17r.sh"
assert_hash "$historical_runner_sha256" \
    "$caddy_root/scripts/run-dual-node-protocol-v2-readiness-action17r-c.sh"
assert_hash "$historical_regression_sha256" \
    "$script_directory/action17r-c-dual-node-protocol-v2-readiness-regression.sh"
printf 'action_17s_regression_assertion_integrity_hashes=true\n'
bash -n "$transaction" "$runner"
shellcheck "$transaction" "$runner"
printf 'action_17s_regression_assertion_shell_validation=true\n'
"$collision_checker" "$transaction" "$runner" "$0" >/dev/null
printf 'action_17s_regression_assertion_readonly_local_collisions_absent=true\n'
"$transaction" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
printf 'action_17s_regression_assertion_self_contract_tests=true\n'
"$source_context_policy" --runner "$runner" >/dev/null
printf 'action_17s_regression_assertion_source_context=true\n'
[[ "$("$transaction" --expected-checks | wc -l)" -eq 143 ]]
[[ "$("$transaction" --expected-checks | LC_ALL=C sort -u | wc -l)" -eq 143 ]]
[[ "$("$transaction" --expected-rollback-checks | wc -l)" -eq 46 ]]
[[ "$("$transaction" --expected-rollback-checks | LC_ALL=C sort -u | wc -l)" -eq 46 ]]
printf 'action_17s_regression_assertion_expected_labels_exact=true\n'
assert_static_policy
printf 'action_17s_regression_assertion_static_policy=true\n'
if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
    [[ "$caddy_root" = /workspace/homelab-server-configs/Caddy ]]
    printf 'action_17s_container_projection_validated=true\n'
else
    run_production_path_regression
fi
printf 'action_17s_regression_assertion_production_boundary=true\n'

printf 'action_17s_node_b_marker_migration_regression_complete=true\n'
