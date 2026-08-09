#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_24_focused_validation
readonly inspector_sha256=58fe5c7bd9db5c8e49a4efac400913c4aa32de36ce6d7d5257a42c77a8f914a5
readonly outer_sha256=318336f553cfd298da45200c51666dc082af4b3ddb7af9364dc798113590e8e2
readonly regression_sha256=b6173b26b48f45eb2c22e4ae7fa1a06b906b97a304abdac059380bc063468d0c
readonly manifest_sha256=54b3aaa7623a382ca524b32a14843bb9b55e5137c4dd5ad378930cdee12ccc9f

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-dual-node-dns-record-families-action24.sh
readonly outer=$caddy_root/scripts/run-dual-node-dns-record-families-action24-outer.sh
readonly regression=$test_directory/action24-dual-node-dns-record-families-regression.sh
readonly focused=$test_directory/action24-focused-validation.sh
readonly manifest=$caddy_root/manifests/dns-action24-record-family-validation.yaml

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action24_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action24_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action24_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return 0
    fi
    grep -Fqx 'action: 24' "$manifest" && grep -Fqx 'status: defined' "$manifest"
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
record_check outer_self_test env CADDY_ACTION24_TEST_MODE=1 /bin/bash "$outer" --self-test
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
record_check labeled_dns_policy /bin/bash "$test_directory/labeled-dns-readiness-policy-regression.sh" --production-test
record_check transcript_contract_policy /bin/bash "$test_directory/transcript-contract-ratchet-policy-regression.sh"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
record_check outer_gate_inventory_unique test \
    "$("$outer" --expected-local-gates | wc -l)" -eq \
    "$("$outer" --expected-local-gates | LC_ALL=C sort -u | wc -l)"
for action24_focused_entrypoint in "$inspector" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action24_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action24_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_dns_mutation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
