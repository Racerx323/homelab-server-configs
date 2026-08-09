#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_c_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly candidate=$caddy_root/configs/wsl/.wslconfig
readonly core=$caddy_root/scripts/install-workstation-wsl-mirrored-action26-c.sh
readonly outer=$caddy_root/scripts/run-workstation-wsl-mirrored-action26-c-outer.sh
readonly regression=$test_directory/action26-c-wsl-mirrored-regression.sh
readonly focused=$test_directory/action26-c-focused-validation.sh
readonly manifest=$caddy_root/manifests/wsl-ipv6-integration-action26-c.yaml
readonly candidate_sha256=6dffdf2bfc174eaca2a0bfcf8fe224929fd1006fbb48e3ccf34d642d234ab8a7
readonly core_sha256=04968f5408f65e7cf9e22947a1fcfe6cc861655da45617946e81f3cbb7ed03f9
readonly outer_sha256=2c02b10f4d8ef5dcee3a9d240d10aed33c1451a9bdd92b5677cc69cfdc685e99
readonly regression_sha256=785550cf587d438838439bb445a29f461afa814471464b550cab8e75bd58d382
readonly manifest_sha256=bcb08a892e6fa388c8a06b13ca143c11fbdd6774e2d76750920177fc3f269f3f

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action26c_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26c_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26c_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 26c' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    grep -Fqx '[wsl2]' "$candidate" || return 1
    grep -Fqx 'networkingMode=mirrored' "$candidate" || return 1
    test "$(wc -l <"$candidate")" -eq 2 || return 1
    grep -Fq 'wsl_shutdown: false' "$manifest" || return 1
    grep -Fq 'resolver_change: false' "$manifest" || return 1
    grep -Fq 'windows_firewall_change: false' "$manifest" || return 1
    ! grep -Eq 'wsl(\.exe)?[[:space:]]+--shutdown' "$core" || return 1
    ! grep -Eq 'resolv[.]conf|dnsTunneling|dnsProxy' "$core" || return 1
    ! grep -Eq '(^|[[:space:]])(ssh|scp|rsync|curl|dig)([[:space:]]|$)' "$core"
}
no_live_execution_path() {
    # Dollar-prefixed expression is an intentional literal source check.
    # shellcheck disable=SC2016
    ! grep -Eq '^[[:space:]]*/bin/bash[[:space:]]+"?\$outer"?([[:space:]]|$)' "$0"
}

record_check candidate_hash test "$(file_hash "$candidate")" = "$candidate_sha256"
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
for action26c_focused_entrypoint in "$core" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action26c_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action26c_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_network_probe=false\n' "$prefix"
printf '%s_wsl_shutdown=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
