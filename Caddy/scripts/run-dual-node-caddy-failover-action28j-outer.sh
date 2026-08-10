#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28j_outer
readonly node_a_target=pi@10.1.0.53
readonly node_a_alias=pihole0.local.theama.co
readonly node_b_target=pi@10.1.0.54
readonly node_b_alias=pihole00.local.theama.co
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-dual-node-caddy-failover-action28j.sh
readonly transaction=$script_directory/transact-node-a-caddy-failover-action28j.sh
readonly regression=$caddy_root/tests/action28j-node-a-first-caddy-failover-regression.sh
readonly inspector_sha256=3f4e4ca1c55677f22e997d7cda3a105f2bbc662870885f3df1e343b5049de735
readonly transaction_sha256=fd62e65aa587001e855efb691e2efdca69a833b90923edbb93de64f31ddc4aac
readonly regression_sha256=ef76b21b0e81c64d2041544717e7b78a31fc3538e23d66f5d9d0ddc2379690ba
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
work_directory=
mutation_started=false
action_accepted=false
rollback_attempted=false

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
record_gate() {
    local action28j_outer_gate=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28j_outer_gate"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28j_outer_gate" >&2
    return 1
}
record_validation() {
    local action28j_outer_label=$1
    local action28j_outer_value=$2
    validation_count=$((validation_count + 1))
    printf '%s_validation_%s=%s\n' "$prefix" "$action28j_outer_label" "$action28j_outer_value"
    if [[ "$action28j_outer_value" != true ]]; then
        validation_failed=$((validation_failed + 1))
        [[ "$validation_first_failure" != none ]] || validation_first_failure=$action28j_outer_label
    fi
}
validate_command() {
    local action28j_outer_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        record_validation "$action28j_outer_label" true
    else
        record_validation "$action28j_outer_label" false
    fi
}
require_source() {
    local action28j_outer_expected_hash=$1
    local action28j_outer_source=$2
    local action28j_outer_owner=aaron:aaron
    [[ "${CADDY_VALIDATION_CONTAINER:-}" != 1 ]] || action28j_outer_owner=root:root
    [[ -f "$action28j_outer_source" && ! -L "$action28j_outer_source" && -x "$action28j_outer_source" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$action28j_outer_source")" = "$action28j_outer_owner:755" ]] || return 1
    [[ "$(file_hash "$action28j_outer_source")" = "$action28j_outer_expected_hash" ]]
}
working_directory_approved() {
    if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
        [[ "$PWD" = /workspace/homelab-server-configs ]]
    else
        [[ "$PWD" = /home/aaron/code/homelab-server-configs ]]
    fi
}
run_local_gates() {
    record_gate working_directory working_directory_approved
    record_gate inspector_source require_source "$inspector_sha256" "$inspector"
    record_gate transaction_source require_source "$transaction_sha256" "$transaction"
    record_gate regression_source require_source "$regression_sha256" "$regression"
    record_gate syntax /bin/bash -n "$inspector" "$transaction" "$regression" "$0"
    record_gate shellcheck shellcheck "$inspector" "$transaction" "$regression" "$0"
    record_gate canonical_format /bin/bash "$shfmt_canonical" --check "$inspector" "$transaction" "$regression" "$0"
    record_gate collision_policy /bin/bash "$collision_policy" "$inspector" "$transaction" "$regression" "$0"
    record_gate conditional_policy /bin/bash "$conditional_policy"
    record_gate output_policy /bin/bash "$output_policy"
    record_gate scalar_grep_policy /bin/bash "$scalar_grep_policy" --check "$inspector" "$transaction" "$regression" "$0"
    record_gate portable_awk_policy /bin/bash "$portable_awk_policy" --check "$inspector" "$transaction" "$regression" "$0"
    record_gate remote_cwd_policy /bin/bash "$remote_cwd_policy" --check "$0"
    record_gate inspector_self_test /bin/bash "$inspector" --self-test
    record_gate transaction_self_test /bin/bash "$transaction" --self-test
    if [[ "${CADDY_ACTION28J_TEST_MODE:-}" = 1 ]]; then
        record_gate regression test true
    else
        record_gate regression /bin/bash "$regression"
    fi
}
expected_local_gates() {
    printf '%s\n' working_directory inspector_source transaction_source regression_source \
        syntax shellcheck canonical_format collision_policy conditional_policy \
        output_policy scalar_grep_policy portable_awk_policy remote_cwd_policy \
        inspector_self_test transaction_self_test regression
}
safe_stream() {
    local action28j_outer_stream=$1
    [[ "$(wc -c <"$action28j_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28j_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28j_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' "$action28j_outer_stream"
}
emit_stream() {
    local action28j_outer_label=$1
    local action28j_outer_stream=$2
    printf '%s_%s_bytes=%s\n' "$prefix" "$action28j_outer_label" "$(wc -c <"$action28j_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28j_outer_label" "$(line_count "$action28j_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28j_outer_label" "$(file_hash "$action28j_outer_stream")"
    if ! safe_stream "$action28j_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28j_outer_label" >&2
        printf '%s_%s_protected_evidence=%s\n' "$prefix" "$action28j_outer_label" "$work_directory" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28j_outer_label"
    if [[ -s "$action28j_outer_stream" ]]; then
        printf '%s_%s_content_begin\n' "$prefix" "$action28j_outer_label"
        sed "s/^/${prefix}_${action28j_outer_label}_content=/" "$action28j_outer_stream"
        printf '%s_%s_content_end\n' "$prefix" "$action28j_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action28j_outer_label"
    fi
}
run_remote() {
    local action28j_outer_target=$1
    local action28j_outer_alias=$2
    local action28j_outer_source=$3
    local action28j_outer_stdout=$4
    local action28j_outer_stderr=$5
    local action28j_outer_status_name=$6
    shift 6
    local action28j_outer_status=0
    local action28j_outer_ssh=${CADDY_ACTION28J_SSH_PROGRAM:-ssh}
    "$action28j_outer_ssh" -T -o BatchMode=yes -o ClearAllForwardings=yes \
        -o ConnectTimeout=10 -o "HostKeyAlias=$action28j_outer_alias" \
        -o StrictHostKeyChecking=yes "$action28j_outer_target" \
        "cd / && sudo -n /bin/bash -s -- $*" <"$action28j_outer_source" \
        >"$action28j_outer_stdout" 2>"$action28j_outer_stderr" || action28j_outer_status=$?
    printf -v "$action28j_outer_status_name" '%s' "$action28j_outer_status"
}
validate_producer() {
    local action28j_outer_label=$1
    local action28j_outer_source=$2
    local action28j_outer_transcript=$3
    local action28j_outer_stderr=$4
    local action28j_outer_status=$5
    local action28j_outer_record_prefix=$6
    local action28j_outer_expected=$work_directory/$action28j_outer_label.expected
    local action28j_outer_observed=$work_directory/$action28j_outer_label.observed
    sed "s/^/${action28j_outer_record_prefix}_check_/; s/\$/=true/" < <(/bin/bash "$action28j_outer_source" --expected-checks) >"$action28j_outer_expected"
    sed -n "/^${action28j_outer_record_prefix}_check_[a-z0-9_]*=true\$/p" "$action28j_outer_transcript" >"$action28j_outer_observed"
    validate_command "${action28j_outer_label}_status_zero" test "$action28j_outer_status" -eq 0
    validate_command "${action28j_outer_label}_stderr_empty" test ! -s "$action28j_outer_stderr"
    validate_command "${action28j_outer_label}_checks_exact" cmp -s "$action28j_outer_expected" "$action28j_outer_observed"
    validate_command "${action28j_outer_label}_failed_zero" grep -Fqx "${action28j_outer_record_prefix}_failed_check_count=0" "$action28j_outer_transcript"
    validate_command "${action28j_outer_label}_first_failure_none" grep -Fqx "${action28j_outer_record_prefix}_first_failure=none" "$action28j_outer_transcript"
    validate_command "${action28j_outer_label}_accepted" grep -Fqx "${action28j_outer_record_prefix}_acceptance=true" "$action28j_outer_transcript"
    validate_command "${action28j_outer_label}_publisher_absent" grep -Fqx "${action28j_outer_record_prefix}_publisher_invoked=false" "$action28j_outer_transcript"
}
capture_run() {
    local action28j_outer_label=$1
    local action28j_outer_target=$2
    local action28j_outer_alias=$3
    local action28j_outer_source=$4
    local action28j_outer_status_name=$5
    shift 5
    local action28j_outer_stdout=$work_directory/$action28j_outer_label.stdout
    local action28j_outer_stderr=$work_directory/$action28j_outer_label.stderr
    : >"$action28j_outer_stdout"
    : >"$action28j_outer_stderr"
    chmod 0600 "$action28j_outer_stdout" "$action28j_outer_stderr"
    run_remote "$action28j_outer_target" "$action28j_outer_alias" "$action28j_outer_source" \
        "$action28j_outer_stdout" "$action28j_outer_stderr" "$action28j_outer_status_name" "$@"
    emit_stream "${action28j_outer_label}_stdout" "$action28j_outer_stdout"
    emit_stream "${action28j_outer_label}_stderr" "$action28j_outer_stderr"
}
perform_rollback() {
    local action28j_outer_failures_before_rollback=$validation_failed

    rollback_attempted=true
    rollback_status=0
    capture_run rollback "$node_a_target" "$node_a_alias" "$transaction" rollback_status --rollback
    validate_producer rollback "$transaction" "$work_directory/rollback.stdout" \
        "$work_directory/rollback.stderr" "$rollback_status" action_28j_transaction
    validate_command rollback_mode_exact grep -Fqx 'action_28j_transaction_value_mode=rollback' "$work_directory/rollback.stdout"
    [[ "$validation_failed" -eq "$action28j_outer_failures_before_rollback" ]]
}
fallback_rollback() {
    local action28j_outer_exit_status=$?
    if [[ "$mutation_started" = true && "$action_accepted" != true && "$rollback_attempted" != true ]]; then
        ssh -T -o BatchMode=yes -o ClearAllForwardings=yes -o ConnectTimeout=10 \
            -o "HostKeyAlias=$node_a_alias" -o StrictHostKeyChecking=yes "$node_a_target" \
            'cd / && sudo -n /bin/bash -s -- --rollback' <"$transaction" >/dev/null 2>&1 || true
    fi
    [[ -z "$work_directory" || ! -d "$work_directory" ]] || rm -rf -- "$work_directory"
    return "$action28j_outer_exit_status"
}
trap fallback_rollback EXIT

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        local_gate_inventory=$(expected_local_gates) || exit 1
        readonly local_gate_inventory
        [[ "$(printf '%s\n' "$local_gate_inventory" | wc -l)" -eq "$(printf '%s\n' "$local_gate_inventory" | LC_ALL=C sort -u | wc -l)" ]] || exit 1
        CADDY_ACTION28J_TEST_MODE=1
        export CADDY_ACTION28J_TEST_MODE
        run_local_gates
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    '') [[ $# -eq 0 ]] || exit 64 ;;
    *) exit 64 ;;
esac

run_local_gates
work_directory=$(mktemp -d /tmp/caddy-action28j-outer.XXXXXX)
chmod 0700 "$work_directory"

node_a_baseline_status=0
capture_run node_a_baseline "$node_a_target" "$node_a_alias" "$inspector" node_a_baseline_status --node node-a --phase baseline
validate_producer node_a_baseline "$inspector" "$work_directory/node_a_baseline.stdout" "$work_directory/node_a_baseline.stderr" "$node_a_baseline_status" action_28j_node_a_baseline
node_b_baseline_status=0
capture_run node_b_baseline "$node_b_target" "$node_b_alias" "$inspector" node_b_baseline_status --node node-b --phase baseline
validate_producer node_b_baseline "$inspector" "$work_directory/node_b_baseline.stdout" "$work_directory/node_b_baseline.stderr" "$node_b_baseline_status" action_28j_node_b_baseline
if [[ "$validation_failed" -ne 0 ]]; then
    printf '%s_failure=baseline_rejected\n' "$prefix"
    exit 1
fi

failover_status=0
mutation_started=true
capture_run failover "$node_a_target" "$node_a_alias" "$transaction" failover_status --failover
validate_producer failover "$transaction" "$work_directory/failover.stdout" "$work_directory/failover.stderr" "$failover_status" action_28j_transaction
validate_command failover_mode_exact grep -Fqx 'action_28j_transaction_value_mode=failover' "$work_directory/failover.stdout"

node_a_failed_status=0
capture_run node_a_failed "$node_a_target" "$node_a_alias" "$inspector" node_a_failed_status --node node-a --phase failed
validate_producer node_a_failed "$inspector" "$work_directory/node_a_failed.stdout" "$work_directory/node_a_failed.stderr" "$node_a_failed_status" action_28j_node_a_failed
node_b_failed_status=0
capture_run node_b_failed "$node_b_target" "$node_b_alias" "$inspector" node_b_failed_status --node node-b --phase failed
validate_producer node_b_failed "$inspector" "$work_directory/node_b_failed.stdout" "$work_directory/node_b_failed.stderr" "$node_b_failed_status" action_28j_node_b_failed
validate_command node_a_fault_exact grep -Fqx 'action_28j_node_a_failed_value_vrrp_state=FAULT' "$work_directory/node_a_failed.stdout"
validate_command node_b_master_exact grep -Fqx 'action_28j_node_b_failed_value_vrrp_state=MASTER' "$work_directory/node_b_failed.stdout"
validate_command node_a_caddy_ipv4_zero grep -Fqx 'action_28j_node_a_failed_value_caddy_ipv4_count=0' "$work_directory/node_a_failed.stdout"
validate_command node_b_caddy_ipv4_one grep -Fqx 'action_28j_node_b_failed_value_caddy_ipv4_count=1' "$work_directory/node_b_failed.stdout"
validate_command node_a_caddy_ipv6_zero grep -Fqx 'action_28j_node_a_failed_value_caddy_ipv6_count=0' "$work_directory/node_a_failed.stdout"
validate_command node_b_caddy_ipv6_one grep -Fqx 'action_28j_node_b_failed_value_caddy_ipv6_count=1' "$work_directory/node_b_failed.stdout"
validate_command node_a_dns_ipv4_one grep -Fqx 'action_28j_node_a_failed_value_dns_ipv4_count=1' "$work_directory/node_a_failed.stdout"
validate_command node_a_dns_ipv6_one grep -Fqx 'action_28j_node_a_failed_value_dns_ipv6_count=1' "$work_directory/node_a_failed.stdout"
validate_command node_b_dns_ipv4_zero grep -Fqx 'action_28j_node_b_failed_value_dns_ipv4_count=0' "$work_directory/node_b_failed.stdout"
validate_command node_b_dns_ipv6_zero grep -Fqx 'action_28j_node_b_failed_value_dns_ipv6_count=0' "$work_directory/node_b_failed.stdout"

if [[ "$validation_failed" -ne 0 ]]; then
    if ! perform_rollback; then
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        exit 125
    fi
    printf '%s_rollback_complete=true\n' "$prefix"
    exit 1
fi

action_accepted=true
printf '%s_validation_count=%s\n' "$prefix" "$validation_count"
printf '%s_validation_failed=0\n' "$prefix"
printf '%s_validation_first_failure=none\n' "$prefix"
printf '%s_node_a_caddy_stopped=true\n' "$prefix"
printf '%s_node_b_master=true\n' "$prefix"
printf '%s_emergency_publisher_invoked=false\n' "$prefix"
printf '%s_publication_created=false\n' "$prefix"
printf '%s_transfer_invoked=false\n' "$prefix"
printf '%s_rollback_invoked=false\n' "$prefix"
printf '%s_acceptance=true\n' "$prefix"
rm -rf -- "$work_directory"
work_directory=
trap - EXIT
