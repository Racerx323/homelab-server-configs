#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_a_consumer_correction
readonly builder_sha256=25cc3253bfd38721cd962f18214b2c82fc9684b14c28b92a4e1548ab96160021
readonly fixture_sha256=3947d0ce3bc2f953a55fb28ebfa9b4b006a47d3ddf530736bc4f9e35e7792757
readonly fixture_bytes=6000
readonly fixture_lines=104
readonly corrected_inspector_sha256=9bef62fec313eb8565abc148d9f6741c8ef2c4ac80c72e1f68a97ea80100b4cf
readonly corrected_runner_sha256=7abd7f22819a955462deb423764da334e5892a3431b4b9435bcbb50d7c41710c
readonly corrected_regression_sha256=c11af8e8dce950a6ae234bbfbee8a7cf22291c219a24c5cbe055db1fe0fbadb3
readonly executed_outer_sha256=a0ce95eb0fb355b3ef8ee6e167431b746e6c69b00f31d6b315ee7c631ee38e4c
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly builder=$script_directory/build-action20h-a-consumer-correction.sh
readonly fixture=$caddy_root/tests/fixtures/action20h-a-remote-stdout.txt
readonly executed_outer=$script_directory/run-node-a-caddy-health-helper-postinstall-action20h-a-outer.sh
readonly governing_plan=$caddy_root/docs/caddy_plan-v1.1.md

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
source_exact() {
    local action20h_a_consumer_expected_hash=$1
    local action20h_a_consumer_source_path=$2

    [[ -f "$action20h_a_consumer_source_path" &&
        ! -L "$action20h_a_consumer_source_path" ]] || return 1
    [[ "$(file_hash "$action20h_a_consumer_source_path")" = "$action20h_a_consumer_expected_hash" ]] || return 1
}
gate() {
    local action20h_a_consumer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20h_a_consumer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20h_a_consumer_gate_label" >&2
    return 1
}
safe_stream() {
    local action20h_a_consumer_stream_path=$1

    [[ "$(wc -c <"$action20h_a_consumer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20h_a_consumer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' \
        "$action20h_a_consumer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20h_a_consumer_stream_path"
}
emit_stream() {
    local action20h_a_consumer_stream_label=$1
    local action20h_a_consumer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20h_a_consumer_stream_label" \
        "$(wc -c <"$action20h_a_consumer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20h_a_consumer_stream_label" \
        "$(line_count "$action20h_a_consumer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20h_a_consumer_stream_label" \
        "$(file_hash "$action20h_a_consumer_stream_path")"
    if ! safe_stream "$action20h_a_consumer_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$action20h_a_consumer_stream_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' \
        "$prefix" "$action20h_a_consumer_stream_label"
    if [[ -s "$action20h_a_consumer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20h_a_consumer_stream_label"
        cat "$action20h_a_consumer_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action20h_a_consumer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' \
            "$prefix" "$action20h_a_consumer_stream_label"
    fi
}
fixture_exact() {
    [[ ! -L "$fixture" ]] || return 1
    [[ "$(file_hash "$fixture")" = "$fixture_sha256" ]] || return 1
    [[ "$(wc -c <"$fixture")" -eq "$fixture_bytes" ]] || return 1
    [[ "$(line_count "$fixture")" -eq "$fixture_lines" ]] || return 1
}
plan_evidence_exact() {
    grep -Fq \
        'Remote stdout was 6000 bytes/104 lines/SHA-256 `3947d0ce...2757`' \
        "$governing_plan" || return 1
    grep -Fq \
        '45-byte/SHA-256 `47a637e4...8b76`' "$governing_plan" || return 1
}
generated_sources_exact() {
    local action20h_a_consumer_generated_root=$1

    source_exact "$corrected_inspector_sha256" \
        "$action20h_a_consumer_generated_root/scripts/inspect-node-a-caddy-health-helper-postinstall-action20h-a.sh" || return 1
    source_exact "$corrected_runner_sha256" \
        "$action20h_a_consumer_generated_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a-consumer-corrected.sh" || return 1
    source_exact "$corrected_regression_sha256" \
        "$action20h_a_consumer_generated_root/tests/action20h-a-consumer-correction-regression.sh" || return 1
}
run_static_gates() {
    gate working_directory working_directory_approved || return 1
    gate builder_source source_exact "$builder_sha256" "$builder" || return 1
    gate fixture_source source_exact "$fixture_sha256" "$fixture" || return 1
    gate fixture_contract fixture_exact || return 1
    gate executed_outer_source source_exact \
        "$executed_outer_sha256" "$executed_outer" || return 1
    gate governing_plan_evidence plan_evidence_exact || return 1
    gate syntax /bin/bash -n "$builder" "$0" || return 1
    gate shellcheck shellcheck "$builder" "$0" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$builder" "$0" || return 1
    gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$builder" "$0" || return 1
    gate multifile_count_policy /bin/bash \
        "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$builder" "$0" || return 1
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        printf '%s\n' \
            working_directory builder_source fixture_source fixture_contract \
            executed_outer_source governing_plan_evidence syntax shellcheck \
            canonical_format collision_policy multifile_count_policy \
            builder_status generated_sources regression_status \
            transcript_consumer_status
        exit 0
        ;;
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        readonly action20h_a_consumer_mode=${1#--}
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        readonly action20h_a_consumer_mode=execute
        ;;
    *)
        printf 'Usage: %s [--expected-local-gates|--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

run_static_gates
work_root=$(mktemp -d /tmp/caddy-action20h-a-consumer.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
readonly generated_root=$work_root/generated

run_captured() {
    local action20h_a_consumer_capture_label=$1
    shift
    local action20h_a_consumer_capture_stdout=$work_root/${action20h_a_consumer_capture_label}.stdout
    local action20h_a_consumer_capture_stderr=$work_root/${action20h_a_consumer_capture_label}.stderr
    local action20h_a_consumer_capture_status=0

    install -m 0600 /dev/null \
        "$action20h_a_consumer_capture_stdout" || return 1
    install -m 0600 /dev/null \
        "$action20h_a_consumer_capture_stderr" || return 1
    "$@" >"$action20h_a_consumer_capture_stdout" \
        2>"$action20h_a_consumer_capture_stderr" ||
        action20h_a_consumer_capture_status=$?
    emit_stream "${action20h_a_consumer_capture_label}_stdout" \
        "$action20h_a_consumer_capture_stdout" || return 97
    emit_stream "${action20h_a_consumer_capture_label}_stderr" \
        "$action20h_a_consumer_capture_stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" \
        "$action20h_a_consumer_capture_label" \
        "$action20h_a_consumer_capture_status"
    [[ "$action20h_a_consumer_capture_status" -eq 0 ]]
}

if run_captured builder /bin/bash "$builder" --output "$generated_root"; then
    gate builder_status true || exit 1
else
    gate builder_status false || true
    exit 1
fi
gate generated_sources generated_sources_exact "$generated_root" || exit 1
if run_captured regression /bin/bash \
    "$generated_root/tests/action20h-a-consumer-correction-regression.sh"; then
    gate regression_status true || exit 1
else
    gate regression_status false || true
    exit 1
fi
if run_captured transcript_consumer /bin/bash \
    "$generated_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a-consumer-corrected.sh" \
    --validate-transcript "$fixture" /dev/null 0; then
    gate transcript_consumer_status true || exit 1
else
    gate transcript_consumer_status false || true
    exit 1
fi

printf '%s_mode=%s\n' "$prefix" "$action20h_a_consumer_mode"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_ssh_invoked=false\n' "$prefix"
printf '%s_node_diagnostic=false\n' "$prefix"
printf '%s_repair=false\n' "$prefix"
printf '%s_transactional_retry=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_action20h_acceptance_evidence_valid=true\n' "$prefix"
printf '%s_cleanup_complete=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
