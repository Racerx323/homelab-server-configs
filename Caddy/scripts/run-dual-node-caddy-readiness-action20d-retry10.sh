#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_readiness
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096
readonly probe_sha256=7f448b968df5c96feb11e5ca8d0d0cc738b1019edfa61a32ebde4c9c02ea98c0
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly node_a_alias=pihole0.local.theama.co
readonly node_b_alias=pihole00.local.theama.co

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly probe="$script_directory/inspect-dual-node-caddy-readiness-action20d-retry10.sh"
readonly ssh_binary=${CADDY_ACTION20D_RETRY10_READINESS_SSH_BINARY:-/usr/bin/ssh}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
safe_stream() {
    local stream_path=$1

    [[ "$(wc -c <"$stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
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
expected_assertions() {
    printf '%s\n' \
        node_a_ssh_completed node_b_ssh_completed \
        node_a_probe_accepted node_b_probe_accepted \
        node_a_inherited_user_pi node_b_inherited_user_pi inherited_user_same \
        node_a_state_directory_metadata_collected \
        node_b_state_directory_metadata_collected \
        node_a_dedupe_directory_metadata_collected \
        node_b_dedupe_directory_metadata_collected \
        node_a_caddy_ipv4_vip_absent node_a_caddy_ipv6_vip_absent \
        node_b_caddy_ipv4_vip_absent node_b_caddy_ipv6_vip_absent \
        node_a_dns_ipv4_vip_owner node_a_dns_ipv6_vip_owner \
        node_b_dns_ipv4_vip_absent node_b_dns_ipv6_vip_absent \
        node_a_notifier_not_invoked node_b_notifier_not_invoked \
        node_a_before_hash_collected node_a_after_hash_collected \
        node_b_before_hash_collected node_b_after_hash_collected \
        node_a_state_unchanged node_b_state_unchanged
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
validate_probe() {
    local validation_role=$1
    local validation_stdout=$2
    local validation_stderr=$3
    local validation_status=$4
    local validation_label
    local validation_expected_count
    local validation_observed_count

    [[ "$validation_status" -eq 0 ]] || return 1
    [[ ! -s "$validation_stderr" ]] || return 1
    validation_expected_count=$("$probe" --expected-assertions | wc -l) || return 1
    validation_observed_count=$(grep -Ec '^action_20d_retry10_readiness_probe_assertion_[a-z0-9_]+=(true|false)$' "$validation_stdout") || return 1
    [[ "$validation_observed_count" -eq "$validation_expected_count" ]] || return 1
    [[ "$(grep '^action_20d_retry10_readiness_probe_assertion_' "$validation_stdout" | cut -d= -f1 | LC_ALL=C sort | uniq -d | wc -l)" -eq 0 ]] || return 1
    while IFS= read -r validation_label; do
        require_one "action_20d_retry10_readiness_probe_assertion_${validation_label}=true" "$validation_stdout" || return 1
    done < <("$probe" --expected-assertions)
    require_one "action_20d_retry10_readiness_probe_value_node_role=$validation_role" "$validation_stdout" || return 1
    require_one "action_20d_retry10_readiness_probe_assertion_count=$validation_expected_count" "$validation_stdout" || return 1
    require_one 'action_20d_retry10_readiness_probe_failed_assertion_count=0' "$validation_stdout" || return 1
    require_one 'action_20d_retry10_readiness_probe_first_failure=none' "$validation_stdout" || return 1
    require_one 'action_20d_retry10_readiness_probe_notification_helper_invoked=false' "$validation_stdout" || return 1
    for validation_marker in filesystem_mutations service_mutations keepalived_mutations \
        vrrp_mutations vip_mutations network_mutations persistent_mutations; do
        require_one "action_20d_retry10_readiness_probe_${validation_marker}=false" "$validation_stdout" || return 1
    done
    require_one 'action_20d_retry10_readiness_probe_remote_complete=true' "$validation_stdout"
}
run_probe() {
    local probe_role=$1
    local probe_target=$2
    local probe_alias=$3
    local probe_stdout=$4
    local probe_stderr=$5

    "$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o "HostKeyAlias=$probe_alias" \
        -o ConnectTimeout=10 -o ConnectionAttempts=1 -o LogLevel=ERROR \
        "$probe_target" 'cd / && sudo -n /bin/bash -s -- --node '"$probe_role" \
        <"$probe" >"$probe_stdout" 2>"$probe_stderr"
}
verify_sources() {
    [[ -f "$probe" && ! -L "$probe" && -x "$probe" ]] || return 1
    [[ "$(file_hash "$probe")" = "$probe_sha256" ]] || return 1
    /bin/bash -n "$probe" || return 1
    /bin/bash "$probe" --self-test >/dev/null || return 1
}
write_probe_fixture() {
    local fixture_role=$1
    local fixture_dns_count=$2
    local fixture_path=$3
    local fixture_label
    local fixture_state_metadata fixture_dedupe_metadata
    local fixture_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    fixture_state_metadata=pi:pi:750
    fixture_dedupe_metadata=pi:pi:750
    {
        while IFS= read -r fixture_label; do
            printf 'action_20d_retry10_readiness_probe_assertion_%s=true\n' "$fixture_label"
        done < <("$probe" --expected-assertions)
        printf '%s\n' \
            "action_20d_retry10_readiness_probe_value_node_role=$fixture_role" \
            'action_20d_retry10_readiness_probe_value_inherited_execution_user=pi' \
            "action_20d_retry10_readiness_probe_value_state_directory_metadata=$fixture_state_metadata" \
            "action_20d_retry10_readiness_probe_value_dedupe_directory_metadata=$fixture_dedupe_metadata" \
            'action_20d_retry10_readiness_probe_value_caddy_ipv4_vip_count=0' \
            'action_20d_retry10_readiness_probe_value_caddy_ipv6_vip_count=0' \
            "action_20d_retry10_readiness_probe_value_dns_ipv4_vip_count=$fixture_dns_count" \
            "action_20d_retry10_readiness_probe_value_dns_ipv6_vip_count=$fixture_dns_count" \
            "action_20d_retry10_readiness_probe_value_before_snapshot_sha256=$fixture_hash" \
            "action_20d_retry10_readiness_probe_value_after_snapshot_sha256=$fixture_hash" \
            "action_20d_retry10_readiness_probe_assertion_count=$("$probe" --expected-assertions | wc -l)" \
            'action_20d_retry10_readiness_probe_failed_assertion_count=0' \
            'action_20d_retry10_readiness_probe_first_failure=none' \
            'action_20d_retry10_readiness_probe_notification_helper_invoked=false' \
            'action_20d_retry10_readiness_probe_filesystem_mutations=false' \
            'action_20d_retry10_readiness_probe_service_mutations=false' \
            'action_20d_retry10_readiness_probe_keepalived_mutations=false' \
            'action_20d_retry10_readiness_probe_vrrp_mutations=false' \
            'action_20d_retry10_readiness_probe_vip_mutations=false' \
            'action_20d_retry10_readiness_probe_network_mutations=false' \
            'action_20d_retry10_readiness_probe_persistent_mutations=false' \
            'action_20d_retry10_readiness_probe_remote_complete=true'
    } >"$fixture_path"
}
run_self_test() {
    local self_root
    local self_label

    self_root=$(mktemp -d /tmp/caddy-action20d-c-runner-self.XXXXXX) || return 1
    trap 'rm -rf -- "$self_root"' RETURN
    write_probe_fixture node-a 1 "$self_root/node-a"
    write_probe_fixture node-b 0 "$self_root/node-b"
    validate_probe node-a "$self_root/node-a" /dev/null 0 || return 1
    validate_probe node-b "$self_root/node-b" /dev/null 0 || return 1
    printf '%s\n' \
        'action_20d_retry10_readiness_probe_assertion_state_directory_writable_as_pi=false' \
        >>"$self_root/node-a"
    if validate_probe node-a "$self_root/node-a" /dev/null 0; then return 1; fi
    for self_label in $(expected_assertions); do
        [[ "$self_label" =~ ^[a-z0-9_]+$ ]] || return 1
    done
    printf '%s_self_test_complete=true\n' "$prefix"
    rm -rf -- "$self_root"
    trap - RETURN
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        run_self_test
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        ;;
    *)
        printf 'Usage: %s [--expected-assertions|--self-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
work_directory=$(mktemp -d /tmp/caddy-action20d-c-runner.XXXXXX)
readonly work_directory
cleanup() { rm -rf -- "$work_directory"; }
trap cleanup EXIT
readonly node_a_stdout=$work_directory/node-a.stdout
readonly node_a_stderr=$work_directory/node-a.stderr
readonly node_b_stdout=$work_directory/node-b.stdout
readonly node_b_stderr=$work_directory/node-b.stderr
for capture_path in "$node_a_stdout" "$node_a_stderr" "$node_b_stdout" "$node_b_stderr"; do
    : >"$capture_path"
    chmod 0600 "$capture_path"
done

node_a_status=0
run_probe node-a "$node_a_target" "$node_a_alias" "$node_a_stdout" "$node_a_stderr" || node_a_status=$?
node_b_status=0
run_probe node-b "$node_b_target" "$node_b_alias" "$node_b_stdout" "$node_b_stderr" || node_b_status=$?
readonly node_a_status node_b_status

stream_failure=0
emit_stream node_a_stdout "$node_a_stdout" || stream_failure=1
emit_stream node_a_stderr "$node_a_stderr" || stream_failure=1
emit_stream node_b_stdout "$node_b_stdout" || stream_failure=1
emit_stream node_b_stderr "$node_b_stderr" || stream_failure=1
if [[ "$stream_failure" -ne 0 ]]; then
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
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
run_assertion node_a_ssh_completed test "$node_a_status" -eq 0
run_assertion node_b_ssh_completed test "$node_b_status" -eq 0
run_assertion node_a_probe_accepted validate_probe node-a "$node_a_stdout" "$node_a_stderr" "$node_a_status"
run_assertion node_b_probe_accepted validate_probe node-b "$node_b_stdout" "$node_b_stderr" "$node_b_status"
node_a_user=$(extract_one action_20d_retry10_readiness_probe_value_inherited_execution_user "$node_a_stdout" 2>/dev/null || true)
node_b_user=$(extract_one action_20d_retry10_readiness_probe_value_inherited_execution_user "$node_b_stdout" 2>/dev/null || true)
readonly node_a_user node_b_user
run_assertion node_a_inherited_user_pi test "$node_a_user" = pi
run_assertion node_b_inherited_user_pi test "$node_b_user" = pi
run_assertion inherited_user_same test "$node_a_user" = "$node_b_user"
node_a_state_metadata=$(extract_one action_20d_retry10_readiness_probe_value_state_directory_metadata "$node_a_stdout" 2>/dev/null || true)
node_b_state_metadata=$(extract_one action_20d_retry10_readiness_probe_value_state_directory_metadata "$node_b_stdout" 2>/dev/null || true)
node_a_dedupe_metadata=$(extract_one action_20d_retry10_readiness_probe_value_dedupe_directory_metadata "$node_a_stdout" 2>/dev/null || true)
node_b_dedupe_metadata=$(extract_one action_20d_retry10_readiness_probe_value_dedupe_directory_metadata "$node_b_stdout" 2>/dev/null || true)
readonly node_a_state_metadata node_b_state_metadata node_a_dedupe_metadata node_b_dedupe_metadata
run_assertion node_a_state_directory_metadata_collected test -n "$node_a_state_metadata"
run_assertion node_b_state_directory_metadata_collected test -n "$node_b_state_metadata"
run_assertion node_a_dedupe_directory_metadata_collected test -n "$node_a_dedupe_metadata"
run_assertion node_b_dedupe_directory_metadata_collected test -n "$node_b_dedupe_metadata"
run_assertion node_a_caddy_ipv4_vip_absent require_one \
    'action_20d_retry10_readiness_probe_value_caddy_ipv4_vip_count=0' "$node_a_stdout"
run_assertion node_a_caddy_ipv6_vip_absent require_one \
    'action_20d_retry10_readiness_probe_value_caddy_ipv6_vip_count=0' "$node_a_stdout"
run_assertion node_b_caddy_ipv4_vip_absent require_one \
    'action_20d_retry10_readiness_probe_value_caddy_ipv4_vip_count=0' "$node_b_stdout"
run_assertion node_b_caddy_ipv6_vip_absent require_one \
    'action_20d_retry10_readiness_probe_value_caddy_ipv6_vip_count=0' "$node_b_stdout"
run_assertion node_a_dns_ipv4_vip_owner require_one \
    'action_20d_retry10_readiness_probe_value_dns_ipv4_vip_count=1' "$node_a_stdout"
run_assertion node_a_dns_ipv6_vip_owner require_one \
    'action_20d_retry10_readiness_probe_value_dns_ipv6_vip_count=1' "$node_a_stdout"
run_assertion node_b_dns_ipv4_vip_absent require_one \
    'action_20d_retry10_readiness_probe_value_dns_ipv4_vip_count=0' "$node_b_stdout"
run_assertion node_b_dns_ipv6_vip_absent require_one \
    'action_20d_retry10_readiness_probe_value_dns_ipv6_vip_count=0' "$node_b_stdout"
run_assertion node_a_notifier_not_invoked require_one \
    'action_20d_retry10_readiness_probe_notification_helper_invoked=false' "$node_a_stdout"
run_assertion node_b_notifier_not_invoked require_one \
    'action_20d_retry10_readiness_probe_notification_helper_invoked=false' "$node_b_stdout"
node_a_before_hash=$(extract_one action_20d_retry10_readiness_probe_value_before_snapshot_sha256 "$node_a_stdout" 2>/dev/null || true)
node_a_after_hash=$(extract_one action_20d_retry10_readiness_probe_value_after_snapshot_sha256 "$node_a_stdout" 2>/dev/null || true)
node_b_before_hash=$(extract_one action_20d_retry10_readiness_probe_value_before_snapshot_sha256 "$node_b_stdout" 2>/dev/null || true)
node_b_after_hash=$(extract_one action_20d_retry10_readiness_probe_value_after_snapshot_sha256 "$node_b_stdout" 2>/dev/null || true)
readonly node_a_before_hash node_a_after_hash node_b_before_hash node_b_after_hash
run_assertion node_a_before_hash_collected test -n "$node_a_before_hash"
run_assertion node_a_after_hash_collected test -n "$node_a_after_hash"
run_assertion node_b_before_hash_collected test -n "$node_b_before_hash"
run_assertion node_b_after_hash_collected test -n "$node_b_after_hash"
run_assertion node_a_state_unchanged test "$node_a_before_hash" = "$node_a_after_hash"
run_assertion node_b_state_unchanged test "$node_b_before_hash" = "$node_b_after_hash"

printf '%s_value_node_a_status=%s\n' "$prefix" "$node_a_status"
printf '%s_value_node_b_status=%s\n' "$prefix" "$node_b_status"
printf '%s_value_node_a_state_directory_metadata=%s\n' "$prefix" "$node_a_state_metadata"
printf '%s_value_node_b_state_directory_metadata=%s\n' "$prefix" "$node_b_state_metadata"
printf '%s_value_node_a_dedupe_directory_metadata=%s\n' "$prefix" "$node_a_dedupe_metadata"
printf '%s_value_node_b_dedupe_directory_metadata=%s\n' "$prefix" "$node_b_dedupe_metadata"
printf '%s_assertion_count=%s\n' "$prefix" "$(expected_assertions | wc -l)"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_notification_helper_invoked=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_network_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_runner_cleanup_complete=true\n' "$prefix"
[[ "$failed_assertion_count" -eq 0 ]]
