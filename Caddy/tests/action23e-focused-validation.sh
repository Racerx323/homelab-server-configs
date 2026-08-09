#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_23e_focused_validation
readonly driver_sha256=eac76f543d34dcbca908774c2586b2e8679fde5675c6f8773e45b389af3231d7
readonly outer_sha256=02504457fbba70b412a7af0ca9ac8f532f090873a66ddee10ee6e5578ca5379e
readonly regression_sha256=cdd2c3f2d5c1c13f9feebd4b4235b51e67d56d3cc52c96503f9e6a2507201be5
readonly manifest_sha256=42541e35aeccdee35e7d68e8dd8e49eaca798da6065e691c00623fbada9773a3

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
repository_root=${caddy_root%/Caddy}
readonly repository_root
readonly driver=$caddy_root/scripts/apply-node-a-pihole-ptr-policy-action23e.sh
readonly outer=$caddy_root/scripts/run-node-a-pihole-ptr-policy-action23e-outer.sh
readonly regression=$test_directory/action23e-node-a-pihole-ptr-policy-regression.sh
readonly focused=$test_directory/action23e-focused-validation.sh
readonly manifest=$caddy_root/manifests/dns-action23e-pihole-ptr-policy.yaml

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action23e_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action23e_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23e_focused_label" >&2
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
    grep -Fqx 'action: 23e' "$manifest" || return 1
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

for action23e_focused_entrypoint in "$driver" "$outer" "$regression" "$focused"; do
    record_check "index_mode_$(basename "$action23e_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action23e_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_action_23b_rerun=false\n' "$prefix"
printf '%s_action_23d_rerun=false\n' "$prefix"
printf '%s_action_23e_executed=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
