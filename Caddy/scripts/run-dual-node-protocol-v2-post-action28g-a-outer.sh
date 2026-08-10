#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28g_a_outer
readonly main_inspector_sha256=96b159653883c5a67ae384b1129ce619f2e74f0b44c4846da1d44ae898cd96d9
readonly residue_inspector_sha256=b4d5672ad87de72852683578df484991de02ce382242b2d7235b67c729fbdb26
readonly regression_sha256=a99bc920ed0c66106bf5e3318fdc2a052998d04b68193aac54fd5e0bbbe503d9
readonly action28g_outer_sha256=ffc572b7c84d76288f293af814cfe917dc52128f878509ca160c5fd2d6bd2642
readonly revision=20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63
readonly parent_revision=action16ar-retry-node-a-default-deny
readonly release_manifest_sha256=c72b5bc5a6586ac3be098c0c5ca2fc3dc01a09c2afe4dcf90ed4bdbda6d166de
readonly payload_manifest_sha256=fdc6ed955f14226ac3e1777eca37507cc8ab6ca16add3135dece9d6964e27568
readonly historical_release_manifest_sha256=81afa957c65b4f8a3f539b0018ebd700b0c926812f1b1e18b2ea7ade0be0e1b3
readonly historical_payload_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly historical_node_a_tree_sha256=dc6f4359cd6f0f424f2db89b180d63d5478f0de36c344e406c707340b57ceb37
readonly node_b_target=pi@10.1.0.54
readonly node_b_alias=pihole00.local.theama.co
readonly node_a_target=pi@10.1.0.53
readonly node_a_alias=pihole0.local.theama.co
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=8192

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=${script_directory%/scripts}
readonly caddy_root
readonly main_inspector=$script_directory/inspect-protocol-v2-post-action28e-e.sh
readonly residue_inspector=$script_directory/inspect-protocol-v2-post-action28g-a-residue.sh
readonly regression=$caddy_root/tests/action28g-a-dual-node-post-execution-regression.sh
readonly action28g_outer=$script_directory/run-node-a-to-node-b-retained-release-action28g-outer.sh
readonly shfmt_canonical=$caddy_root/tests/shfmt-canonical.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_sha256() {
    [[ ${#1} -eq 64 ]] || return 1
    [[ "$1" != *[!0-9a-f]* ]]
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]]
            ;;
        *) return 1 ;;
    esac
}
require_source() {
    local action28g_a_outer_path=$1
    local action28g_a_outer_hash=$2

    [[ -f "$action28g_a_outer_path" && ! -L "$action28g_a_outer_path" &&
        -x "$action28g_a_outer_path" ]] || return 1
    [[ "$(file_hash "$action28g_a_outer_path")" = "$action28g_a_outer_hash" ]]
}
read_only_contract() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|(^|[[:space:]])(install|mv|cp|chmod|chown|rsync)[[:space:]]' \
        "$main_inspector" "$residue_inspector"
}
run_gate() {
    local action28g_a_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28g_a_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28g_a_outer_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory main_inspector_source residue_inspector_source regression_source \
        action28g_outer_immutable syntax shellcheck canonical_format collision_policy \
        conditional_policy output_evidence_policy scalar_grep_policy portable_awk_policy \
        remote_cwd_policy main_inspector_self_test residue_inspector_self_test \
        read_only_contract regression
}
run_local_gates() {
    local action28g_a_outer_skip_regression=$1

    run_gate working_directory working_directory_approved || return 1
    run_gate main_inspector_source require_source "$main_inspector" "$main_inspector_sha256" || return 1
    run_gate residue_inspector_source require_source "$residue_inspector" "$residue_inspector_sha256" || return 1
    run_gate regression_source require_source "$regression" "$regression_sha256" || return 1
    run_gate action28g_outer_immutable require_source "$action28g_outer" "$action28g_outer_sha256" || return 1
    run_gate syntax /bin/bash -n "$main_inspector" "$residue_inspector" "$regression" "$0" || return 1
    run_gate shellcheck shellcheck "$main_inspector" "$residue_inspector" "$regression" "$0" || return 1
    run_gate canonical_format /bin/bash "$shfmt_canonical" --check \
        "$main_inspector" "$residue_inspector" "$regression" "$0" || return 1
    run_gate collision_policy /bin/bash \
        "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$main_inspector" "$residue_inspector" "$regression" "$0" || return 1
    run_gate conditional_policy /bin/bash \
        "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash \
        "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate scalar_grep_policy /bin/bash \
        "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$main_inspector" "$residue_inspector" "$regression" "$0" || return 1
    run_gate portable_awk_policy /bin/bash \
        "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$main_inspector" "$residue_inspector" "$regression" "$0" || return 1
    run_gate remote_cwd_policy /bin/bash \
        "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" --check "$0" || return 1
    run_gate main_inspector_self_test /bin/bash "$main_inspector" --self-test || return 1
    run_gate residue_inspector_self_test /bin/bash "$residue_inspector" --self-test || return 1
    run_gate read_only_contract read_only_contract || return 1
    if [[ "$action28g_a_outer_skip_regression" == true ]]; then
        run_gate regression true || return 1
    else
        run_gate regression /bin/bash "$regression" || return 1
    fi
}
safe_stream() {
    local action28g_a_outer_stream=$1

    [[ "$(wc -c <"$action28g_a_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28g_a_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28g_a_outer_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action28g_a_outer_stream"
}
emit_stream() {
    local action28g_a_outer_label=$1
    local action28g_a_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28g_a_outer_label" "$(wc -c <"$action28g_a_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28g_a_outer_label" "$(line_count "$action28g_a_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28g_a_outer_label" "$(file_hash "$action28g_a_outer_stream")"
    if ! safe_stream "$action28g_a_outer_stream"; then
        trap - EXIT
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28g_a_outer_label" >&2
        printf '%s_%s_protected_evidence=%s\n' "$prefix" "$action28g_a_outer_label" "$work_root" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28g_a_outer_label"
    printf '%s_%s_content_begin\n' "$prefix" "$action28g_a_outer_label"
    sed "s/^/${prefix}_${action28g_a_outer_label}_content=/" "$action28g_a_outer_stream"
    printf '%s_%s_content_end\n' "$prefix" "$action28g_a_outer_label"
}
require_one() {
    local action28g_a_outer_line=$1
    local action28g_a_outer_transcript=$2

    [[ "$(grep -Fxc "$action28g_a_outer_line" "$action28g_a_outer_transcript" || true)" -eq 1 ]]
}
extract_one() {
    local action28g_a_outer_key=$1
    local action28g_a_outer_transcript=$2
    local action28g_a_outer_value

    [[ "$(grep -Ec "^${action28g_a_outer_key}=" "$action28g_a_outer_transcript" || true)" -eq 1 ]] || return 1
    action28g_a_outer_value=$(sed -n "s/^${action28g_a_outer_key}=//p" "$action28g_a_outer_transcript")
    printf '%s\n' "$action28g_a_outer_value"
}
validate_assert() {
    local action28g_a_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_validation_%s=true\n' "$prefix" "$action28g_a_outer_label"
        return 0
    fi
    printf '%s_validation_%s=false\n' "$prefix" "$action28g_a_outer_label" >&2
    return 1
}
main_grammar_exact() {
    local action28g_a_outer_transcript=$1
    local action28g_a_outer_line

    while IFS= read -r action28g_a_outer_line || [[ -n "$action28g_a_outer_line" ]]; do
        case "$action28g_a_outer_line" in
            action_28e_e_check_*=true | \
                action_28e_e_value_historical_release_manifest_expected_sha256=* | \
                action_28e_e_value_historical_release_manifest_observed_sha256=* | \
                action_28e_e_value_historical_payload_manifest_expected_sha256=* | \
                action_28e_e_value_historical_payload_manifest_observed_sha256=* | \
                action_28e_e_value_historical_tree_expected_sha256=* | \
                action_28e_e_value_historical_tree_observed_sha256=* | \
                action_28e_e_value_role=* | action_28e_e_value_candidate_count=* | \
                action_28e_e_value_candidate_state=* | action_28e_e_value_candidate_revision=* | \
                action_28e_e_value_candidate_parent=* | action_28e_e_value_candidate_manifest_sha256=* | \
                action_28e_e_value_candidate_payload_manifest_sha256=* | \
                action_28e_e_value_candidate_tree_sha256=* | action_28e_e_value_candidate_metadata=* | \
                action_28e_e_value_candidate_request_state=* | \
                action_28e_e_value_candidate_complete_state=* | \
                action_28e_e_value_candidate_pending_state=* | action_28e_e_value_snapshot_sha256=* | \
                action_28e_e_check_count=* | action_28e_e_failed_check_count=0 | \
                action_28e_e_first_failure=none | action_28e_e_publisher_invoked=false | \
                action_28e_e_receiver_invoked=false | action_28e_e_finalizer_invoked=false | \
                action_28e_e_cleanup_executed=false | action_28e_e_service_mutations=false | \
                action_28e_e_filesystem_mutations=false | action_28e_e_lsyncd_enabled=false | \
                action_28e_e_reconciliation_executed=false | \
                action_28e_e_remote_delete_executed=false | action_28e_e_acceptance=true) ;;
            *) return 1 ;;
        esac
    done <"$action28g_a_outer_transcript"
}
residue_grammar_exact() {
    local action28g_a_outer_transcript=$1
    local action28g_a_outer_line

    while IFS= read -r action28g_a_outer_line || [[ -n "$action28g_a_outer_line" ]]; do
        case "$action28g_a_outer_line" in
            action_28g_a_residue_check_*=true | action_28g_a_residue_value_role=* | \
                action_28g_a_residue_value_revision=* | \
                action_28g_a_residue_value_parent_revision=* | \
                action_28g_a_residue_value_release_manifest_sha256=* | \
                action_28g_a_residue_value_payload_manifest_sha256=* | \
                action_28g_a_residue_value_snapshot_sha256=* | \
                action_28g_a_residue_check_count=* | action_28g_a_residue_failed_check_count=0 | \
                action_28g_a_residue_first_failure=none | \
                action_28g_a_residue_filesystem_mutations=false | \
                action_28g_a_residue_service_mutations=false | \
                action_28g_a_residue_cleanup_executed=false | \
                action_28g_a_residue_acceptance=true) ;;
            *) return 1 ;;
        esac
    done <"$action28g_a_outer_transcript"
}
validate_inventory() {
    local action28g_a_outer_label=$1
    local action28g_a_outer_producer=$2
    local action28g_a_outer_prefix=$3
    local action28g_a_outer_transcript=$4
    local action28g_a_outer_expected=$5
    local action28g_a_outer_observed=$6

    /bin/bash "$action28g_a_outer_producer" --expected-checks >"$action28g_a_outer_expected" || return 1
    sed -n "s/^${action28g_a_outer_prefix}_check_\([a-zA-Z0-9_]*\)=true$/\1/p" \
        "$action28g_a_outer_transcript" >"$action28g_a_outer_observed"
    validate_assert "${action28g_a_outer_label}_expected_unique" test \
        "$(LC_ALL=C sort -u "$action28g_a_outer_expected" | wc -l)" -eq \
        "$(line_count "$action28g_a_outer_expected")" || return 1
    validate_assert "${action28g_a_outer_label}_ordered_inventory" cmp -s \
        "$action28g_a_outer_expected" "$action28g_a_outer_observed" || return 1
}
validate_main() {
    local action28g_a_outer_role=$1
    local action28g_a_outer_stdout=$2
    local action28g_a_outer_stderr=$3
    local action28g_a_outer_status=$4
    local action28g_a_outer_expected=$5
    local action28g_a_outer_observed=$6
    local action28g_a_outer_expected_state=sender_ready
    local action28g_a_outer_expected_complete=absent
    local action28g_a_outer_snapshot
    local action28g_a_outer_marker

    if [[ "$action28g_a_outer_role" == node-b ]]; then
        action28g_a_outer_expected_state=receiver_finalized
        action28g_a_outer_expected_complete=regular_empty
    fi
    validate_assert "${action28g_a_outer_role}_main_status_zero" test "$action28g_a_outer_status" -eq 0 || return 1
    validate_assert "${action28g_a_outer_role}_main_stderr_empty" test ! -s "$action28g_a_outer_stderr" || return 1
    validate_assert "${action28g_a_outer_role}_main_grammar_exact" main_grammar_exact "$action28g_a_outer_stdout" || return 1
    validate_inventory "${action28g_a_outer_role}_main" "$main_inspector" action_28e_e \
        "$action28g_a_outer_stdout" "$action28g_a_outer_expected" "$action28g_a_outer_observed" || return 1
    validate_assert "${action28g_a_outer_role}_role_exact" require_one \
        "action_28e_e_value_role=$action28g_a_outer_role" "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_candidate_count_exact" require_one \
        'action_28e_e_value_candidate_count=1' "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_candidate_state_exact" require_one \
        "action_28e_e_value_candidate_state=$action28g_a_outer_expected_state" "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_revision_exact" require_one \
        "action_28e_e_value_candidate_revision=$revision" "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_parent_exact" require_one \
        "action_28e_e_value_candidate_parent=$parent_revision" "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_release_manifest_exact" require_one \
        "action_28e_e_value_candidate_manifest_sha256=$release_manifest_sha256" "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_payload_manifest_exact" require_one \
        "action_28e_e_value_candidate_payload_manifest_sha256=$payload_manifest_sha256" "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_request_marker_exact" require_one \
        'action_28e_e_value_candidate_request_state=regular_empty' "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_complete_marker_exact" require_one \
        "action_28e_e_value_candidate_complete_state=$action28g_a_outer_expected_complete" \
        "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_pending_marker_absent" require_one \
        'action_28e_e_value_candidate_pending_state=absent' "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_historical_release_expected" require_one \
        "action_28e_e_value_historical_release_manifest_expected_sha256=$historical_release_manifest_sha256" \
        "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_historical_release_observed" require_one \
        "action_28e_e_value_historical_release_manifest_observed_sha256=$historical_release_manifest_sha256" \
        "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_historical_payload_expected" require_one \
        "action_28e_e_value_historical_payload_manifest_expected_sha256=$historical_payload_manifest_sha256" \
        "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_historical_payload_observed" require_one \
        "action_28e_e_value_historical_payload_manifest_observed_sha256=$historical_payload_manifest_sha256" \
        "$action28g_a_outer_stdout" || return 1
    if [[ "$action28g_a_outer_role" == node-a ]]; then
        validate_assert node_a_historical_tree_exact require_one \
            "action_28e_e_value_historical_tree_observed_sha256=$historical_node_a_tree_sha256" \
            "$action28g_a_outer_stdout" || return 1
    else
        validate_assert node_b_historical_tree_not_applicable require_one \
            'action_28e_e_value_historical_tree_observed_sha256=not_applicable' \
            "$action28g_a_outer_stdout" || return 1
    fi
    action28g_a_outer_snapshot=$(extract_one action_28e_e_value_snapshot_sha256 "$action28g_a_outer_stdout") || return 1
    validate_assert "${action28g_a_outer_role}_snapshot_hash_valid" valid_sha256 "$action28g_a_outer_snapshot" || return 1
    for action28g_a_outer_marker in \
        publisher_invoked receiver_invoked finalizer_invoked cleanup_executed \
        service_mutations filesystem_mutations lsyncd_enabled reconciliation_executed \
        remote_delete_executed; do
        validate_assert "${action28g_a_outer_role}_${action28g_a_outer_marker}_false" require_one \
            "action_28e_e_${action28g_a_outer_marker}=false" "$action28g_a_outer_stdout" || return 1
    done
    validate_assert "${action28g_a_outer_role}_main_acceptance" require_one \
        'action_28e_e_acceptance=true' "$action28g_a_outer_stdout" || return 1
}
validate_residue() {
    local action28g_a_outer_role=$1
    local action28g_a_outer_stdout=$2
    local action28g_a_outer_stderr=$3
    local action28g_a_outer_status=$4
    local action28g_a_outer_expected=$5
    local action28g_a_outer_observed=$6
    local action28g_a_outer_snapshot

    validate_assert "${action28g_a_outer_role}_residue_status_zero" test "$action28g_a_outer_status" -eq 0 || return 1
    validate_assert "${action28g_a_outer_role}_residue_stderr_empty" test ! -s "$action28g_a_outer_stderr" || return 1
    validate_assert "${action28g_a_outer_role}_residue_grammar_exact" residue_grammar_exact "$action28g_a_outer_stdout" || return 1
    validate_inventory "${action28g_a_outer_role}_residue" "$residue_inspector" action_28g_a_residue \
        "$action28g_a_outer_stdout" "$action28g_a_outer_expected" "$action28g_a_outer_observed" || return 1
    validate_assert "${action28g_a_outer_role}_residue_role_exact" require_one \
        "action_28g_a_residue_value_role=$action28g_a_outer_role" "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_residue_revision_exact" require_one \
        "action_28g_a_residue_value_revision=$revision" "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_residue_parent_exact" require_one \
        "action_28g_a_residue_value_parent_revision=$parent_revision" "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_residue_release_manifest_exact" require_one \
        "action_28g_a_residue_value_release_manifest_sha256=$release_manifest_sha256" \
        "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_residue_payload_manifest_exact" require_one \
        "action_28g_a_residue_value_payload_manifest_sha256=$payload_manifest_sha256" \
        "$action28g_a_outer_stdout" || return 1
    action28g_a_outer_snapshot=$(extract_one action_28g_a_residue_value_snapshot_sha256 "$action28g_a_outer_stdout") || return 1
    validate_assert "${action28g_a_outer_role}_residue_snapshot_hash_valid" valid_sha256 \
        "$action28g_a_outer_snapshot" || return 1
    validate_assert "${action28g_a_outer_role}_residue_filesystem_mutations_false" require_one \
        'action_28g_a_residue_filesystem_mutations=false' "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_residue_service_mutations_false" require_one \
        'action_28g_a_residue_service_mutations=false' "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_residue_cleanup_false" require_one \
        'action_28g_a_residue_cleanup_executed=false' "$action28g_a_outer_stdout" || return 1
    validate_assert "${action28g_a_outer_role}_residue_acceptance" require_one \
        'action_28g_a_residue_acceptance=true' "$action28g_a_outer_stdout" || return 1
}
validate_pair() {
    local action28g_a_outer_node_b=$1
    local action28g_a_outer_node_a=$2
    local action28g_a_outer_key
    local action28g_a_outer_b_value
    local action28g_a_outer_a_value

    for action28g_a_outer_key in \
        candidate_revision candidate_parent candidate_manifest_sha256 \
        candidate_payload_manifest_sha256; do
        action28g_a_outer_b_value=$(extract_one \
            "action_28e_e_value_${action28g_a_outer_key}" "$action28g_a_outer_node_b") || return 1
        action28g_a_outer_a_value=$(extract_one \
            "action_28e_e_value_${action28g_a_outer_key}" "$action28g_a_outer_node_a") || return 1
        validate_assert "pair_${action28g_a_outer_key}_exact" test \
            "$action28g_a_outer_b_value" = "$action28g_a_outer_a_value" || return 1
    done
    printf '%s_value_classification=receiver_finalized\n' "$prefix"
    printf '%s_value_revision=%s\n' "$prefix" "$revision"
    printf '%s_acceptance=true\n' "$prefix"
}
cleanup() {
    local action28g_a_outer_status=$?

    if [[ -n "${work_root:-}" && -d "$work_root" ]]; then
        rm -rf -- "$work_root"
    fi
    exit "$action28g_a_outer_status"
}
run_remote() {
    local action28g_a_outer_alias=$1
    local action28g_a_outer_target=$2
    local action28g_a_outer_role=$3
    local action28g_a_outer_payload=$4
    local action28g_a_outer_stdout=$5
    local action28g_a_outer_stderr=$6
    local action28g_a_outer_status_name=$7
    local action28g_a_outer_remote_status=0

    "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 \
        -o StrictHostKeyChecking=yes -o "HostKeyAlias=$action28g_a_outer_alias" \
        "$action28g_a_outer_target" "cd / && sudo -n /bin/bash -s -- $action28g_a_outer_role" \
        <"$action28g_a_outer_payload" >"$action28g_a_outer_stdout" \
        2>"$action28g_a_outer_stderr" || action28g_a_outer_remote_status=$?
    printf -v "$action28g_a_outer_status_name" '%s' "$action28g_a_outer_remote_status"
}

