#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28e_d_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly runner=$caddy_root/scripts/run-action28e-c-historical-identity-consumer-correction.sh
readonly registry=$caddy_root/manifests/protocol-v2-historical-identities-action28e-d.tsv
readonly release_hash=81afa957c65b4f8a3f539b0018ebd700b0c926812f1b1e18b2ea7ade0be0e1b3
readonly payload_hash=f4dc87dab7075c4b20ed2acafb4969b757534bad49f5b47c85de4474d17175c8

work_root=$(mktemp -d /tmp/action28e-d-regression.XXXXXX)
readonly work_root
cleanup() {
    local action28e_d_regression_status=$?

    rm -rf -- "$work_root"
    exit "$action28e_d_regression_status"
}
trap cleanup EXIT

record_check() {
    local action28e_d_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28e_d_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28e_d_regression_label" >&2
    return 1
}
run_case() {
    local action28e_d_regression_name=$1
    local action28e_d_regression_expected_status=$2
    local action28e_d_regression_fixture=$work_root/$action28e_d_regression_name.tsv
    local action28e_d_regression_stdout=$work_root/$action28e_d_regression_name.stdout
    local action28e_d_regression_stderr=$work_root/$action28e_d_regression_name.stderr
    local action28e_d_regression_status=0

    CADDY_ACTION28E_D_TEST_MODE=1 /bin/bash "$runner" --test-registry \
        "$action28e_d_regression_fixture" >"$action28e_d_regression_stdout" \
        2>"$action28e_d_regression_stderr" || action28e_d_regression_status=$?
    [[ "$action28e_d_regression_status" -eq "$action28e_d_regression_expected_status" ]] || return 1
    if [[ "$action28e_d_regression_expected_status" -eq 0 ]]; then
        grep -Fqx "action_28e_d_value_release_manifest_observed_sha256=$release_hash" \
            "$action28e_d_regression_stdout" || return 1
        grep -Fqx "action_28e_d_value_payload_manifest_observed_sha256=$payload_hash" \
            "$action28e_d_regression_stdout" || return 1
        grep -Fqx 'action_28e_d_acceptance=true' "$action28e_d_regression_stdout" || return 1
        [[ ! -s "$action28e_d_regression_stderr" ]] || return 1
    fi
}

cp -- "$registry" "$work_root/valid.tsv"
for action28e_d_regression_case in swapped duplicate missing stale_release extra altered_path altered_evidence; do
    cp -- "$registry" "$work_root/$action28e_d_regression_case.tsv"
done
awk -F '\t' -v OFS='\t' -v release="$release_hash" -v payload="$payload_hash" '
    NR == 1 { print; next }
    $2 == "release_manifest" { $4 = payload }
    $2 == "payload_manifest" { $4 = release }
    { print }
' "$registry" >"$work_root/swapped.tsv"
sed -n '2p' "$registry" >>"$work_root/duplicate.tsv"
sed -i '2d' "$work_root/missing.tsv"
sed -i "s/$release_hash/$payload_hash/" "$work_root/stale_release.tsv"
printf '%s\t%s\t%s\t%s\t%s\n' \
    action17p-node-a-to-node-b-bootstrap release_manifest extra.json "$release_hash" 28e-c \
    >>"$work_root/extra.tsv"
sed -i 's/release-manifest[.]json/release_manifest.json/' "$work_root/altered_path.tsv"
sed -i 's/28e-c$/28e-b/' "$work_root/altered_evidence.tsv"

record_check runner_self_test /bin/bash "$runner" --self-test
record_check valid_mapping_accepted run_case valid 0
for action28e_d_regression_case in swapped duplicate missing stale_release extra altered_path altered_evidence; do
    record_check "${action28e_d_regression_case}_rejected" run_case \
        "$action28e_d_regression_case" 1
done
# The awk programs intentionally receive hashes through -v.
# shellcheck disable=SC2016
record_check release_kind_exact awk -F '\t' -v hash="$release_hash" '
    $1 == "action17p-node-a-to-node-b-bootstrap" && $2 == "release_manifest" &&
        $3 == "release-manifest.json" && $4 == hash && $5 == "28e-c" { found++ }
    END { exit found != 1 }
' "$registry"
# shellcheck disable=SC2016
record_check payload_kind_exact awk -F '\t' -v hash="$payload_hash" '
    $1 == "action17p-node-a-to-node-b-bootstrap" && $2 == "payload_manifest" &&
        $3 == "manifest.sha256" && $4 == hash && $5 == "28e-c" { found++ }
    END { exit found != 1 }
' "$registry"
record_check historical_artifacts_not_modified test \
    "$(grep -Fxc "readonly historical_manifest_sha256=$payload_hash" \
        "$caddy_root/scripts/inspect-protocol-v2-post-action28e-b.sh")" -eq 1

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_predecessor_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
