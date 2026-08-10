#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28s_focused
readonly regression_sha256=1b73f26b188270ed60b6337baec2b2ca1a60e6ea5bc9ddfcfcba2d3a5aeb8538
readonly manifest_sha256=77977bfbfa5194436c3a8d574c878af5398c7f33631298f9d1f780fc0d7b21cd
readonly template_sha256=c9b66dcfbe6cb015ea16ad9e865831ec23317f2bc3d71bdc3be73c42f88737b1
readonly node_a_sha256=d8f96c4f018f90370aea38fc3ef932af649158f6edc99cc7e95dea1edff4908a
readonly node_b_sha256=034ee9c45acaca4e48e2faeda24cd371e945bdb52a117b5871403958ab36794c
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly workspace_root=${repository_root%/homelab-server-configs}
readonly regression=$test_directory/action28s-protocol-compatible-coupling-regression.sh
readonly focused=$test_directory/action28s-focused-validation.sh
readonly manifest=$caddy_root/manifests/caddy-protocol-compatible-coupling-action28s.yaml
readonly template=$caddy_root/templates/keepalived-caddy-ha-v2.conf.in
readonly node_a=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
readonly node_b=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
readonly plan=$caddy_root/docs/caddy_plan-v1.1.md

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
check() {
    local action28s_focused_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28s_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28s_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$manifest" || return 1
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
    grep -Fqx -- '---' "$manifest" || return 1
    grep -Fqx 'action: 28s' "$manifest" || return 1
    grep -Fqx '  execution: false' "$manifest"
}

check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
check template_hash test "$(file_hash "$template")" = "$template_sha256"
check node_a_hash test "$(file_hash "$node_a")" = "$node_a_sha256"
check node_b_hash test "$(file_hash "$node_b")" = "$node_b_sha256"
check syntax /bin/bash -n "$regression" "$focused"
check shellcheck shellcheck "$regression" "$focused"
check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check "$regression" "$focused"
check yaml yaml_check
check regression /bin/bash "$regression"
check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$regression" "$focused"
check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
check multifile_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" \
    --check "$regression" "$focused"
check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" \
    --check "$regression" "$focused"
check plan_gate grep -Fq 'Protocol-compatible Caddy-to-DNS ownership correction Action 28s' "$plan"
for action28s_focused_entrypoint in "$regression" "$focused"; do
    check "executable_$(basename "$action28s_focused_entrypoint" | tr '.-' '__')" \
        test -x "$action28s_focused_entrypoint"
    check "index_mode_$(basename "$action28s_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action28s_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