case "${1:-}" in
    --expected-local-gates)
        [[ $# -eq 1 ]]
        expected_local_gates
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        run_local_gates true
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --test-main)
        [[ $# -eq 5 && "${CADDY_ACTION28G_A_TEST_MODE:-}" == 1 ]]
        test_root=$(mktemp -d /tmp/action28g-a-main-test.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT
        validate_main "$2" "$3" "$4" "$5" \
            "$test_root/expected" "$test_root/observed"
        exit
        ;;
    --test-residue)
        [[ $# -eq 5 && "${CADDY_ACTION28G_A_TEST_MODE:-}" == 1 ]]
        test_root=$(mktemp -d /tmp/action28g-a-residue-test.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT
        validate_residue "$2" "$3" "$4" "$5" \
            "$test_root/expected" "$test_root/observed"
        exit
        ;;
    --test-pair)
        [[ $# -eq 3 && "${CADDY_ACTION28G_A_TEST_MODE:-}" == 1 ]]
        validate_pair "$2" "$3"
        exit
        ;;
    "") [[ $# -eq 0 ]] ;;
    *) exit 64 ;;
esac

skip_embedded_regression=false
if [[ "${CADDY_ACTION28G_A_REGRESSION_INTERCEPT:-}" == 1 &&
    -n "${CADDY_ACTION28G_A_SSH_BINARY:-}" ]]; then
    skip_embedded_regression=true
fi
readonly skip_embedded_regression
run_local_gates "$skip_embedded_regression"
work_root=$(mktemp -d /tmp/action28g-a-outer.XXXXXX)
readonly work_root
trap cleanup EXIT
for action28g_a_outer_name in \
    node-b-main.stdout node-b-main.stderr node-b-residue.stdout node-b-residue.stderr \
    node-a-main.stdout node-a-main.stderr node-a-residue.stdout node-a-residue.stderr; do
    : >"$work_root/$action28g_a_outer_name"
    chmod 0600 "$work_root/$action28g_a_outer_name"
done
ssh_binary=${CADDY_ACTION28G_A_SSH_BINARY:-ssh}
readonly ssh_binary

node_b_main_status=0
run_remote "$node_b_alias" "$node_b_target" node-b "$main_inspector" \
    "$work_root/node-b-main.stdout" "$work_root/node-b-main.stderr" node_b_main_status
emit_stream node_b_main_stdout "$work_root/node-b-main.stdout"
emit_stream node_b_main_stderr "$work_root/node-b-main.stderr"
validate_main node-b "$work_root/node-b-main.stdout" "$work_root/node-b-main.stderr" \
    "$node_b_main_status" "$work_root/node-b-main.expected" "$work_root/node-b-main.observed" || exit 97

node_b_residue_status=0
run_remote "$node_b_alias" "$node_b_target" node-b "$residue_inspector" \
    "$work_root/node-b-residue.stdout" "$work_root/node-b-residue.stderr" node_b_residue_status
emit_stream node_b_residue_stdout "$work_root/node-b-residue.stdout"
emit_stream node_b_residue_stderr "$work_root/node-b-residue.stderr"
validate_residue node-b "$work_root/node-b-residue.stdout" "$work_root/node-b-residue.stderr" \
    "$node_b_residue_status" "$work_root/node-b-residue.expected" \
    "$work_root/node-b-residue.observed" || exit 97

node_a_main_status=0
run_remote "$node_a_alias" "$node_a_target" node-a "$main_inspector" \
    "$work_root/node-a-main.stdout" "$work_root/node-a-main.stderr" node_a_main_status
emit_stream node_a_main_stdout "$work_root/node-a-main.stdout"
emit_stream node_a_main_stderr "$work_root/node-a-main.stderr"
validate_main node-a "$work_root/node-a-main.stdout" "$work_root/node-a-main.stderr" \
    "$node_a_main_status" "$work_root/node-a-main.expected" "$work_root/node-a-main.observed" || exit 97

node_a_residue_status=0
run_remote "$node_a_alias" "$node_a_target" node-a "$residue_inspector" \
    "$work_root/node-a-residue.stdout" "$work_root/node-a-residue.stderr" node_a_residue_status
emit_stream node_a_residue_stdout "$work_root/node-a-residue.stdout"
emit_stream node_a_residue_stderr "$work_root/node-a-residue.stderr"
validate_residue node-a "$work_root/node-a-residue.stdout" "$work_root/node-a-residue.stderr" \
    "$node_a_residue_status" "$work_root/node-a-residue.expected" \
    "$work_root/node-a-residue.observed" || exit 97

validate_pair "$work_root/node-b-main.stdout" "$work_root/node-a-main.stdout" || exit 97
printf '%s_node_b_contacted=true\n' "$prefix"
printf '%s_node_a_contacted=true\n' "$prefix"
printf '%s_action_28g_rerun=false\n' "$prefix"
printf '%s_cleanup_executed=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
