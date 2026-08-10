#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28g_a_regression
readonly main_inspector_sha256=96b159653883c5a67ae384b1129ce619f2e74f0b44c4846da1d44ae898cd96d9
readonly action28g_outer_sha256=ffc572b7c84d76288f293af814cfe917dc52128f878509ca160c5fd2d6bd2642
readonly revision=20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63
readonly parent_revision=action16ar-retry-node-a-default-deny
readonly release_manifest_sha256=c72b5bc5a6586ac3be098c0c5ca2fc3dc01a09c2afe4dcf90ed4bdbda6d166de
readonly payload_manifest_sha256=fdc6ed955f14226ac3e1777eca37507cc8ab6ca16add3135dece9d6964e27568
readonly historical_release_manifest_sha256=81afa957c65b4f8a3f539b0018ebd700b0c926812f1b1e18b2ea7ade0be0e1b3
readonly historical_payload_manifest_sha256=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8
readonly historical_node_a_tree_sha256=dc6f4359cd6f0f424f2db89b180d63d5478f0de36c344e406c707340b57ceb37
# shellcheck disable=SC2016 # Intentional literal production-source assertion.
readonly action28g_hash_check_line='    run_gate action28g_outer_immutable require_source "$action28g_outer" "$action28g_outer_sha256" || return 1'
# shellcheck disable=SC2016 # Intentional literal production-source assertion.
readonly action28g_invocation_pattern='/bin/bash[[:space:]]+"?\$action28g_outer|run_remote.*action28g_outer'

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly main_inspector=$caddy_root/scripts/inspect-protocol-v2-post-action28e-e.sh
readonly residue_inspector=$caddy_root/scripts/inspect-protocol-v2-post-action28g-a-residue.sh
readonly outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28g-a-outer.sh
readonly action28g_outer=$caddy_root/scripts/run-node-a-to-node-b-retained-release-action28g-outer.sh
work_root=$(mktemp -d /tmp/action28g-a-regression.XXXXXX)
readonly work_root

cleanup() {
    local action28g_a_regression_status=$?

    rm -rf -- "$work_root"
    exit "$action28g_a_regression_status"
}
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28g_a_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28g_a_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28g_a_regression_label" >&2
    return 1
}
command_fails() { ! "$@" >/dev/null 2>&1; }
make_main_transcript() {
    local action28g_a_regression_role=$1
    local action28g_a_regression_output=$2
    local action28g_a_regression_state=sender_ready
    local action28g_a_regression_complete=absent
    local action28g_a_regression_tree=$historical_node_a_tree_sha256
    local action28g_a_regression_count

    if [[ "$action28g_a_regression_role" == node-b ]]; then
        action28g_a_regression_state=receiver_finalized
        action28g_a_regression_complete=regular_empty
        action28g_a_regression_tree=not_applicable
    fi
    /bin/bash "$main_inspector" --expected-checks |
        sed 's/^/action_28e_e_check_/; s/$/=true/' >"$action28g_a_regression_output"
    action28g_a_regression_count=$(/bin/bash "$main_inspector" --expected-checks | wc -l)
    printf '%s\n' \
        "action_28e_e_value_historical_release_manifest_expected_sha256=$historical_release_manifest_sha256" \
        "action_28e_e_value_historical_release_manifest_observed_sha256=$historical_release_manifest_sha256" \
        "action_28e_e_value_historical_payload_manifest_expected_sha256=$historical_payload_manifest_sha256" \
        "action_28e_e_value_historical_payload_manifest_observed_sha256=$historical_payload_manifest_sha256" \
        "action_28e_e_value_historical_tree_expected_sha256=$action28g_a_regression_tree" \
        "action_28e_e_value_historical_tree_observed_sha256=$action28g_a_regression_tree" \
        "action_28e_e_value_role=$action28g_a_regression_role" \
        'action_28e_e_value_candidate_count=1' \
        "action_28e_e_value_candidate_state=$action28g_a_regression_state" \
        "action_28e_e_value_candidate_revision=$revision" \
        "action_28e_e_value_candidate_parent=$parent_revision" \
        "action_28e_e_value_candidate_manifest_sha256=$release_manifest_sha256" \
        "action_28e_e_value_candidate_payload_manifest_sha256=$payload_manifest_sha256" \
        'action_28e_e_value_candidate_tree_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
        'action_28e_e_value_candidate_metadata=994:990:550:4096:1786304072' \
        'action_28e_e_value_candidate_request_state=regular_empty' \
        "action_28e_e_value_candidate_complete_state=$action28g_a_regression_complete" \
        'action_28e_e_value_candidate_pending_state=absent' \
        'action_28e_e_value_snapshot_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
        "action_28e_e_check_count=$action28g_a_regression_count" \
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
        'action_28e_e_acceptance=true' >>"$action28g_a_regression_output"
}
make_residue_transcript() {
    local action28g_a_regression_role=$1
    local action28g_a_regression_output=$2
    local action28g_a_regression_count

    /bin/bash "$residue_inspector" --expected-checks |
        sed 's/^/action_28g_a_residue_check_/; s/$/=true/' >"$action28g_a_regression_output"
    action28g_a_regression_count=$(/bin/bash "$residue_inspector" --expected-checks | wc -l)
    printf '%s\n' \
        "action_28g_a_residue_value_role=$action28g_a_regression_role" \
        "action_28g_a_residue_value_revision=$revision" \
        "action_28g_a_residue_value_parent_revision=$parent_revision" \
        "action_28g_a_residue_value_release_manifest_sha256=$release_manifest_sha256" \
        "action_28g_a_residue_value_payload_manifest_sha256=$payload_manifest_sha256" \
        'action_28g_a_residue_value_snapshot_sha256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
        "action_28g_a_residue_check_count=$action28g_a_regression_count" \
        'action_28g_a_residue_failed_check_count=0' \
        'action_28g_a_residue_first_failure=none' \
        'action_28g_a_residue_filesystem_mutations=false' \
        'action_28g_a_residue_service_mutations=false' \
        'action_28g_a_residue_cleanup_executed=false' \
        'action_28g_a_residue_acceptance=true' >>"$action28g_a_regression_output"
}
validate_main_fixture() {
    local action28g_a_regression_role=$1
    local action28g_a_regression_stdout=$2
    local action28g_a_regression_stderr=$3

    CADDY_ACTION28G_A_TEST_MODE=1 /bin/bash "$outer" --test-main \
        "$action28g_a_regression_role" "$action28g_a_regression_stdout" \
        "$action28g_a_regression_stderr" 0
}
validate_residue_fixture() {
    local action28g_a_regression_role=$1
    local action28g_a_regression_stdout=$2
    local action28g_a_regression_stderr=$3

    CADDY_ACTION28G_A_TEST_MODE=1 /bin/bash "$outer" --test-residue \
        "$action28g_a_regression_role" "$action28g_a_regression_stdout" \
        "$action28g_a_regression_stderr" 0
}

