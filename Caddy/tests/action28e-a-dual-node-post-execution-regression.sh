#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28e_a_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly inspector=$caddy_root/scripts/inspect-protocol-v2-post-action28e-a.sh
readonly outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28e-a-outer.sh
readonly fixture_revision=20260809T193000Z-11111111-2222-3333-4444-555555555555
readonly fixture_parent=action16ar-retry-node-a-default-deny
readonly fixture_manifest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
readonly fixture_payload=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

work_root=$(mktemp -d /tmp/action28e-a-regression.XXXXXX)
readonly work_root
cleanup() {
    local action28e_a_regression_status=$?

    rm -rf -- "$work_root"
    exit "$action28e_a_regression_status"
}
trap cleanup EXIT

record_check() {
    local action28e_a_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28e_a_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28e_a_regression_label" >&2
    return 1
}
make_transcript() {
    local action28e_a_regression_role=$1
    local action28e_a_regression_state=$2
    local action28e_a_regression_output=$3
    local action28e_a_regression_label
    local action28e_a_regression_count=0

    : >"$action28e_a_regression_output"
    while IFS= read -r action28e_a_regression_label; do
        printf 'action_28e_a_check_%s=true\n' "$action28e_a_regression_label" >>"$action28e_a_regression_output"
        action28e_a_regression_count=$((action28e_a_regression_count + 1))
    done < <(/bin/bash "$inspector" --expected-checks)
    printf 'action_28e_a_value_role=%s\n' "$action28e_a_regression_role" >>"$action28e_a_regression_output"
    if [[ "$action28e_a_regression_state" == absent ]]; then
        printf '%s\n' \
            'action_28e_a_value_candidate_count=0' \
            'action_28e_a_value_candidate_state=absent' \
            'action_28e_a_value_candidate_revision=absent' \
            'action_28e_a_value_candidate_parent=absent' \
            'action_28e_a_value_candidate_manifest_sha256=absent' \
            'action_28e_a_value_candidate_payload_manifest_sha256=absent' \
            'action_28e_a_value_candidate_tree_sha256=absent' \
            'action_28e_a_value_candidate_metadata=absent' \
            'action_28e_a_value_candidate_request_state=absent' \
            'action_28e_a_value_candidate_complete_state=absent' \
            'action_28e_a_value_candidate_pending_state=absent' \
            >>"$action28e_a_regression_output"
    else
        printf '%s\n' \
            'action_28e_a_value_candidate_count=1' \
            "action_28e_a_value_candidate_state=$action28e_a_regression_state" \
            "action_28e_a_value_candidate_revision=$fixture_revision" \
            "action_28e_a_value_candidate_parent=$fixture_parent" \
            "action_28e_a_value_candidate_manifest_sha256=$fixture_manifest" \
            "action_28e_a_value_candidate_payload_manifest_sha256=$fixture_payload" \
            'action_28e_a_value_candidate_tree_sha256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' \
            'action_28e_a_value_candidate_metadata=994:990:550:4096:1785461697' \
            'action_28e_a_value_candidate_request_state=regular_empty' \
            >>"$action28e_a_regression_output"
        if [[ "$action28e_a_regression_role" == node-a ]]; then
            printf 'action_28e_a_value_candidate_complete_state=absent\n' >>"$action28e_a_regression_output"
        else
            printf 'action_28e_a_value_candidate_complete_state=regular_empty\n' >>"$action28e_a_regression_output"
        fi
        printf 'action_28e_a_value_candidate_pending_state=absent\n' >>"$action28e_a_regression_output"
    fi
    printf '%s\n' \
        'action_28e_a_value_snapshot_sha256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
        "action_28e_a_check_count=$action28e_a_regression_count" \
        'action_28e_a_failed_check_count=0' \
        'action_28e_a_first_failure=none' \
        'action_28e_a_publisher_invoked=false' \
        'action_28e_a_receiver_invoked=false' \
        'action_28e_a_finalizer_invoked=false' \
        'action_28e_a_cleanup_executed=false' \
        'action_28e_a_service_mutations=false' \
        'action_28e_a_filesystem_mutations=false' \
        'action_28e_a_lsyncd_enabled=false' \
        'action_28e_a_reconciliation_executed=false' \
        'action_28e_a_remote_delete_executed=false' \
        'action_28e_a_acceptance=true' >>"$action28e_a_regression_output"
}
run_case() {
    local action28e_a_regression_name=$1
    local action28e_a_regression_expected_status=$2
    local action28e_a_regression_node_b_state=$3
    local action28e_a_regression_node_a_state=$4
    local action28e_a_regression_mutation=${5:-none}
    local action28e_a_regression_case_root=$work_root/$action28e_a_regression_name
    local action28e_a_regression_status=0

    mkdir -m 0700 "$action28e_a_regression_case_root"
    make_transcript node-b "$action28e_a_regression_node_b_state" "$action28e_a_regression_case_root/node-b.stdout"
    make_transcript node-a "$action28e_a_regression_node_a_state" "$action28e_a_regression_case_root/node-a.stdout"
    : >"$action28e_a_regression_case_root/node-b.stderr"
    : >"$action28e_a_regression_case_root/node-a.stderr"
    case "$action28e_a_regression_mutation" in
        none) ;;
        missing_label) sed -i '/^action_28e_a_check_candidate_paths_safe=true$/d' "$action28e_a_regression_case_root/node-a.stdout" ;;
        false_label) sed -i 's/^action_28e_a_check_snapshot_stable=true$/action_28e_a_check_snapshot_stable=false/' "$action28e_a_regression_case_root/node-b.stdout" ;;
        duplicate_label) printf 'action_28e_a_check_snapshot_stable=true\n' >>"$action28e_a_regression_case_root/node-a.stdout" ;;
        reordered_labels) sed -i '1{h;d};2{G}' "$action28e_a_regression_case_root/node-b.stdout" ;;
        altered_manifest) sed -i 's/^action_28e_a_value_candidate_manifest_sha256=.*/action_28e_a_value_candidate_manifest_sha256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd/' "$action28e_a_regression_case_root/node-b.stdout" ;;
        altered_tree_evidence) sed -i 's/^action_28e_a_value_candidate_tree_sha256=.*/action_28e_a_value_candidate_tree_sha256=not-a-hash/' "$action28e_a_regression_case_root/node-b.stdout" ;;
        stderr) printf 'bounded regression stderr\n' >"$action28e_a_regression_case_root/node-a.stderr" ;;
        mutation_true) sed -i 's/^action_28e_a_service_mutations=false$/action_28e_a_service_mutations=true/' "$action28e_a_regression_case_root/node-b.stdout" ;;
        *) return 1 ;;
    esac
    if CADDY_ACTION28E_A_TEST_MODE=1 /bin/bash "$outer" --test-validate \
        "$action28e_a_regression_case_root/node-b.stdout" \
        "$action28e_a_regression_case_root/node-b.stderr" 0 \
        "$action28e_a_regression_case_root/node-a.stdout" \
        "$action28e_a_regression_case_root/node-a.stderr" 0 \
        >"$action28e_a_regression_case_root/outer.stdout" \
        2>"$action28e_a_regression_case_root/outer.stderr"; then
        action28e_a_regression_status=0
    else
        action28e_a_regression_status=$?
    fi
    [[ "$action28e_a_regression_status" -eq "$action28e_a_regression_expected_status" ]]
}

