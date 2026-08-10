#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28g_b_regression
readonly builder_sha256=09f988d332c6ddae7d268ee6de6690bf7e100fbc512f49f9322b307eb24c791e
readonly source_inspector_sha256=96b159653883c5a67ae384b1129ce619f2e74f0b44c4846da1d44ae898cd96d9
readonly corrected_inspector_sha256=8f0258c07cd1f75f9f0af0fe8a47b295ef8afc229da6952d65d9ba1fff2dea59
readonly predecessor_regression_sha256=a99bc920ed0c66106bf5e3318fdc2a052998d04b68193aac54fd5e0bbbe503d9

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly builder=$caddy_root/scripts/build-protocol-v2-post-action28g-b-inspector.sh
readonly source_inspector=$caddy_root/scripts/inspect-protocol-v2-post-action28e-e.sh
readonly corrected_inspector=$caddy_root/scripts/inspect-protocol-v2-post-action28g-b.sh
readonly predecessor_regression=$test_directory/action28g-a-dual-node-post-execution-regression.sh
readonly outer=$caddy_root/scripts/run-dual-node-protocol-v2-post-action28g-b-outer.sh
work_root=$(mktemp -d /tmp/action28g-b-regression.XXXXXX)
readonly work_root

cleanup() {
    local action28g_b_regression_status=$?

    rm -rf -- "$work_root"
    exit "$action28g_b_regression_status"
}
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28g_b_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28g_b_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28g_b_regression_label" >&2
    return 1
}
record_check builder_hash_exact test "$(file_hash "$builder")" = "$builder_sha256"
record_check source_inspector_immutable test "$(file_hash "$source_inspector")" = "$source_inspector_sha256"
record_check corrected_inspector_hash_exact test "$(file_hash "$corrected_inspector")" = "$corrected_inspector_sha256"
record_check predecessor_regression_immutable test \
    "$(file_hash "$predecessor_regression")" = "$predecessor_regression_sha256"

/bin/bash "$builder" "$work_root/generated-inspector" >"$work_root/build.stdout" 2>"$work_root/build.stderr"
record_check builder_stderr_empty test ! -s "$work_root/build.stderr"
record_check generated_matches_tracked cmp -s "$work_root/generated-inspector" "$corrected_inspector"

printf '%s\n' \
    '{"revision":"r","parent_revision":"p","source_node":"node-a","created_at":"t"}' \
    >"$work_root/valid.json"
valid_status=0
CADDY_ACTION28G_B_TEST_MODE=1 /bin/bash "$corrected_inspector" \
    --test-assertion-output "$work_root/valid.json" \
    >"$work_root/valid.stdout" 2>"$work_root/valid.stderr" || valid_status=$?
record_check production_jq_status_zero test "$valid_status" -eq 0
record_check production_jq_stdout_exact test \
    "$(wc -l <"$work_root/valid.stdout")" -eq 1
record_check production_jq_label_exact grep -Fxq \
    'action_28e_e_check_candidate_manifest_schema=true' "$work_root/valid.stdout"
record_check production_jq_unlabeled_true_absent test \
    "$(grep -Fxc true "$work_root/valid.stdout" || true)" -eq 0
record_check production_jq_stderr_empty test ! -s "$work_root/valid.stderr"

printf '%s\n' \
    '{"revision":"r","parent_revision":"p","source_node":"node-b","created_at":"t"}' \
    >"$work_root/invalid.json"
invalid_status=0
CADDY_ACTION28G_B_TEST_MODE=1 /bin/bash "$corrected_inspector" \
    --test-assertion-output "$work_root/invalid.json" \
    >"$work_root/invalid.stdout" 2>"$work_root/invalid.stderr" || invalid_status=$?
record_check production_jq_failure_nonzero test "$invalid_status" -ne 0
record_check production_jq_failure_stdout_empty test ! -s "$work_root/invalid.stdout"
record_check production_jq_failure_check_labeled grep -Fxq \
    'action_28e_e_check_candidate_manifest_schema=false' "$work_root/invalid.stderr"
record_check production_jq_failure_label_labeled grep -Fxq \
    'action_28e_e_failed_check=candidate_manifest_schema' "$work_root/invalid.stderr"
record_check production_jq_failure_stderr_exact test \
    "$(wc -l <"$work_root/invalid.stderr")" -eq 2

record_check predecessor_consumer_contract /bin/bash "$predecessor_regression"
record_check predecessor_environment_names_absent test \
    "$(grep -Fc 'CADDY_ACTION28G_A_' "$outer" || true)" -eq 0
record_check successor_environment_names_present test \
    "$(grep -Fc 'CADDY_ACTION28G_B_' "$outer" || true)" -eq 6

cat >"$work_root/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${ACTION28G_B_CALL_LOG:?}"
exit 70
FAKE_SSH
chmod 0755 "$work_root/ssh"
: >"$work_root/calls"
production_status=0
ACTION28G_B_CALL_LOG=$work_root/calls \
    CADDY_ACTION28G_B_REGRESSION_INTERCEPT=1 \
    CADDY_ACTION28G_B_SSH_BINARY=$work_root/ssh \
    /bin/bash "$outer" >"$work_root/production.stdout" \
    2>"$work_root/production.stderr" || production_status=$?
record_check intercepted_production_nonzero test "$production_status" -ne 0
record_check corrected_inspector_is_production_payload grep -Fq \
    'inspect-protocol-v2-post-action28g-b.sh' "$outer"
record_check node_b_main_first grep -Fxq -- \
    '-T -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes -o HostKeyAlias=pihole00.local.theama.co pi@10.1.0.54 cd / && sudo -n /bin/bash -s -- node-b' \
    "$work_root/calls"
record_check production_stops_after_first_ssh test "$(wc -l <"$work_root/calls")" -eq 1
record_check action28g_a_not_invoked test \
    "$(grep -Ec 'run-dual-node-protocol-v2-post-action28g-a-outer[.]sh' "$outer" || true)" -eq 0

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28g_a_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