record_check main_inspector_immutable test "$(file_hash "$main_inspector")" = "$main_inspector_sha256"
record_check action28g_outer_immutable test "$(file_hash "$action28g_outer")" = "$action28g_outer_sha256"
record_check main_inspector_inventory_unique test \
    "$(/bin/bash "$main_inspector" --expected-checks | wc -l)" -eq \
    "$(/bin/bash "$main_inspector" --expected-checks | LC_ALL=C sort -u | wc -l)"
record_check residue_inspector_inventory_unique test \
    "$(/bin/bash "$residue_inspector" --expected-checks | wc -l)" -eq \
    "$(/bin/bash "$residue_inspector" --expected-checks | LC_ALL=C sort -u | wc -l)"

make_main_transcript node-b "$work_root/node-b-main"
make_main_transcript node-a "$work_root/node-a-main"
make_residue_transcript node-b "$work_root/node-b-residue"
make_residue_transcript node-a "$work_root/node-a-residue"
: >"$work_root/empty.stderr"

record_check node_b_main_valid validate_main_fixture node-b "$work_root/node-b-main" "$work_root/empty.stderr"
record_check node_a_main_valid validate_main_fixture node-a "$work_root/node-a-main" "$work_root/empty.stderr"
record_check node_b_residue_valid validate_residue_fixture node-b "$work_root/node-b-residue" "$work_root/empty.stderr"
record_check node_a_residue_valid validate_residue_fixture node-a "$work_root/node-a-residue" "$work_root/empty.stderr"
record_check finalized_pair_valid env CADDY_ACTION28G_A_TEST_MODE=1 /bin/bash "$outer" \
    --test-pair "$work_root/node-b-main" "$work_root/node-a-main"

for action28g_a_regression_field in \
    candidate_revision candidate_parent candidate_manifest_sha256 \
    candidate_payload_manifest_sha256; do
    sed "s/^action_28e_e_value_${action28g_a_regression_field}=.*/action_28e_e_value_${action28g_a_regression_field}=wrong/" \
        "$work_root/node-b-main" >"$work_root/main-wrong-${action28g_a_regression_field}"
    record_check "wrong_${action28g_a_regression_field}_rejected" command_fails \
        validate_main_fixture node-b "$work_root/main-wrong-${action28g_a_regression_field}" \
        "$work_root/empty.stderr"
