#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20j_outer
readonly builder_sha256=79ec3c5318f378dae1438a005e6ac1da32cf4cbe0b12c113ebbd50b1566861b6
readonly regression_sha256=2957a5660d100564abe068feabf1ef93bc596feab784e99856d353a36bc350ca
readonly accepted_action20i_a_correction_sha256=7d48e4f7ab1b0de37d78ae36c8d8e4724643229cdefa209f1da12e5624cbd772
readonly generated_transaction_sha256=1a50687b74ef627c8ebacce6ffddb0ee50df37b8d5ddeb88d6d2a713868ac157
readonly generated_runner_sha256=c0c51fa9403e0c6871f22e2abbb8f0d1652464f502daeee7cd5a59f6485affb0
readonly accepted_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=65536

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly builder=$script_directory/build-node-b-caddy-vrrp-activation-action20j.sh
readonly regression=$caddy_root/tests/action20j-node-b-vrrp-activation-regression.sh
readonly accepted_action20i_a_correction=$script_directory/run-action20i-a-retry-transcript-consumer-correction.sh
readonly accepted_manifest=$caddy_root/manifests/accepted-live-artifacts.tsv
readonly governing_plan=$caddy_root/docs/caddy_plan-v1.1.md

retain_work_root=false
work_root=
capture_status=0

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
    local action20j_outer_expected_hash=$1
    local action20j_outer_source_path=$2

    [[ -f "$action20j_outer_source_path" &&
        ! -L "$action20j_outer_source_path" ]] || return 1
    [[ "$(stat -c '%a' "$action20j_outer_source_path")" = 755 ]] || return 1
    [[ "$(file_hash "$action20j_outer_source_path")" = "$action20j_outer_expected_hash" ]] || return 1
}
gate() {
    local action20j_outer_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20j_outer_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20j_outer_gate_label" >&2
    return 1
}
safe_stream() {
    local action20j_outer_stream_path=$1

    [[ "$(wc -c <"$action20j_outer_stream_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20j_outer_stream_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' \
        "$action20j_outer_stream_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20j_outer_stream_path"
}
emit_stream() {
    local action20j_outer_stream_label=$1
    local action20j_outer_stream_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20j_outer_stream_label" \
        "$(wc -c <"$action20j_outer_stream_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20j_outer_stream_label" \
        "$(line_count "$action20j_outer_stream_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20j_outer_stream_label" \
        "$(file_hash "$action20j_outer_stream_path")"
    if ! safe_stream "$action20j_outer_stream_path"; then
        printf '%s_%s_classification=unsafe_retained\n' \
            "$prefix" "$action20j_outer_stream_label" >&2
        retain_work_root=true
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' \
        "$prefix" "$action20j_outer_stream_label"
    if [[ -s "$action20j_outer_stream_path" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action20j_outer_stream_label"
        cat "$action20j_outer_stream_path"
        printf '%s_%s_end\n' "$prefix" "$action20j_outer_stream_label"
    else
        printf '%s_%s_content_secured=empty\n' \
            "$prefix" "$action20j_outer_stream_label"
    fi
}
run_capture() {
    local action20j_outer_capture_label=$1
    local action20j_outer_capture_stdout=$work_root/$action20j_outer_capture_label.stdout
    local action20j_outer_capture_stderr=$work_root/$action20j_outer_capture_label.stderr

    shift
    install -m 0600 /dev/null "$action20j_outer_capture_stdout"
    install -m 0600 /dev/null "$action20j_outer_capture_stderr"
    capture_status=0
    "$@" >"$action20j_outer_capture_stdout" \
        2>"$action20j_outer_capture_stderr" || capture_status=$?
    emit_stream "${action20j_outer_capture_label}_stdout" \
        "$action20j_outer_capture_stdout" || return 97
    emit_stream "${action20j_outer_capture_label}_stderr" \
        "$action20j_outer_capture_stderr" || return 97
    printf '%s_%s_status=%s\n' "$prefix" \
        "$action20j_outer_capture_label" "$capture_status"
}
accepted_state_exact() {
    awk -F '\t' -v expected="$accepted_health_sha256" '
        $1 == "node_b_health_helper" {
            count++
            valid = ($2 == expected && $3 == "20i")
        }
        END { exit !(count == 1 && valid) }
    ' "$accepted_manifest" || return 1
}
governing_acceptance_exact() {
    grep -Fq \
        'Action 20i and independent Action 20i-a are accepted.' \
        "$governing_plan" || return 1
    grep -Fq \
        'Node B activation remains unauthorized. The next gate is definition only of the transactional Node B Caddy VRRP activation action' \
        "$governing_plan" || return 1
}
generated_sources_exact() {
    local action20j_outer_generated_root=$1

    source_exact "$generated_transaction_sha256" \
        "$action20j_outer_generated_root/scripts/activate-node-b-caddy-vrrp-action20j.sh" || return 1
    source_exact "$generated_runner_sha256" \
        "$action20j_outer_generated_root/scripts/run-node-b-caddy-vrrp-activation-action20j.sh" || return 1
}
cleanup() {
    if [[ "$retain_work_root" = true ]]; then
        printf '%s_protected_evidence=%s\n' "$prefix" "$work_root" >&2
    elif [[ -n "$work_root" && -d "$work_root" ]]; then
        rm -rf -- "$work_root"
    fi
}

case "${1:-}" in
    --self-test | --source-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        readonly action20j_outer_mode=${1#--}
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        readonly action20j_outer_mode=execute
        ;;
    *)
        printf 'Usage: %s [--self-test|--source-test|--contract-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

gate working_directory working_directory_approved
gate builder_source source_exact "$builder_sha256" "$builder"
gate regression_source source_exact "$regression_sha256" "$regression"
gate accepted_action20i_a_correction source_exact \
    "$accepted_action20i_a_correction_sha256" \
    "$accepted_action20i_a_correction"
gate accepted_state accepted_state_exact
gate governing_acceptance governing_acceptance_exact
gate syntax /bin/bash -n "$builder" "$regression" "$0"
gate shellcheck shellcheck "$builder" "$regression" "$0"
gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
    "$builder" "$regression" "$0"
gate collision_policy /bin/bash \
    "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$regression" "$0"
gate conditional_policy /bin/bash \
    "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh"
gate multifile_grep_policy /bin/bash \
    "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
    "$builder" "$regression" "$0"
gate portable_awk_policy /bin/bash \
    "$caddy_root/tests/portable-awk-policy-regression.sh"
gate output_evidence_policy /bin/bash \
    "$caddy_root/tests/transaction-output-evidence-policy-regression.sh"

work_root=$(mktemp -d /tmp/caddy-action20j-outer.XXXXXX)
readonly work_root
trap cleanup EXIT INT TERM
readonly generated_root=$work_root/generated
run_capture builder /bin/bash "$builder" --output "$generated_root"
[[ "$capture_status" -eq 0 ]] || exit "$capture_status"
gate builder_status true
gate generated_sources generated_sources_exact "$generated_root"
run_capture regression /bin/bash "$regression"
[[ "$capture_status" -eq 0 ]] || exit "$capture_status"
gate regression_status true

if [[ "$action20j_outer_mode" != execute ]]; then
    printf '%s_mode=%s\n' "$prefix" "$action20j_outer_mode"
    printf '%s_node_a_contacted=false\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_keepalived_reload=false\n' "$prefix"
    printf '%s_vrrp_transition=false\n' "$prefix"
    printf '%s_vip_assignment=false\n' "$prefix"
    printf '%s_persistent_mutations=false\n' "$prefix"
    printf '%s_action_executed=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
    exit 0
fi

run_capture activation /bin/bash \
    "$generated_root/scripts/run-node-b-caddy-vrrp-activation-action20j.sh"
[[ "$capture_status" -eq 0 ]] || exit "$capture_status"
gate activation_status true
printf '%s_mode=execute\n' "$prefix"
printf '%s_node_a_contacted=true\n' "$prefix"
printf '%s_node_b_contacted=true\n' "$prefix"
printf '%s_node_a_persistent_mutations=false\n' "$prefix"
printf '%s_node_b_keepalived_reload=true\n' "$prefix"
printf '%s_node_b_expected_state=BACKUP\n' "$prefix"
printf '%s_node_b_expected_caddy_vips=0\n' "$prefix"
printf '%s_node_a_expected_state=MASTER\n' "$prefix"
printf '%s_node_a_expected_caddy_vips=2\n' "$prefix"
printf '%s_activation_accepted=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
