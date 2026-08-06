#!/usr/bin/env bash

# Functions passed through independently labeled dispatchers are reachable.
# shellcheck disable=SC2317

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_c_retry
readonly prior_prefix=action_20d_c
readonly probe_prefix=action_20d_c_probe
readonly prior_probe_sha256=defff2a76889c084b9903c2012b3fe16fdb8dd581882e4acb7dd62d6f625524d
readonly prior_runner_sha256=a492843c8439339a95cc996c437a2dfc7ce7710057940cf82b7dcde25ffad77c
readonly prior_outer_sha256=db6d6296a4fedc987a2ab2b7a02a01cf11e484c4308262e20ff32617689d7595
readonly accepted_runtime_acceptance_sha256=b0f478e67477195c9b5127c1f465ae0bfc588c582853cf693ca0352fef33b21d
readonly regression_sha256=f895cdda5f3e9528d6ef4643c13b8c62fff2049bc7198cd95c9b7f665a55002b
readonly collision_sha256=ba1e769a3d00b5884421a8860f820e2dc8a3d8074837dab930630407f047886f
readonly conditional_sha256=68cd687916f9d8be78f50af7a410d376f457ca74ab906a8e459795de6c495455
readonly transcript_sha256=99e0040d785e70a4f2e8d1796f8c6bf29675593d1ae5d13e54d9ac2dceebe44c
readonly output_evidence_sha256=84873a1ad3ee1745fe445f179f6a002c2ccee5b147b93cc3db0d6f17d54d4441
readonly expected_probe_count=44
readonly expected_runner_count=27
readonly expected_state_metadata=pi:caddy-sync:750
readonly expected_dedupe_metadata=pi:pi:700
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=16384

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly prior_probe=$script_directory/inspect-caddy-notifier-context-action20d-c.sh
readonly prior_runner=$script_directory/run-dual-node-caddy-notifier-context-action20d-c.sh
readonly prior_outer=$script_directory/run-dual-node-caddy-notifier-context-action20d-c-outer.sh
readonly accepted_runtime_acceptance=$script_directory/run-dual-node-caddy-runtime-postinstall-action20e-retry2-a-outer.sh
readonly regression=$caddy_root/tests/action20d-c-retry-notifier-context-regression.sh
readonly collision=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh
readonly conditional=$caddy_root/tests/conditional-validator-errexit-policy-regression.sh
readonly transcript=$caddy_root/tests/transcript-contract-ratchet-policy-regression.sh
readonly output_evidence=$caddy_root/tests/transaction-output-evidence-policy-regression.sh

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
    run_gate prior_probe_hash require_hash "$prior_probe_sha256" "$prior_probe" || return 1
    run_gate prior_runner_hash require_hash "$prior_runner_sha256" "$prior_runner" || return 1
    run_gate prior_outer_hash require_hash "$prior_outer_sha256" "$prior_outer" || return 1
    run_gate accepted_runtime_acceptance_hash require_hash "$accepted_runtime_acceptance_sha256" "$accepted_runtime_acceptance" || return 1
    run_gate regression_hash require_hash "$regression_sha256" "$regression" || return 1
    run_gate collision_hash require_hash "$collision_sha256" "$collision" || return 1
    run_gate conditional_hash require_hash "$conditional_sha256" "$conditional" || return 1
    run_gate transcript_hash require_hash "$transcript_sha256" "$transcript" || return 1
    run_gate output_evidence_hash require_hash "$output_evidence_sha256" "$output_evidence" || return 1
    run_gate syntax /bin/bash -n "$prior_probe" "$prior_runner" "$prior_outer" "$regression" || return 1
    run_gate collision_policy /bin/bash "$collision" "$prior_probe" "$prior_runner" "$prior_outer" "$regression" || return 1
    run_gate conditional_policy /bin/bash "$conditional" || return 1
    run_gate transcript_policy /bin/bash "$transcript" || return 1
    run_gate output_evidence_policy /bin/bash "$output_evidence" || return 1
    run_gate regression /bin/bash "$regression" || return 1
    run_gate prior_probe_self_test /bin/bash "$prior_probe" --self-test || return 1
    run_gate prior_runner_self_test /bin/bash "$prior_runner" --self-test || return 1
    run_gate prior_outer_self_test /bin/bash "$prior_outer" --self-test || return 1
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

    printf '%s_outer_%s_bytes=%s\n' "$prefix" "$emitted_label" "$(wc -c <"$emitted_path")"
    printf '%s_outer_%s_lines=%s\n' "$prefix" "$emitted_label" "$(line_count "$emitted_path")"
    printf '%s_outer_%s_sha256=%s\n' "$prefix" "$emitted_label" "$(file_hash "$emitted_path")"
    if [[ ! -s "$emitted_path" ]]; then
        printf '%s_outer_%s_content_secured=empty\n' "$prefix" "$emitted_label"
        return 0
    fi
    printf '%s_outer_%s_begin\n' "$prefix" "$emitted_label"
    cat "$emitted_path"
    printf '%s_outer_%s_end\n' "$prefix" "$emitted_label"
}
line_count_exact() {
    local expected_line=$1
    local inspected_path=$2
    local expected_count=$3

    [[ "$(grep -Fxc "$expected_line" "$inspected_path" || true)" -eq "$expected_count" ]]
}
no_false_assertions() {
    local inspected_path=$1

    [[ "$(grep -Ec "^(${probe_prefix}|${prior_prefix})_assertion_[a-z0-9_]+=false$" "$inspected_path" || true)" -eq 0 ]]
}
run_validation_assertion() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$assertion_label" >&2
    return 1
}
validate_readiness_transcript() {
    local inspected_path=$1
    local status_value=$2
    local expected_label
    local validation_failures=0

    run_validation_assertion prior_outer_status_zero test "$status_value" -eq 0 || validation_failures=$((validation_failures + 1))
    run_validation_assertion node_a_role_exact line_count_exact "${probe_prefix}_value_node_role=node-a" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    run_validation_assertion node_b_role_exact line_count_exact "${probe_prefix}_value_node_role=node-b" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    run_validation_assertion inherited_user_pi_twice line_count_exact "${probe_prefix}_value_inherited_execution_user=pi" "$inspected_path" 2 || validation_failures=$((validation_failures + 1))
    run_validation_assertion probe_state_metadata_exact line_count_exact "${probe_prefix}_value_state_directory_metadata=${expected_state_metadata}" "$inspected_path" 2 || validation_failures=$((validation_failures + 1))
    run_validation_assertion probe_dedupe_metadata_exact line_count_exact "${probe_prefix}_value_dedupe_directory_metadata=${expected_dedupe_metadata}" "$inspected_path" 2 || validation_failures=$((validation_failures + 1))
    run_validation_assertion runner_node_a_state_metadata_exact line_count_exact "${prior_prefix}_value_node_a_state_directory_metadata=${expected_state_metadata}" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    run_validation_assertion runner_node_b_state_metadata_exact line_count_exact "${prior_prefix}_value_node_b_state_directory_metadata=${expected_state_metadata}" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    run_validation_assertion runner_node_a_dedupe_metadata_exact line_count_exact "${prior_prefix}_value_node_a_dedupe_directory_metadata=${expected_dedupe_metadata}" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    run_validation_assertion runner_node_b_dedupe_metadata_exact line_count_exact "${prior_prefix}_value_node_b_dedupe_directory_metadata=${expected_dedupe_metadata}" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    run_validation_assertion probe_count_exact line_count_exact "${probe_prefix}_assertion_count=${expected_probe_count}" "$inspected_path" 2 || validation_failures=$((validation_failures + 1))
    run_validation_assertion probe_failed_count_zero line_count_exact "${probe_prefix}_failed_assertion_count=0" "$inspected_path" 2 || validation_failures=$((validation_failures + 1))
    run_validation_assertion probe_first_failure_none line_count_exact "${probe_prefix}_first_failure=none" "$inspected_path" 2 || validation_failures=$((validation_failures + 1))
    while IFS= read -r expected_label; do
        run_validation_assertion "probe_${expected_label}_twice" line_count_exact \
            "${probe_prefix}_assertion_${expected_label}=true" "$inspected_path" 2 || validation_failures=$((validation_failures + 1))
    done < <(/bin/bash "$prior_probe" --expected-assertions)
    run_validation_assertion runner_count_exact line_count_exact "${prior_prefix}_assertion_count=${expected_runner_count}" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    run_validation_assertion runner_failed_count_zero line_count_exact "${prior_prefix}_failed_assertion_count=0" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    run_validation_assertion runner_first_failure_none line_count_exact "${prior_prefix}_first_failure=none" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    while IFS= read -r expected_label; do
        run_validation_assertion "runner_${expected_label}" line_count_exact \
            "${prior_prefix}_assertion_${expected_label}=true" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    done < <(/bin/bash "$prior_runner" --expected-assertions)
    run_validation_assertion no_false_assertions no_false_assertions "$inspected_path" || validation_failures=$((validation_failures + 1))
    for expected_label in notification_helper_invoked filesystem_mutations service_mutations \
        keepalived_mutations vrrp_mutations vip_mutations network_mutations persistent_mutations; do
        run_validation_assertion "runner_${expected_label}_false" line_count_exact \
            "${prior_prefix}_${expected_label}=false" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    done
    run_validation_assertion runner_cleanup_complete line_count_exact "${prior_prefix}_runner_cleanup_complete=true" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    run_validation_assertion prior_inner_status_zero line_count_exact "${prior_prefix}_inner_status=0" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    run_validation_assertion prior_outer_cleanup_complete line_count_exact "${prior_prefix}_outer_cleanup_complete=true" "$inspected_path" 1 || validation_failures=$((validation_failures + 1))
    [[ "$validation_failures" -eq 0 ]]
}

