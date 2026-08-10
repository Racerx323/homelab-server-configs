#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28s_install_focused
readonly transaction_sha256=40649ef09d9b63be9094e29d132a14d55379e0c578e1a69eff18e0d8f4e80178
readonly outer_sha256=c54d09b9f06908bc7c520db8c3d0cca57d36cfa5c8c07a8ca7b92d4a9ae60c2c
readonly regression_sha256=175b38d4e41cdd93143e4f3d44917ffc701488b90ff5fb0cb943ae95daee86a7
readonly manifest_sha256=40f3f69b75dc097e724a2c7ea2adfc12f7f5db3ad0a02cb5e1f0e7399afda610
readonly architecture_manifest_sha256=77977bfbfa5194436c3a8d574c878af5398c7f33631298f9d1f780fc0d7b21cd
readonly source_sha256=034ee9c45acaca4e48e2faeda24cd371e945bdb52a117b5871403958ab36794c
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly workspace_root=${repository_root%/homelab-server-configs}
readonly transaction=$caddy_root/scripts/install-node-b-protocol-compatible-coupling-action28s.sh
readonly outer=$caddy_root/scripts/run-node-b-protocol-compatible-coupling-action28s-outer.sh
readonly regression=$test_directory/action28s-node-b-installation-regression.sh
readonly focused=$test_directory/action28s-node-b-installation-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-node-b-protocol-compatible-coupling-action28s.yaml
readonly architecture_manifest=$caddy_root/manifests/caddy-protocol-compatible-coupling-action28s.yaml
readonly source_configuration=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
readonly plan=$caddy_root/docs/caddy_plan-v1.1.md

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
check() {
    local action28s_install_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28s_install_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28s_install_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest" "$architecture_manifest" || return 1
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
    grep -Fqx 'action: 28s' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest" || return 1
    grep -Fqx '  execution: false' "$manifest"
}

check transaction_hash test "$(file_hash "$transaction")" = "$transaction_sha256"
check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
check architecture_manifest_hash test \
    "$(file_hash "$architecture_manifest")" = "$architecture_manifest_sha256"
check source_hash test "$(file_hash "$source_configuration")" = "$source_sha256"
check syntax /bin/bash -n "$transaction" "$outer" "$regression" "$focused"
check shellcheck shellcheck "$transaction" "$outer" "$regression" "$focused"
check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$transaction" "$outer" "$regression" "$focused"
check yaml yaml_check
check transaction_self_test "$transaction" --self-test
check outer_self_test "$outer" --self-test
check regression /bin/bash "$regression"
check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$transaction" "$outer" "$regression" "$focused"
check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
check multifile_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" \
    --check "$transaction" "$outer" "$regression" "$focused"
check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" \
    --check "$transaction" "$outer" "$regression" "$focused"
check root_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-precommit.sh" "$outer"
check ssh_evidence_policy /bin/bash "$test_directory/ssh-stream-local-evidence-policy.sh" --check "$outer"
check outer_labels /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
check plan_gate grep -Fq "Action 28s once using outer SHA-256 \`$outer_sha256\`" "$plan"
for action28s_install_focused_entrypoint in "$transaction" "$outer" "$regression" "$focused"; do
    check "executable_$(basename "$action28s_install_focused_entrypoint" | tr '.-' '__')" \
        test -x "$action28s_install_focused_entrypoint"
    check "index_mode_$(basename "$action28s_install_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action28s_install_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
