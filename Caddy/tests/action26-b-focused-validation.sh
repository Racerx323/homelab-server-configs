#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_b_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly core=$caddy_root/scripts/run-workstation-wsl-ipv6-provenance-action26-b.sh
readonly outer=$caddy_root/scripts/run-workstation-wsl-ipv6-provenance-action26-b-outer.sh
readonly regression=$test_directory/action26-b-wsl-ipv6-provenance-regression.sh
readonly focused=$test_directory/action26-b-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-wsl-ipv6-provenance-action26-b.yaml
readonly core_sha256=dc60ed1f3a67aa5aed9919ddbbeda44378112d3fc34959e87dddbe0c56fb1440
readonly outer_sha256=a97e43703862f75132b7272d43db137b6e1b65daf92505835d97d2e7deb5b6b4
readonly regression_sha256=a3474dc05b69b8521945ce52613478092d81978fb7172d4a19fdc14bb498b015
readonly manifest_sha256=2e8a785078bfdd293139825134b2a6ff0d0f3832bf1284ff78d858c29aae1262

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action26b_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26b_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26b_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 26b' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    grep -Fq 'fd36:5aa8:6971:1::56' "$core" || return 1
    grep -Fq -- '-6 route get' "$core" || return 1
    grep -Fq '/etc/resolv.conf' "$core" || return 1
    grep -Fq 'dns_query: false' "$manifest" || return 1
    grep -Fq 'live_network_probe: false' "$manifest" || return 1
    ! grep -Eq '(^|[[:space:]])(ssh|scp|rsync|curl|dig|nslookup)([[:space:]]|$)' "$core"
}
no_live_execution_path() {
    # Dollar-prefixed expression is an intentional literal source check.
    # shellcheck disable=SC2016
    ! grep -Eq '^[[:space:]]*/bin/bash[[:space:]]+"?\$outer"?([[:space:]]|$)' "$0" || return 1
    ! grep -Eq '^[[:space:]]*(ip|sysctl|wslinfo)[[:space:]]' "$regression" "$0"
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
for action26b_focused_entrypoint in "$core" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action26b_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action26b_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_network_probe=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
