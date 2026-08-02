#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly inspector="$caddy_root/scripts/inspect-release-transfer-failure-action17p-a.sh"
readonly runner="$caddy_root/scripts/run-release-transfer-failure-diagnostic-action17p-a.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions.sh"
readonly source_context_policy="$script_directory/run-source-test-in-context.sh"
readonly inspector_sha256=cb6100bca0d67a5eabcf432daa5794c91684780cd3a1861ae432550b0e55e8d1
readonly runner_sha256=0e2d887516efe40f689f10ff7be4de4c22a17d84b43aa1db729f10f58cbb77d8
readonly collision_checker_sha256=78b46fcdc6c4ca6b4cfe0121c347e0e101c472d723a891aac2dea7f23f085cd8
readonly node_a_assertion_count=50
readonly node_b_assertion_count=54
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly parent_revision=action15-health-follow-redirects

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

write_fixture() {
    local fixture_path=$1
    local fixture_role=$2
    local fixture_expected_count=$3
    local fixture_marker_state=$4
    local fixture_writable=$5
    local fixture_false_index=${6:-0}
    local fixture_prefix="action_17p_a_${fixture_role//-/_}"
    local fixture_index
    local fixture_value
    local fixture_failed_count=0
    local fixture_first_failure=none
    local fixture_conclusion
    local fixture_state=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local fixture_payload=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local fixture_manifest=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

    for ((fixture_index = 1;  \
    fixture_index <= fixture_expected_count;  \
    fixture_index += 1)); do
        fixture_value=true
        if [[ "$fixture_index" -eq "$fixture_false_index" ]]; then
            fixture_value=false
            fixture_failed_count=1
            fixture_first_failure="fixture_$fixture_index"
        fi
        printf '%s_assertion_fixture_%02d=%s\n' \
            "$fixture_prefix" "$fixture_index" "$fixture_value"
    done >"$fixture_path"
    fixture_conclusion="marker_${fixture_marker_state%%_*}_release_"
    if [[ "$fixture_writable" == true ]]; then
        fixture_conclusion+=writable
    else
        fixture_conclusion+=nonwritable
    fi
    printf '%s\n' \
        "${fixture_prefix}_value_node_role=$fixture_role" \
        "${fixture_prefix}_value_revision=$revision" \
        "${fixture_prefix}_value_parent_revision=$parent_revision" \
        "${fixture_prefix}_value_before_state_sha256=$fixture_state" \
        "${fixture_prefix}_value_after_state_sha256=$fixture_state" \
        "${fixture_prefix}_value_payload_sha256=$fixture_payload" \
        "${fixture_prefix}_value_manifest_sha256=$fixture_manifest" \
        "${fixture_prefix}_value_marker_state=$fixture_marker_state" \
        "${fixture_prefix}_value_release_owner=caddy-sync" \
        "${fixture_prefix}_value_release_group=caddy-sync" \
        "${fixture_prefix}_value_release_mode=550" \
        "${fixture_prefix}_value_release_writable_by_sync=$fixture_writable" \
        "${fixture_prefix}_value_acl_tool_available=false" \
        "${fixture_prefix}_value_acl_sha256=unavailable" \
        "${fixture_prefix}_value_conclusion=$fixture_conclusion" \
        "${fixture_prefix}_assertion_count=$fixture_expected_count" \
        "${fixture_prefix}_failed_assertion_count=$fixture_failed_count" \
        "${fixture_prefix}_first_failure=$fixture_first_failure" \
        "${fixture_prefix}_peer_connections=false" \
        "${fixture_prefix}_release_transfer_executed=false" \
        "${fixture_prefix}_completion_marker_write_executed=false" \
        "${fixture_prefix}_reconciliation_executed=false" \
        "${fixture_prefix}_service_mutations=false" \
        "${fixture_prefix}_persistent_mutations=false" \
        "${fixture_prefix}_remote_complete=true" >>"$fixture_path"
}

write_fake_ssh() {
    local fake_ssh_path=$1

    # shellcheck disable=SC2016
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'set -euo pipefail'
        printf '%s\n' 'cat >/dev/null'
        printf '%s\n' 'printf "%s\n" "$*" >>"$ACTION17P_A_SSH_LOG"'
        printf '%s\n' 'case " $* " in'
        printf '%s\n' '    *" pi@10.1.0.53 "*)'
        printf '%s\n' '        fixture=$ACTION17P_A_NODE_A_FIXTURE'
        printf '%s\n' '        ;;'
        printf '%s\n' '    *" pi@10.1.0.54 "*)'
        printf '%s\n' \
            '        count=$(grep -Fc " pi@10.1.0.54 " "$ACTION17P_A_SSH_LOG")'
        printf '%s\n' '        if [[ "$count" -eq 1 ]]; then'
        printf '%s\n' \
            '            fixture=$ACTION17P_A_NODE_B_BEFORE_FIXTURE'
        printf '%s\n' '        else'
        printf '%s\n' \
            '            fixture=$ACTION17P_A_NODE_B_AFTER_FIXTURE'
        printf '%s\n' '        fi'
        printf '%s\n' '        ;;'
        printf '%s\n' '    *)'
        printf '%s\n' '        exit 92'
        printf '%s\n' '        ;;'
        printf '%s\n' 'esac'
        printf '%s\n' 'cat "$fixture"'
        printf '%s\n' \
            'failed=$(sed -n "s/.*_failed_assertion_count=//p" "$fixture")'
        printf '%s\n' 'if [[ "$failed" -gt 0 ]]; then'
        printf '%s\n' '    exit 1'
        printf '%s\n' 'fi'
    } >"$fake_ssh_path"
    chmod 0755 "$fake_ssh_path"
}

