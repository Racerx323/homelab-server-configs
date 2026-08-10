#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28m_focused
readonly driver_sha256=6f4818fe31041f6eaefa0112390ce6e66444c19b241aa737ac9af5506760dc78
readonly inspector_sha256=0a3914e0ae77e3f8ac06e1c9147057a8c98f04a7d903e164b85b5598370b45a3
readonly transaction_outer_sha256=bfef273fc93a85543965901b137952543bd804d92c697eec3b3d1a267617a357
readonly acceptance_outer_sha256=b980d3057683fa241c600fa585c9abd31a8c2a46c00bd829b22e9171ecac2af4
readonly regression_sha256=a81f766d65a15f3e3ad8298ff4f38cb62726d6a86ed6b11d58df38629372da1e
readonly manifest_sha256=7525f9969951f9f799ca34978b9dacfe2d100194027ecceef3c82b0a6406324c
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
repository_root=${caddy_root%/Caddy}
readonly repository_root
readonly driver=$caddy_root/scripts/restore-node-a-caddy-service-action28m.sh
readonly inspector=$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-a.sh
readonly transaction_outer=$caddy_root/scripts/run-node-a-caddy-service-restoration-action28m-outer.sh
readonly acceptance_outer=$caddy_root/scripts/run-node-a-caddy-service-restoration-post-action28m-a-outer.sh
readonly regression=$test_directory/action28m-caddy-service-restoration-regression.sh
readonly focused=$test_directory/action28m-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-service-restoration-action28m.yaml

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
check() {
    local action28m_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28m_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28m_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest" || return 1
        return 0
    fi
    grep -Fqx 'action: 28m' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx '  execution: false' "$manifest"
}

check driver_hash test "$(file_hash "$driver")" = "$driver_sha256"
check inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256"
check transaction_outer_hash test "$(file_hash "$transaction_outer")" = "$transaction_outer_sha256"
check acceptance_outer_hash test "$(file_hash "$acceptance_outer")" = "$acceptance_outer_sha256"
check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
check syntax /bin/bash -n "$driver" "$inspector" "$transaction_outer" \
    "$acceptance_outer" "$regression" "$focused"
check shellcheck shellcheck "$driver" "$inspector" "$transaction_outer" \
    "$acceptance_outer" "$regression" "$focused"
check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$driver" "$inspector" "$transaction_outer" "$acceptance_outer" \
    "$regression" "$focused"
check yaml yaml_check
check regression /bin/bash "$regression"
check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$driver" "$inspector" "$transaction_outer" "$acceptance_outer" "$regression" "$focused"
check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$driver" "$inspector" "$transaction_outer" "$acceptance_outer" "$regression" "$focused"
check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$driver" "$inspector" "$transaction_outer" "$acceptance_outer" "$regression" "$focused"
check remote_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-policy.sh" --check \
    "$transaction_outer" "$acceptance_outer"

for action28m_focused_entrypoint in "$driver" "$inspector" "$transaction_outer" \
    "$acceptance_outer" "$regression" "$focused"; do
    check "index_mode_$(basename "$action28m_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action28m_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
