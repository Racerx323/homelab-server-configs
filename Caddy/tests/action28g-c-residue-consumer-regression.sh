#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28g_c_regression
readonly predecessor_outer_sha256=b30a7ec915004491d58f5e4cc94d45a697661559eb1bb250ba640f98ba84fef4
readonly residue_inspector_sha256=b4d5672ad87de72852683578df484991de02ce382242b2d7235b67c729fbdb26
readonly predecessor_regression_sha256=d05aeb367a0b150c45cdb5efb75068c8f049f1ca7f02f952ed5ab1fdb6000e71
readonly revision=20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63
readonly parent_revision=action16ar-retry-node-a-default-deny
readonly release_manifest_sha256=c72b5bc5a6586ac3be098c0c5ca2fc3dc01a09c2afe4dcf90ed4bdbda6d166de
readonly payload_manifest_sha256=fdc6ed955f14226ac3e1777eca37507cc8ab6ca16add3135dece9d6964e27568

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly predecessor_outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28g-b-outer.sh
readonly successor_outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28g-c-outer.sh
readonly residue_inspector=$caddy_root/scripts/inspect-protocol-v2-post-action28g-a-residue.sh
readonly predecessor_regression=$test_directory/action28g-b-assertion-output-regression.sh
work_root=$(mktemp -d /tmp/action28g-c-regression.XXXXXX)
readonly work_root

cleanup() {
    local action28g_c_regression_status=$?

    rm -rf -- "$work_root"
    exit "$action28g_c_regression_status"
}
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28g_c_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28g_c_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28g_c_regression_label" >&2
    return 1
}
command_fails() { ! "$@" >/dev/null 2>&1; }
validate_residue() {
    local action28g_c_regression_outer=$1
    local action28g_c_regression_transcript=$2
    local action28g_c_regression_stderr=$3

    CADDY_ACTION28G_B_TEST_MODE=1 /bin/bash "$action28g_c_regression_outer" \
        --test-residue node-b "$action28g_c_regression_transcript" \
        "$action28g_c_regression_stderr" 0
}

record_check predecessor_outer_immutable test \
    "$(file_hash "$predecessor_outer")" = "$predecessor_outer_sha256"
record_check residue_inspector_immutable test \
    "$(file_hash "$residue_inspector")" = "$residue_inspector_sha256"
record_check predecessor_regression_immutable test \
    "$(file_hash "$predecessor_regression")" = "$predecessor_regression_sha256"
record_check successor_old_prefix_absent test \
    "$(grep -Fc action_28g_b_residue "$successor_outer" || true)" -eq 0
record_check successor_producer_prefix_present test \
    "$(grep -Fc action_28g_a_residue "$successor_outer" || true)" -eq 23

/bin/bash "$residue_inspector" --expected-checks |
    sed 's/^/action_28g_a_residue_check_/; s/$/=true/' >"$work_root/node-b-residue.stdout"
residue_count=$(/bin/bash "$residue_inspector" --expected-checks | wc -l)
readonly residue_count
printf '%s\n' \
    'action_28g_a_residue_value_role=node-b' \
    "action_28g_a_residue_value_revision=$revision" \
    "action_28g_a_residue_value_parent_revision=$parent_revision" \
    "action_28g_a_residue_value_release_manifest_sha256=$release_manifest_sha256" \
    "action_28g_a_residue_value_payload_manifest_sha256=$payload_manifest_sha256" \
    'action_28g_a_residue_value_snapshot_sha256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' \
    "action_28g_a_residue_check_count=$residue_count" \
    'action_28g_a_residue_failed_check_count=0' \
    'action_28g_a_residue_first_failure=none' \
    'action_28g_a_residue_filesystem_mutations=false' \
    'action_28g_a_residue_service_mutations=false' \
    'action_28g_a_residue_cleanup_executed=false' \
    'action_28g_a_residue_acceptance=true' >>"$work_root/node-b-residue.stdout"
: >"$work_root/empty.stderr"

record_check real_producer_inventory_accepted validate_residue \
    "$successor_outer" "$work_root/node-b-residue.stdout" "$work_root/empty.stderr"
record_check predecessor_prefix_rejected command_fails validate_residue \
    "$predecessor_outer" "$work_root/node-b-residue.stdout" "$work_root/empty.stderr"
sed '0,/=true/s//=false/' "$work_root/node-b-residue.stdout" >"$work_root/false.stdout"
record_check false_real_producer_assertion_rejected command_fails validate_residue \
    "$successor_outer" "$work_root/false.stdout" "$work_root/empty.stderr"

record_check predecessor_contract_preserved /bin/bash "$predecessor_regression"

cat >"$work_root/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${ACTION28G_C_CALL_LOG:?}"
exit 70
FAKE_SSH
chmod 0755 "$work_root/ssh"
: >"$work_root/calls"
production_status=0
ACTION28G_C_CALL_LOG=$work_root/calls \
    CADDY_ACTION28G_B_REGRESSION_INTERCEPT=1 \
    CADDY_ACTION28G_B_SSH_BINARY=$work_root/ssh \
    /bin/bash "$successor_outer" >"$work_root/production.stdout" \
    2>"$work_root/production.stderr" || production_status=$?
record_check intercepted_production_nonzero test "$production_status" -ne 0
record_check node_b_main_first grep -Fxq -- \
    '-T -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co pi@10.1.0.54 cd / && sudo -n /bin/bash -s -- node-b' \
    "$work_root/calls"
record_check production_stops_after_first_ssh test "$(wc -l <"$work_root/calls")" -eq 1
record_check predecessors_not_invoked test \
    "$(grep -Ec 'run-dual-node-protocol-v2-post-action28g-[ab]-outer[.]sh' "$successor_outer" || true)" -eq 0

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_predecessor_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
