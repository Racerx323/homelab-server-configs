#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_c_a_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly core=$caddy_root/scripts/inspect-workstation-wsl-mirrored-postinstall-action26-c-a.sh
readonly outer=$caddy_root/scripts/run-workstation-wsl-mirrored-postinstall-action26-c-a-outer.sh
readonly regression=$test_directory/action26-c-a-postinstall-regression.sh
readonly focused=$test_directory/action26-c-a-focused-validation.sh
readonly manifest=$caddy_root/manifests/wsl-ipv6-integration-action26-c-a.yaml
readonly core_sha256=43411248fe9f36d43383dc3fa6a21e483da2703a4d38703954d8230b1f22a76e
readonly outer_sha256=f2a8b14d08b6783b170192fd9a3da3484f7046d5868d464d62b7ccfb5bbbcb90
readonly regression_sha256=de81141e6813366b2953cb43f8b425a73a4450ad3761e13cddf98ac62c5d374c
readonly manifest_sha256=46d92d2ad046fb22097f60d9be1ead100cf105ca8b8943e23371ce4c3c45fd80

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action26ca_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26ca_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26ca_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 26c-a' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    grep -Fq '/mnt/c/Users/aaron/.wslconfig' "$core" || return 1
    grep -Fq '/home/aaron/.local/state/caddy-ha/action26c-wsl-mirrored' "$core" || return 1
    grep -Fq '/mnt/wsl/resolv.conf' "$core" || return 1
    grep -Fq 'expected_running_mode: nat' "$manifest" || return 1
    grep -Fq 'persistent_mutation: false' "$manifest" || return 1
    ! grep -Eq 'wsl(\.exe)?[[:space:]]+--shutdown' "$core" || return 1
    ! grep -Eq '(^|[[:space:]])(ssh|scp|rsync|curl|dig)([[:space:]]|$)' "$core"
}
no_live_execution_path() {
    # Dollar-prefixed expression is an intentional literal source check.
    # shellcheck disable=SC2016
    ! grep -Eq '^[[:space:]]*/bin/bash[[:space:]]+"?\$outer"?([[:space:]]|$)' "$0" || return 1
    ! grep -Eq '^[[:space:]]*(ip|wslinfo)[[:space:]]' "$regression" "$0"
}

record_check core_hash test "$(file_hash "$core")" = "$core_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$core" "$outer" "$regression" "$0"
record_check shellcheck shellcheck "$core" "$outer" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$core" "$outer" "$regression" "$0"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check contract contract_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$core" "$outer" "$regression" "$0"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$core" "$outer" "$regression" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$core" "$outer" "$regression" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
record_check outer_gate_inventory_unique test \
    "$("$outer" --expected-local-gates | wc -l)" -eq \
    "$("$outer" --expected-local-gates | LC_ALL=C sort -u | wc -l)"
record_check no_live_execution_path no_live_execution_path
for action26ca_focused_entrypoint in "$core" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action26ca_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action26ca_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_network_probe=false\n' "$prefix"
printf '%s_wsl_shutdown=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