record_check inspector_self_test /bin/bash "$inspector" --self-test
record_check finalized_pair_accepted run_case finalized 0 receiver_finalized sender_ready
record_check absent_pair_nonaccepted run_case absent 97 absent absent
record_check node_a_only_nonaccepted run_case node_a_only 97 absent sender_ready
record_check node_b_only_nonaccepted run_case node_b_only 97 receiver_finalized absent
record_check missing_label_rejected run_case missing_label 97 receiver_finalized sender_ready missing_label
record_check false_label_rejected run_case false_label 97 receiver_finalized sender_ready false_label
record_check duplicate_label_rejected run_case duplicate_label 97 receiver_finalized sender_ready duplicate_label
record_check reordered_labels_rejected run_case reordered 97 receiver_finalized sender_ready reordered_labels
record_check altered_manifest_rejected run_case altered_manifest 97 receiver_finalized sender_ready altered_manifest
record_check altered_tree_evidence_rejected run_case altered_tree 97 receiver_finalized sender_ready altered_tree_evidence
record_check stderr_rejected run_case stderr 97 receiver_finalized sender_ready stderr
record_check mutation_true_rejected run_case mutation_true 97 receiver_finalized sender_ready mutation_true
record_check exact_node_b_remote_command grep -Fq \
    '"cd / && sudo -n /bin/bash -s -- node-b"' "$outer"
record_check exact_node_a_remote_command grep -Fq \
    '"cd / && sudo -n /bin/bash -s -- node-a"' "$outer"
record_check action28e_not_invoked test "$(grep -Ec 'run-node-a-to-node-b-release-transfer-action28e-outer[.]sh' "$outer" || true)" -eq 0
record_check publisher_not_invoked test "$(grep -Ec 'publish-release-v2[.]sh' "$inspector" || true)" -eq 0
record_check finalizer_not_invoked test "$(grep -Ec 'finalize-incoming-release-v2[.]sh' "$inspector" || true)" -eq 0

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28e_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
