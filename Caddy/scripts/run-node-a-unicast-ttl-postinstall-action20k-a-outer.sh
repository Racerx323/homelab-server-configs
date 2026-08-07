#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20k_a_outer
readonly inspector_sha256=d8bc0a25b003f5803c90624d3e2d2b4b2387cc78d161e93ce0b747a68fdda137
readonly action20k_outer_sha256=0ad806d5fc08b8a05b55d4ee756f43379846d58db16e2da094c6167732e3422d
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly output_evidence_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly multifile_grep_sha256=0c8d5453e906964143311bcec93c9c755b0fccd84bcbdf9f8bda7c367ed38655
readonly portable_awk_sha256=30e6be4f4737b9df3c9669572252ee8bff7ae949387a7f96ebe62a2e384fc755
readonly expected_check_count=61
readonly expected_remote_line_count=76
readonly expected_backup=/var/backups/caddy-ha/action20k-node-a-unicast-ttl.5YRfcn
readonly expected_fragment_sha256=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
readonly maximum_stream_bytes=1048576
readonly maximum_stream_lines=4096

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly inspector=$script_directory/inspect-node-a-unicast-ttl-postinstall-action20k-a.sh
readonly action20k_outer=$script_directory/run-caddy-unicast-ttl-action20k-outer.sh
readonly collision=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$caddy_root/tests/transaction-output-evidence-policy-regression.sh
readonly multifile_grep=$caddy_root/tests/multifile-grep-count-policy.sh
readonly portable_awk=$caddy_root/tests/portable-awk-policy.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_sha256() {
    local action20ka_outer_value=$1

    [[ ${#action20ka_outer_value} -eq 64 ]] || return 1
    [[ "$action20ka_outer_value" != *[!0-9a-f]* ]]
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
require_source() {
    local action20ka_outer_expected_hash=$1
    local action20ka_outer_source=$2

    [[ -f "$action20ka_outer_source" && ! -L "$action20ka_outer_source" &&
        -x "$action20ka_outer_source" ]] || return 1
    [[ "$(file_hash "$action20ka_outer_source")" = "$action20ka_outer_expected_hash" ]]
}
read_only_contract() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del)|(^|[;&|[:space:]])(install|cp|mv)[[:space:]]+(/etc|/var/backups|/usr/local)' \
        "$inspector"
}
run_gate() {
    local action20ka_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20ka_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20ka_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory inspector_hash action20k_outer_hash collision_hash \
        conditional_hash output_evidence_hash multifile_grep_hash \
        portable_awk_hash syntax shellcheck canonical_format collision_policy \
        conditional_policy output_evidence_policy multifile_grep_policy \
        portable_awk_policy read_only_contract inspector_self_test
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate inspector_hash require_source "$inspector_sha256" "$inspector" || return 1
    run_gate action20k_outer_hash require_source "$action20k_outer_sha256" "$action20k_outer" || return 1
    run_gate collision_hash require_source "$collision_sha256" "$collision" || return 1
    run_gate conditional_hash require_source "$conditional_sha256" "$conditional" || return 1
    run_gate output_evidence_hash require_source "$output_evidence_sha256" "$output_evidence" || return 1
    run_gate multifile_grep_hash require_source "$multifile_grep_sha256" "$multifile_grep" || return 1
    run_gate portable_awk_hash require_source "$portable_awk_sha256" "$portable_awk" || return 1
    run_gate syntax /bin/bash -n "$inspector" "$0" || return 1
    run_gate shellcheck shellcheck "$inspector" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check "$inspector" "$0" || return 1
    run_gate collision_policy /bin/bash "$collision" "$inspector" "$0" || return 1
    run_gate conditional_policy /bin/bash "$conditional" || return 1
    run_gate output_evidence_policy /bin/bash "$output_evidence" || return 1
    run_gate multifile_grep_policy /bin/bash "$multifile_grep" --check "$inspector" "$0" || return 1
    run_gate portable_awk_policy /bin/bash "$portable_awk" --check "$inspector" "$0" || return 1
    run_gate read_only_contract read_only_contract || return 1
    run_gate inspector_self_test /bin/bash "$inspector" --self-test || return 1
}
safe_stream() {
    local action20ka_outer_stream=$1

    [[ "$(wc -c <"$action20ka_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20ka_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20ka_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20ka_outer_stream"
}
emit_stream() {
    local action20ka_outer_stream_label=$1
    local action20ka_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20ka_outer_stream_label" \
        "$(wc -c <"$action20ka_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20ka_outer_stream_label" \
        "$(line_count "$action20ka_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20ka_outer_stream_label" \
        "$(file_hash "$action20ka_outer_stream_path")"
    if safe_stream "$action20ka_outer_stream_path"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20ka_outer_stream_label"
        if [[ -s "$action20ka_outer_stream_path" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20ka_outer_stream_label"
            cat "$action20ka_outer_stream_path"
            printf '%s_%s_end\n' "$prefix" "$action20ka_outer_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action20ka_outer_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20ka_outer_stream_label" >&2
    return 97
}
require_one_line() {
    local action20ka_outer_expected_line=$1
    local action20ka_outer_transcript=$2

    [[ "$(grep -Fxc "$action20ka_outer_expected_line" "$action20ka_outer_transcript")" -eq 1 ]]
}
extract_value() {
    local action20ka_outer_key=$1
    local action20ka_outer_transcript=$2

    sed -n "s/^${action20ka_outer_key}=//p" "$action20ka_outer_transcript"
}
validate_remote_transcript() {
    local action20ka_outer_stdout=$1
    local action20ka_outer_stderr=$2
    local action20ka_outer_expected_file=$3
    local action20ka_outer_actual_file=$4
    local action20ka_outer_before_hash
    local action20ka_outer_after_hash

    [[ ! -s "$action20ka_outer_stderr" ]] || return 1
    [[ "$(line_count "$action20ka_outer_stdout")" -eq "$expected_remote_line_count" ]] || return 1
    /bin/bash "$inspector" --expected-checks >"$action20ka_outer_expected_file" || return 1
    [[ "$(line_count "$action20ka_outer_expected_file")" -eq "$expected_check_count" ]] || return 1
    ! grep -Eq '^action_20k_a_check_[a-z0-9_]+=false$' "$action20ka_outer_stdout" || return 1
    sed -n 's/^action_20k_a_check_\([a-z0-9_]*\)=true$/\1/p' \
        "$action20ka_outer_stdout" >"$action20ka_outer_actual_file" || return 1
    [[ "$(line_count "$action20ka_outer_actual_file")" -eq "$expected_check_count" ]] || return 1
    [[ "$(LC_ALL=C sort -u "$action20ka_outer_actual_file" | wc -l)" -eq "$expected_check_count" ]] || return 1
    diff -u "$action20ka_outer_expected_file" "$action20ka_outer_actual_file" >/dev/null || return 1
    require_one_line "action_20k_a_value_expected_check_count=$expected_check_count" "$action20ka_outer_stdout" || return 1
    require_one_line "action_20k_a_value_backup_path=$expected_backup" "$action20ka_outer_stdout" || return 1
    require_one_line "action_20k_a_value_fragment_sha256=$expected_fragment_sha256" "$action20ka_outer_stdout" || return 1
    require_one_line "action_20k_a_check_count=$expected_check_count" "$action20ka_outer_stdout" || return 1
    require_one_line 'action_20k_a_failed_check_count=0' "$action20ka_outer_stdout" || return 1
    require_one_line 'action_20k_a_first_failure=none' "$action20ka_outer_stdout" || return 1
    require_one_line 'action_20k_a_helper_execution=false' "$action20ka_outer_stdout" || return 1
    require_one_line 'action_20k_a_filesystem_mutations=false' "$action20ka_outer_stdout" || return 1
    require_one_line 'action_20k_a_service_mutations=false' "$action20ka_outer_stdout" || return 1
    require_one_line 'action_20k_a_vrrp_mutations=false' "$action20ka_outer_stdout" || return 1
    require_one_line 'action_20k_a_vip_mutations=false' "$action20ka_outer_stdout" || return 1
    require_one_line 'action_20k_a_node_b_contacted=false' "$action20ka_outer_stdout" || return 1
    require_one_line 'action_20k_a_remote_complete=true' "$action20ka_outer_stdout" || return 1
    action20ka_outer_before_hash=$(extract_value action_20k_a_value_before_state_sha256 "$action20ka_outer_stdout") || return 1
    action20ka_outer_after_hash=$(extract_value action_20k_a_value_after_state_sha256 "$action20ka_outer_stdout") || return 1
    valid_sha256 "$action20ka_outer_before_hash" || return 1
    valid_sha256 "$action20ka_outer_after_hash" || return 1
    [[ "$action20ka_outer_before_hash" = "$action20ka_outer_after_hash" ]]
}
run_transport() {
    local action20ka_outer_ssh_binary=${CADDY_ACTION20KA_SSH_BINARY:-ssh}
    local action20ka_outer_work_root
    local action20ka_outer_stdout
    local action20ka_outer_stderr
    local action20ka_outer_expected
    local action20ka_outer_actual
    local action20ka_outer_status=0
    local action20ka_outer_stream_failure=0

    if [[ "$action20ka_outer_ssh_binary" != ssh ]]; then
        [[ "${CADDY_ACTION20KA_TEST_MODE:-}" = 1 && -x "$action20ka_outer_ssh_binary" ]] || return 64
    fi
    action20ka_outer_work_root=$(mktemp -d /tmp/caddy-action20k-a-outer.XXXXXX) || return 1
    trap 'rm -rf -- "$action20ka_outer_work_root"' RETURN
    action20ka_outer_stdout=$action20ka_outer_work_root/remote.stdout
    action20ka_outer_stderr=$action20ka_outer_work_root/remote.stderr
    action20ka_outer_expected=$action20ka_outer_work_root/expected
    action20ka_outer_actual=$action20ka_outer_work_root/actual
    : >"$action20ka_outer_stdout"
    : >"$action20ka_outer_stderr"
    chmod 0600 "$action20ka_outer_stdout" "$action20ka_outer_stderr"
    "$action20ka_outer_ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=yes pi@10.1.0.53 \
        'cd / && sudo -n /bin/bash -s --' <"$inspector" \
        >"$action20ka_outer_stdout" 2>"$action20ka_outer_stderr" ||
        action20ka_outer_status=$?
    emit_stream remote_stdout "$action20ka_outer_stdout" || action20ka_outer_stream_failure=1
    emit_stream remote_stderr "$action20ka_outer_stderr" || action20ka_outer_stream_failure=1
    printf '%s_remote_status=%s\n' "$prefix" "$action20ka_outer_status"
    if [[ "$action20ka_outer_stream_failure" -ne 0 ]]; then
        trap - RETURN
        printf '%s_protected_evidence=%s\n' "$prefix" "$action20ka_outer_work_root" >&2
        return 97
    fi
    [[ "$action20ka_outer_status" -eq 0 ]] || return "$action20ka_outer_status"
    validate_remote_transcript "$action20ka_outer_stdout" "$action20ka_outer_stderr" \
        "$action20ka_outer_expected" "$action20ka_outer_actual" || return 97
    printf '%s_node_a_contacted=true\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_helper_execution=false\n' "$prefix"
    printf '%s_keepalived_reload=false\n' "$prefix"
    printf '%s_keepalived_restart=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_vrrp_mutation=false\n' "$prefix"
    printf '%s_vip_mutation=false\n' "$prefix"
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
        [[ $# -eq 1 && "${CADDY_ACTION20KA_TEST_MODE:-}" = 1 ]] || exit 64
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