case "${1:-}" in
    --expected-local-gates)
        printf '%s\n' working_directory prior_probe_hash prior_runner_hash prior_outer_hash \
            accepted_runtime_acceptance_hash regression_hash collision_hash conditional_hash \
            transcript_hash output_evidence_hash syntax collision_policy conditional_policy \
            transcript_policy output_evidence_policy regression prior_probe_self_test \
            prior_runner_self_test prior_outer_self_test
        exit 0
        ;;
    --validate-transcript)
        [[ $# -eq 3 ]] || exit 64
        validate_readiness_transcript "$2" "$3"
        exit
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
capture_root=$(mktemp -d /tmp/caddy-action20d-c-retry-outer.XXXXXX)
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
readonly prior_stdout=$capture_root/prior.stdout
readonly prior_stderr=$capture_root/prior.stderr
touch "$prior_stdout" "$prior_stderr"
chmod 0600 "$prior_stdout" "$prior_stderr"
prior_status=0
/bin/bash "$prior_outer" >"$prior_stdout" 2>"$prior_stderr" || prior_status=$?
readonly prior_status
if ! safe_stream "$prior_stdout" || ! safe_stream "$prior_stderr"; then
    retain_evidence=true
    printf '%s_outer_stream_classification=unsafe_retained\n' "$prefix" >&2
    exit 97
fi
printf '%s_outer_stream_classification=bounded_safe\n' "$prefix"
emit_stream prior_stdout "$prior_stdout"
emit_stream prior_stderr "$prior_stderr"
printf '%s_outer_prior_status=%s\n' "$prefix" "$prior_status"
validation_status=0
validate_readiness_transcript "$prior_stdout" "$prior_status" || validation_status=$?
readonly validation_status
printf '%s_outer_validation_status=%s\n' "$prefix" "$validation_status"
[[ "$validation_status" -eq 0 ]]
rm -rf -- "$capture_root"
trap - EXIT
printf '%s_outer_notification_helper_invoked=false\n' "$prefix"
printf '%s_outer_filesystem_mutations=false\n' "$prefix"
printf '%s_outer_service_mutations=false\n' "$prefix"
printf '%s_outer_keepalived_mutations=false\n' "$prefix"
printf '%s_outer_vrrp_mutations=false\n' "$prefix"
printf '%s_outer_vip_mutations=false\n' "$prefix"
printf '%s_outer_network_mutations=false\n' "$prefix"
printf '%s_outer_persistent_mutations=false\n' "$prefix"
printf '%s_outer_cleanup_complete=true\n' "$prefix"
printf '%s_outer_readiness_complete=true\n' "$prefix"