prepare_case() {
    local case_directory=$1
    local node_b_marker=$2
    local node_b_false_index=${3:-0}
    local case_scripts="$case_directory/Caddy/scripts"
    local case_tests="$case_directory/Caddy/tests"
    local case_bin="$case_directory/bin"

    install -d -m 0700 "$case_scripts" "$case_tests" "$case_bin"
    cp -- "$inspector" "$collision_checker" "$case_scripts/"
    mv -- \
        "$case_scripts/check-shell-readonly-local-collisions.sh" \
        "$case_tests/check-shell-readonly-local-collisions.sh"
    sed \
        "s|^PATH=/usr/bin:/bin$|PATH=$case_bin:/usr/bin:/bin|" \
        "$runner" >"$case_scripts/run-release-transfer-failure-diagnostic-action17p-a.sh"
    chmod 0755 \
        "$case_scripts/run-release-transfer-failure-diagnostic-action17p-a.sh"
    write_fake_ssh "$case_bin/ssh"
    write_fixture \
        "$case_directory/node-a.fixture" node-a "$node_a_assertion_count" \
        present_empty_regular false
    write_fixture \
        "$case_directory/node-b-before.fixture" node-b \
        "$node_b_assertion_count" "$node_b_marker" false \
        "$node_b_false_index"
    cp -- \
        "$case_directory/node-b-before.fixture" \
        "$case_directory/node-b-after.fixture"
}

run_case() {
    local case_directory=$1
    local expected_status=$2
    local expected_classification=$3
    local case_runner="$case_directory/Caddy/scripts/run-release-transfer-failure-diagnostic-action17p-a.sh"
    local case_status=0

    : >"$case_directory/ssh.log"
    ACTION17P_A_SSH_LOG="$case_directory/ssh.log" \
        ACTION17P_A_NODE_A_FIXTURE="$case_directory/node-a.fixture" \
        ACTION17P_A_NODE_B_BEFORE_FIXTURE="$case_directory/node-b-before.fixture" \
        ACTION17P_A_NODE_B_AFTER_FIXTURE="$case_directory/node-b-after.fixture" \
        "$case_runner" >"$case_directory/runner.out" \
        2>"$case_directory/runner.err" || case_status=$?
    [[ "$case_status" -eq "$expected_status" ]]
    grep -Fxq \
        "action_17p_a_runner_classification=$expected_classification" \
        "$case_directory/runner.out"
    [[ ! -s "$case_directory/runner.err" ]]
    [[ "$(wc -l <"$case_directory/ssh.log")" -eq 3 ]]
    [[ "$(grep -Fc ' pi@10.1.0.53 ' \
        "$case_directory/ssh.log")" -eq 1 ]]
    [[ "$(grep -Fc ' pi@10.1.0.54 ' \
        "$case_directory/ssh.log")" -eq 2 ]]
}

run_regression() {
    local regression_root
    local static_path

    [[ "$(file_hash "$inspector")" == "$inspector_sha256" ]]
    [[ "$(file_hash "$runner")" == "$runner_sha256" ]]
    [[ "$(file_hash "$collision_checker")" == "$collision_checker_sha256" ]]
    bash -n "$inspector" "$runner"
    shellcheck "$inspector" "$runner"
    "$collision_checker" "$inspector" "$runner" >/dev/null
    "$inspector" --self-test >/dev/null
    "$runner" --self-test >/dev/null
    "$runner" --contract-test >/dev/null
    "$source_context_policy" --runner "$runner" >/dev/null

    for static_path in "$inspector" "$runner"; do
        if grep -Eq \
            'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
            "$static_path"; then
            printf 'Action 17p-a contains a service mutation.\n' >&2
            exit 1
        fi
        if grep -Eq \
            '^[[:space:]]*(rsync|scp|sftp)([[:space:]]|$)' \
            "$static_path"; then
            printf 'Action 17p-a contains a transport probe or transfer.\n' >&2
            exit 1
        fi
    done
    if grep -Eq \
        '^[[:space:]]*(chmod|chown|cp|install|ln|mkdir|mv|tee|touch|truncate)([[:space:]]|$)' \
        "$inspector"; then
        printf 'Action 17p-a inspector contains a persistent mutation.\n' >&2
        exit 1
    fi
    if grep -Fq 'ACTION17P_A_' "$runner"; then
        printf 'Production Action 17p-a runner contains a fixture bypass.\n' >&2
        exit 1
    fi

    regression_root=$(mktemp -d /tmp/caddy-action17p-a-regression.XXXXXX)
    trap 'rm -rf -- "$regression_root"' RETURN
    prepare_case "$regression_root/absent" absent
    prepare_case "$regression_root/present" present_empty_regular
    prepare_case "$regression_root/mismatch" absent 7
    prepare_case "$regression_root/duplicate" absent
    printf 'action_17p_a_node_b_assertion_fixture_01=true\n' \
        >>"$regression_root/duplicate/node-b-after.fixture"

    run_case "$regression_root/absent" 0 state_verified
    run_case "$regression_root/present" 0 state_verified
    run_case "$regression_root/mismatch" 1 semantic_mismatch
    run_case "$regression_root/duplicate" 97 evidence_failure

    printf 'action_17p_a_false_negative_absent_marker_production_accepted=true\n'
    printf 'action_17p_a_false_negative_present_marker_production_accepted=true\n'
    printf 'action_17p_a_false_negative_semantic_mismatch_production_classified=true\n'
    printf 'action_17p_a_false_positive_duplicate_production_rejected=true\n'
    printf 'action_17p_a_production_path_network_contact=false\n'
    printf 'action_17p_a_regression_complete=true\n'
}

case "${1:-}" in
    --self-test | --production-test)
        [[ $# -eq 1 ]]
        run_regression
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
