#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20e_a
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly inspector=$script_directory/inspect-caddy-runtime-directories-action20e-a.sh

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
verify_source() {
    local source_identity

    source_identity="$(id -un):$(id -gn):755"
    [[ -f "$inspector" && ! -L "$inspector" && -x "$inspector" ]] || return 1
    [[ "$(stat -c '%U:%G:%a' "$inspector")" = "$source_identity" ]] || return 1
    /bin/bash -n "$inspector" || return 1
    /bin/bash "$inspector" --self-test >/dev/null || return 1
}
validate_probe() {
    local output_path=$1
    local status_value=$2
    local expected_count
    local observed_count
    local unique_count

    [[ "$status_value" -eq 0 ]] || return 1
    expected_count=$(/bin/bash "$inspector" --expected-assertions | wc -l) || return 1
    observed_count=$(grep -Ec '^action_20e_a_probe_assertion_[a-z0-9_]+=true$' "$output_path" || true)
    unique_count=$(sed -n 's/^\(action_20e_a_probe_assertion_[a-z0-9_]*\)=true$/\1/p' "$output_path" | LC_ALL=C sort -u | wc -l)
    [[ "$observed_count" -eq "$expected_count" ]] || return 1
    [[ "$unique_count" -eq "$expected_count" ]] || return 1
    diff -u \
        <(/bin/bash "$inspector" --expected-assertions | sed 's/^/action_20e_a_probe_assertion_/' | LC_ALL=C sort) \
        <(sed -n 's/^\(action_20e_a_probe_assertion_[a-z0-9_]*\)=true$/\1/p' "$output_path" | LC_ALL=C sort) >/dev/null || return 1
    [[ "$(grep -Ec '^action_20e_a_probe_assertion_[a-z0-9_]+=false$' "$output_path" || true)" -eq 0 ]] || return 1
    grep -Fxq 'action_20e_a_probe_persistent_mutations=false' "$output_path" || return 1
    grep -Fxq 'action_20e_a_probe_inspection_complete=true' "$output_path" || return 1
}
run_node() {
    local node_role=$1
    local node_target=$2
    local output_path=$3
    local error_path=$4

    /usr/bin/ssh -T -o BatchMode=yes -o ConnectTimeout=5 \
        "$node_target" 'cd / && sudo -n /bin/bash -s -- --node '"$node_role" \
        <"$inspector" >"$output_path" 2>"$error_path"
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        verify_source
        printf '%s_runner_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac

verify_source
working_directory_approved
work_directory=$(mktemp -d /tmp/caddy-action20e-a-runner.XXXXXX)
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

for node_role in node-b node-a; do
    if [[ "$node_role" = node-b ]]; then node_target=$node_b_target; else node_target=$node_a_target; fi
    stdout_path=$work_directory/$node_role.stdout
    stderr_path=$work_directory/$node_role.stderr
    touch "$stdout_path" "$stderr_path"
    chmod 0600 "$stdout_path" "$stderr_path"
    node_status=0
    run_node "$node_role" "$node_target" "$stdout_path" "$stderr_path" || node_status=$?
    if ! safe_stream "$stdout_path" || ! safe_stream "$stderr_path"; then
        retain_evidence=true
        printf '%s_%s_stream_classification=unsafe_retained\n' "$prefix" "${node_role//-/_}" >&2
        exit 97
    fi
    printf '%s_%s_stream_classification=bounded_safe\n' "$prefix" "${node_role//-/_}"
    emit_stream "${node_role//-/_}_stdout" "$stdout_path"
    emit_stream "${node_role//-/_}_stderr" "$stderr_path"
    printf '%s_%s_status=%s\n' "$prefix" "${node_role//-/_}" "$node_status"
    if validate_probe "$stdout_path" "$node_status"; then
        printf '%s_%s_accepted=true\n' "$prefix" "${node_role//-/_}"
    else
        printf '%s_%s_accepted=false\n' "$prefix" "${node_role//-/_}" >&2
        exit 1
    fi
done
printf '%s_keepalived_mutated=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutated=false\n' "$prefix"
printf '%s_vip_mutated=false\n' "$prefix"
printf '%s_notifier_invoked=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_acceptance_complete=true\n' "$prefix"
