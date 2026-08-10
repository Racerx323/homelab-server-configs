#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28g_regression
readonly builder_sha256=c0fb743b4901e061c48363749d7200eff616935740e83ba60f272858d2efac2f
readonly source_runner_sha256=9eebe135098792bb8a5f1bbbbfa4a7f6a1e13bf1cfc89be411b22ef4ed45b7ec
readonly generated_runner_sha256=6fe5f82c4960fabf240cf647672a37e6b71f0961ad81e4d2e7351435b89b05cf
readonly driver_sha256=23a36fda7fa4087026678d10305b3d61cd1d4e1193c154d1a68b3ba3c4a700aa
readonly inspector_sha256=3260a3d52884ab141f26356ebecd2699f611dac359d1f921c96a2037234bc906

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly builder=$caddy_root/scripts/build-node-a-to-node-b-retained-release-action28g.sh
readonly source_runner=$caddy_root/scripts/run-node-a-to-node-b-retained-release-action28f.sh
readonly driver=$caddy_root/scripts/transfer-retained-node-a-release-action28f.sh
readonly inspector=$caddy_root/scripts/inspect-node-b-incoming-release-action28f.sh
work_root=$(mktemp -d /tmp/caddy-action28g-regression.XXXXXX)
readonly work_root

cleanup() {
    local action28g_regression_status=$?
    rm -rf -- "$work_root"
    exit "$action28g_regression_status"
}
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28g_regression_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28g_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28g_regression_label" >&2
    return 1
}

record_check builder_hash_exact test "$(file_hash "$builder")" = "$builder_sha256"
record_check source_runner_hash_exact test "$(file_hash "$source_runner")" = "$source_runner_sha256"
record_check driver_hash_exact test "$(file_hash "$driver")" = "$driver_sha256"
record_check inspector_hash_exact test "$(file_hash "$inspector")" = "$inspector_sha256"

readonly generated_runner=$work_root/run-node-a-to-node-b-retained-release-action28g.sh
/bin/bash "$builder" "$generated_runner" >"$work_root/build.out"
cp -- "$driver" "$work_root/transfer-retained-node-a-release-action28f.sh"
cp -- "$inspector" "$work_root/inspect-node-b-incoming-release-action28f.sh"
chmod 0755 "$work_root"/*.sh

record_check generated_runner_hash_exact test \
    "$(file_hash "$generated_runner")" = "$generated_runner_sha256"
record_check generated_runner_syntax /bin/bash -n "$generated_runner"
record_check builder_reports_three_expectations grep -Fxq \
    'action_28g_builder_corrected_identity_expectations=3' "$work_root/build.out"
record_check builder_reports_real_producer_coverage grep -Fxq \
    'action_28g_builder_real_producer_contract_coverage=true' "$work_root/build.out"
# This literal generated-source expression is the contract under test.
# shellcheck disable=SC2016
record_check node_a_preflight_uses_candidate_identity test \
    "$(grep -Fc '[[ "$transcript_prefix" == action_28f_node_b && "$expected_phase" == preflight ]]' "$generated_runner")" -eq 3
record_check source_runner_preserved test \
    "$(file_hash "$source_runner")" = "$source_runner_sha256"

contract_status=0
CADDY_ACTION28F_CADDY_ROOT=$caddy_root /bin/bash "$generated_runner" \
    --contract-test >"$work_root/contract.out" 2>"$work_root/contract.err" ||
    contract_status=$?
record_check contract_status_zero test "$contract_status" -eq 0
record_check contract_stderr_empty test ! -s "$work_root/contract.err"
record_check real_node_a_label_inventory_accepted grep -Fxq \
    'action_28f_false_negative_valid_transcript_accepted=true' "$work_root/contract.out"
record_check node_b_unavailable_identity_accepted grep -Fxq \
    'action_28g_node_b_preflight_unavailable_identity_accepted=true' "$work_root/contract.out"
record_check node_a_revision_unavailable_rejected grep -Fxq \
    'action_28g_node_a_preflight_revision_unavailable_rejected=true' "$work_root/contract.out"
record_check node_a_parent_unavailable_rejected grep -Fxq \
    'action_28g_node_a_preflight_parent_revision_unavailable_rejected=true' "$work_root/contract.out"
record_check node_a_manifest_unavailable_rejected grep -Fxq \
    'action_28g_node_a_preflight_manifest_sha256_unavailable_rejected=true' "$work_root/contract.out"
record_check node_b_candidate_identity_rejected grep -Fxq \
    'action_28g_node_b_preflight_candidate_identity_rejected=true' "$work_root/contract.out"
record_check false_assertion_rejected grep -Fxq \
    'action_28f_false_positive_failed_assertion_rejected=true' "$work_root/contract.out"
record_check duplicate_value_rejected grep -Fxq \
    'action_28f_false_positive_duplicate_value_rejected=true' "$work_root/contract.out"
record_check unmatched_line_rejected grep -Fxq \
    'action_28f_false_positive_unmatched_line_rejected=true' "$work_root/contract.out"

cat >"$work_root/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${ACTION28G_CALL_LOG:?}"
exit 70
FAKE_SSH
chmod 0755 "$work_root/ssh"
: >"$work_root/calls"
production_status=0
ACTION28G_CALL_LOG=$work_root/calls \
    CADDY_ACTION28F_CADDY_ROOT=$caddy_root \
    CADDY_ACTION28F_SSH_BINARY=$work_root/ssh \
    /bin/bash "$generated_runner" >"$work_root/production.out" \
    2>"$work_root/production.err" || production_status=$?
record_check intercepted_production_rejected test "$production_status" -ne 0
record_check node_b_preflight_first grep -Fxq -- \
    '-T -o BatchMode=yes -o ConnectTimeout=5 -o HostKeyAlias=pihole00.local.theama.co -o StrictHostKeyChecking=yes pi@10.1.0.54 cd / && sudo -n /bin/bash -s -- --preflight' \
    "$work_root/calls"
record_check no_second_ssh test "$(wc -l <"$work_root/calls")" -eq 1
record_check no_publication_before_preflight_failure test \
    "$(grep -Ec 'publication_started=true|--transfer|--complete' "$work_root/production.out" || true)" -eq 0

printf '%s_complete=true\n' "$prefix"
