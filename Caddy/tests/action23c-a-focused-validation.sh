#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_23c_a_focused_validation
readonly inspector_sha256=8060fe05a26ef41210930beb06dec083d89c1afe862556612cb75c0f3c78f64b
readonly outer_sha256=58e1e58c7375aa179959907fc368542e52e8616a14fdce354382f0f659eb969d
readonly regression_sha256=a32ce36a97451ed9bd7dab6b638af3450f5b3b2002bf408ab7c6d71e982a34cd
readonly manifest_sha256=a1a37e16620cd8a7893b6ffd0a54fb3a2d5b2ee106a08bb2371b6d741e3492f9

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
repository_root=${caddy_root%/Caddy}
readonly repository_root
readonly inspector=$caddy_root/scripts/inspect-node-b-pihole-ptr-postfailure-action23c-a.sh
readonly outer=$caddy_root/scripts/run-node-b-pihole-ptr-postfailure-action23c-a-outer.sh
readonly regression=$test_directory/action23c-a-node-b-postfailure-regression.sh
readonly focused=$test_directory/action23c-a-focused-validation.sh
readonly manifest=$caddy_root/manifests/dns-action23c-a-postfailure-diagnostic.yaml

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action23ca_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action23ca_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23ca_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return 0
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" == 1 ]] || return 1
    grep -Fqx -- '---' "$manifest" || return 1
    grep -Fqx 'action: 23c-a' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest" || return 1
    grep -Fqx 'mode: read-only' "$manifest" || return 1
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

for action23ca_focused_entrypoint in "$inspector" "$outer" "$regression" "$focused"; do
    record_check "index_mode_$(basename "$action23ca_focused_entrypoint" | tr '.-' '__')" \
        test "$(git -C "$repository_root" ls-files --stage -- \
            "Caddy/${action23ca_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_23c_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
