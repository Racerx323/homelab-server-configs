#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28h_outer
readonly node_b_alias=pihole00.local.theama.co
readonly node_b_target=pi@10.1.0.54
readonly probe_sha256=d6c69b9b43d807986c647c6a449e3c431f76cfb1c4fddf976b24473161a2d300
readonly regression_sha256=55d64b819bd6893802436be1219ee15583ac24e3539585c8fb070c7a06597e5e
readonly action28g_c_outer_sha256=24f7a4fc6e37a5c878fc6cc89f145a1ba3422e773ceabf780ef83f194a99ec8b
readonly maximum_stream_bytes=262144
readonly maximum_stream_lines=2048

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly probe=$script_directory/inspect-node-b-normal-publisher-rejection-action28h.sh
readonly regression=$caddy_root/tests/action28h-node-b-normal-publisher-rejection-regression.sh
readonly action28g_c_outer=$script_directory/run-dual-node-protocol-v2-post-action28g-c-outer.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh
readonly collision_policy=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional_policy=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly output_policy=$caddy_root/tests/transaction-output-evidence-policy-regression.sh
readonly scalar_grep_policy=$caddy_root/tests/multifile-grep-count-policy.sh
readonly portable_awk_policy=$caddy_root/tests/portable-awk-policy.sh
readonly remote_cwd_policy=$caddy_root/tests/remote-streamed-bash-cwd-policy.sh

validation_count=0
validation_failed=0
validation_first_failure=none

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

record_gate() {
    local action28h_outer_gate_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28h_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28h_outer_gate_label" >&2
    return 1
}

record_validation() {
    local action28h_outer_validation_label=$1
    local action28h_outer_validation_value=$2

    validation_count=$((validation_count + 1))
    printf '%s_validation_%s=%s\n' "$prefix" "$action28h_outer_validation_label" \
        "$action28h_outer_validation_value"
    if [[ "$action28h_outer_validation_value" != true ]]; then
        validation_failed=$((validation_failed + 1))
        if [[ "$validation_first_failure" == none ]]; then
            validation_first_failure=$action28h_outer_validation_label
        fi
    fi
}

validate_command() {
    local action28h_outer_command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_validation "$action28h_outer_command_label" true
    else
        record_validation "$action28h_outer_command_label" false
    fi
}

require_source() {
    local action28h_outer_expected_hash=$1
    local action28h_outer_source=$2
    local action28h_outer_expected_owner=aaron:aaron

    if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
        action28h_outer_expected_owner=root:root
    fi
    [[ -f "$action28h_outer_source" && ! -L "$action28h_outer_source" &&
        -x "$action28h_outer_source" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$action28h_outer_source")" == "$action28h_outer_expected_owner:755" ]] || return 1
    [[ "$(file_hash "$action28h_outer_source")" == "$action28h_outer_expected_hash" ]]
}

working_directory_approved() {
    if [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]; then
        [[ "$PWD" == /workspace/homelab-server-configs ]]
        return
    fi
    [[ "$PWD" == /home/aaron/code/homelab-server-configs ]]
}

run_local_gates() {
    record_gate working_directory working_directory_approved
    record_gate probe_source require_source "$probe_sha256" "$probe"
    record_gate regression_source require_source "$regression_sha256" "$regression"
    record_gate action28g_c_outer_immutable test "$(file_hash "$action28g_c_outer")" = \
        "$action28g_c_outer_sha256"
    record_gate syntax /bin/bash -n "$probe" "$regression" "$0"
    record_gate shellcheck shellcheck "$probe" "$regression" "$0"
    record_gate canonical_format /bin/bash "$shfmt_canonical" --check \
        "$probe" "$regression" "$0"
    record_gate collision_policy /bin/bash "$collision_policy" "$probe" "$regression" "$0"
    record_gate conditional_policy /bin/bash "$conditional_policy"
    record_gate output_policy /bin/bash "$output_policy"
    record_gate scalar_grep_policy /bin/bash "$scalar_grep_policy" --check \
        "$probe" "$regression" "$0"
    record_gate portable_awk_policy /bin/bash "$portable_awk_policy" --check \
        "$probe" "$regression" "$0"
    record_gate remote_cwd_policy /bin/bash "$remote_cwd_policy" --check "$0"
    record_gate probe_self_test /bin/bash "$probe" --self-test
    if [[ "${CADDY_ACTION28H_TEST_MODE:-}" == 1 ]]; then
        record_gate regression_intercept test true
    else
        record_gate regression /bin/bash "$regression"
    fi
}

