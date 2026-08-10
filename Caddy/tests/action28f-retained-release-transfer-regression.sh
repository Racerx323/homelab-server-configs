#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28f_regression
readonly driver_sha256=23a36fda7fa4087026678d10305b3d61cd1d4e1193c154d1a68b3ba3c4a700aa
readonly inspector_sha256=3260a3d52884ab141f26356ebecd2699f611dac359d1f921c96a2037234bc906
readonly runner_sha256=9eebe135098792bb8a5f1bbbbfa4a7f6a1e13bf1cfc89be411b22ef4ed45b7ec
readonly predecessor_outer_sha256=f7e397e28cae312c57ff0d30b782ea3e3ce927715cf04ad0a891b0073618cb6c

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly driver=$caddy_root/scripts/transfer-retained-node-a-release-action28f.sh
readonly inspector=$caddy_root/scripts/inspect-node-b-incoming-release-action28f.sh
readonly runner=$caddy_root/scripts/run-node-a-to-node-b-retained-release-action28f.sh
readonly predecessor_outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28e-e-outer.sh
readonly collision_policy=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional_policy=$test_directory/conditional-validator-errexit-policy-regression.sh
work_root=$(mktemp -d /tmp/caddy-action28f-regression.XXXXXX)
readonly work_root

cleanup() {
    local action28f_regression_status=$?
    rm -rf -- "$work_root"
    exit "$action28f_regression_status"
}
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28f_regression_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28f_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28f_regression_label" >&2
    return 1
}
remote_delete_tokens_absent() {
    ! grep -Eq 'rsync.*(--delete|--remove-source-files)|ssh.*[[:space:]]rm[[:space:]]' "$1"
}

record_check driver_hash_exact test "$(file_hash "$driver")" = "$driver_sha256"
record_check inspector_hash_exact test "$(file_hash "$inspector")" = "$inspector_sha256"
record_check runner_hash_exact test "$(file_hash "$runner")" = "$runner_sha256"
record_check predecessor_immutable test "$(file_hash "$predecessor_outer")" = "$predecessor_outer_sha256"
record_check driver_syntax /bin/bash -n "$driver"
record_check inspector_syntax /bin/bash -n "$inspector"
record_check runner_syntax /bin/bash -n "$runner"
record_check driver_collision_policy "$collision_policy" "$driver"
record_check inspector_collision_policy "$collision_policy" "$inspector"
record_check runner_collision_policy "$collision_policy" "$runner"
record_check conditional_policy "$conditional_policy"
record_check retained_revision_pinned grep -Fq \
    '20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63' "$driver"
record_check retained_tree_pinned grep -Fq \
    'ad5bf3781d8c45eb1c6153aca85766ca58dd65ab06c825041f0d8014f3f3244b' "$driver"
record_check publisher_absent test \
    "$(grep -Ec 'publish-release|protocol-v2-publisher|publication_started=true' "$driver" || true)" -eq 0
# The literal shell source is the contract under test.
# shellcheck disable=SC2016
record_check exact_source_bound_transport grep -Fq \
    '"$candidate_release" "caddy-sync@$node_b_fqdn:/"' "$driver"
record_check receiver_finalization_only grep -Fq \
    'caddy-sync-release-receiver-v2 --source-role node-a' "$inspector"
record_check remote_delete_absent remote_delete_tokens_absent "$driver"
record_check exact_remote_cwd grep -Fq \
    'cd / && sudo -n /bin/bash -s --' "$runner"
record_check producer_labels_exported test \
    "$($driver --expected-checks transfer | wc -l)" -gt 40
record_check inspector_labels_exported test \
    "$($inspector --expected-checks complete | wc -l)" -gt 40

contract_stdout=$work_root/contract.out
contract_stderr=$work_root/contract.err
contract_status=0
CADDY_ACTION28F_CADDY_ROOT=$caddy_root /bin/bash "$runner" --contract-test \
    >"$contract_stdout" 2>"$contract_stderr" || contract_status=$?
record_check contract_status_zero test "$contract_status" -eq 0
record_check contract_stderr_empty test ! -s "$contract_stderr"
record_check unmatched_line_rejected grep -Fxq \
    'action_28f_false_positive_unmatched_line_rejected=true' "$contract_stdout"
record_check false_assertion_rejected grep -Fxq \
    'action_28f_false_positive_failed_assertion_rejected=true' "$contract_stdout"
record_check duplicate_value_rejected grep -Fxq \
    'action_28f_false_positive_duplicate_value_rejected=true' "$contract_stdout"

cat >"$work_root/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${ACTION28F_CALL_LOG:?}"
exit 70
EOF
chmod 0755 "$work_root/ssh"
: >"$work_root/calls"
production_status=0
ACTION28F_CALL_LOG=$work_root/calls \
    CADDY_ACTION28F_CADDY_ROOT=$caddy_root \
    CADDY_ACTION28F_SSH_BINARY=$work_root/ssh \
    /bin/bash "$runner" >"$work_root/production.out" \
    2>"$work_root/production.err" || production_status=$?
record_check intercepted_production_rejected test "$production_status" -ne 0
record_check node_b_preflight_first grep -Fxq -- \
    '-T -o BatchMode=yes -o ConnectTimeout=5 -o HostKeyAlias=pihole00.local.theama.co -o StrictHostKeyChecking=yes pi@10.1.0.54 cd / && sudo -n /bin/bash -s -- --preflight' \
    "$work_root/calls"
record_check no_second_ssh test "$(wc -l <"$work_root/calls")" -eq 1

printf '%s_complete=true\n' "$prefix"
