#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_d_retry2_a_runner
readonly probe_prefix=action_20d_retry10_d_retry2_a
readonly inspector_sha256=2904f0e0d6cfbe87d4f041998c7bad294215f93522b37995c93fa57a4b3c18ff
readonly expected_health_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly expected_backup_path=/var/backups/caddy-ha/action20d-retry10-d-retry2-node-a-health-instrumentation.18d7kI
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=16384

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly inspector=$script_directory/inspect-node-a-caddy-health-instrumentation-postinstall-action20d-retry10-d-retry2-a.sh
readonly ssh_binary=${CADDY_ACTION20D_RETRY2_A_SSH_BINARY:-/usr/bin/ssh}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_one() {
    local action20d_retry2_a_runner_expected_line=$1
    local action20d_retry2_a_runner_transcript_path=$2

    [[ "$(grep -Fxc "$action20d_retry2_a_runner_expected_line" \
        "$action20d_retry2_a_runner_transcript_path")" -eq 1 ]]
}
safe_stream() {
    local action20d_retry2_a_runner_stream_path=$1

    [[ "$(wc -c <"$action20d_retry2_a_runner_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20d_retry2_a_runner_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' \
        "$action20d_retry2_a_runner_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20d_retry2_a_runner_stream_path"
}
emit_stream() {
    local action20d_retry2_a_runner_stream_label=$1
    local action20d_retry2_a_runner_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20d_retry2_a_runner_stream_label" \
        "$(wc -c <"$action20d_retry2_a_runner_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20d_retry2_a_runner_stream_label" \
        "$(line_count "$action20d_retry2_a_runner_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20d_retry2_a_runner_stream_label" \
        "$(file_hash "$action20d_retry2_a_runner_stream_path")"
    if ! safe_stream "$action20d_retry2_a_runner_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$action20d_retry2_a_runner_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' \
        "$prefix" "$action20d_retry2_a_runner_stream_label"
    if [[ -s "$action20d_retry2_a_runner_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20d_retry2_a_runner_stream_label"
        cat "$action20d_retry2_a_runner_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action20d_retry2_a_runner_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' \
            "$prefix" "$action20d_retry2_a_runner_stream_label"
    fi
}
validate_capture_contract() {
    local action20d_retry2_a_runner_capture_label=$1
    local action20d_retry2_a_runner_transcript_path=$2
    local action20d_retry2_a_runner_capture_bytes
    local action20d_retry2_a_runner_capture_lines
    local action20d_retry2_a_runner_capture_sha256

    [[ "$(grep -Ec "^${probe_prefix}_capture_${action20d_retry2_a_runner_capture_label}_bytes=[0-9]+$" \
        "$action20d_retry2_a_runner_transcript_path" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Ec "^${probe_prefix}_capture_${action20d_retry2_a_runner_capture_label}_lines=[0-9]+$" \
        "$action20d_retry2_a_runner_transcript_path" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Ec "^${probe_prefix}_capture_${action20d_retry2_a_runner_capture_label}_sha256=[0-9a-f]{64}$" \
        "$action20d_retry2_a_runner_transcript_path" || true)" -eq 1 ]] || return 1
    require_one \
        "${probe_prefix}_capture_${action20d_retry2_a_runner_capture_label}_classification=bounded_safe" \
        "$action20d_retry2_a_runner_transcript_path" || return 1
    action20d_retry2_a_runner_capture_bytes=$(sed -n \
        "s/^${probe_prefix}_capture_${action20d_retry2_a_runner_capture_label}_bytes=//p" \
        "$action20d_retry2_a_runner_transcript_path")
    action20d_retry2_a_runner_capture_lines=$(sed -n \
        "s/^${probe_prefix}_capture_${action20d_retry2_a_runner_capture_label}_lines=//p" \
        "$action20d_retry2_a_runner_transcript_path")
    action20d_retry2_a_runner_capture_sha256=$(sed -n \
        "s/^${probe_prefix}_capture_${action20d_retry2_a_runner_capture_label}_sha256=//p" \
        "$action20d_retry2_a_runner_transcript_path")
    if [[ "$action20d_retry2_a_runner_capture_label" == *_stderr ]]; then
        [[ "$action20d_retry2_a_runner_capture_bytes" -eq 0 ]] || return 1
        [[ "$action20d_retry2_a_runner_capture_lines" -eq 0 ]] || return 1
        [[ "$action20d_retry2_a_runner_capture_sha256" = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]] || return 1
        require_one \
            "${probe_prefix}_capture_${action20d_retry2_a_runner_capture_label}_content_secured=empty" \
            "$action20d_retry2_a_runner_transcript_path" || return 1
    else
        [[ "$action20d_retry2_a_runner_capture_bytes" -eq 56 ]] || return 1
        [[ "$action20d_retry2_a_runner_capture_lines" -eq 1 ]] || return 1
        [[ "$action20d_retry2_a_runner_capture_sha256" = c54624ec3637e76415fbda315ad2aa937433939ee97203051de705d40bf84f2c ]] || return 1
        require_one \
            "${probe_prefix}_capture_${action20d_retry2_a_runner_capture_label}_begin" \
            "$action20d_retry2_a_runner_transcript_path" || return 1
        require_one \
            "${probe_prefix}_capture_${action20d_retry2_a_runner_capture_label}_content=caddy_ha_health_instrumentation_self_test_complete=true" \
            "$action20d_retry2_a_runner_transcript_path" || return 1
        require_one \
            "${probe_prefix}_capture_${action20d_retry2_a_runner_capture_label}_end" \
            "$action20d_retry2_a_runner_transcript_path" || return 1
    fi
}
validate_transcript() {
    local action20d_retry2_a_runner_output_path=$1
    local action20d_retry2_a_runner_error_path=$2
    local action20d_retry2_a_runner_remote_status=$3
    local action20d_retry2_a_runner_contract_root
    local action20d_retry2_a_runner_expected_count
    local action20d_retry2_a_runner_observed_count
    local action20d_retry2_a_runner_reported_count
    local action20d_retry2_a_runner_reported_failed
    local action20d_retry2_a_runner_before_hash
    local action20d_retry2_a_runner_after_hash
    local action20d_retry2_a_runner_capture

    [[ "$action20d_retry2_a_runner_remote_status" -eq 0 ]] || return 1
    [[ ! -s "$action20d_retry2_a_runner_error_path" ]] || return 1
    action20d_retry2_a_runner_contract_root=$(mktemp -d \
        /tmp/caddy-action20d-retry10-d-retry2-a-contract.XXXXXX) || return 97
    trap 'rm -rf -- "$action20d_retry2_a_runner_contract_root"; trap - RETURN' RETURN
    /bin/bash "$inspector" --expected-assertions | LC_ALL=C sort \
        >"$action20d_retry2_a_runner_contract_root/expected" || return 97
    sed -n \
        "s/^${probe_prefix}_assertion_\([a-z0-9_]*\)=\(true\|false\)$/\1/p" \
        "$action20d_retry2_a_runner_output_path" | LC_ALL=C sort \
        >"$action20d_retry2_a_runner_contract_root/observed"
    action20d_retry2_a_runner_expected_count=$(wc -l \
        <"$action20d_retry2_a_runner_contract_root/expected")
    action20d_retry2_a_runner_observed_count=$(wc -l \
        <"$action20d_retry2_a_runner_contract_root/observed")
    [[ "$action20d_retry2_a_runner_expected_count" -gt 0 ]] || return 97
    [[ "$action20d_retry2_a_runner_expected_count" -eq "$(LC_ALL=C sort -u "$action20d_retry2_a_runner_contract_root/expected" | wc -l)" ]] || return 97
    [[ "$action20d_retry2_a_runner_observed_count" -eq "$action20d_retry2_a_runner_expected_count" ]] || return 1
    [[ "$action20d_retry2_a_runner_observed_count" -eq "$(LC_ALL=C sort -u "$action20d_retry2_a_runner_contract_root/observed" | wc -l)" ]] || return 1
    cmp -s "$action20d_retry2_a_runner_contract_root/expected" \
        "$action20d_retry2_a_runner_contract_root/observed" || return 1
    [[ "$(grep -Ec "^${probe_prefix}_assertion_[a-z0-9_]+=false$" \
        "$action20d_retry2_a_runner_output_path" || true)" -eq 0 ]] || return 1

    action20d_retry2_a_runner_reported_count=$(sed -n \
        "s/^${probe_prefix}_assertion_count=//p" \
        "$action20d_retry2_a_runner_output_path")
    action20d_retry2_a_runner_reported_failed=$(sed -n \
        "s/^${probe_prefix}_failed_assertion_count=//p" \
        "$action20d_retry2_a_runner_output_path")
    [[ "$action20d_retry2_a_runner_reported_count" = "$action20d_retry2_a_runner_expected_count" ]] || return 1
    [[ "$action20d_retry2_a_runner_reported_failed" = 0 ]] || return 1
    require_one "${probe_prefix}_first_failure=none" \
        "$action20d_retry2_a_runner_output_path" || return 1
    require_one \
        "${probe_prefix}_value_expected_assertion_count=$action20d_retry2_a_runner_expected_count" \
        "$action20d_retry2_a_runner_output_path" || return 1
    require_one "${probe_prefix}_value_health_sha256=$expected_health_sha256" \
        "$action20d_retry2_a_runner_output_path" || return 1
    require_one "${probe_prefix}_value_backup_path=$expected_backup_path" \
        "$action20d_retry2_a_runner_output_path" || return 1
    action20d_retry2_a_runner_before_hash=$(sed -n \
        "s/^${probe_prefix}_value_before_snapshot_sha256=//p" \
        "$action20d_retry2_a_runner_output_path")
    action20d_retry2_a_runner_after_hash=$(sed -n \
        "s/^${probe_prefix}_value_after_snapshot_sha256=//p" \
        "$action20d_retry2_a_runner_output_path")
    [[ "$action20d_retry2_a_runner_before_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$action20d_retry2_a_runner_before_hash" = "$action20d_retry2_a_runner_after_hash" ]] || return 1
    for action20d_retry2_a_runner_capture in \
        root_self_test_stdout root_self_test_stderr \
        exact_context_self_test_stdout exact_context_self_test_stderr; do
        validate_capture_contract "$action20d_retry2_a_runner_capture" \
            "$action20d_retry2_a_runner_output_path" || return 1
    done
    require_one "${probe_prefix}_full_health_helper_invoked=false" \
        "$action20d_retry2_a_runner_output_path" || return 1
    require_one "${probe_prefix}_notification_helper_invoked=false" \
        "$action20d_retry2_a_runner_output_path" || return 1
    require_one "${probe_prefix}_filesystem_mutations=false" \
        "$action20d_retry2_a_runner_output_path" || return 1
    require_one "${probe_prefix}_service_mutations=false" \
        "$action20d_retry2_a_runner_output_path" || return 1
    require_one "${probe_prefix}_keepalived_mutations=false" \
        "$action20d_retry2_a_runner_output_path" || return 1
    require_one "${probe_prefix}_vrrp_mutations=false" \
        "$action20d_retry2_a_runner_output_path" || return 1
    require_one "${probe_prefix}_vip_mutations=false" \
        "$action20d_retry2_a_runner_output_path" || return 1
    require_one "${probe_prefix}_network_mutations=false" \
        "$action20d_retry2_a_runner_output_path" || return 1
    require_one "${probe_prefix}_persistent_mutations=false" \
        "$action20d_retry2_a_runner_output_path" || return 1
    require_one "${probe_prefix}_remote_cleanup_complete=true" \
        "$action20d_retry2_a_runner_output_path" || return 1
    require_one "${probe_prefix}_remote_complete=true" \
        "$action20d_retry2_a_runner_output_path" || return 1
}
source_exact() {
    [[ -f "$inspector" && ! -L "$inspector" ]] || return 1
    [[ "$(file_hash "$inspector")" = "$inspector_sha256" ]] || return 1
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        source_exact
        /bin/bash -n "$inspector" "$0"
        /bin/bash "$inspector" --self-test >/dev/null
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    --validate-transcript)
        [[ $# -eq 4 ]] || exit 64
        source_exact
        validate_transcript "$2" "$3" "$4"
        printf '%s_transcript_validation_complete=true\n' "$prefix"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test|--validate-transcript STDOUT STDERR STATUS]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

source_exact
work_root=$(mktemp -d /tmp/caddy-action20d-retry10-d-retry2-a-runner.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
readonly remote_stdout=$work_root/remote.stdout
readonly remote_stderr=$work_root/remote.stderr
install -m 0600 /dev/null "$remote_stdout"
install -m 0600 /dev/null "$remote_stderr"
remote_status=0
"$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 \
    -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
    pi@10.1.0.53 'cd / && sudo /bin/bash -s -- --inspect' \
    <"$inspector" >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
readonly remote_status
emit_stream remote_stdout "$remote_stdout" || {
    trap - EXIT INT TERM
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
}
emit_stream remote_stderr "$remote_stderr" || {
    trap - EXIT INT TERM
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
}
validate_transcript "$remote_stdout" "$remote_stderr" "$remote_status"
printf '%s_remote_status=%s\n' "$prefix" "$remote_status"
printf '%s_node_a_contacted=true\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_full_health_helper_invoked=false\n' "$prefix"
printf '%s_keepalived_reloaded=false\n' "$prefix"
printf '%s_vrrp_activation=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_cleanup_complete=true\n' "$prefix"
