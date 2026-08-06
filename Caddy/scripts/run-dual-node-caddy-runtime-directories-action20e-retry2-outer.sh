#!/usr/bin/env bash

# Functions passed through the independently labeled gate dispatcher are reachable.
# shellcheck disable=SC2317

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20e_retry2
readonly config_sha256=9d36d8b3e6a872bed9a435f569b543db8517e6ee79c2aa089583b8ca3dac6bc2
readonly installer_sha256=fa28511aab6380796f7b8a25975f9cc917429c1bef83a696464e26816141f5f8
readonly runner_sha256=358a0e21cc5a5814db48baf2163bd9efd38da9ad56a94c7135d66fd1e08cb3c3
readonly regression_sha256=25c5eb3f61dcabcef3f7042a4ace45e31a49c6cb8d67149e445bcc497112d335
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly transcript_sha256=99e0040d785e70a4f2e8d1796f8c6bf29675593d1ae5d13e54d9ac2dceebe44c
readonly output_evidence_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly config=$caddy_root/configs/tmpfiles.d/caddy-ha.conf
readonly installer=$script_directory/install-caddy-runtime-directories-action20e-retry2.sh
readonly runner=$script_directory/run-dual-node-caddy-runtime-directories-action20e-retry2.sh
readonly regression=$caddy_root/tests/action20e-retry2-runtime-directories-regression.sh
readonly collision=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly transcript=$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh
readonly output_evidence=$caddy_root/tests/transaction-output-evidence-policy-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs) [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] ;;
        *) return 1 ;;
    esac
}
require_hash() {
    local expected_hash=$1
    local source_path=$2

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ "$(file_hash "$source_path")" = "$expected_hash" ]]
}
run_gate() {
    local gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_outer_gate_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_outer_gate_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}
run_local_gates() {
    run_gate working_directory working_directory_approved || return 1
    run_gate config_hash require_hash "$config_sha256" "$config" || return 1
    run_gate installer_hash require_hash "$installer_sha256" "$installer" || return 1
    run_gate runner_hash require_hash "$runner_sha256" "$runner" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate collision_hash require_hash "$collision_sha256" "$collision" || return 1
    run_gate conditional_hash require_hash "$conditional_sha256" "$conditional" || return 1
    run_gate transcript_hash require_hash "$transcript_sha256" "$transcript" || return 1
    run_gate output_evidence_hash require_hash "$output_evidence_sha256" "$output_evidence" || return 1
    run_gate syntax /bin/bash -n "$installer" "$runner" "$regression" || return 1
    run_gate collision_policy /bin/bash "$collision" "$installer" "$runner" "$regression" || return 1
    run_gate conditional_policy /bin/bash "$conditional" || return 1
    run_gate transcript_policy /bin/bash "$transcript" || return 1
    run_gate output_evidence_policy /bin/bash "$output_evidence" || return 1
    run_gate regression /bin/bash "$regression" || return 1
    run_gate runner_self_test /bin/bash "$runner" --self-test || return 1
}
safe_stream() {
    local inspected_path=$1

    [[ "$(wc -c <"$inspected_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_path" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' "$inspected_path"
}
emit_stream() {
    local emitted_label=$1
    local emitted_path=$2

    printf '%s_outer_%s_bytes=%s\n' "$prefix" "$emitted_label" "$(wc -c <"$emitted_path")"
    printf '%s_outer_%s_lines=%s\n' "$prefix" "$emitted_label" "$(line_count "$emitted_path")"
    printf '%s_outer_%s_sha256=%s\n' "$prefix" "$emitted_label" "$(file_hash "$emitted_path")"
    if [[ -s "$emitted_path" ]]; then
        printf '%s_outer_%s_begin\n' "$prefix" "$emitted_label"
        cat "$emitted_path"
        printf '%s_outer_%s_end\n' "$prefix" "$emitted_label"
    else
        printf '%s_outer_%s_content_secured=empty\n' "$prefix" "$emitted_label"
    fi
}

case "${1:-}" in
    --expected-local-gates)
        printf '%s\n' working_directory config_hash installer_hash runner_hash regression_hash \
            collision_hash conditional_hash transcript_hash output_evidence_hash syntax \
            collision_policy conditional_policy transcript_policy output_evidence_policy \
            regression runner_self_test
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        run_local_gates
        printf '%s_outer_%s_complete=true\n' "$prefix" "${1#--}"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *) exit 64 ;;
esac

run_local_gates
capture_root=$(mktemp -d /tmp/caddy-action20e-retry2-outer.XXXXXX)
readonly capture_root
retain_evidence=false
cleanup() {
    # shellcheck disable=SC2317
    if [[ "$retain_evidence" = true ]]; then
        printf '%s_outer_protected_evidence=%s\n' "$prefix" "$capture_root" >&2
    else
        rm -rf -- "$capture_root"
    fi
}
trap cleanup EXIT
readonly runner_stdout=$capture_root/runner.stdout
readonly runner_stderr=$capture_root/runner.stderr
touch "$runner_stdout" "$runner_stderr"
chmod 0600 "$runner_stdout" "$runner_stderr"
runner_status=0
/bin/bash "$runner" >"$runner_stdout" 2>"$runner_stderr" || runner_status=$?
readonly runner_status
if ! safe_stream "$runner_stdout" || ! safe_stream "$runner_stderr"; then
    retain_evidence=true
    printf '%s_outer_stream_classification=unsafe_retained\n' "$prefix" >&2
    exit 97
fi
printf '%s_outer_stream_classification=bounded_safe\n' "$prefix"
emit_stream runner_stdout "$runner_stdout"
emit_stream runner_stderr "$runner_stderr"
printf '%s_outer_runner_status=%s\n' "$prefix" "$runner_status"
rm -rf -- "$capture_root"
trap - EXIT
printf '%s_outer_cleanup_complete=true\n' "$prefix"
exit "$runner_status"
