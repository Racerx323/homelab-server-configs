#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_b
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=8192
readonly expected_node_b_environment_sha256=f692d5b7e0a7e0f0ab142e36face6a8cc8c6680a44a2bcaf6a992247ec4c8113
readonly rejected_node_a_environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly probe=$script_directory/inspect-node-b-caddy-environment-provenance-action20d-retry10-b.sh
readonly ssh_binary=${CADDY_ACTION20D_RETRY10_B_SSH_BINARY:-ssh}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
require_one() {
    local exact_line=$1
    local transcript_path=$2

    [[ "$(grep -Fxc "$exact_line" "$transcript_path")" -eq 1 ]]
}
extract_one() {
    local key_name=$1
    local transcript_path=$2
    local extracted_value

    [[ "$(grep -c "^${key_name}=" "$transcript_path")" -eq 1 ]] || return 1
    extracted_value=$(sed -n "s/^${key_name}=//p" "$transcript_path") || return 1
    printf '%s\n' "$extracted_value"
}
is_sha256() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }
safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer|NODE_FQDN=|NODE_IPV[46]=|PEER_IPV[46]=|SYNC_TARGET=' \
        "$stream_path"
}
emit_stream() {
    local stream_label=$1
    local stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$stream_label" "$(wc -c <"$stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$stream_label" "$(line_count "$stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$stream_label" "$(file_hash "$stream_path")"
    if safe_stream "$stream_path"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$stream_label"
        if [[ -s "$stream_path" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$stream_label"
            cat "$stream_path"
            printf '%s_%s_end\n' "$prefix" "$stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$stream_label" >&2
    return 97
}
expected_assertions() {
    printf '%s\n' \
        ssh_status_zero ssh_stderr_empty probe_assertions_exact probe_values_complete \
        source_classification_consistent package_classification_supported \
        snapshot_hashes_exact mutation_markers_false
}
record_assertion() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$assertion_label"
    return 1
}
probe_assertions_exact() {
    local transcript_path=$1
    local contract_root
    local expected_label

    contract_root=$(mktemp -d /tmp/caddy-action20d-retry10-b-contract.XXXXXX) || return 1
    /bin/bash "$probe" --expected-assertions | LC_ALL=C sort >"$contract_root/expected" || {
        rm -rf -- "$contract_root"
        return 1
    }
    sed -n 's/^action_20d_retry10_b_probe_assertion_\([a-z0-9_]*\)=true$/\1/p' \
        "$transcript_path" | LC_ALL=C sort >"$contract_root/observed" || {
        rm -rf -- "$contract_root"
        return 1
    }
    cmp -s "$contract_root/expected" "$contract_root/observed" || {
        rm -rf -- "$contract_root"
        return 1
    }
    while IFS= read -r expected_label; do
        require_one "action_20d_retry10_b_probe_assertion_${expected_label}=true" \
            "$transcript_path" || {
            rm -rf -- "$contract_root"
            return 1
        }
    done <"$contract_root/expected"
    ! grep -Eq '^action_20d_retry10_b_probe_assertion_[a-z0-9_]+=false$' \
        "$transcript_path" || {
        rm -rf -- "$contract_root"
        return 1
    }
    rm -rf -- "$contract_root"
}
probe_values_complete() {
    local transcript_path=$1
    local expected_key
    local observed_value

    for expected_key in environment_sha256 expected_node_b_environment_sha256 \
        rejected_node_a_environment_sha256 before_snapshot_sha256 \
        after_snapshot_sha256; do
        observed_value=$(extract_one \
            "action_20d_retry10_b_probe_value_${expected_key}" "$transcript_path") || return 1
        is_sha256 "$observed_value" || return 1
    done
    while IFS= read -r expected_key; do
        observed_value=$(extract_one \
            "action_20d_retry10_b_probe_value_line_${expected_key,,}_sha256" \
            "$transcript_path") || return 1
        is_sha256 "$observed_value" || return 1
    done < <(/bin/bash "$probe" --expected-keys)
    [[ "$(grep -Ec '^action_20d_retry10_b_probe_value_line_[a-z0-9_]+_sha256=[0-9a-f]{64}$' \
        "$transcript_path")" -eq 10 ]]
}
source_classification_consistent() {
    local transcript_path=$1
    local observed_hash
    local observed_classification
    local expected_classification

    observed_hash=$(extract_one action_20d_retry10_b_probe_value_environment_sha256 \
        "$transcript_path") || return 1
    observed_classification=$(extract_one \
        action_20d_retry10_b_probe_value_source_classification "$transcript_path") || return 1
    case "$observed_hash" in
        "$expected_node_b_environment_sha256") expected_classification=rendered_node_b_candidate ;;
        "$rejected_node_a_environment_sha256") expected_classification=rendered_node_a_candidate ;;
        *) expected_classification=unrecognized ;;
    esac
    [[ "$observed_classification" = "$expected_classification" ]]
}
package_classification_supported() {
    local transcript_path=$1
    local observed_classification

    observed_classification=$(extract_one \
        action_20d_retry10_b_probe_value_package_classification "$transcript_path") || return 1
    case "$observed_classification" in
        package_owned | locally_managed | query_error) return 0 ;;
        *) return 1 ;;
    esac
}
snapshot_hashes_exact() {
    local transcript_path=$1
    local before_hash
    local after_hash

    before_hash=$(extract_one action_20d_retry10_b_probe_value_before_snapshot_sha256 \
        "$transcript_path") || return 1
    after_hash=$(extract_one action_20d_retry10_b_probe_value_after_snapshot_sha256 \
        "$transcript_path") || return 1
    is_sha256 "$before_hash" && [[ "$before_hash" = "$after_hash" ]]
}
mutation_markers_false() {
    local transcript_path=$1
    local exact_record

    for exact_record in \
        action_20d_retry10_b_probe_environment_values_emitted=false \
        action_20d_retry10_b_probe_health_helper_invoked=false \
        action_20d_retry10_b_probe_notification_helper_invoked=false \
        action_20d_retry10_b_probe_node_a_contacted=false \
        action_20d_retry10_b_probe_filesystem_mutations=false \
        action_20d_retry10_b_probe_service_mutations=false \
        action_20d_retry10_b_probe_keepalived_mutations=false \
        action_20d_retry10_b_probe_vrrp_mutations=false \
        action_20d_retry10_b_probe_vip_mutations=false \
        action_20d_retry10_b_probe_network_mutations=false \
        action_20d_retry10_b_probe_persistent_mutations=false \
        action_20d_retry10_b_probe_remote_complete=true; do
        require_one "$exact_record" "$transcript_path" || return 1
    done
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$(expected_assertions | wc -l)" -eq 8 ]]
        [[ "$(expected_assertions | LC_ALL=C sort -u | wc -l)" -eq 8 ]]
        /bin/bash "$probe" --self-test >/dev/null
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-assertions|--self-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

[[ -z "${CADDY_ACTION20D_RETRY10_B_INTERCEPTED_TEST:-}" ]]
work_root=$(mktemp -d /tmp/caddy-action20d-retry10-b-runner.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT
readonly remote_stdout=$work_root/remote.stdout
readonly remote_stderr=$work_root/remote.stderr
: >"$remote_stdout"
: >"$remote_stderr"
chmod 0600 "$remote_stdout" "$remote_stderr"

remote_status=0
"$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
    -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co \
    pi@10.1.0.54 'cd / && sudo -n /bin/bash -s' \
    <"$probe" >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
readonly remote_status

stream_failure=0
emit_stream remote_stdout "$remote_stdout" || stream_failure=1
emit_stream remote_stderr "$remote_stderr" || stream_failure=1
if [[ "$stream_failure" -ne 0 ]]; then
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
fi

failed_assertion_count=0
first_failure=none
run_assertion() {
    local run_label=$1

    shift
    if ! record_assertion "$run_label" "$@"; then
        failed_assertion_count=$((failed_assertion_count + 1))
        if [[ "$first_failure" = none ]]; then first_failure=$run_label; fi
    fi
}

run_assertion ssh_status_zero test "$remote_status" -eq 0
run_assertion ssh_stderr_empty test ! -s "$remote_stderr"
run_assertion probe_assertions_exact probe_assertions_exact "$remote_stdout"
run_assertion probe_values_complete probe_values_complete "$remote_stdout"
run_assertion source_classification_consistent source_classification_consistent "$remote_stdout"
run_assertion package_classification_supported package_classification_supported "$remote_stdout"
run_assertion snapshot_hashes_exact snapshot_hashes_exact "$remote_stdout"
run_assertion mutation_markers_false mutation_markers_false "$remote_stdout"

printf '%s_value_remote_status=%s\n' "$prefix" "$remote_status"
if is_sha256 "$(extract_one action_20d_retry10_b_probe_value_environment_sha256 \
    "$remote_stdout" 2>/dev/null || true)"; then
    printf '%s_value_observed_environment_sha256=%s\n' "$prefix" \
        "$(extract_one action_20d_retry10_b_probe_value_environment_sha256 "$remote_stdout")"
fi
printf '%s_value_source_classification=%s\n' "$prefix" \
    "$(extract_one action_20d_retry10_b_probe_value_source_classification \
        "$remote_stdout" 2>/dev/null || printf unavailable)"
printf '%s_assertion_count=%s\n' "$prefix" "$(expected_assertions | wc -l)"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_node_b_contacted=true\n' "$prefix"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_health_helper_invoked=false\n' "$prefix"
printf '%s_notification_helper_invoked=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_network_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_runner_cleanup_complete=true\n' "$prefix"

rm -rf -- "$work_root"
trap - EXIT
[[ "$failed_assertion_count" -eq 0 ]]
printf '%s_diagnostic_complete=true\n' "$prefix"
