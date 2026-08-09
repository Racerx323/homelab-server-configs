#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_23f_focused_validation
readonly driver_sha256=8bf33ff6fceb4128c7ca9ba51bc1f79c1df54d7d982c21e1b56b0c815862f96c
readonly outer_sha256=0ce6a2248abfa985fa5c70c6f8c7011e9bf24d5ec42133e7ccbb956541f59fb0
readonly regression_sha256=47f6c52651cff9f0c83bc93904d99bc2860a1ec5c4c2ae155abcc9f7d76a402a
readonly manifest_sha256=e24f67ead98e2d9b5eea1e85c1679138246482b7c8be2dbcf1053f061bd7ad70

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
repository_root=${caddy_root%/Caddy}
readonly repository_root
readonly driver=$caddy_root/scripts/apply-node-a-pihole-ptr-policy-action23f.sh
readonly outer=$caddy_root/scripts/run-node-a-pihole-ptr-policy-action23f-outer.sh
readonly regression=$test_directory/action23f-node-a-pihole-ptr-policy-regression.sh
readonly focused=$test_directory/action23f-focused-validation.sh
readonly manifest=$caddy_root/manifests/dns-action23f-pihole-ptr-policy.yaml

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action23f_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action23f_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23f_focused_label" >&2
    return 1
}
yaml_check() {
    # conditional-validator-explicit-failures-begin
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest" || return 1
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]] || return 1
    grep -Fqx -- '---' "$manifest" || return 1
    grep -Fqx 'action: 23f' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest" || return 1
    grep -Fqx '  rerun_permitted: false' "$manifest" || return 1
    grep -Fqx '  ftl_owner: pihole' "$manifest" || return 1
    grep -Fqx '  ftl_group: root' "$manifest" || return 1
    grep -Fqx '  ftl_mode: "0664"' "$manifest" || return 1
    grep -Fqx '  old_line: PIHOLE_PTR=HOSTNAMEFQDN' "$manifest" || return 1
    grep -Fqx '  new_line: PIHOLE_PTR=NONE' "$manifest" || return 1
    grep -Fqx '  required_domain_line: domain=local.theama.co' "$manifest" || return 1
    grep -Fqx '  definition_only: true' "$manifest" || return 1
    grep -Fqx '  node_contact_authorized: false' "$manifest" || return 1
    grep -Fqx '  live_mutation_authorized: false' "$manifest" || return 1
    # conditional-validator-explicit-failures-end
}
record_check driver_hash test "$(file_hash "$driver")" = "$driver_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$driver" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$driver" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$driver" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$driver" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash \
    "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$driver" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$driver" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash \
    "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check source_context /bin/bash \
    "$test_directory/run-source-test-in-context.sh" --runner "$outer"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check
record_check executable_policy /bin/bash \
    "$test_directory/executable-wrapper-policy-regression.sh"

for action23f_focused_entrypoint in "$driver" "$outer" "$regression" "$focused"; do
    record_check "index_mode_$(basename "$action23f_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action23f_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_action_23b_rerun=false\n' "$prefix"
printf '%s_action_23d_rerun=false\n' "$prefix"
printf '%s_action_23e_rerun=false\n' "$prefix"
printf '%s_action_23e_a_rerun=false\n' "$prefix"
printf '%s_action_23e_a_retry_rerun=false\n' "$prefix"
printf '%s_action_23e_a_retry2_rerun=false\n' "$prefix"
printf '%s_action_23f_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
