#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_25_retry2_outer
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-dual-node-pihole-web-access-action25-retry2.sh
readonly regression=$caddy_root/tests/action25-retry2-bounded-redirect-regression.sh
readonly inspector_sha256=440363dd64be6eca737129ee6f708a6a25f17b3d1fdab1be10a35edc7ace7d0c
readonly regression_sha256=2d680e3ce9b12ce816bdb16a60d08bc07d07d3b58eb88353910399e00434de4f
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=50000
action25_retry2_outer_work_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
}
run_gate() {
    local action25_retry2_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action25_retry2_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action25_retry2_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory inspector_regular inspector_executable inspector_hash \
        regression_regular regression_executable regression_hash syntax shellcheck canonical_format \
        inspector_node_a_self_test inspector_node_b_self_test collision_policy conditional_policy \
        output_evidence_policy scalar_grep_policy portable_awk_policy remote_cwd_policy \
        accepted_live_hash_policy regression
}
run_local_gates() {
    local action25_retry2_outer_skip_regression=$1

    run_gate working_directory working_directory_approved || return 1
    run_gate inspector_regular test -f "$inspector" || return 1
    run_gate inspector_executable test -x "$inspector" || return 1
    run_gate inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256" || return 1
    run_gate regression_regular test -f "$regression" || return 1
    run_gate regression_executable test -x "$regression" || return 1
    run_gate regression_hash test "$(file_hash "$regression")" = "$regression_sha256" || return 1
    run_gate syntax /bin/bash -n "$inspector" "$regression" "$0" || return 1
    run_gate shellcheck shellcheck "$inspector" "$regression" "$0" || return 1
    run_gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$inspector" "$regression" "$0" || return 1
    run_gate inspector_node_a_self_test /bin/bash "$inspector" --self-test-node node-a || return 1
    run_gate inspector_node_b_self_test /bin/bash "$inspector" --self-test-node node-b || return 1
    run_gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$inspector" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate scalar_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$inspector" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$inspector" "$regression" "$0" || return 1
    run_gate remote_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" --check "$0" || return 1
    run_gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
    if [[ "$action25_retry2_outer_skip_regression" == true ]]; then
        run_gate regression test "$action25_retry2_outer_skip_regression" = true || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action25_retry2_outer_stream=$1

    [[ "$(wc -c <"$action25_retry2_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action25_retry2_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action25_retry2_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action25_retry2_outer_stream"
}
emit_stream() {
    local action25_retry2_outer_label=$1
    local action25_retry2_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action25_retry2_outer_label" "$(wc -c <"$action25_retry2_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action25_retry2_outer_label" "$(line_count "$action25_retry2_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action25_retry2_outer_label" "$(file_hash "$action25_retry2_outer_stream")"
    if safe_stream "$action25_retry2_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action25_retry2_outer_label"
        if [[ -s "$action25_retry2_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action25_retry2_outer_label"
            cat "$action25_retry2_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action25_retry2_outer_label"
        else
            printf '%s_%s_content=empty\n' "$prefix" "$action25_retry2_outer_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action25_retry2_outer_label" >&2
    return 97
}
validation_check() {
    local action25_retry2_outer_validation_role=$1
    local action25_retry2_outer_validation_label=$2

    shift 2
    if "$@" >/dev/null; then
        printf '%s_validation_%s_%s=true\n' "$prefix" \
            "${action25_retry2_outer_validation_role//-/_}" "$action25_retry2_outer_validation_label"
        return 0
    fi
    printf '%s_validation_%s_%s=false\n' "$prefix" \
        "${action25_retry2_outer_validation_role//-/_}" "$action25_retry2_outer_validation_label" >&2
    return 1
}
validate_observed_endpoint() {
    local action25_retry2_outer_observed_role=$1
    local action25_retry2_outer_observed_token=$2
    local action25_retry2_outer_observed_transcript=$3
    local action25_retry2_outer_observed_label=$4
    local action25_retry2_outer_observed_fqdn=$5
    local action25_retry2_outer_observed_remote=$6
    local action25_retry2_outer_observed_prefix="action_25_retry2_${action25_retry2_outer_observed_token}_observed_${action25_retry2_outer_observed_label}"

    validation_check "$action25_retry2_outer_observed_role" "${action25_retry2_outer_observed_label}_observed_command_status" \
        grep -Fqx "${action25_retry2_outer_observed_prefix}_command_status=0" \
        "$action25_retry2_outer_observed_transcript" || return 1
    validation_check "$action25_retry2_outer_observed_role" "${action25_retry2_outer_observed_label}_observed_output_classification" \
        grep -Fqx "${action25_retry2_outer_observed_prefix}_output_classification=bounded_safe" \
        "$action25_retry2_outer_observed_transcript" || return 1
    validation_check "$action25_retry2_outer_observed_role" "${action25_retry2_outer_observed_label}_observed_output_begin" \
        grep -Fqx "${action25_retry2_outer_observed_prefix}_output_begin" \
        "$action25_retry2_outer_observed_transcript" || return 1
    validation_check "$action25_retry2_outer_observed_role" "${action25_retry2_outer_observed_label}_observed_output_end" \
        grep -Fqx "${action25_retry2_outer_observed_prefix}_output_end" \
        "$action25_retry2_outer_observed_transcript" || return 1
    validation_check "$action25_retry2_outer_observed_role" "${action25_retry2_outer_observed_label}_observed_http_code" \
        grep -Fqx "${action25_retry2_outer_observed_prefix}_http_code=200" \
        "$action25_retry2_outer_observed_transcript" || return 1
    validation_check "$action25_retry2_outer_observed_role" "${action25_retry2_outer_observed_label}_observed_effective_url" \
        grep -Fqx "${action25_retry2_outer_observed_prefix}_effective_url=https://${action25_retry2_outer_observed_fqdn}/admin/login.php" \
        "$action25_retry2_outer_observed_transcript" || return 1
    validation_check "$action25_retry2_outer_observed_role" "${action25_retry2_outer_observed_label}_observed_remote_ip" \
        grep -Fqx "${action25_retry2_outer_observed_prefix}_remote_ip=${action25_retry2_outer_observed_remote}" \
        "$action25_retry2_outer_observed_transcript" || return 1
    validation_check "$action25_retry2_outer_observed_role" "${action25_retry2_outer_observed_label}_observed_redirect_count" \
        grep -Fqx "${action25_retry2_outer_observed_prefix}_redirect_count=1" \
        "$action25_retry2_outer_observed_transcript" || return 1
    validation_check "$action25_retry2_outer_observed_role" "${action25_retry2_outer_observed_label}_observed_body_bytes" \
        grep -Eq "^${action25_retry2_outer_observed_prefix}_body_bytes=[1-9][0-9]*$" \
        "$action25_retry2_outer_observed_transcript" || return 1
    validation_check "$action25_retry2_outer_observed_role" "${action25_retry2_outer_observed_label}_observed_body_sha256" \
        grep -Eq "^${action25_retry2_outer_observed_prefix}_body_sha256=[0-9a-f]{64}$" \
        "$action25_retry2_outer_observed_transcript" || return 1
    validation_check "$action25_retry2_outer_observed_role" "${action25_retry2_outer_observed_label}_observed_body_classification" \
        grep -Fqx "${action25_retry2_outer_observed_prefix}_body_classification=bounded_safe" \
        "$action25_retry2_outer_observed_transcript" || return 1
    validation_check "$action25_retry2_outer_observed_role" "${action25_retry2_outer_observed_label}_observed_body_marker" \
        grep -Fqx "${action25_retry2_outer_observed_prefix}_body_pihole_marker=true" \
        "$action25_retry2_outer_observed_transcript" || return 1
}
validate_node_transcript() {
    local action25_retry2_outer_role=$1
    local action25_retry2_outer_transcript=$2
    local action25_retry2_outer_status=$3
    local action25_retry2_outer_stderr=$4
    local action25_retry2_outer_token=${action25_retry2_outer_role//-/_}
    local action25_retry2_outer_expected_text
    local action25_retry2_outer_actual_text
    local action25_retry2_outer_check_lines
    local action25_retry2_outer_expected_count
    local action25_retry2_outer_http_count
    local action25_retry2_outer_body_hash_count
    local action25_retry2_outer_false_count
    local action25_retry2_outer_expected_vrrp

    # conditional-validator-explicit-failures-begin
    validation_check "$action25_retry2_outer_role" status_zero \
        test "$action25_retry2_outer_status" -eq 0 || return 1
    validation_check "$action25_retry2_outer_role" stderr_empty \
        test ! -s "$action25_retry2_outer_stderr" || return 1
    action25_retry2_outer_expected_text=$(/bin/bash "$inspector" --expected-checks "$action25_retry2_outer_role") || return 1
    action25_retry2_outer_actual_text=$(sed -n \
        "s/^action_25_retry2_${action25_retry2_outer_token}_check_\([^=]*\)=true$/\1/p" \
        "$action25_retry2_outer_transcript") || return 1
    validation_check "$action25_retry2_outer_role" ordered_checks \
        test "$action25_retry2_outer_actual_text" = "$action25_retry2_outer_expected_text" || return 1
    action25_retry2_outer_expected_count=$(printf '%s\n' "$action25_retry2_outer_expected_text" | wc -l) || return 1
    action25_retry2_outer_check_lines=$(grep -Ec "^action_25_retry2_${action25_retry2_outer_token}_check_.*=(true|false)$" \
        "$action25_retry2_outer_transcript" || true) || return 1
    validation_check "$action25_retry2_outer_role" actual_count_exact \
        test "$action25_retry2_outer_check_lines" -eq "$action25_retry2_outer_expected_count" || return 1
    validation_check "$action25_retry2_outer_role" declared_check_count \
        grep -Fqx "action_25_retry2_${action25_retry2_outer_token}_check_count=$action25_retry2_outer_expected_count" \
        "$action25_retry2_outer_transcript" || return 1
    validation_check "$action25_retry2_outer_role" endpoint_count \
        grep -Fqx "action_25_retry2_${action25_retry2_outer_token}_endpoint_count=6" \
        "$action25_retry2_outer_transcript" || return 1
    validation_check "$action25_retry2_outer_role" filesystem_mutation_false \
        grep -Fqx "action_25_retry2_${action25_retry2_outer_token}_filesystem_mutation=false" \
        "$action25_retry2_outer_transcript" || return 1
    validation_check "$action25_retry2_outer_role" service_mutation_false \
        grep -Fqx "action_25_retry2_${action25_retry2_outer_token}_service_mutation=false" \
        "$action25_retry2_outer_transcript" || return 1
    validation_check "$action25_retry2_outer_role" dns_mutation_false \
        grep -Fqx "action_25_retry2_${action25_retry2_outer_token}_dns_mutation=false" \
        "$action25_retry2_outer_transcript" || return 1
    validation_check "$action25_retry2_outer_role" peer_ssh_false \
        grep -Fqx "action_25_retry2_${action25_retry2_outer_token}_peer_ssh=false" \
        "$action25_retry2_outer_transcript" || return 1
    validation_check "$action25_retry2_outer_role" remote_complete \
        grep -Fqx "action_25_retry2_${action25_retry2_outer_token}_remote_complete=true" \
        "$action25_retry2_outer_transcript" || return 1
    validation_check "$action25_retry2_outer_role" local_zone_hash \
        grep -Fqx "action_25_retry2_${action25_retry2_outer_token}_value_local_zone_sha256=fa9f4850386ab1328f323c7c88bd9fa9ad0d5a84994b3066b6874deb5beb569c" \
        "$action25_retry2_outer_transcript" || return 1
    if [[ "$action25_retry2_outer_role" == node-a ]]; then
        action25_retry2_outer_expected_vrrp=MASTER
    else
        action25_retry2_outer_expected_vrrp=BACKUP
    fi
    validation_check "$action25_retry2_outer_role" vrrp_state \
        grep -Fqx "action_25_retry2_${action25_retry2_outer_token}_value_vrrp_state=$action25_retry2_outer_expected_vrrp" \
        "$action25_retry2_outer_transcript" || return 1
    while IFS='|' read -r action25_retry2_outer_observed_label action25_retry2_outer_observed_fqdn action25_retry2_outer_observed_remote; do
        validate_observed_endpoint "$action25_retry2_outer_role" "$action25_retry2_outer_token" \
            "$action25_retry2_outer_transcript" "$action25_retry2_outer_observed_label" \
            "$action25_retry2_outer_observed_fqdn" "$action25_retry2_outer_observed_remote" || return 1
    done <<'EOF'
shared_ipv4|pihole-admin.local.theama.co|10.1.0.56
shared_ipv6|pihole-admin.local.theama.co|fd36:5aa8:6971:1::56
node_a_ipv4|pihole0.local.theama.co|10.1.0.53
node_a_ipv6|pihole0.local.theama.co|fd36:5aa8:6971:1::53
node_b_ipv4|pihole00.local.theama.co|10.1.0.54
node_b_ipv6|pihole00.local.theama.co|fd36:5aa8:6971:1::54
EOF
    action25_retry2_outer_http_count=$(grep -Ec \
        "^action_25_retry2_${action25_retry2_outer_token}_value_.*_http_code=200$" \
        "$action25_retry2_outer_transcript" || true) || return 1
    validation_check "$action25_retry2_outer_role" http_count \
        test "$action25_retry2_outer_http_count" -eq 6 || return 1
    action25_retry2_outer_body_hash_count=$(grep -Ec \
        "^action_25_retry2_${action25_retry2_outer_token}_value_.*_body_sha256=[0-9a-f]+$" \
        "$action25_retry2_outer_transcript" || true) || return 1
    validation_check "$action25_retry2_outer_role" body_hash_count \
        test "$action25_retry2_outer_body_hash_count" -eq 6 || return 1
    action25_retry2_outer_false_count=$(grep -Ec \
        "^action_25_retry2_${action25_retry2_outer_token}_check_.*=false$" \
        "$action25_retry2_outer_transcript" || true) || return 1
    validation_check "$action25_retry2_outer_role" false_checks_absent \
        test "$action25_retry2_outer_false_count" -eq 0 || return 1
    # conditional-validator-explicit-failures-end
}
run_node() {
    local action25_retry2_outer_role=$1
    local action25_retry2_outer_target=$2
    local action25_retry2_outer_alias=$3
    local action25_retry2_outer_stdout=$4
    local action25_retry2_outer_stderr=$5
    local action25_retry2_outer_ssh_status=0

    "${CADDY_ACTION25_RETRY2_SSH_BIN:-ssh}" \
        -T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes \
        -o "HostKeyAlias=$action25_retry2_outer_alias" -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 -o LogLevel=ERROR \
        "$action25_retry2_outer_target" "cd / && sudo -n /bin/bash -s -- --node $action25_retry2_outer_role" \
        <"$inspector" >"$action25_retry2_outer_stdout" 2>"$action25_retry2_outer_stderr" ||
        action25_retry2_outer_ssh_status=$?
    emit_stream "${action25_retry2_outer_role//-/_}_stdout" "$action25_retry2_outer_stdout" || return $?
    emit_stream "${action25_retry2_outer_role//-/_}_stderr" "$action25_retry2_outer_stderr" || return $?
    validate_node_transcript "$action25_retry2_outer_role" "$action25_retry2_outer_stdout" \
        "$action25_retry2_outer_ssh_status" "$action25_retry2_outer_stderr" || return 1
}
cleanup() {
    local action25_retry2_outer_cleanup_status=$?

    trap - EXIT INT TERM
    if [[ -n "$action25_retry2_outer_work_root" ]]; then
        rm -rf -- "$action25_retry2_outer_work_root"
    fi
    exit "$action25_retry2_outer_cleanup_status"
}
run_action() {
    action25_retry2_outer_work_root=$(mktemp -d /tmp/caddy-action25-outer.XXXXXX)
    trap cleanup EXIT INT TERM
    run_local_gates "${CADDY_ACTION25_RETRY2_SKIP_REGRESSION:-false}" || return 1
    run_node node-a pi@10.1.0.53 pihole0.local.theama.co \
        "$action25_retry2_outer_work_root/node-a.stdout" "$action25_retry2_outer_work_root/node-a.stderr" || return 1
    run_node node-b pi@10.1.0.54 pihole00.local.theama.co \
        "$action25_retry2_outer_work_root/node-b.stdout" "$action25_retry2_outer_work_root/node-b.stderr" || return 1
    printf '%s_node_a_contacted=true\n' "$prefix"
    printf '%s_node_b_contacted=true\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_dns_mutation=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-local-gates) expected_local_gates ;;
    --validate-transcript)
        validate_node_transcript "${2:?}" "${3:?}" "${4:?}" "${5:?}"
        ;;
    --self-test)
        CADDY_ACTION25_RETRY2_SKIP_REGRESSION=true run_local_gates true
        ;;
    '') run_action ;;
    *) exit 64 ;;
esac
