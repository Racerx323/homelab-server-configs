#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_a_retry_outer
readonly builder_sha256=b23a75e6bd1b17803f79d2824065c58c7ed7f1b350593d50f6c86469e69929c3
readonly regression_sha256=fb2a038d52e3889018c8887d584a6c77ce3444ec2dbefec974c0186f7d79da1a
readonly corrected_probe_sha256=aa86451cea27a257ff9b14ca10e774a6189e4859df3fcf9bb1449f889bff54e2
readonly corrected_runner_sha256=5c7d5b9c3732371b6b3e0b5422b7e1772f723887103f168d827fe1c95cac50a8
readonly historical_probe_sha256=564380f2753950716612518fbbedbd43c7461d33e0695b0d3c2162b70f30fb84
readonly historical_runner_sha256=f9006403f30644b58a96474979aa8c88083ca14ad79ba97e77c4185e5de7e978
readonly accepted_provenance_outer_sha256=1d65abce9e15efaa2052b954dcf1a9029c1d75deb687f2cd33d51d22b675e0fa
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly output_evidence_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly builder=$script_directory/build-dual-node-caddy-postactivation-action20d-retry10-a-retry.sh
readonly regression=$caddy_root/tests/action20d-retry10-a-retry-postactivation-regression.sh
readonly historical_probe=$script_directory/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly historical_runner=$script_directory/run-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly accepted_provenance_outer=$script_directory/run-node-b-caddy-environment-provenance-action20d-retry10-b-outer.sh
readonly collision=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly output_evidence=$caddy_root/tests/transaction-output-evidence-policy-regression.sh

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
    local expected_source_hash=$1
    local inspected_source_path=$2

    [[ -f "$inspected_source_path" && ! -L "$inspected_source_path" &&
        -x "$inspected_source_path" ]] || return 1
    [[ "$(file_hash "$inspected_source_path")" = "$expected_source_hash" ]]
}
run_gate() {
    local gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory builder_hash regression_hash historical_probe_hash \
        historical_runner_hash accepted_provenance_outer_hash collision_hash \
        conditional_hash output_evidence_hash syntax collision_policy \
        conditional_policy output_evidence_policy builder_self_test \
        builder_contract_test regression
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate builder_hash require_hash "$builder_sha256" "$builder" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate historical_probe_hash require_hash \
        "$historical_probe_sha256" "$historical_probe" || return 1
    run_gate historical_runner_hash require_hash \
        "$historical_runner_sha256" "$historical_runner" || return 1
    run_gate accepted_provenance_outer_hash require_hash \
        "$accepted_provenance_outer_sha256" "$accepted_provenance_outer" || return 1
    run_gate collision_hash require_hash "$collision_sha256" "$collision" || return 1
    run_gate conditional_hash require_hash "$conditional_sha256" "$conditional" || return 1
    run_gate output_evidence_hash require_hash \
        "$output_evidence_sha256" "$output_evidence" || return 1
    run_gate syntax /bin/bash -n "$builder" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash "$collision" "$builder" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash "$conditional" || return 1
    run_gate output_evidence_policy /bin/bash "$output_evidence" || return 1
    run_gate builder_self_test /bin/bash "$builder" --self-test || return 1
    run_gate builder_contract_test /bin/bash "$builder" --contract-test || return 1
    run_gate regression /bin/bash "$regression" || return 1
}
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
work_root=$(mktemp -d /tmp/caddy-action20d-retry10-a-retry-outer.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT
readonly candidate_root=$work_root/candidate
readonly builder_stdout=$work_root/builder.stdout
readonly builder_stderr=$work_root/builder.stderr
readonly runner_stdout=$work_root/runner.stdout
readonly runner_stderr=$work_root/runner.stderr
install -d -m 0700 "$candidate_root"
for capture_path in "$builder_stdout" "$builder_stderr" "$runner_stdout" "$runner_stderr"; do
    : >"$capture_path"
    chmod 0600 "$capture_path"
done

builder_status=0
/bin/bash "$builder" --output "$candidate_root" \
    >"$builder_stdout" 2>"$builder_stderr" || builder_status=$?
readonly builder_status
readonly corrected_probe=$candidate_root/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly corrected_runner=$candidate_root/run-dual-node-caddy-postactivation-action20d-retry10-a.sh
candidate_status=0
if [[ "$builder_status" -eq 0 &&
    "$(file_hash "$corrected_probe")" = "$corrected_probe_sha256" &&
    "$(file_hash "$corrected_runner")" = "$corrected_runner_sha256" ]]; then
    /bin/bash "$corrected_runner" >"$runner_stdout" 2>"$runner_stderr" || candidate_status=$?
else
    candidate_status=98
fi
readonly candidate_status

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
printf '%s_candidate_status=%s\n' "$prefix" "$candidate_status"
printf '%s_corrected_probe_sha256=%s\n' "$prefix" \
    "$(file_hash "$corrected_probe" 2>/dev/null || printf unavailable)"
printf '%s_corrected_runner_sha256=%s\n' "$prefix" \
    "$(file_hash "$corrected_runner" 2>/dev/null || printf unavailable)"
if [[ "$builder_status" -eq 0 && "$candidate_status" -eq 0 ]] &&
    [[ "$(grep -Fxc 'action_20d_retry10_a_retry_acceptance_complete=true' \
        "$runner_stdout")" -eq 1 ]]; then
    printf '%s_acceptance_accepted=true\n' "$prefix"
else
    printf '%s_acceptance_accepted=false\n' "$prefix" >&2
fi
rm -rf -- "$work_root"
trap - EXIT
printf '%s_boundary_cleanup_complete=true\n' "$prefix"
[[ "$builder_status" -eq 0 && "$candidate_status" -eq 0 ]]
