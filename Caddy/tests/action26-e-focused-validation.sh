#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_e_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly core=$caddy_root/scripts/inspect-workstation-wsl-mirrored-postrestart-action26-d.sh
readonly outer=$caddy_root/scripts/run-workstation-wsl-mirrored-postrestart-action26-e-outer.sh
readonly regression=$test_directory/action26-e-postrestart-regression.sh
readonly focused=$test_directory/action26-e-focused-validation.sh
readonly manifest=$caddy_root/manifests/wsl-ipv6-integration-action26-e.yaml
readonly core_sha256=c28daa30a7b127d8d6b4ca9e669564350367695e8be4986112b4478d37d23a1d
readonly outer_sha256=d5ecf40a30450962ef7ce79f4cce02331f53a4c924650518208808adf86b8133
readonly regression_sha256=658ff062a8ae194b1b9988469a7333190cc21eee92e1807831632a9cd2392c0c
readonly manifest_sha256=8cc03bce0a87accd15c349b232f2205be76e3741fb924a7152474b672cccaa73

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action26e_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26e_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26e_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 26e' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    grep -Fq 'failed_activation_action: 26d' "$manifest" || return 1
    grep -Fq 'action26d_shutdown_executed: false' "$manifest" || return 1
    grep -Fq 'networking_mode: mirrored' "$manifest" || return 1
    grep -Fq "selected_ula_source: 'fd36:5aa8:6971:1:3856:ef8b:d838:254c'" \
        "$manifest" || return 1
    grep -Fq 'resolver_sha256: 9e0e2f98735e119102ea8b675021e263fa6a226c8dc6c09b127dfebf16ca4bd5' \
        "$manifest" || return 1
    grep -Fq 'caddy_vip_https_probe: true' "$manifest" || return 1
    grep -Fq 'wsl_shutdown: false' "$manifest" || return 1
    grep -Fq 'windows_process_launch: false' "$manifest" || return 1
    ! grep -Eq 'wsl(\.exe)?[[:space:]]+--shutdown|Invoke-WorkstationWslMirroredActivationAction26d' \
        "$outer" "$regression" || return 1
    ! grep -Eq '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' "$core" "$outer" "$regression"
}
no_live_execution_path() {
    # Dollar-prefixed expression is an intentional literal source check.
    # shellcheck disable=SC2016
    ! grep -Eq '^[[:space:]]*/bin/bash[[:space:]]+"?\$outer"?([[:space:]]|$)' "$0" || return 1
    ! grep -Eq '^[[:space:]]*(wslinfo|ip|dig|curl)[[:space:]]' "$0"
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
record_check outer_self_test /bin/bash "$outer" --self-test
record_check contract contract_check
record_check core_check_count test "$("$outer" --expected-core-checks | wc -l)" -eq 39
record_check core_check_inventory_unique test \
    "$("$outer" --expected-core-checks | wc -l)" -eq \
    "$("$outer" --expected-core-checks | LC_ALL=C sort -u | wc -l)"
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
record_check no_live_execution_path no_live_execution_path
for action26e_focused_entrypoint in "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action26e_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action26e_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_wsl_shutdown=false\n' "$prefix"
printf '%s_live_network_probe=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
