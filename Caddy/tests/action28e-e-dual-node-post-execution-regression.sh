#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28e_e_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly inspector=$caddy_root/scripts/inspect-protocol-v2-post-action28e-e.sh
readonly outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28e-e-outer.sh
readonly registry=$caddy_root/manifests/protocol-v2-historical-identities-action28e-d.tsv
readonly historical_release_manifest=81afa957c65b4f8a3f539b0018ebd700b0c926812f1b1e18b2ea7ade0be0e1b3
readonly historical_payload_manifest=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly historical_outbound_tree=dc6f4359cd6f0f424f2db89b180d63d5478f0de36c344e406c707340b57ceb37
readonly fixture_revision=20260809T193000Z-11111111-2222-3333-4444-555555555555
readonly fixture_parent=action16ar-retry-node-a-default-deny
readonly fixture_manifest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
readonly fixture_payload=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

work_root=$(mktemp -d /tmp/action28e-e-regression.XXXXXX)
readonly work_root
cleanup() {
    local action28e_e_regression_status=$?

    rm -rf -- "$work_root"
    exit "$action28e_e_regression_status"
}
trap cleanup EXIT

record_check() {
    local action28e_e_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28e_e_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28e_e_regression_label" >&2
    return 1
}
command_fails() {
    ! "$@"
}
make_transcript() {
    local action28e_e_regression_role=$1
    local action28e_e_regression_state=$2
    local action28e_e_regression_output=$3
    local action28e_e_regression_label
    local action28e_e_regression_count=0

    : >"$action28e_e_regression_output"
    while IFS= read -r action28e_e_regression_label; do
        printf 'action_28e_e_check_%s=true\n' "$action28e_e_regression_label" >>"$action28e_e_regression_output"
        action28e_e_regression_count=$((action28e_e_regression_count + 1))
    done < <(/bin/bash "$inspector" --expected-checks)
    printf 'action_28e_e_value_role=%s\n' "$action28e_e_regression_role" >>"$action28e_e_regression_output"
    printf '%s\n' \
        "action_28e_e_value_historical_release_manifest_expected_sha256=$historical_release_manifest" \
        "action_28e_e_value_historical_release_manifest_observed_sha256=$historical_release_manifest" \
        "action_28e_e_value_historical_payload_manifest_expected_sha256=$historical_payload_manifest" \
        "action_28e_e_value_historical_payload_manifest_observed_sha256=$historical_payload_manifest" \
        >>"$action28e_e_regression_output"
    if [[ "$action28e_e_regression_role" == node-a ]]; then
        printf '%s\n' \
            "action_28e_e_value_historical_tree_expected_sha256=$historical_outbound_tree" \
            "action_28e_e_value_historical_tree_observed_sha256=$historical_outbound_tree" \
            >>"$action28e_e_regression_output"
    else
        printf '%s\n' \
            'action_28e_e_value_historical_tree_expected_sha256=not_applicable' \
            'action_28e_e_value_historical_tree_observed_sha256=not_applicable' \
            >>"$action28e_e_regression_output"
    fi
    if [[ "$action28e_e_regression_state" == absent ]]; then
        printf '%s\n' \
            'action_28e_e_value_candidate_count=0' \
            'action_28e_e_value_candidate_state=absent' \
            'action_28e_e_value_candidate_revision=absent' \
            'action_28e_e_value_candidate_parent=absent' \
            'action_28e_e_value_candidate_manifest_sha256=absent' \
            'action_28e_e_value_candidate_payload_manifest_sha256=absent' \
            'action_28e_e_value_candidate_tree_sha256=absent' \
            'action_28e_e_value_candidate_metadata=absent' \
            'action_28e_e_value_candidate_request_state=absent' \
            'action_28e_e_value_candidate_complete_state=absent' \
            'action_28e_e_value_candidate_pending_state=absent' \
            >>"$action28e_e_regression_output"
    else
        printf '%s\n' \
            'action_28e_e_value_candidate_count=1' \
            "action_28e_e_value_candidate_state=$action28e_e_regression_state" \
            "action_28e_e_value_candidate_revision=$fixture_revision" \
            "action_28e_e_value_candidate_parent=$fixture_parent" \
            "action_28e_e_value_candidate_manifest_sha256=$fixture_manifest" \
            "action_28e_e_value_candidate_payload_manifest_sha256=$fixture_payload" \
            'action_28e_e_value_candidate_tree_sha256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' \
            'action_28e_e_value_candidate_metadata=994:990:550:4096:1785461697' \
            'action_28e_e_value_candidate_request_state=regular_empty' \
            >>"$action28e_e_regression_output"
        if [[ "$action28e_e_regression_role" == node-a ]]; then
            printf 'action_28e_e_value_candidate_complete_state=absent\n' >>"$action28e_e_regression_output"
        else
            printf 'action_28e_e_value_candidate_complete_state=regular_empty\n' >>"$action28e_e_regression_output"
        fi
        printf 'action_28e_e_value_candidate_pending_state=absent\n' >>"$action28e_e_regression_output"
    fi
    printf '%s\n' \
        'action_28e_e_value_snapshot_sha256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
        "action_28e_e_check_count=$action28e_e_regression_count" \
        'action_28e_e_failed_check_count=0' \
        'action_28e_e_first_failure=none' \
        'action_28e_e_publisher_invoked=false' \
        'action_28e_e_receiver_invoked=false' \
        'action_28e_e_finalizer_invoked=false' \
        'action_28e_e_cleanup_executed=false' \
        'action_28e_e_service_mutations=false' \
        'action_28e_e_filesystem_mutations=false' \
        'action_28e_e_lsyncd_enabled=false' \
        'action_28e_e_reconciliation_executed=false' \
        'action_28e_e_remote_delete_executed=false' \
        'action_28e_e_acceptance=true' >>"$action28e_e_regression_output"
}
run_case() {
    local action28e_e_regression_name=$1
    local action28e_e_regression_expected_status=$2
    local action28e_e_regression_node_b_state=$3
    local action28e_e_regression_node_a_state=$4
    local action28e_e_regression_mutation=${5:-none}
    local action28e_e_regression_case_root=$work_root/$action28e_e_regression_name
    local action28e_e_regression_status=0

    mkdir -m 0700 "$action28e_e_regression_case_root"
    make_transcript node-b "$action28e_e_regression_node_b_state" "$action28e_e_regression_case_root/node-b.stdout"
    make_transcript node-a "$action28e_e_regression_node_a_state" "$action28e_e_regression_case_root/node-a.stdout"
    : >"$action28e_e_regression_case_root/node-b.stderr"
    : >"$action28e_e_regression_case_root/node-a.stderr"
    case "$action28e_e_regression_mutation" in
        none) ;;
        missing_label) sed -i '/^action_28e_e_check_candidate_paths_safe=true$/d' "$action28e_e_regression_case_root/node-a.stdout" ;;
        false_label) sed -i 's/^action_28e_e_check_snapshot_stable=true$/action_28e_e_check_snapshot_stable=false/' "$action28e_e_regression_case_root/node-b.stdout" ;;
        duplicate_label) printf 'action_28e_e_check_snapshot_stable=true\n' >>"$action28e_e_regression_case_root/node-a.stdout" ;;
        reordered_labels) sed -i '1{h;d};2{G}' "$action28e_e_regression_case_root/node-b.stdout" ;;
        altered_manifest) sed -i 's/^action_28e_e_value_candidate_manifest_sha256=.*/action_28e_e_value_candidate_manifest_sha256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd/' "$action28e_e_regression_case_root/node-b.stdout" ;;
        altered_historical_release) sed -i 's/^action_28e_e_value_historical_release_manifest_observed_sha256=.*/action_28e_e_value_historical_release_manifest_observed_sha256=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff/' "$action28e_e_regression_case_root/node-b.stdout" ;;
        altered_historical_payload) sed -i 's/^action_28e_e_value_historical_payload_manifest_observed_sha256=.*/action_28e_e_value_historical_payload_manifest_observed_sha256=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff/' "$action28e_e_regression_case_root/node-a.stdout" ;;
        altered_tree_evidence) sed -i 's/^action_28e_e_value_candidate_tree_sha256=.*/action_28e_e_value_candidate_tree_sha256=not-a-hash/' "$action28e_e_regression_case_root/node-b.stdout" ;;
        stderr) printf 'bounded regression stderr\n' >"$action28e_e_regression_case_root/node-a.stderr" ;;
        mutation_true) sed -i 's/^action_28e_e_service_mutations=false$/action_28e_e_service_mutations=true/' "$action28e_e_regression_case_root/node-b.stdout" ;;
        *) return 1 ;;
    esac
    if CADDY_ACTION28E_E_TEST_MODE=1 /bin/bash "$outer" --test-validate \
        "$action28e_e_regression_case_root/node-b.stdout" \
        "$action28e_e_regression_case_root/node-b.stderr" 0 \
        "$action28e_e_regression_case_root/node-a.stdout" \
        "$action28e_e_regression_case_root/node-a.stderr" 0 \
        >"$action28e_e_regression_case_root/outer.stdout" \
        2>"$action28e_e_regression_case_root/outer.stderr"; then
        action28e_e_regression_status=0
    else
        action28e_e_regression_status=$?
    fi
    [[ "$action28e_e_regression_status" -eq "$action28e_e_regression_expected_status" ]]
}

