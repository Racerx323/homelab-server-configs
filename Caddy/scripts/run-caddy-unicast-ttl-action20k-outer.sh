#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20k_outer
readonly installer_sha256=abe962654982e9ab7cbcf6eabc4875a54eec2c81bf41868b3b5b6c393553a76e
readonly template_sha256=fd5ca8528468c97be6792e2184a71d6c06dc2c2a16abd44183bbfc170ff1f036
readonly regression_sha256=4718b3169c31317451a4657bc6770f09b2021d0e0c2e99a96c77db8b99719e65
readonly accepted_action20j_outer_sha256=50d302239c5675784e100bff358355651d30bdd96f8d02094c565f6403186ae7
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly output_evidence_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly multifile_grep_sha256=0c8d5453e906964143311bcec93c9c755b0fccd84bcbdf9f8bda7c367ed38655
readonly portable_awk_sha256=30e6be4f4737b9df3c9669572252ee8bff7ae949387a7f96ebe62a2e384fc755
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=65536

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly installer=$script_directory/install-caddy-unicast-ttl-action20k.sh
readonly template=$caddy_root/templates/keepalived-caddy-ha.conf.in
readonly regression=$caddy_root/tests/action20k-unicast-ttl-regression.sh
readonly accepted_action20j_outer=$script_directory/run-node-b-caddy-vrrp-activation-action20j-outer.sh
readonly collision=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$caddy_root/tests/transaction-output-evidence-policy-regression.sh
readonly multifile_grep=$caddy_root/tests/multifile-grep-count-policy.sh
readonly portable_awk=$caddy_root/tests/portable-awk-policy.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
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
require_hash() {
    local action20k_outer_expected_hash=$1
    local action20k_outer_path=$2

    [[ -f "$action20k_outer_path" && ! -L "$action20k_outer_path" &&
        -x "$action20k_outer_path" ]] || return 1
    [[ "$(file_hash "$action20k_outer_path")" = "$action20k_outer_expected_hash" ]]
}
run_gate() {
    local action20k_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20k_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20k_outer_gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory installer_hash template_hash regression_hash \
        accepted_action20j_outer_hash collision_hash conditional_hash \
        output_evidence_hash multifile_grep_hash portable_awk_hash syntax \
        shellcheck canonical_format collision_policy conditional_policy \
        output_evidence_policy multifile_grep_policy portable_awk_policy \
        installer_self_test regression
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate installer_hash require_hash "$installer_sha256" "$installer" || return 1
    run_gate template_hash test "$(file_hash "$template")" = "$template_sha256" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate accepted_action20j_outer_hash require_hash \
        "$accepted_action20j_outer_sha256" "$accepted_action20j_outer" || return 1
    run_gate collision_hash require_hash "$collision_sha256" "$collision" || return 1
    run_gate conditional_hash require_hash "$conditional_sha256" "$conditional" || return 1
    run_gate output_evidence_hash require_hash "$output_evidence_sha256" "$output_evidence" || return 1
    run_gate multifile_grep_hash require_hash "$multifile_grep_sha256" "$multifile_grep" || return 1
    run_gate portable_awk_hash require_hash "$portable_awk_sha256" "$portable_awk" || return 1
    run_gate syntax /bin/bash -n "$installer" "$regression" "$0" || return 1
    run_gate shellcheck shellcheck "$installer" "$regression" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check \
        "$installer" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash "$collision" "$installer" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash "$conditional" || return 1
    run_gate output_evidence_policy /bin/bash "$output_evidence" || return 1
    run_gate multifile_grep_policy /bin/bash "$multifile_grep" --check \
        "$installer" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash "$portable_awk" --check \
        "$installer" "$regression" "$0" || return 1
    run_gate installer_self_test /bin/bash "$installer" --self-test || return 1
    run_gate regression /bin/bash "$regression" || return 1
}
safe_stream() {
    local action20k_outer_stream=$1

    [[ "$(wc -c <"$action20k_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20k_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20k_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20k_outer_stream"
}
emit_stream() {
    local action20k_outer_stream_label=$1
    local action20k_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20k_outer_stream_label" \
        "$(wc -c <"$action20k_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20k_outer_stream_label" \
        "$(line_count "$action20k_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20k_outer_stream_label" \
        "$(file_hash "$action20k_outer_stream_path")"
    if safe_stream "$action20k_outer_stream_path"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20k_outer_stream_label"
        if [[ -s "$action20k_outer_stream_path" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20k_outer_stream_label"
            cat "$action20k_outer_stream_path"
            printf '%s_%s_end\n' "$prefix" "$action20k_outer_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action20k_outer_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20k_outer_stream_label" >&2
    return 97
}
validate_remote_transcript() {
    local action20k_outer_node=$1
    local action20k_outer_stdout=$2
    local action20k_outer_stderr=$3
    local action20k_outer_expected_file=$4
    local action20k_outer_actual_file=$5
    local action20k_outer_expected_count
    local action20k_outer_actual_count

    [[ ! -s "$action20k_outer_stderr" ]] || return 1
    /bin/bash "$installer" --expected-checks >"$action20k_outer_expected_file" || return 1
    action20k_outer_expected_count=$(wc -l <"$action20k_outer_expected_file") || return 1
    [[ "$action20k_outer_expected_count" -eq 58 ]] || return 1
    ! grep -Eq '^action_20k_check_[a-z0-9_]+=false$' "$action20k_outer_stdout" || return 1
    sed -n 's/^action_20k_check_\([a-z0-9_]*\)=true$/\1/p' \
        "$action20k_outer_stdout" >"$action20k_outer_actual_file" || return 1
    action20k_outer_actual_count=$(wc -l <"$action20k_outer_actual_file") || return 1
    [[ "$action20k_outer_actual_count" -eq "$action20k_outer_expected_count" ]] || return 1
    [[ "$(LC_ALL=C sort -u "$action20k_outer_actual_file" | wc -l)" -eq "$action20k_outer_expected_count" ]] || return 1
    diff -u "$action20k_outer_expected_file" "$action20k_outer_actual_file" \
        >/dev/null || return 1
    [[ "$(grep -Fxc "action_20k_node=$action20k_outer_node" "$action20k_outer_stdout")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20k_keepalived_reload=false' "$action20k_outer_stdout")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20k_keepalived_restart=false' "$action20k_outer_stdout")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20k_service_mutation=false' "$action20k_outer_stdout")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20k_vrrp_transition=false' "$action20k_outer_stdout")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20k_vip_mutation=false' "$action20k_outer_stdout")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'action_20k_complete=true' "$action20k_outer_stdout")" -eq 1 ]]
}
run_transport() {
    local action20k_outer_node=$1
    local action20k_outer_host
    local action20k_outer_ssh_binary=${CADDY_ACTION20K_SSH_BINARY:-ssh}
    local action20k_outer_work_root
    local action20k_outer_stdout
    local action20k_outer_stderr
    local action20k_outer_expected
    local action20k_outer_actual
    local action20k_outer_status=0
    local action20k_outer_stream_failure=0

    case "$action20k_outer_node" in
        node-a) action20k_outer_host=10.1.0.53 ;;
        node-b) action20k_outer_host=10.1.0.54 ;;
        *) return 64 ;;
    esac
    if [[ "$action20k_outer_ssh_binary" != ssh ]]; then
        [[ "${CADDY_ACTION20K_TEST_MODE:-}" = 1 && -x "$action20k_outer_ssh_binary" ]] || return 64
    fi
    action20k_outer_work_root=$(mktemp -d /tmp/caddy-action20k-outer.XXXXXX) || return 1
    trap 'rm -rf -- "$action20k_outer_work_root"' RETURN
    action20k_outer_stdout=$action20k_outer_work_root/remote.stdout
    action20k_outer_stderr=$action20k_outer_work_root/remote.stderr
    action20k_outer_expected=$action20k_outer_work_root/expected
    action20k_outer_actual=$action20k_outer_work_root/actual
    : >"$action20k_outer_stdout"
    : >"$action20k_outer_stderr"
    chmod 0600 "$action20k_outer_stdout" "$action20k_outer_stderr"
    "$action20k_outer_ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=yes "pi@$action20k_outer_host" \
        "cd / && sudo -n /bin/bash -s -- --node $action20k_outer_node" \
        <"$installer" >"$action20k_outer_stdout" 2>"$action20k_outer_stderr" ||
        action20k_outer_status=$?
    emit_stream remote_stdout "$action20k_outer_stdout" || action20k_outer_stream_failure=1
    emit_stream remote_stderr "$action20k_outer_stderr" || action20k_outer_stream_failure=1
    printf '%s_remote_status=%s\n' "$prefix" "$action20k_outer_status"
    if [[ "$action20k_outer_stream_failure" -ne 0 ]]; then
        trap - RETURN
        printf '%s_protected_evidence=%s\n' "$prefix" "$action20k_outer_work_root" >&2
        return 97
    fi
    [[ "$action20k_outer_status" -eq 0 ]] || return "$action20k_outer_status"
    validate_remote_transcript "$action20k_outer_node" \
        "$action20k_outer_stdout" "$action20k_outer_stderr" \
        "$action20k_outer_expected" "$action20k_outer_actual" || return 97
    printf '%s_node=%s\n' "$prefix" "$action20k_outer_node"
    printf '%s_node_contacted=true\n' "$prefix"
    printf '%s_fragment_mutated=true\n' "$prefix"
    printf '%s_backup_retained=true\n' "$prefix"
    printf '%s_keepalived_reload=false\n' "$prefix"
    printf '%s_keepalived_restart=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_vrrp_transition=false\n' "$prefix"
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
        [[ $# -eq 2 && "${CADDY_ACTION20K_TEST_MODE:-}" = 1 ]] || exit 64
        run_transport "$2"
        ;;
    --node)
        [[ $# -eq 2 ]] || exit 64
        run_local_gates
        run_transport "$2"
        ;;
    *)
        printf 'Usage: %s --expected-local-gates|--self-test|--node node-a|node-b\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
