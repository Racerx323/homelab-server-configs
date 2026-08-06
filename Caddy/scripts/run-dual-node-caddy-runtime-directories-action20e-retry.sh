#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20e_retry
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly installer=$script_directory/install-caddy-runtime-directories-action20e-retry.sh
readonly config=$caddy_root/configs/tmpfiles.d/caddy-ha.conf

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
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
safe_stream() {
    local inspected_path=$1

    [[ "$(wc -c <"$inspected_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_path"
}
emit_stream() {
    local emitted_label=$1
    local emitted_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$emitted_label" "$(wc -c <"$emitted_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$emitted_label" "$(line_count "$emitted_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$emitted_label" "$(file_hash "$emitted_path")"
    if [[ ! -s "$emitted_path" ]]; then
        printf '%s_%s_content_secured=empty\n' "$prefix" "$emitted_label"
        return 0
    fi
    printf '%s_%s_begin\n' "$prefix" "$emitted_label"
    cat "$emitted_path"
    printf '%s_%s_end\n' "$prefix" "$emitted_label"
}
require_source() {
    local expected_mode=$1
    local source_path=$2
    local source_identity

    source_identity="$(id -un):$(id -gn):$expected_mode"
    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$source_path")" = "$source_identity" ]] || return 1
}
verify_sources() {
    require_source 755 "$installer" || return 1
    require_source 644 "$config" || return 1
    /bin/bash -n "$installer" || return 1
    /bin/bash "$installer" --self-test >/dev/null || return 1
    [[ "$(file_hash "$config")" = "$(/bin/bash "$installer" --render-config | sha256sum | awk '{ print $1 }')" ]] || return 1
}
validate_success() {
    local output_path=$1
    local status_value=$2
    local expected_count
    local observed_count
    local unique_count

    [[ "$status_value" -eq 0 ]] || return 1
    expected_count=$(/bin/bash "$installer" --expected-checks | wc -l) || return 1
    observed_count=$(grep -Ec '^action_20e_retry_node_check_[a-z0-9_]+=true$' "$output_path" || true)
    unique_count=$(sed -n 's/^\(action_20e_retry_node_check_[a-z0-9_]*\)=true$/\1/p' "$output_path" | LC_ALL=C sort -u | wc -l)
    [[ "$observed_count" -eq "$expected_count" ]] || return 1
    [[ "$unique_count" -eq "$expected_count" ]] || return 1
    diff -u \
        <(/bin/bash "$installer" --expected-checks | sed 's/^/action_20e_retry_node_check_/' | LC_ALL=C sort) \
        <(sed -n 's/^\(action_20e_retry_node_check_[a-z0-9_]*\)=true$/\1/p' "$output_path" | LC_ALL=C sort) >/dev/null || return 1
    [[ "$(grep -Ec '^action_20e_retry_node_check_[a-z0-9_]+=false$' "$output_path" || true)" -eq 0 ]] || return 1
    grep -Fxq 'action_20e_retry_node_install_complete=true' "$output_path" || return 1
    grep -Fxq 'action_20e_retry_node_keepalived_mutated=false' "$output_path" || return 1
    grep -Fxq 'action_20e_retry_node_service_mutations=false' "$output_path" || return 1
    grep -Fxq 'action_20e_retry_node_vrrp_mutated=false' "$output_path" || return 1
    grep -Fxq 'action_20e_retry_node_vip_mutated=false' "$output_path" || return 1
    grep -Fxq 'action_20e_retry_node_notifier_invoked=false' "$output_path" || return 1
    [[ "$(grep -Ec '^action_20e_retry_node_backup_path=/var/backups/caddy-ha/action20e-node-[ab]-runtime-directories\.[A-Za-z0-9]+$' "$output_path" || true)" -eq 1 ]]
}
extract_backup_path() {
    local output_path=$1

    sed -n 's/^action_20e_retry_node_backup_path=//p' "$output_path"
}
run_node() {
    local node_role=$1
    local node_target=$2
    local output_path=$3
    local error_path=$4

    /usr/bin/ssh -T -o BatchMode=yes -o ConnectTimeout=5 \
        "$node_target" 'cd / && sudo -n /bin/bash -s -- --node '"$node_role" \
        <"$installer" >"$output_path" 2>"$error_path"
}
rollback_node() {
    local node_role=$1
    local node_target=$2
    local backup_path=$3
    local output_path=$4
    local error_path=$5

    /usr/bin/ssh -T -o BatchMode=yes -o ConnectTimeout=5 \
        "$node_target" 'cd / && sudo -n /bin/bash -s -- --rollback --node '"$node_role"' '"$backup_path" \
        <"$installer" >"$output_path" 2>"$error_path"
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        printf '%s_runner_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_sources
working_directory_approved
work_directory=$(mktemp -d /tmp/caddy-action20e-retry-runner.XXXXXX)
readonly work_directory
retain_evidence=false
cleanup() {
    # shellcheck disable=SC2317
    if [[ "$retain_evidence" = true ]]; then
        printf '%s_protected_evidence=%s\n' "$prefix" "$work_directory" >&2
    else
        rm -rf -- "$work_directory"
    fi
}
trap cleanup EXIT
readonly node_b_stdout=$work_directory/node-b.stdout
readonly node_b_stderr=$work_directory/node-b.stderr
readonly node_a_stdout=$work_directory/node-a.stdout
readonly node_a_stderr=$work_directory/node-a.stderr
readonly rollback_stdout=$work_directory/node-b-rollback.stdout
readonly rollback_stderr=$work_directory/node-b-rollback.stderr
touch "$node_b_stdout" "$node_b_stderr" "$node_a_stdout" "$node_a_stderr" "$rollback_stdout" "$rollback_stderr"
chmod 0600 "$work_directory"/*

node_b_status=0
run_node node-b "$node_b_target" "$node_b_stdout" "$node_b_stderr" || node_b_status=$?
readonly node_b_status
if ! safe_stream "$node_b_stdout" || ! safe_stream "$node_b_stderr"; then
    retain_evidence=true
    printf '%s_node_b_stream_classification=unsafe_retained\n' "$prefix" >&2
    exit 97
fi
printf '%s_node_b_stream_classification=bounded_safe\n' "$prefix"
emit_stream node_b_stdout "$node_b_stdout"
emit_stream node_b_stderr "$node_b_stderr"
printf '%s_node_b_status=%s\n' "$prefix" "$node_b_status"
if ! validate_success "$node_b_stdout" "$node_b_status"; then
    printf '%s_node_b_accepted=false\n' "$prefix" >&2
    printf '%s_node_a_contacted=false\n' "$prefix"
    exit 1
fi
printf '%s_node_b_accepted=true\n' "$prefix"
node_b_backup=$(extract_backup_path "$node_b_stdout")
readonly node_b_backup

node_a_status=0
run_node node-a "$node_a_target" "$node_a_stdout" "$node_a_stderr" || node_a_status=$?
readonly node_a_status
if ! safe_stream "$node_a_stdout" || ! safe_stream "$node_a_stderr"; then
    retain_evidence=true
    printf '%s_node_a_stream_classification=unsafe_retained\n' "$prefix" >&2
    exit 97
fi
printf '%s_node_a_stream_classification=bounded_safe\n' "$prefix"
emit_stream node_a_stdout "$node_a_stdout"
emit_stream node_a_stderr "$node_a_stderr"
printf '%s_node_a_status=%s\n' "$prefix" "$node_a_status"
if ! validate_success "$node_a_stdout" "$node_a_status"; then
    printf '%s_node_a_accepted=false\n' "$prefix" >&2
    rollback_status=0
    rollback_node node-b "$node_b_target" "$node_b_backup" "$rollback_stdout" "$rollback_stderr" || rollback_status=$?
    readonly rollback_status
    if ! safe_stream "$rollback_stdout" || ! safe_stream "$rollback_stderr"; then
        retain_evidence=true
        printf '%s_node_b_rollback_stream_classification=unsafe_retained\n' "$prefix" >&2
        exit 125
    fi
    printf '%s_node_b_rollback_stream_classification=bounded_safe\n' "$prefix"
    emit_stream node_b_rollback_stdout "$rollback_stdout"
    emit_stream node_b_rollback_stderr "$rollback_stderr"
    printf '%s_node_b_rollback_status=%s\n' "$prefix" "$rollback_status"
    [[ "$rollback_status" -eq 0 ]]
    grep -Fxq 'action_20e_retry_node_rollback_complete=true' "$rollback_stdout"
    printf '%s_node_b_rollback_accepted=true\n' "$prefix"
    exit 1
fi
printf '%s_node_a_accepted=true\n' "$prefix"
printf '%s_node_a_backup=%s\n' "$prefix" "$(extract_backup_path "$node_a_stdout")"
printf '%s_node_b_backup=%s\n' "$prefix" "$node_b_backup"
printf '%s_keepalived_mutated=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutated=false\n' "$prefix"
printf '%s_vip_mutated=false\n' "$prefix"
printf '%s_notifier_invoked=false\n' "$prefix"
printf '%s_transaction_complete=true\n' "$prefix"
