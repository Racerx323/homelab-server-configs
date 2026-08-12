#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_29e_outer
readonly schema_version=action29e-final-acceptance-v2
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=131072
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-final-deployment-action29e.sh
readonly dns_probe=$script_directory/run-dual-node-dns-record-families-action24-retry-outer.sh
readonly protocol_probe=$script_directory/run-workstation-caddy-http3-action26-h3-retry-outer.sh
readonly tls_probe=$script_directory/run-workstation-caddy-tls-action27-retry3-outer.sh
readonly regression=$caddy_root/tests/action29e-final-deployment-acceptance-regression.sh
readonly manifest=$caddy_root/manifests/caddy-final-deployment-acceptance-action29e.yaml
readonly expected_inspector_sha256=f9bcc8d131f3d7c05fe9f03b9e34796a18cdccd9c81ee2852cb95587b4515220
readonly expected_dns_probe_sha256=daaa1904cab02dbf9a83aa6f8d4479582d6d571bc3fd008f4cd1393878fdc6f6
readonly expected_protocol_probe_sha256=289fd577f78aea2015b162f534b3a6819ba92965a67c579a3b6f6e32bf4d60b2
readonly expected_tls_probe_sha256=954c708830e3e695e329496830d7b3a53ca71d1d30521b9ac6d7b0fe28f4de0d
readonly expected_regression_sha256=9281df7aa8448b45a7c550e0fe40ea7a2bce2e64881df12d42a53a0812d0d028
evidence_root=${CADDY_ACTION29E_EVIDENCE_ROOT:-/tmp/caddy-ssh-evidence/action29e}
readonly evidence_root
ssh_binary=${CADDY_ACTION29E_SSH_BIN:-/usr/bin/ssh}
readonly ssh_binary
run_id=
work_root=
self_test_root=

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs) [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] ;;
        *) return 1 ;;
    esac
}
manifest_valid_local() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest"
        return
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
}
gate() {
    local action29_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action29_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action29_outer_label" >&2
    return 1
}
safe_stream() {
    local action29_outer_stream=$1

    [[ "$(wc -c <"$action29_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action29_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action29_outer_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action29_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
        "$action29_outer_stream"
}
emit_stream() {
    local action29_outer_label=$1
    local action29_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action29_outer_label" "$(wc -c <"$action29_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action29_outer_label" "$(line_count "$action29_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action29_outer_label" "$(file_hash "$action29_outer_stream")"
    if ! safe_stream "$action29_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action29_outer_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action29_outer_label"
    if [[ -s "$action29_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action29_outer_label"
        cat "$action29_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action29_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action29_outer_label"
    fi
}
prepare_capture() {
    local action29_outer_capture

    for action29_outer_capture in "$@"; do
        install -m 0600 /dev/null "$action29_outer_capture" || return 1
        [[ -f "$action29_outer_capture" && ! -L "$action29_outer_capture" ]] || return 1
        [[ "$(stat -c '%a' "$action29_outer_capture")" = 600 ]] || return 1
    done
}
require_one() {
    local action29_outer_line=$1
    local action29_outer_file=$2

    [[ "$(grep -Fxc "$action29_outer_line" "$action29_outer_file")" -eq 1 ]]
}
require_regex_one() {
    local action29e_outer_pattern=$1
    local action29e_outer_file=$2

    [[ "$(grep -Exc "$action29e_outer_pattern" "$action29e_outer_file")" -eq 1 ]]
}
validate_node_transcript() {
    local action29_outer_role=$1
    local action29_outer_stdout=$2
    local action29_outer_status=$3
    local action29_outer_stderr=$4
    local action29_outer_token=${action29_outer_role//-/_}
    local action29_outer_label

    # conditional-validator-explicit-failures-begin
    [[ "$action29_outer_status" -eq 0 ]] || return 1
    [[ ! -s "$action29_outer_stderr" ]] || return 1
    while IFS= read -r action29_outer_label; do
        require_one "action_29e_remote_${action29_outer_token}_check_${action29_outer_label}=true" "$action29_outer_stdout" || return 1
    done < <(/bin/bash "$inspector" --expected-checks "$action29_outer_role")
    ! grep -Eq '^action_29e_remote_.*_check_.*=false$' "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_schema=action29e-node-snapshot-v2" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_expected_pihole_ftl_sha256=a1dc88b1f696a6870e38025be113ff8664750fca6265c79a2aee12f80898cfa3" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_observed_pihole_ftl_sha256=a1dc88b1f696a6870e38025be113ff8664750fca6265c79a2aee12f80898cfa3" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_expected_pihole_domain_sha256=39fa219a7d1c81c7fb36d89bc17ba1caae26f3472eb861a750a8ba03ae55b026" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_observed_pihole_domain_sha256=39fa219a7d1c81c7fb36d89bc17ba1caae26f3472eb861a750a8ba03ae55b026" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_expected_manifest_sha256=5c2fad1133a2fae7ec37253bf1ecadb5971c949a8dc197b4dc7083d20cca6494" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_observed_manifest_sha256=5c2fad1133a2fae7ec37253bf1ecadb5971c949a8dc197b4dc7083d20cca6494" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_observed_manifest_paths_status=0" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_observed_manifest_file_set_status=0" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_manifest_hash_check_status=0" "$action29_outer_stdout" || return 1
    require_regex_one "action_29e_remote_${action29_outer_token}_manifest_hash_check_stdout_bytes=[0-9]+" "$action29_outer_stdout" || return 1
    require_regex_one "action_29e_remote_${action29_outer_token}_manifest_hash_check_stdout_lines=[1-9][0-9]*" "$action29_outer_stdout" || return 1
    require_regex_one "action_29e_remote_${action29_outer_token}_manifest_hash_check_stdout_sha256=[0-9a-f]{64}" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_manifest_hash_check_stdout_classification=bounded_safe" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_manifest_hash_check_stdout_begin" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_manifest_hash_check_stdout_end" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_manifest_hash_check_stderr_bytes=0" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_manifest_hash_check_stderr_lines=0" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_manifest_hash_check_stderr_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_manifest_hash_check_stderr_classification=bounded_safe" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_manifest_hash_check_stderr_content=empty" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_first_failure=none" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_read_only=true" "$action29_outer_stdout" || return 1
    require_one "action_29e_remote_${action29_outer_token}_complete=true" "$action29_outer_stdout" || return 1
    # conditional-validator-explicit-failures-end
}
component_marker() {
    case "$1" in
        dns) printf '%s\n' action_24_retry_outer_complete=true ;;
        protocol) printf '%s\n' action_26_h3_retry_complete=true ;;
        tls) printf '%s\n' action_27_retry3_outer_complete=true ;;
        *) return 64 ;;
    esac
}
validate_component_transcript() {
    local action29_outer_label=$1
    local action29_outer_stdout=$2
    local action29_outer_status=$3
    local action29_outer_stderr=$4
    local action29_outer_marker

    action29_outer_marker=$(component_marker "$action29_outer_label") || return 1
    [[ "$action29_outer_status" -eq 0 ]] || return 1
    [[ ! -s "$action29_outer_stderr" ]] || return 1
    require_one "$action29_outer_marker" "$action29_outer_stdout" || return 1
    ! grep -Eq '(^|_)check_[A-Za-z0-9_]+=false$|(^|_)gate_[A-Za-z0-9_]+=false$' \
        "$action29_outer_stdout"
}
run_local_gates() {
    gate working_directory working_directory_approved || return 1
    gate inspector_hash test "$(file_hash "$inspector")" = "$expected_inspector_sha256" || return 1
    gate dns_probe_hash test "$(file_hash "$dns_probe")" = "$expected_dns_probe_sha256" || return 1
    gate protocol_probe_hash test "$(file_hash "$protocol_probe")" = "$expected_protocol_probe_sha256" || return 1
    gate tls_probe_hash test "$(file_hash "$tls_probe")" = "$expected_tls_probe_sha256" || return 1
    gate regression_hash test "$(file_hash "$regression")" = "$expected_regression_sha256" || return 1
    gate syntax /bin/bash -n "$inspector" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate inspector_node_a_self_test /bin/bash "$inspector" --self-test-node node-a || return 1
    gate inspector_node_b_self_test /bin/bash "$inspector" --self-test-node node-b || return 1
    gate regression /bin/bash "$regression" || return 1
    gate shellcheck shellcheck "$inspector" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$inspector" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$inspector" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$inspector" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$inspector" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate remote_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-precommit.sh" \
        "${BASH_SOURCE[0]}" || return 1
    gate ssh_evidence_policy /bin/bash "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" \
        --check "${BASH_SOURCE[0]}" || return 1
    gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
    gate manifest manifest_valid_local || return 1
}
run_node() {
    local action29_outer_role=$1
    local action29_outer_target=$2
    local action29_outer_alias=$3
    local remote_stdout=$work_root/${action29_outer_role}.stdout
    local remote_stderr=$work_root/${action29_outer_role}.stderr
    local status_file=$work_root/${action29_outer_role}.status
    local remote_status=0

    prepare_capture "$remote_stdout" "$remote_stderr" "$status_file" || return 1
    chmod 0600 "$remote_stdout" "$remote_stderr" "$status_file" || return 1
    "$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes \
        -o "HostKeyAlias=$action29_outer_alias" -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 -o LogLevel=ERROR "$action29_outer_target" \
        "cd / && sudo -n /bin/bash -s -- --node $action29_outer_role" \
        <"$inspector" >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
    printf '%s\n' "$remote_status" >"$status_file"
    printf '%s_%s_status=%s\n' "$prefix" "${action29_outer_role//-/_}" "$remote_status"
    emit_stream remote_stdout "$remote_stdout" || return $?
    emit_stream remote_stderr "$remote_stderr" || return $?
    validate_node_transcript "$action29_outer_role" "$remote_stdout" \
        "$remote_status" "$remote_stderr"
}
run_component() {
    local action29_outer_label=$1
    local action29_outer_command=$2
    local action29_outer_stdout=$work_root/$action29_outer_label.stdout
    local action29_outer_stderr=$work_root/$action29_outer_label.stderr
    local action29_outer_status_file=$work_root/$action29_outer_label.status
    local action29_outer_status=0

    prepare_capture "$action29_outer_stdout" "$action29_outer_stderr" "$action29_outer_status_file" || return 1
    /bin/bash "$action29_outer_command" >"$action29_outer_stdout" \
        2>"$action29_outer_stderr" || action29_outer_status=$?
    printf '%s\n' "$action29_outer_status" >"$action29_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action29_outer_label" "$action29_outer_status"
    emit_stream "${action29_outer_label}_stdout" "$action29_outer_stdout" || return $?
    emit_stream "${action29_outer_label}_stderr" "$action29_outer_stderr" || return $?
    validate_component_transcript "$action29_outer_label" "$action29_outer_stdout" \
        "$action29_outer_status" "$action29_outer_stderr"
}
run_action() {
    local action29_outer_started_ns
    local action29_outer_finished_ns

    run_local_gates || return 1
    run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
    work_root=$evidence_root/$run_id
    install -d -m 0700 "$evidence_root" || return 1
    work_root=$(mktemp -d "$evidence_root/run.XXXXXX") || return 1
    chmod 0700 "$work_root" || return 1
    action29_outer_started_ns=$(date +%s%N) || return 1
    run_node node-a "$node_a_target" pihole0.local.theama.co || return 1
    run_node node-b "$node_b_target" pihole00.local.theama.co || return 1
    run_component dns "$dns_probe" || return 1
    run_component tls "$tls_probe" || return 1
    run_component protocol "$protocol_probe" || return 1
    action29_outer_finished_ns=$(date +%s%N) || return 1
    printf '%s_schema=%s\n' "$prefix" "$schema_version"
    printf '%s_evidence_directory=%s\n' "$prefix" "$work_root"
    printf '%s_elapsed_ms=%s\n' "$prefix" \
        "$(((action29_outer_finished_ns - action29_outer_started_ns) / 1000000))"
    printf '%s_approved_deviation_config_test_free=true\n' "$prefix"
    printf '%s_approved_deviation_notifier_delivery_nonblocking=true\n' "$prefix"
    printf '%s_approved_deviation_mobile_signoff_deferred=true\n' "$prefix"
    printf '%s_complete_historical_suite_run=false\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_core_deployment_accepted=true\n' "$prefix"
}
self_test() {
    local action29_outer_role
    local action29_outer_token
    local action29_outer_stdout
    local action29_outer_stderr

    run_local_gates || return 1
    self_test_root=$(mktemp -d /tmp/action29-outer-selftest.XXXXXX) || return 1
    trap 'rm -rf -- "$self_test_root"' EXIT INT TERM
    work_root=$self_test_root
    for action29_outer_role in node-a node-b; do
        action29_outer_token=${action29_outer_role//-/_}
        action29_outer_stdout=$work_root/$action29_outer_token.stdout
        action29_outer_stderr=$work_root/$action29_outer_token.stderr
        /bin/bash "$inspector" --self-test-node "$action29_outer_role" >"$action29_outer_stdout"
        install -m 0600 /dev/null "$action29_outer_stderr"
        validate_node_transcript "$action29_outer_role" "$action29_outer_stdout" 0 \
            "$action29_outer_stderr" || return 1
    done
    printf '%s_node_contact=false\n' "$prefix"
    printf '%s_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --self-test) self_test ;;
    --validate-node-transcript)
        validate_node_transcript "${2:?}" "${3:?}" "${4:?}" "${5:?}"
        ;;
    --validate-component-transcript)
        validate_component_transcript "${2:?}" "${3:?}" "${4:?}" "${5:?}"
        ;;
    '') run_action ;;
    *) exit 64 ;;
esac
