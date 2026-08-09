#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_25_retry_focused_validation
readonly inspector_sha256=bd28ca220ad7d64893ca85707c9f5ae57fbeb145db2bc5f63a43df489214d8a3
readonly outer_sha256=6b2897fbddcfa1212a1ca296c328095a3b10f76027513cd8ce75aaebe7e48fb2
readonly regression_sha256=9db0470dfab852a005d77d5a61c3a9933b855acceee2ff125cb3d76f3edb25a4
readonly manifest_sha256=42467c143908c157a4e647945de37bc801aa4971439a47dc715f0b67c4a3a31f
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-dual-node-pihole-web-access-action25-retry.sh
readonly outer=$caddy_root/scripts/run-dual-node-pihole-web-access-action25-retry-outer.sh
readonly regression=$test_directory/action25-retry-observed-response-regression.sh
readonly focused=$test_directory/action25-retry-focused-validation.sh
readonly manifest=$caddy_root/manifests/web-access-action25-retry.yaml

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action25_retry_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action25_retry_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action25_retry_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return 0
    fi
    grep -Fqx 'action: 25-retry' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
observed_before_evaluation_check() {
    local action25_retry_focused_observed_line
    local action25_retry_focused_evaluated_line

    action25_retry_focused_observed_line=$(grep -nF \
        "observed_%s_http_code=%s" "$inspector" | head -n 1 | cut -d: -f1) || return 1
    action25_retry_focused_evaluated_line=$(grep -nF \
        "check \"\${action25_endpoint_label}_http_200\"" "$inspector" | head -n 1 | cut -d: -f1) || return 1
    test -n "$action25_retry_focused_observed_line" || return 1
    test -n "$action25_retry_focused_evaluated_line" || return 1
    test "$action25_retry_focused_observed_line" -lt "$action25_retry_focused_evaluated_line"
}

record_check inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$inspector" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$inspector" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check outer_self_test /bin/bash "$outer" --self-test
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$inspector" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check outer_gate_inventory_unique test \
    "$("$outer" --expected-local-gates | wc -l)" -eq \
    "$("$outer" --expected-local-gates | LC_ALL=C sort -u | wc -l)"
record_check observed_before_evaluation_contract observed_before_evaluation_check
record_check non200_production_regression grep -Fq \
    'CADDY_ACTION25_RETRY_FAKE_HTTP_CODE=403' "$regression"
for action25_retry_focused_entrypoint in "$inspector" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action25_retry_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action25_retry_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_http_probe_executed=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
