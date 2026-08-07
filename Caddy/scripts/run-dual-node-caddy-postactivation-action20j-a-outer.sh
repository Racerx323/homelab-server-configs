#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20j_a_outer
readonly builder_sha256=1b488289ee70698b20d05e2eec177b0c2af50b1d1e02e40c9f832d7f3c76a4e0
readonly regression_sha256=5992607f5416988ec4bd9309e6753ffd2c11e760943a2a44a932e45d72fae9a1
readonly generated_probe_sha256=6bd6184f1dc45742eba93845a7b6f3b9025c92a7897fc5078ccbfa9bdac27263
readonly generated_runner_sha256=bd1310ca45b5787c25cc902e7f62474c3b982d0d6fe6fbbf7cadfe570633ac66
readonly accepted_action20j_outer_sha256=50d302239c5675784e100bff358355651d30bdd96f8d02094c565f6403186ae7
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly output_evidence_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly multifile_grep_sha256=0c8d5453e906964143311bcec93c9c755b0fccd84bcbdf9f8bda7c367ed38655
readonly portable_awk_sha256=30e6be4f4737b9df3c9669572252ee8bff7ae949387a7f96ebe62a2e384fc755
readonly accepted_live_hash_sha256=ddd0bac4ed05db2b8a082c3df21e5e1b8a439ad5c7d60e74b09ee0aa99629174
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=65536

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly builder=$script_directory/build-dual-node-caddy-postactivation-action20j-a.sh
readonly regression=$caddy_root/tests/action20j-a-postactivation-regression.sh
readonly accepted_action20j_outer=$script_directory/run-node-b-caddy-vrrp-activation-action20j-outer.sh
readonly collision=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$caddy_root/tests/transaction-output-evidence-policy-regression.sh
readonly multifile_grep=$caddy_root/tests/multifile-grep-count-policy.sh
readonly portable_awk=$caddy_root/tests/portable-awk-policy.sh
readonly accepted_live_hash=$caddy_root/tests/accepted-live-hash-policy.sh
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
    local action20j_a_outer_expected_hash=$1
    local action20j_a_outer_path=$2

    [[ -f "$action20j_a_outer_path" && ! -L "$action20j_a_outer_path" &&
        -x "$action20j_a_outer_path" ]] || return 1
    [[ "$(file_hash "$action20j_a_outer_path")" = "$action20j_a_outer_expected_hash" ]]
}
run_gate() {
    local action20j_a_outer_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20j_a_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20j_a_outer_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory builder_hash regression_hash accepted_action20j_outer_hash \
        collision_hash conditional_hash output_evidence_hash multifile_grep_hash \
        portable_awk_hash accepted_live_hash syntax shellcheck canonical_format \
        collision_policy conditional_policy output_evidence_policy \
        multifile_grep_policy portable_awk_policy accepted_live_hash_policy \
        builder_self_test builder_contract_test regression
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate builder_hash require_hash "$builder_sha256" "$builder" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate accepted_action20j_outer_hash require_hash \
        "$accepted_action20j_outer_sha256" "$accepted_action20j_outer" || return 1
    run_gate collision_hash require_hash "$collision_sha256" "$collision" || return 1
    run_gate conditional_hash require_hash "$conditional_sha256" "$conditional" || return 1
    run_gate output_evidence_hash require_hash "$output_evidence_sha256" "$output_evidence" || return 1
    run_gate multifile_grep_hash require_hash "$multifile_grep_sha256" "$multifile_grep" || return 1
    run_gate portable_awk_hash require_hash "$portable_awk_sha256" "$portable_awk" || return 1
    run_gate accepted_live_hash require_hash "$accepted_live_hash_sha256" "$accepted_live_hash" || return 1
    run_gate syntax /bin/bash -n "$builder" "$regression" "$0" || return 1
    run_gate shellcheck shellcheck "$builder" "$regression" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check \
        "$builder" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash "$collision" "$builder" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash "$conditional" || return 1
    run_gate output_evidence_policy /bin/bash "$output_evidence" || return 1
    run_gate multifile_grep_policy /bin/bash "$multifile_grep" --check \
        "$builder" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash "$portable_awk" --check \
        "$builder" "$regression" "$0" || return 1
    run_gate accepted_live_hash_policy /bin/bash "$accepted_live_hash" --check || return 1
    run_gate builder_self_test /bin/bash "$builder" --self-test || return 1
    run_gate builder_contract_test /bin/bash "$builder" --contract-test || return 1
    run_gate regression /bin/bash "$regression" || return 1
}
safe_stream() {
    local action20j_a_outer_stream=$1

    [[ "$(wc -c <"$action20j_a_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20j_a_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20j_a_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20j_a_outer_stream"
}
emit_stream() {
    local action20j_a_outer_stream_label=$1
    local action20j_a_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20j_a_outer_stream_label" \
        "$(wc -c <"$action20j_a_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20j_a_outer_stream_label" \
        "$(line_count "$action20j_a_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20j_a_outer_stream_label" \
        "$(file_hash "$action20j_a_outer_stream_path")"
    if safe_stream "$action20j_a_outer_stream_path"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20j_a_outer_stream_label"
        if [[ -s "$action20j_a_outer_stream_path" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20j_a_outer_stream_label"
            cat "$action20j_a_outer_stream_path"
            printf '%s_%s_end\n' "$prefix" "$action20j_a_outer_stream_label"
        else
            printf '%s_%s_content_secured=empty\n' "$prefix" "$action20j_a_outer_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20j_a_outer_stream_label" >&2
    return 97
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_local_gates
work_root=$(mktemp -d /tmp/caddy-action20j-a-outer.XXXXXX)
readonly work_root
trap 'rm -rf -- "$work_root"' EXIT INT TERM
readonly generated_root=$work_root/generated
readonly builder_stdout=$work_root/builder.stdout
readonly builder_stderr=$work_root/builder.stderr
readonly runner_stdout=$work_root/runner.stdout
readonly runner_stderr=$work_root/runner.stderr
install -d -m 0700 "$generated_root"
for capture_path in "$builder_stdout" "$builder_stderr" "$runner_stdout" "$runner_stderr"; do
    : >"$capture_path"
    chmod 0600 "$capture_path"
done

builder_status=0
/bin/bash "$builder" --output "$generated_root" \
    >"$builder_stdout" 2>"$builder_stderr" || builder_status=$?
readonly builder_status
readonly generated_probe=$generated_root/inspect-dual-node-caddy-postactivation-action20j-a.sh
readonly generated_runner=$generated_root/run-dual-node-caddy-postactivation-action20j-a.sh
runner_status=0
if [[ "$builder_status" -eq 0 &&
    "$(file_hash "$generated_probe")" = "$generated_probe_sha256" &&
    "$(file_hash "$generated_runner")" = "$generated_runner_sha256" ]]; then
    /bin/bash "$generated_runner" >"$runner_stdout" 2>"$runner_stderr" || runner_status=$?
else
    runner_status=98
fi
readonly runner_status

stream_failure=0
emit_stream builder_stdout "$builder_stdout" || stream_failure=1
emit_stream builder_stderr "$builder_stderr" || stream_failure=1
emit_stream runner_stdout "$runner_stdout" || stream_failure=1
emit_stream runner_stderr "$runner_stderr" || stream_failure=1
if [[ "$stream_failure" -ne 0 ]]; then
    trap - EXIT
    printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    exit 97
fi
printf '%s_builder_status=%s\n' "$prefix" "$builder_status"
printf '%s_runner_status=%s\n' "$prefix" "$runner_status"
printf '%s_generated_probe_sha256=%s\n' "$prefix" \
    "$(file_hash "$generated_probe" 2>/dev/null || printf unavailable)"
printf '%s_generated_runner_sha256=%s\n' "$prefix" \
    "$(file_hash "$generated_runner" 2>/dev/null || printf unavailable)"
if [[ "$builder_status" -eq 0 && "$runner_status" -eq 0 ]] &&
    [[ "$(grep -Fxc 'action_20j_a_acceptance_complete=true' "$runner_stdout")" -eq 1 ]]; then
    printf '%s_acceptance_accepted=true\n' "$prefix"
else
    printf '%s_acceptance_accepted=false\n' "$prefix" >&2
fi
rm -rf -- "$work_root"
trap - EXIT
printf '%s_node_a_contacted=true\n' "$prefix"
printf '%s_node_b_contacted=true\n' "$prefix"
printf '%s_health_helpers_read_only_invoked=true\n' "$prefix"
printf '%s_notification_helpers_invoked=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_network_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_boundary_cleanup_complete=true\n' "$prefix"
[[ "$builder_status" -eq 0 && "$runner_status" -eq 0 ]]