historical_stdout=$work_root/historical.stdout
historical_stderr=$work_root/historical.stderr
readonly historical_stdout historical_stderr
historical_status=0
CADDY_ACTION28E_E_TEST_MODE=1 /bin/bash "$inspector" --test-historical-identity \
    release_manifest "$fixture_manifest" "$fixture_payload" historical_release_manifest_hash_exact \
    >"$historical_stdout" 2>"$historical_stderr" || historical_status=$?
readonly historical_status

record_check inspector_self_test /bin/bash "$inspector" --self-test
record_check historical_mismatch_nonzero test "$historical_status" -ne 0
record_check historical_expected_emitted grep -Fqx \
    "action_28e_e_value_historical_release_manifest_expected_sha256=$fixture_manifest" "$historical_stdout"
record_check historical_observed_emitted grep -Fqx \
    "action_28e_e_value_historical_release_manifest_observed_sha256=$fixture_payload" "$historical_stdout"
record_check historical_false_labeled grep -Fqx \
    'action_28e_e_check_historical_release_manifest_hash_exact=false' "$historical_stderr"
record_check historical_first_failure_labeled grep -Fqx \
    'action_28e_e_failed_check=historical_release_manifest_hash_exact' "$historical_stderr"
record_check historical_evidence_precedes_assertion awk \
    '/value_historical_release_manifest_expected_sha256=/{ expected=NR } \
     /value_historical_release_manifest_observed_sha256=/{ observed=NR } \
     END { exit !(expected == 1 && observed == 2) }' "$historical_stdout"
