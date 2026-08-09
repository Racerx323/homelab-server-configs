#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_23e_a_focused_validation
readonly inspector_sha256=ac2855a9d9d77438720ef0f072e1adacf1feb4cb21c31fbb06116dc9c60659f4
readonly outer_sha256=b865eff6e816f403d8e6a41297bd733fa2e2fca8ba283f5b8b53269396259514
readonly regression_sha256=023660761e137360e5b5bc47d1d3eef75be564f9366011892e0677d20d5dce10
readonly manifest_sha256=5aa2d2b1b203eaca051be49c62bb79a574b2e7aeba817cbdaede2c7a59abd3a7

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
repository_root=${caddy_root%/Caddy}
readonly repository_root
readonly inspector=$caddy_root/scripts/inspect-node-a-pihole-ptr-postchange-action23e-a.sh
readonly outer=$caddy_root/scripts/run-node-a-pihole-ptr-postchange-action23e-a-outer.sh
readonly regression=$test_directory/action23e-a-node-a-postchange-regression.sh
readonly focused=$test_directory/action23e-a-focused-validation.sh
readonly manifest=$caddy_root/manifests/dns-action23e-a-postchange-acceptance.yaml

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action23ea_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action23ea_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23ea_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]] || return 1
    grep -Fqx -- '---' "$manifest" || return 1
    grep -Fqx 'action: 23e-a' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest" || return 1
    grep -Fqx 'mode: read-only' "$manifest" || return 1
    grep -Fqx '  ftl_owner: pihole' "$manifest" || return 1
    grep -Fqx '  ftl_group: root' "$manifest" || return 1
    grep -Fqx '  ftl_mode: "0664"' "$manifest" || return 1
    grep -Fqx '  ptr_policy: PIHOLE_PTR=HOSTNAMEFQDN' "$manifest" || return 1
    grep -Fqx '  obsolete_extensionless_state: absent' "$manifest" || return 1
    grep -Fqx '  action23e_backup_state: absent' "$manifest" || return 1
    grep -Fqx '  action23e_transaction_state: absent' "$manifest" || return 1
    grep -Fqx '  definition_only: true' "$manifest" || return 1
    grep -Fqx '  node_contact_authorized: false' "$manifest" || return 1
    grep -Fqx '  live_mutation_authorized: false' "$manifest" || return 1
}
read_only_contract() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|pihole[[:space:]]+restartdns|(^|[[:space:]])(install|mv|rm)[[:space:]]' \
        "$inspector"
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
record_check inspector_self_test /bin/bash "$inspector" --self-test
record_check read_only_contract read_only_contract
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$inspector" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash \
    "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash \
    "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check source_context /bin/bash \
    "$test_directory/run-source-test-in-context.sh" --runner "$outer"
record_check executable_policy /bin/bash \
    "$test_directory/executable-wrapper-policy-regression.sh"

for action23ea_focused_entrypoint in "$inspector" "$outer" "$regression" "$focused"; do
    record_check "index_mode_$(basename "$action23ea_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action23ea_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_23b_rerun=false\n' "$prefix"
printf '%s_action_23e_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
