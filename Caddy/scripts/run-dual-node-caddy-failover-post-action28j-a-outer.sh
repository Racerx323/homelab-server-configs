#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28j_a_outer
readonly node_a_target=pi@10.1.0.53
readonly node_a_alias=pihole0.local.theama.co
readonly node_b_target=pi@10.1.0.54
readonly node_b_alias=pihole00.local.theama.co
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=${script_directory%/scripts}
readonly caddy_root
readonly state_inspector=$script_directory/inspect-dual-node-caddy-failover-action28j.sh
readonly route_inspector=$script_directory/inspect-caddy-failover-action28j-a-route.sh
readonly residue_inspector=$script_directory/inspect-caddy-failover-action28j-a-residue.sh
readonly regression=$caddy_root/tests/action28j-a-dual-node-failover-post-regression.sh
readonly state_inspector_sha256=3f4e4ca1c55677f22e997d7cda3a105f2bbc662870885f3df1e343b5049de735
readonly route_inspector_sha256=33c1ba24aedc557d7c6e09bf9ecac2221b77b569759ebc60247ee7084f414068
readonly residue_inspector_sha256=c7ea3f9bc127dc8636bd860aadcf80c15961e84d08910f874615073427a90c5b
readonly regression_sha256=dddc97375ae42544fd5ffac375bd11f3f611a3ba2635ea21191c055b5e281737
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

