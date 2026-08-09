#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_25_focused_validation
readonly inspector_sha256=7b9e1f6425ad4ed9975f66e6e0bbc85b8c79d32b9a9d0aa96c7d7b151beeaf68
readonly outer_sha256=cbb583bbb80b73825a3c97c8468a7d34c20f7eac31eb6f2229c4895950a77b24
readonly regression_sha256=43723f281fb91e3103ecce3cc44e6e002a7efbf3c2578ccc8732fe03e31df874
readonly manifest_sha256=590bb1facdac0d9d309d68028503442a8a4bb839a56299c671f0dc8652267b87
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-dual-node-pihole-web-access-action25.sh
readonly outer=$caddy_root/scripts/run-dual-node-pihole-web-access-action25-outer.sh
readonly regression=$test_directory/action25-dual-node-pihole-web-access-regression.sh
readonly focused=$test_directory/action25-focused-validation.sh
readonly manifest=$caddy_root/manifests/web-access-action25.yaml

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action25_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action25_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action25_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return 0
    fi
    grep -Fqx 'action: 25' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
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
for action25_focused_entrypoint in "$inspector" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action25_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action25_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_http_probe_executed=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