done

sed '1d' "$work_root/node-b-main" >"$work_root/main-missing"
record_check main_missing_label_rejected command_fails \
    validate_main_fixture node-b "$work_root/main-missing" "$work_root/empty.stderr"
sed '1{h;d};2{G}' "$work_root/node-b-main" >"$work_root/main-reordered"
record_check main_reordered_label_rejected command_fails \
    validate_main_fixture node-b "$work_root/main-reordered" "$work_root/empty.stderr"
sed '0,/=true/s//=false/' "$work_root/node-b-main" >"$work_root/main-false"
record_check main_false_label_rejected command_fails \
    validate_main_fixture node-b "$work_root/main-false" "$work_root/empty.stderr"
cp -- "$work_root/node-b-main" "$work_root/main-extra"
printf 'unexpected=true\n' >>"$work_root/main-extra"
record_check main_extra_line_rejected command_fails \
    validate_main_fixture node-b "$work_root/main-extra" "$work_root/empty.stderr"
printf 'bounded stderr\n' >"$work_root/nonempty.stderr"
record_check main_stderr_rejected command_fails \
    validate_main_fixture node-b "$work_root/node-b-main" "$work_root/nonempty.stderr"

sed 's/^action_28g_a_residue_check_release_root_entry_count_exact=true$/action_28g_a_residue_check_release_root_entry_count_exact=false/' \
    "$work_root/node-b-residue" >"$work_root/residue-false"
record_check residue_false_assertion_rejected command_fails \
    validate_residue_fixture node-b "$work_root/residue-false" "$work_root/empty.stderr"
sed 's/^action_28g_a_residue_value_revision=.*/action_28g_a_residue_value_revision=wrong/' \
    "$work_root/node-b-residue" >"$work_root/residue-wrong-revision"
record_check residue_wrong_revision_rejected command_fails \
    validate_residue_fixture node-b "$work_root/residue-wrong-revision" "$work_root/empty.stderr"
sed 's/^action_28g_a_residue_filesystem_mutations=false$/action_28g_a_residue_filesystem_mutations=true/' \
    "$work_root/node-b-residue" >"$work_root/residue-mutation"
record_check residue_mutation_rejected command_fails \
    validate_residue_fixture node-b "$work_root/residue-mutation" "$work_root/empty.stderr"
cp -- "$work_root/node-b-residue" "$work_root/residue-extra"
printf 'unexpected=true\n' >>"$work_root/residue-extra"
record_check residue_extra_line_rejected command_fails \
    validate_residue_fixture node-b "$work_root/residue-extra" "$work_root/empty.stderr"

cat >"$work_root/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${ACTION28G_A_CALL_LOG:?}"
exit 70
FAKE_SSH
chmod 0755 "$work_root/ssh"
: >"$work_root/calls"
production_status=0
ACTION28G_A_CALL_LOG=$work_root/calls \
    CADDY_ACTION28G_A_REGRESSION_INTERCEPT=1 \
    CADDY_ACTION28G_A_SSH_BINARY=$work_root/ssh \
    /bin/bash "$outer" >"$work_root/production.stdout" \
    2>"$work_root/production.stderr" || production_status=$?
record_check production_intercept_nonzero test "$production_status" -ne 0
record_check node_b_main_first grep -Fxq -- \
    '-T -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co pi@10.1.0.54 cd / && sudo -n /bin/bash -s -- node-b' \
    "$work_root/calls"
record_check production_stops_after_first_ssh test "$(wc -l <"$work_root/calls")" -eq 1
record_check action28g_only_hash_checked test \
    "$(grep -Fxc "$action28g_hash_check_line" \
        "$outer" || true)" -eq 1
record_check action28g_not_invoked test \
    "$(grep -Ec "$action28g_invocation_pattern" "$outer" || true)" -eq 0
record_check main_inspector_mutating_commands_absent test \
    "$(grep -Ec 'systemctl[[:space:]]+(reload|restart|start|stop)|rsync[[:space:]]' \
        "$main_inspector" || true)" -eq 0
record_check residue_inspector_mutating_commands_absent test \
    "$(grep -Ec 'systemctl[[:space:]]+(reload|restart|start|stop)|rsync[[:space:]]' \
        "$residue_inspector" || true)" -eq 0

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28g_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