work_root=
validation_count=0
validation_failed=0
validation_first_failure=none

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
            ;;
        *) return 1 ;;
    esac
}
require_source() {
    local action28j_a_outer_source=$1
    local action28j_a_outer_expected_hash=$2
    local action28j_a_outer_expected_owner=aaron:aaron

    [[ "${CADDY_VALIDATION_CONTAINER:-}" != 1 ]] || action28j_a_outer_expected_owner=root:root
    [[ -f "$action28j_a_outer_source" && ! -L "$action28j_a_outer_source" &&
        -x "$action28j_a_outer_source" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$action28j_a_outer_source")" = "$action28j_a_outer_expected_owner:755" ]] || return 1
    [[ "$(file_hash "$action28j_a_outer_source")" = "$action28j_a_outer_expected_hash" ]]
}
read_only_contract() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|(^|[[:space:]])(install|mv|cp|chmod|chown|rsync)[[:space:]]' \
        "$state_inspector" "$route_inspector" "$residue_inspector"
}
local_residue_absent() {
    [[ -z "$(find /tmp -maxdepth 1 -type d -name 'caddy-action28j-outer.*' -print -quit)" ]]
}
record_gate() {
    local action28j_a_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28j_a_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28j_a_outer_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' working_directory state_inspector_source route_inspector_source residue_inspector_source \
        regression_source syntax shellcheck canonical_format collision_policy \
        conditional_policy output_policy scalar_grep_policy portable_awk_policy \
        remote_cwd_policy state_inspector_self_test route_inspector_self_test residue_inspector_self_test \
        read_only_contract local_residue_absent regression
}
run_local_gates() {
    local action28j_a_outer_skip_regression=$1

    record_gate working_directory working_directory_approved || return 1
    record_gate state_inspector_source require_source "$state_inspector" "$state_inspector_sha256" || return 1
    record_gate route_inspector_source require_source "$route_inspector" "$route_inspector_sha256" || return 1
    record_gate residue_inspector_source require_source "$residue_inspector" "$residue_inspector_sha256" || return 1
    record_gate regression_source require_source "$regression" "$regression_sha256" || return 1
    record_gate syntax /bin/bash -n "$state_inspector" "$route_inspector" "$residue_inspector" "$regression" "$0" || return 1
    record_gate shellcheck shellcheck "$state_inspector" "$route_inspector" "$residue_inspector" "$regression" "$0" || return 1
    record_gate canonical_format /bin/bash "$shfmt_canonical" --check \
        "$state_inspector" "$route_inspector" "$residue_inspector" "$regression" "$0" || return 1
    record_gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$state_inspector" "$route_inspector" "$residue_inspector" "$regression" "$0" || return 1
    record_gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    record_gate output_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    record_gate scalar_grep_policy /bin/bash \
        "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$state_inspector" "$route_inspector" "$residue_inspector" "$regression" "$0" || return 1
    record_gate portable_awk_policy /bin/bash \
        "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$state_inspector" "$route_inspector" "$residue_inspector" "$regression" "$0" || return 1
    record_gate remote_cwd_policy /bin/bash \
        "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" --check "$0" || return 1
    record_gate state_inspector_self_test /bin/bash "$state_inspector" --self-test || return 1
    record_gate route_inspector_self_test /bin/bash "$route_inspector" --self-test || return 1
    record_gate residue_inspector_self_test /bin/bash "$residue_inspector" --self-test || return 1
    record_gate read_only_contract read_only_contract || return 1
    record_gate local_residue_absent local_residue_absent || return 1
    if [[ "$action28j_a_outer_skip_regression" = true ]]; then
        record_gate regression true || return 1
    else
        record_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action28j_a_outer_stream=$1

    [[ "$(wc -c <"$action28j_a_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28j_a_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28j_a_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action28j_a_outer_stream"
}
emit_stream() {
    local action28j_a_outer_label=$1
    local action28j_a_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28j_a_outer_label" "$(wc -c <"$action28j_a_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28j_a_outer_label" "$(line_count "$action28j_a_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28j_a_outer_label" "$(file_hash "$action28j_a_outer_stream")"
    if ! safe_stream "$action28j_a_outer_stream"; then
        trap - EXIT
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28j_a_outer_label" >&2
        printf '%s_%s_protected_evidence=%s\n' "$prefix" "$action28j_a_outer_label" "$work_root" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28j_a_outer_label"
    if [[ -s "$action28j_a_outer_stream" ]]; then
        printf '%s_%s_content_begin\n' "$prefix" "$action28j_a_outer_label"
        sed "s/^/${prefix}_${action28j_a_outer_label}_content=/" "$action28j_a_outer_stream"
        printf '%s_%s_content_end\n' "$prefix" "$action28j_a_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action28j_a_outer_label"
    fi
}
record_validation() {
    local action28j_a_outer_label=$1
    local action28j_a_outer_result=$2

    validation_count=$((validation_count + 1))
    printf '%s_validation_%s=%s\n' "$prefix" "$action28j_a_outer_label" "$action28j_a_outer_result"
    if [[ "$action28j_a_outer_result" != true ]]; then
        validation_failed=$((validation_failed + 1))
        [[ "$validation_first_failure" != none ]] || validation_first_failure=$action28j_a_outer_label
    fi
}
validate_command() {
    local action28j_a_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_validation "$action28j_a_outer_label" true
    else
        record_validation "$action28j_a_outer_label" false
    fi
}
run_remote() {
    local action28j_a_outer_target=$1
    local action28j_a_outer_alias=$2
    local action28j_a_outer_source=$3
    local action28j_a_outer_stdout=$4
    local action28j_a_outer_stderr=$5
    local action28j_a_outer_status_name=$6

    shift 6
    local action28j_a_outer_status=0
    local action28j_a_outer_ssh=${CADDY_ACTION28J_A_SSH_PROGRAM:-ssh}
    "$action28j_a_outer_ssh" -T -o BatchMode=yes -o ClearAllForwardings=yes \
        -o ConnectTimeout=10 -o "HostKeyAlias=$action28j_a_outer_alias" \
        -o StrictHostKeyChecking=yes "$action28j_a_outer_target" \
        "cd / && sudo -n /bin/bash -s -- $*" <"$action28j_a_outer_source" \
        >"$action28j_a_outer_stdout" 2>"$action28j_a_outer_stderr" || action28j_a_outer_status=$?
    printf -v "$action28j_a_outer_status_name" '%s' "$action28j_a_outer_status"
}
capture_run() {
    local action28j_a_outer_label=$1
    local action28j_a_outer_target=$2
    local action28j_a_outer_alias=$3
    local action28j_a_outer_source=$4
    local action28j_a_outer_status_name=$5

    shift 5
    local action28j_a_outer_stdout=$work_root/$action28j_a_outer_label.stdout
    local action28j_a_outer_stderr=$work_root/$action28j_a_outer_label.stderr
    : >"$action28j_a_outer_stdout"
    : >"$action28j_a_outer_stderr"
    chmod 0600 "$action28j_a_outer_stdout" "$action28j_a_outer_stderr"
    run_remote "$action28j_a_outer_target" "$action28j_a_outer_alias" \
        "$action28j_a_outer_source" "$action28j_a_outer_stdout" \
        "$action28j_a_outer_stderr" "$action28j_a_outer_status_name" "$@"
    emit_stream "${action28j_a_outer_label}_stdout" "$action28j_a_outer_stdout"
    emit_stream "${action28j_a_outer_label}_stderr" "$action28j_a_outer_stderr"
}
validate_producer() {
    local action28j_a_outer_label=$1
    local action28j_a_outer_source=$2
    local action28j_a_outer_transcript=$3
    local action28j_a_outer_stderr=$4
    local action28j_a_outer_status=$5
    local action28j_a_outer_record_prefix=$6
    local action28j_a_outer_expected=$work_root/$action28j_a_outer_label.expected
    local action28j_a_outer_observed=$work_root/$action28j_a_outer_label.observed

    sed "s/^/${action28j_a_outer_record_prefix}_check_/; s/\$/=true/" \
        < <(/bin/bash "$action28j_a_outer_source" --expected-checks) >"$action28j_a_outer_expected"
    sed -n "/^${action28j_a_outer_record_prefix}_check_[a-z0-9_]*=true\$/p" \
        "$action28j_a_outer_transcript" >"$action28j_a_outer_observed"
    validate_command "${action28j_a_outer_label}_status_zero" test "$action28j_a_outer_status" -eq 0
    validate_command "${action28j_a_outer_label}_stderr_empty" test ! -s "$action28j_a_outer_stderr"
    validate_command "${action28j_a_outer_label}_checks_exact" cmp -s \
        "$action28j_a_outer_expected" "$action28j_a_outer_observed"
    validate_command "${action28j_a_outer_label}_failed_zero" grep -Fqx \
        "${action28j_a_outer_record_prefix}_failed_check_count=0" "$action28j_a_outer_transcript"
    validate_command "${action28j_a_outer_label}_first_failure_none" grep -Fqx \
        "${action28j_a_outer_record_prefix}_first_failure=none" "$action28j_a_outer_transcript"
    validate_command "${action28j_a_outer_label}_accepted" grep -Fqx \
        "${action28j_a_outer_record_prefix}_acceptance=true" "$action28j_a_outer_transcript"
}
require_value() {
    local action28j_a_outer_label=$1
    local action28j_a_outer_line=$2
    local action28j_a_outer_transcript=$3

    validate_command "$action28j_a_outer_label" test \
        "$(grep -Fxc "$action28j_a_outer_line" "$action28j_a_outer_transcript")" -eq 1
}
cleanup() {
    local action28j_a_outer_status=$?

    [[ -z "$work_root" || ! -d "$work_root" ]] || rm -rf -- "$work_root"
    return "$action28j_a_outer_status"
}
trap cleanup EXIT

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
        CADDY_ACTION28J_A_TEST_MODE=1
        export CADDY_ACTION28J_A_TEST_MODE
        run_local_gates true
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    '') [[ $# -eq 0 ]] || exit 64 ;;
    *) exit 64 ;;
esac

skip_regression=false
[[ "${CADDY_ACTION28J_A_TEST_MODE:-}" != 1 ]] || skip_regression=true
run_local_gates "$skip_regression"
work_root=$(mktemp -d /tmp/caddy-action28j-a-post.XXXXXX)
chmod 0700 "$work_root"

node_a_state_status=0
capture_run node_a_state "$node_a_target" "$node_a_alias" "$state_inspector" \
    node_a_state_status --node node-a --phase failed
validate_producer node_a_state "$state_inspector" "$work_root/node_a_state.stdout" \
    "$work_root/node_a_state.stderr" "$node_a_state_status" action_28j_node_a_failed

node_a_route_status=0
capture_run node_a_route "$node_a_target" "$node_a_alias" "$route_inspector" \
    node_a_route_status node-a
validate_producer node_a_route "$route_inspector" "$work_root/node_a_route.stdout" \
    "$work_root/node_a_route.stderr" "$node_a_route_status" action_28j_a_route

node_a_residue_status=0
capture_run node_a_residue "$node_a_target" "$node_a_alias" "$residue_inspector" \
    node_a_residue_status node-a
validate_producer node_a_residue "$residue_inspector" "$work_root/node_a_residue.stdout" \
    "$work_root/node_a_residue.stderr" "$node_a_residue_status" action_28j_a_residue

node_b_state_status=0
capture_run node_b_state "$node_b_target" "$node_b_alias" "$state_inspector" \
    node_b_state_status --node node-b --phase failed
validate_producer node_b_state "$state_inspector" "$work_root/node_b_state.stdout" \
    "$work_root/node_b_state.stderr" "$node_b_state_status" action_28j_node_b_failed

node_b_route_status=0
capture_run node_b_route "$node_b_target" "$node_b_alias" "$route_inspector" \
    node_b_route_status node-b
validate_producer node_b_route "$route_inspector" "$work_root/node_b_route.stdout" \
    "$work_root/node_b_route.stderr" "$node_b_route_status" action_28j_a_route

node_b_residue_status=0
capture_run node_b_residue "$node_b_target" "$node_b_alias" "$residue_inspector" \
    node_b_residue_status node-b
validate_producer node_b_residue "$residue_inspector" "$work_root/node_b_residue.stdout" \
    "$work_root/node_b_residue.stderr" "$node_b_residue_status" action_28j_a_residue

require_value node_a_vrrp_fault action_28j_node_a_failed_value_vrrp_state=FAULT "$work_root/node_a_state.stdout"
require_value node_a_caddy_ipv4_zero action_28j_node_a_failed_value_caddy_ipv4_count=0 "$work_root/node_a_state.stdout"
require_value node_a_caddy_ipv6_zero action_28j_node_a_failed_value_caddy_ipv6_count=0 "$work_root/node_a_state.stdout"
require_value node_a_dns_ipv4_one action_28j_node_a_failed_value_dns_ipv4_count=1 "$work_root/node_a_state.stdout"
require_value node_a_dns_ipv6_one action_28j_node_a_failed_value_dns_ipv6_count=1 "$work_root/node_a_state.stdout"
require_value node_b_vrrp_master action_28j_node_b_failed_value_vrrp_state=MASTER "$work_root/node_b_state.stdout"
require_value node_b_caddy_ipv4_one action_28j_node_b_failed_value_caddy_ipv4_count=1 "$work_root/node_b_state.stdout"
require_value node_b_caddy_ipv6_one action_28j_node_b_failed_value_caddy_ipv6_count=1 "$work_root/node_b_state.stdout"
require_value node_b_dns_ipv4_zero action_28j_node_b_failed_value_dns_ipv4_count=0 "$work_root/node_b_state.stdout"
require_value node_b_dns_ipv6_zero action_28j_node_b_failed_value_dns_ipv6_count=0 "$work_root/node_b_state.stdout"
for action28j_a_outer_route_node in node_a node_b; do
    require_value "${action28j_a_outer_route_node}_route_a_exact" \
        action_28j_a_route_value_a_answer=10.1.0.56 \
        "$work_root/${action28j_a_outer_route_node}_route.stdout"
    require_value "${action28j_a_outer_route_node}_route_aaaa_exact" \
        action_28j_a_route_value_aaaa_answer=fd36:5aa8:6971:1::56 \
        "$work_root/${action28j_a_outer_route_node}_route.stdout"
    require_value "${action28j_a_outer_route_node}_route_cname_absent" \
        action_28j_a_route_value_cname_answer=empty \
        "$work_root/${action28j_a_outer_route_node}_route.stdout"
    require_value "${action28j_a_outer_route_node}_route_ipv4_url_same_origin" \
        action_28j_a_route_value_https_ipv4_url=https://pihole-admin.local.theama.co/admin/login.php \
        "$work_root/${action28j_a_outer_route_node}_route.stdout"
    require_value "${action28j_a_outer_route_node}_route_ipv6_url_same_origin" \
        action_28j_a_route_value_https_ipv6_url=https://pihole-admin.local.theama.co/admin/login.php \
        "$work_root/${action28j_a_outer_route_node}_route.stdout"
done
require_value node_a_transaction_residue_zero action_28j_a_residue_value_transaction_residue_count=0 "$work_root/node_a_residue.stdout"
require_value node_b_transaction_residue_zero action_28j_a_residue_value_transaction_residue_count=0 "$work_root/node_b_residue.stdout"
validate_command local_residue_still_absent local_residue_absent

printf '%s_validation_count=%s\n' "$prefix" "$validation_count"
printf '%s_validation_failed=%s\n' "$prefix" "$validation_failed"
printf '%s_validation_first_failure=%s\n' "$prefix" "$validation_first_failure"
printf '%s_node_a_contacted=true\n' "$prefix"
printf '%s_node_b_contacted=true\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_predecessor_rerun=false\n' "$prefix"
printf '%s_emergency_publication=false\n' "$prefix"
if [[ "$validation_failed" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$prefix"
    exit 1
fi
printf '%s_acceptance=true\n' "$prefix"