registry_valid=$work_root/registry-valid.tsv
registry_swapped=$work_root/registry-swapped.tsv
registry_missing=$work_root/registry-missing.tsv
registry_duplicate=$work_root/registry-duplicate.tsv
registry_altered_kind=$work_root/registry-altered-kind.tsv
registry_altered_path=$work_root/registry-altered-path.tsv
registry_altered_action=$work_root/registry-altered-action.tsv
readonly registry_valid registry_swapped registry_missing registry_duplicate
readonly registry_altered_kind registry_altered_path registry_altered_action
cp -- "$registry" "$registry_valid"
awk -F '\t' -v OFS='\t' \
    -v release_hash="$historical_release_manifest" \
    -v payload_hash="$historical_payload_manifest" '
    NR == 2 { $4 = payload_hash }
    NR == 3 { $4 = release_hash }
    { print }
' "$registry" >"$registry_swapped"
sed '3d' "$registry" >"$registry_missing"
cp -- "$registry" "$registry_duplicate"
sed -n '2p' "$registry" >>"$registry_duplicate"
sed '2s/release_manifest/release-manifest/' "$registry" >"$registry_altered_kind"
sed '2s/release-manifest[.]json/release_manifest.json/' "$registry" >"$registry_altered_path"
sed '2s/28e-c/28e-b/' "$registry" >"$registry_altered_action"
record_check typed_registry_accepted env CADDY_ACTION28E_E_TEST_MODE=1 \
    /bin/bash "$outer" --test-registry "$registry_valid"
record_check typed_registry_swapped_rejected command_fails env CADDY_ACTION28E_E_TEST_MODE=1 \
    /bin/bash "$outer" --test-registry "$registry_swapped"
record_check typed_registry_missing_rejected command_fails env CADDY_ACTION28E_E_TEST_MODE=1 \
    /bin/bash "$outer" --test-registry "$registry_missing"
record_check typed_registry_duplicate_rejected command_fails env CADDY_ACTION28E_E_TEST_MODE=1 \
    /bin/bash "$outer" --test-registry "$registry_duplicate"
record_check typed_registry_altered_kind_rejected command_fails env CADDY_ACTION28E_E_TEST_MODE=1 \
    /bin/bash "$outer" --test-registry "$registry_altered_kind"
record_check typed_registry_altered_path_rejected command_fails env CADDY_ACTION28E_E_TEST_MODE=1 \
    /bin/bash "$outer" --test-registry "$registry_altered_path"
record_check typed_registry_altered_action_rejected command_fails env CADDY_ACTION28E_E_TEST_MODE=1 \
    /bin/bash "$outer" --test-registry "$registry_altered_action"
record_check finalized_pair_accepted run_case finalized 0 receiver_finalized sender_ready
record_check absent_pair_nonaccepted run_case absent 97 absent absent
record_check node_a_only_nonaccepted run_case node_a_only 97 absent sender_ready
record_check node_b_only_nonaccepted run_case node_b_only 97 receiver_finalized absent
record_check missing_label_rejected run_case missing_label 97 receiver_finalized sender_ready missing_label
record_check false_label_rejected run_case false_label 97 receiver_finalized sender_ready false_label
record_check duplicate_label_rejected run_case duplicate_label 97 receiver_finalized sender_ready duplicate_label
record_check reordered_labels_rejected run_case reordered 97 receiver_finalized sender_ready reordered_labels
record_check altered_manifest_rejected run_case altered_manifest 97 receiver_finalized sender_ready altered_manifest
record_check altered_historical_release_rejected run_case altered_historical_release 97 receiver_finalized sender_ready altered_historical_release
record_check altered_historical_payload_rejected run_case altered_historical_payload 97 receiver_finalized sender_ready altered_historical_payload
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
