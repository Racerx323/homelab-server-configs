#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20l_outer
readonly inspector_sha256=4e3d6139778108fd5aed4cfbcd5175322e0c590404cc106e3b0dac8c66369875
readonly expected_check_count=49
readonly expected_remote_line_count=86
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-keepalived-dbus-readiness-action20l.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_sha256() {
    local action20l_outer_hash_value=$1

    [[ ${#action20l_outer_hash_value} -eq 64 ]] || return 1
    [[ "$action20l_outer_hash_value" != *[!0-9a-f]* ]]
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
}
read_only_contract() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del)|(^|[;&|[:space:]])(install|cp|mv)[[:space:]]+(/etc|/var/backups|/usr/local)' \
        "$inspector"
}
run_gate() {
    local action20l_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20l_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20l_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory inspector_regular inspector_executable inspector_hash \
        syntax shellcheck canonical_format read_only_contract inspector_self_test
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate inspector_regular test -f "$inspector" || return 1
    run_gate inspector_executable test -x "$inspector" || return 1
    run_gate inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256" || return 1
    run_gate syntax /bin/bash -n "$inspector" "$0" || return 1
    run_gate shellcheck shellcheck "$inspector" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check "$inspector" "$0" || return 1
    run_gate read_only_contract read_only_contract || return 1
    run_gate inspector_self_test /bin/bash "$inspector" --self-test || return 1
}
safe_stream() {
    local action20l_outer_stream_path=$1

    [[ "$(wc -c <"$action20l_outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20l_outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20l_outer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20l_outer_stream_path"
}
emit_stream() {
    local action20l_outer_stream_label=$1
    local action20l_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20l_outer_stream_label" \
        "$(wc -c <"$action20l_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20l_outer_stream_label" \
        "$(line_count "$action20l_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20l_outer_stream_label" \
        "$(file_hash "$action20l_outer_stream_path")"
    if safe_stream "$action20l_outer_stream_path"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20l_outer_stream_label"
        if [[ -s "$action20l_outer_stream_path" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20l_outer_stream_label"
            cat "$action20l_outer_stream_path"
            printf '%s_%s_end\n' "$prefix" "$action20l_outer_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action20l_outer_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20l_outer_stream_label" >&2
    return 97
}
require_one_line() {
    local action20l_outer_expected_line=$1
    local action20l_outer_transcript=$2

    [[ "$(grep -Fxc "$action20l_outer_expected_line" "$action20l_outer_transcript")" -eq 1 ]]
}
extract_one_value() {
    local action20l_outer_key=$1
    local action20l_outer_transcript=$2
    local action20l_outer_matches

    action20l_outer_matches=$(grep -Fc "${action20l_outer_key}=" "$action20l_outer_transcript" || true)
    [[ "$action20l_outer_matches" -eq 1 ]] || return 1
    sed -n "s/^${action20l_outer_key}=//p" "$action20l_outer_transcript"
}
expected_transcript_keys() {
    local action20l_outer_label
    local action20l_outer_capture_name

    while IFS= read -r action20l_outer_label; do
        printf 'action_20l_check_%s\n' "$action20l_outer_label"
    done < <(/bin/bash "$inspector" --expected-checks)
    for action20l_outer_capture_name in version_stdout version_stderr bus_stdout bus_stderr; do
        printf '%s\n' \
            "action_20l_capture_${action20l_outer_capture_name}_bytes" \
            "action_20l_capture_${action20l_outer_capture_name}_lines" \
            "action_20l_capture_${action20l_outer_capture_name}_sha256" \
            "action_20l_capture_${action20l_outer_capture_name}_classification" \
            "action_20l_capture_${action20l_outer_capture_name}_base64"
    done
    printf '%s\n' \
        action_20l_value_node action_20l_value_expected_check_count \
        action_20l_value_main_sha256 action_20l_value_fragment_sha256 \
        action_20l_value_before_state_sha256 action_20l_value_after_state_sha256 \
        action_20l_check_count action_20l_failed_check_count \
        action_20l_first_failure action_20l_keepalived_dbus_registration_checked \
        action_20l_config_installation action_20l_keepalived_reload \
        action_20l_service_mutations action_20l_vrrp_mutations \
        action_20l_vip_mutations action_20l_persistent_mutations \
        action_20l_remote_complete
}
validate_capture() {
    local action20l_outer_capture_name=$1
    local action20l_outer_transcript=$2
    local action20l_outer_decode_path=$3
    local action20l_outer_expected_bytes
    local action20l_outer_expected_lines
    local action20l_outer_expected_hash
    local action20l_outer_encoded

    action20l_outer_expected_bytes=$(extract_one_value \
        "action_20l_capture_${action20l_outer_capture_name}_bytes" "$action20l_outer_transcript") || return 1
    action20l_outer_expected_lines=$(extract_one_value \
        "action_20l_capture_${action20l_outer_capture_name}_lines" "$action20l_outer_transcript") || return 1
    action20l_outer_expected_hash=$(extract_one_value \
        "action_20l_capture_${action20l_outer_capture_name}_sha256" "$action20l_outer_transcript") || return 1
    action20l_outer_encoded=$(extract_one_value \
        "action_20l_capture_${action20l_outer_capture_name}_base64" "$action20l_outer_transcript") || return 1
    require_one_line \
        "action_20l_capture_${action20l_outer_capture_name}_classification=bounded_safe" \
        "$action20l_outer_transcript" || return 1
    [[ "$action20l_outer_expected_bytes" =~ ^[0-9]+$ ]] || return 1
    [[ "$action20l_outer_expected_lines" =~ ^[0-9]+$ ]] || return 1
    valid_sha256 "$action20l_outer_expected_hash" || return 1
    printf '%s' "$action20l_outer_encoded" | base64 -d >"$action20l_outer_decode_path" 2>/dev/null || return 1
    [[ "$(wc -c <"$action20l_outer_decode_path")" -eq "$action20l_outer_expected_bytes" ]] || return 1
    [[ "$(line_count "$action20l_outer_decode_path")" -eq "$action20l_outer_expected_lines" ]] || return 1
    [[ "$(file_hash "$action20l_outer_decode_path")" = "$action20l_outer_expected_hash" ]] || return 1
    safe_stream "$action20l_outer_decode_path"
}
version_has_dbus() {
    local action20l_outer_version_file=$1

    awk '
        $1 == "Config" && $2 == "options:" {
            for (field = 3; field <= NF; field++) {
                if ($field == "DBUS") found = 1
            }
        }
        END { exit(found == 1 ? 0 : 1) }
    ' "$action20l_outer_version_file"
}
validate_node_transcript() {
    local action20l_outer_node=$1
    local action20l_outer_stdout=$2
    local action20l_outer_stderr=$3
    local action20l_outer_validation_root=$4
    local action20l_outer_expected_main
    local action20l_outer_expected_fragment
    local action20l_outer_before_hash
    local action20l_outer_after_hash

    case "$action20l_outer_node" in
        node-a)
            action20l_outer_expected_main=357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2
            action20l_outer_expected_fragment=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
            ;;
        node-b)
            action20l_outer_expected_main=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f
            action20l_outer_expected_fragment=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
            ;;
        *) return 64 ;;
    esac
    [[ ! -s "$action20l_outer_stderr" ]] || return 1
    [[ "$(line_count "$action20l_outer_stdout")" -eq "$expected_remote_line_count" ]] || return 1
    expected_transcript_keys >"$action20l_outer_validation_root/expected.keys" || return 1
    sed 's/=.*$//' "$action20l_outer_stdout" >"$action20l_outer_validation_root/actual.keys" || return 1
    diff -u "$action20l_outer_validation_root/expected.keys" \
        "$action20l_outer_validation_root/actual.keys" >/dev/null || return 1
    ! grep -Eq '^action_20l_check_[a-z0-9_]+=false$' "$action20l_outer_stdout" || return 1
    require_one_line "action_20l_value_node=$action20l_outer_node" "$action20l_outer_stdout" || return 1
    require_one_line "action_20l_value_expected_check_count=$expected_check_count" "$action20l_outer_stdout" || return 1
    require_one_line "action_20l_value_main_sha256=$action20l_outer_expected_main" "$action20l_outer_stdout" || return 1
    require_one_line "action_20l_value_fragment_sha256=$action20l_outer_expected_fragment" "$action20l_outer_stdout" || return 1
    require_one_line "action_20l_check_count=$expected_check_count" "$action20l_outer_stdout" || return 1
    require_one_line 'action_20l_failed_check_count=0' "$action20l_outer_stdout" || return 1
    require_one_line 'action_20l_first_failure=none' "$action20l_outer_stdout" || return 1
    require_one_line 'action_20l_keepalived_dbus_registration_checked=false' "$action20l_outer_stdout" || return 1
    require_one_line 'action_20l_config_installation=false' "$action20l_outer_stdout" || return 1
    require_one_line 'action_20l_keepalived_reload=false' "$action20l_outer_stdout" || return 1
    require_one_line 'action_20l_service_mutations=false' "$action20l_outer_stdout" || return 1
    require_one_line 'action_20l_vrrp_mutations=false' "$action20l_outer_stdout" || return 1
    require_one_line 'action_20l_vip_mutations=false' "$action20l_outer_stdout" || return 1
    require_one_line 'action_20l_persistent_mutations=false' "$action20l_outer_stdout" || return 1
    require_one_line 'action_20l_remote_complete=true' "$action20l_outer_stdout" || return 1
    action20l_outer_before_hash=$(extract_one_value action_20l_value_before_state_sha256 "$action20l_outer_stdout") || return 1
    action20l_outer_after_hash=$(extract_one_value action_20l_value_after_state_sha256 "$action20l_outer_stdout") || return 1
    valid_sha256 "$action20l_outer_before_hash" || return 1
    valid_sha256 "$action20l_outer_after_hash" || return 1
    [[ "$action20l_outer_before_hash" = "$action20l_outer_after_hash" ]] || return 1
    validate_capture version_stdout "$action20l_outer_stdout" \
        "$action20l_outer_validation_root/version.stdout" || return 1
    validate_capture version_stderr "$action20l_outer_stdout" \
        "$action20l_outer_validation_root/version.stderr" || return 1
    validate_capture bus_stdout "$action20l_outer_stdout" \
        "$action20l_outer_validation_root/bus.stdout" || return 1
    validate_capture bus_stderr "$action20l_outer_stdout" \
        "$action20l_outer_validation_root/bus.stderr" || return 1
    cat "$action20l_outer_validation_root/version.stdout" \
        "$action20l_outer_validation_root/version.stderr" \
        >"$action20l_outer_validation_root/version.combined" || return 1
    grep -Eq '^Keepalived v[^[:space:]]+' \
        "$action20l_outer_validation_root/version.combined" || return 1
    grep -Eq '^Config options:' \
        "$action20l_outer_validation_root/version.combined" || return 1
    version_has_dbus "$action20l_outer_validation_root/version.combined" || return 1
    grep -Eq '^org\.freedesktop\.DBus[[:space:]]' \
        "$action20l_outer_validation_root/bus.stdout" || return 1
}
run_one_node() {
    local action20l_outer_node=$1
    local action20l_outer_target=$2
    local action20l_outer_ssh_binary=${CADDY_ACTION20L_SSH_BINARY:-ssh}
    local action20l_outer_node_root
    local action20l_outer_remote_stdout
    local action20l_outer_remote_stderr
    local action20l_outer_remote_status=0
    local action20l_outer_stream_failure=0
    local action20l_outer_cleanup_command

    if [[ "$action20l_outer_ssh_binary" != ssh ]]; then
        [[ "${CADDY_ACTION20L_TEST_MODE:-}" = 1 && -x "$action20l_outer_ssh_binary" ]] || return 64
    fi
    action20l_outer_node_root=$(mktemp -d "/tmp/caddy-action20l-${action20l_outer_node}.XXXXXX") || return 1
    printf -v action20l_outer_cleanup_command 'rm -rf -- %q' "$action20l_outer_node_root"
    # Intentionally expand the shell-escaped immutable path before the local
    # variable leaves scope at RETURN.
    # shellcheck disable=SC2064
    trap "$action20l_outer_cleanup_command" RETURN
    action20l_outer_remote_stdout=$action20l_outer_node_root/remote.stdout
    action20l_outer_remote_stderr=$action20l_outer_node_root/remote.stderr
    install -m 0600 /dev/null "$action20l_outer_remote_stdout" || return 1
    install -m 0600 /dev/null "$action20l_outer_remote_stderr" || return 1
    "$action20l_outer_ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=yes "$action20l_outer_target" \
        "cd / && sudo -n /bin/bash -s -- --node $action20l_outer_node" \
        <"$inspector" >"$action20l_outer_remote_stdout" \
        2>"$action20l_outer_remote_stderr" || action20l_outer_remote_status=$?
    emit_stream "${action20l_outer_node}_remote_stdout" "$action20l_outer_remote_stdout" ||
        action20l_outer_stream_failure=1
    emit_stream "${action20l_outer_node}_remote_stderr" "$action20l_outer_remote_stderr" ||
        action20l_outer_stream_failure=1
    printf '%s_%s_remote_status=%s\n' "$prefix" "$action20l_outer_node" "$action20l_outer_remote_status"
    if [[ "$action20l_outer_stream_failure" -ne 0 ]]; then
        trap - RETURN
        printf '%s_%s_protected_evidence=%s\n' \
            "$prefix" "$action20l_outer_node" "$action20l_outer_node_root" >&2
        return 97
    fi
    [[ "$action20l_outer_remote_status" -eq 0 ]] || return "$action20l_outer_remote_status"
    validate_node_transcript "$action20l_outer_node" "$action20l_outer_remote_stdout" \
        "$action20l_outer_remote_stderr" "$action20l_outer_node_root" || return 97
    emit_stream "${action20l_outer_node}_keepalived_version_stdout" \
        "$action20l_outer_node_root/version.stdout" || return 97
    emit_stream "${action20l_outer_node}_keepalived_version_stderr" \
        "$action20l_outer_node_root/version.stderr" || return 97
    emit_stream "${action20l_outer_node}_system_bus_stdout" \
        "$action20l_outer_node_root/bus.stdout" || return 97
    emit_stream "${action20l_outer_node}_system_bus_stderr" \
        "$action20l_outer_node_root/bus.stderr" || return 97
    printf '%s_%s_accepted=true\n' "$prefix" "$action20l_outer_node"
}
run_transport() {
    run_one_node node-b pi@10.1.0.54 || return $?
    run_one_node node-a pi@10.1.0.53 || return $?
    printf '%s_node_b_contacted=true\n' "$prefix"
    printf '%s_node_a_contacted=true\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_keepalived_dbus_registration_checked=false\n' "$prefix"
    printf '%s_config_installation=false\n' "$prefix"
    printf '%s_keepalived_reload=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_vrrp_mutation=false\n' "$prefix"
    printf '%s_vip_mutation=false\n' "$prefix"
    printf '%s_persistent_live_mutations=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_self_test_complete=true\n' "$prefix"
        ;;
    --test-transport)
        [[ $# -eq 1 && "${CADDY_ACTION20L_TEST_MODE:-}" = 1 ]] || exit 64
        run_transport
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        run_local_gates
        run_transport
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test]\n' "${0##*/}" >&2
        exit 64
        ;;
esac