safe_stream() {
    local action28h_outer_stream=$1

    [[ "$(wc -c <"$action28h_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28h_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28h_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action28h_outer_stream"
}

emit_stream() {
    local action28h_outer_stream_label=$1
    local action28h_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28h_outer_stream_label" \
        "$(wc -c <"$action28h_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28h_outer_stream_label" \
        "$(line_count "$action28h_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28h_outer_stream_label" \
        "$(file_hash "$action28h_outer_stream")"
    if ! safe_stream "$action28h_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" \
            "$action28h_outer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28h_outer_stream_label"
    printf '%s_%s_content_begin\n' "$prefix" "$action28h_outer_stream_label"
    while IFS= read -r action28h_outer_stream_line ||
        [[ -n "$action28h_outer_stream_line" ]]; do
        printf '%s_%s_content=%s\n' "$prefix" "$action28h_outer_stream_label" \
            "$action28h_outer_stream_line"
    done <"$action28h_outer_stream"
    printf '%s_%s_content_end\n' "$prefix" "$action28h_outer_stream_label"
}

extract_one() {
    local action28h_outer_key=$1
    local action28h_outer_transcript=$2
    local action28h_outer_value

    [[ "$(grep -Ec "^${action28h_outer_key}=" "$action28h_outer_transcript")" -eq 1 ]] || return 1
    action28h_outer_value=$(grep -E "^${action28h_outer_key}=" "$action28h_outer_transcript")
    printf '%s\n' "${action28h_outer_value#*=}"
}

grammar_exact() {
    local action28h_outer_transcript=$1

    while IFS= read -r action28h_outer_line || [[ -n "$action28h_outer_line" ]]; do
        case "$action28h_outer_line" in
            action_28h_node_b_check_*=true | action_28h_node_b_value_*=* | \
                action_28h_node_b_check_count=* | action_28h_node_b_failed_check_count=0 | \
                action_28h_node_b_first_failure=none | action_28h_node_b_publisher_invoked=true | \
                action_28h_node_b_emergency_flag_supplied=false | \
                action_28h_node_b_publication_created=false | action_28h_node_b_ssh_invoked=false | \
                action_28h_node_b_rsync_invoked=false | action_28h_node_b_node_a_contacted=false | \
                action_28h_node_b_filesystem_mutations=false | \
                action_28h_node_b_service_mutations=false | action_28h_node_b_acceptance=true) ;;
            *) return 1 ;;
        esac
    done <"$action28h_outer_transcript"
}

validate_transcript() {
    local action28h_outer_transcript=$1
    local action28h_outer_stderr=$2
    local action28h_outer_status=$3
    local action28h_outer_expected=$4
    local action28h_outer_observed=$5
    local action28h_outer_before
    local action28h_outer_after
    local action28h_outer_before_count
    local action28h_outer_after_count

    validate_command remote_status_zero test "$action28h_outer_status" -eq 0
    validate_command remote_stderr_empty test ! -s "$action28h_outer_stderr"
    validate_command transcript_grammar_exact grammar_exact "$action28h_outer_transcript"
    sed 's/^/action_28h_node_b_check_/; s/$/=true/' < <("$probe" --expected-checks) \
    >"$action28h_outer_expected"
    sed -n '/^action_28h_node_b_check_[a-z0-9_]*=true$/p' \
        "$action28h_outer_transcript" >"$action28h_outer_observed"
    validate_command assertion_inventory_exact cmp -s \
        "$action28h_outer_expected" "$action28h_outer_observed"
    validate_command rejection_status_exact grep -Fqx \
        'action_28h_node_b_value_publisher_status=1' "$action28h_outer_transcript"
    validate_command rejection_stderr_exact grep -Fqx \
        'action_28h_node_b_value_publisher_stderr_content=Node B publishing requires --emergency.' \
        "$action28h_outer_transcript"
    validate_command publisher_stdout_empty grep -Fqx \
        'action_28h_node_b_value_publisher_stdout_bytes=0' "$action28h_outer_transcript"
    validate_command publisher_stdout_lines_exact grep -Fqx \
        'action_28h_node_b_value_publisher_stdout_lines=0' "$action28h_outer_transcript"
    validate_command publisher_stdout_hash_exact grep -Fqx \
        'action_28h_node_b_value_publisher_stdout_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' \
        "$action28h_outer_transcript"
    validate_command publisher_stderr_bytes_exact grep -Fqx \
        'action_28h_node_b_value_publisher_stderr_bytes=40' "$action28h_outer_transcript"
    validate_command publisher_stderr_lines_exact grep -Fqx \
        'action_28h_node_b_value_publisher_stderr_lines=1' "$action28h_outer_transcript"
    validate_command publisher_stderr_hash_exact grep -Fqx \
        'action_28h_node_b_value_publisher_stderr_sha256=5a0cfb38d9dc7d58f9024dd72eff955e6ea9a881200bf1d16a0ba896a67366b7' \
        "$action28h_outer_transcript"
    validate_command vrrp_state_backup grep -Fqx \
        'action_28h_node_b_value_vrrp_state=BACKUP' "$action28h_outer_transcript"
    action28h_outer_before=$(extract_one action_28h_node_b_value_before_snapshot_sha256 \
        "$action28h_outer_transcript") || action28h_outer_before=invalid
    action28h_outer_after=$(extract_one action_28h_node_b_value_after_snapshot_sha256 \
        "$action28h_outer_transcript") || action28h_outer_after=invalid
    validate_command before_snapshot_hash_valid test ${#action28h_outer_before} -eq 64
    validate_command after_snapshot_hash_valid test ${#action28h_outer_after} -eq 64
    validate_command snapshots_equal test "$action28h_outer_after" = "$action28h_outer_before"
    action28h_outer_before_count=$(extract_one action_28h_node_b_value_before_outbound_entry_count \
        "$action28h_outer_transcript") || action28h_outer_before_count=invalid
    action28h_outer_after_count=$(extract_one action_28h_node_b_value_after_outbound_entry_count \
        "$action28h_outer_transcript") || action28h_outer_after_count=invalid
    validate_command outbound_counts_numeric test "$action28h_outer_before_count" -eq \
        "$action28h_outer_before_count"
    validate_command outbound_counts_equal test "$action28h_outer_after_count" -eq \
        "$action28h_outer_before_count"
    validate_command publisher_invoked_once grep -Fqx \
        'action_28h_node_b_publisher_invoked=true' "$action28h_outer_transcript"
    validate_command emergency_flag_absent grep -Fqx \
        'action_28h_node_b_emergency_flag_supplied=false' "$action28h_outer_transcript"
    validate_command publication_absent grep -Fqx \
        'action_28h_node_b_publication_created=false' "$action28h_outer_transcript"
    validate_command ssh_absent grep -Fqx \
        'action_28h_node_b_ssh_invoked=false' "$action28h_outer_transcript"
    validate_command rsync_absent grep -Fqx \
        'action_28h_node_b_rsync_invoked=false' "$action28h_outer_transcript"
    validate_command node_a_contact_absent grep -Fqx \
        'action_28h_node_b_node_a_contacted=false' "$action28h_outer_transcript"
    validate_command filesystem_mutation_absent grep -Fqx \
        'action_28h_node_b_filesystem_mutations=false' "$action28h_outer_transcript"
    validate_command service_mutation_absent grep -Fqx \
        'action_28h_node_b_service_mutations=false' "$action28h_outer_transcript"
    validate_command remote_acceptance grep -Fqx \
        'action_28h_node_b_acceptance=true' "$action28h_outer_transcript"
}

case "${1:-}" in
    --test-validate)
        [[ "${CADDY_ACTION28H_TEST_MODE:-}" == 1 && $# -eq 4 ]] || exit 64
        test_directory=$(mktemp -d /tmp/caddy-action28h-validate.XXXXXX)
        trap 'rm -rf -- "$test_directory"' EXIT
        validate_transcript "$2" "$3" "$4" "$test_directory/expected" \
            "$test_directory/observed" >/dev/null
        [[ "$validation_failed" -eq 0 ]]
        exit
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        require_source "$probe_sha256" "$probe"
        "$probe" --self-test >/dev/null
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
work_directory=$(mktemp -d /tmp/caddy-action28h-outer.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly remote_stdout=$work_directory/node-b.stdout
readonly remote_stderr=$work_directory/node-b.stderr
readonly expected_checks=$work_directory/expected
readonly observed_checks=$work_directory/observed
: >"$remote_stdout"
: >"$remote_stderr"
chmod 0600 "$remote_stdout" "$remote_stderr"

ssh_program=ssh
if [[ "${CADDY_ACTION28H_TEST_MODE:-}" == 1 ]]; then
    ssh_program=${CADDY_ACTION28H_SSH_PROGRAM:?}
fi
readonly ssh_program
remote_status=0
"$ssh_program" -T -o BatchMode=yes -o ConnectTimeout=5 \
    -o "HostKeyAlias=$node_b_alias" -o StrictHostKeyChecking=yes \
    "$node_b_target" 'cd / && sudo -n /bin/bash -s -- --run' \
    <"$probe" >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
readonly remote_status

emit_stream node_b_stdout "$remote_stdout"
emit_stream node_b_stderr "$remote_stderr"
validate_transcript "$remote_stdout" "$remote_stderr" "$remote_status" \
    "$expected_checks" "$observed_checks"

printf '%s_validation_count=%s\n' "$prefix" "$validation_count"
printf '%s_validation_failed=%s\n' "$prefix" "$validation_failed"
printf '%s_validation_first_failure=%s\n' "$prefix" "$validation_first_failure"
printf '%s_node_b_contacted=true\n' "$prefix"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_normal_publisher_invoked=true\n' "$prefix"
printf '%s_emergency_publisher_invoked=false\n' "$prefix"
printf '%s_publication_created=false\n' "$prefix"
printf '%s_transfer_started=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"

if [[ "$validation_failed" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$prefix"
    exit 97
fi
printf '%s_acceptance=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
