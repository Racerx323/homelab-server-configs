#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20m_a_retry_focused_validation
readonly builder_sha256=0722dc42584555fcc5b79db8a6ee7ca558043a85f885e698aad6b3c337798605
readonly outer_sha256=a13bd0710d07e55e43b3941dcd35bd115a88f98773716960ed85d42bf5354955
readonly source_outer_sha256=cc6d8179dbb85bb4411043854ad8dde17c6f212fbcc397eb9a748e56525d47fe
readonly generated_inspector_sha256=a40acf039a4be8a47a3deb786ed241baf0c305fd4f8b25c4224781646ffca1df
readonly generated_outer_sha256=aae1b12b8e7da596c549648c156fa1117095f429fe96f78871fe41ffd0455371
readonly generated_regression_sha256=93cb113f60d5b41c6bf880c50d4eff19c371800e0d6bfe42419a42e26953b763

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-b-keepalived-dbus-main-postinstall-action20m-a-retry.sh
readonly outer=$caddy_root/scripts/run-node-b-keepalived-dbus-main-postinstall-action20m-a-retry-outer.sh
readonly source_outer=$caddy_root/scripts/run-node-b-keepalived-dbus-main-postinstall-action20m-a-outer.sh
readonly cwd_policy=$test_directory/remote-streamed-bash-cwd-policy.sh
readonly cwd_precommit=$test_directory/remote-streamed-bash-cwd-precommit.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20ma_retry_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20ma_retry_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20ma_retry_focused_label" >&2
    return 1
}
validate_generated() {
    local action20ma_retry_focused_root=$1
    local action20ma_retry_focused_inspector=$action20ma_retry_focused_root/scripts/inspect-node-b-keepalived-dbus-main-postinstall-action20m-a.sh
    local action20ma_retry_focused_outer=$action20ma_retry_focused_root/scripts/run-node-b-keepalived-dbus-main-postinstall-action20m-a-retry-generated.sh
    local action20ma_retry_focused_regression=$action20ma_retry_focused_root/tests/action20m-a-retry-node-b-keepalived-dbus-main-postinstall-regression.sh

    # conditional-validator-explicit-failures-begin
    record_check generated_inspector_hash test \
        "$(file_hash "$action20ma_retry_focused_inspector")" = "$generated_inspector_sha256" || return 1
    record_check generated_outer_hash test \
        "$(file_hash "$action20ma_retry_focused_outer")" = "$generated_outer_sha256" || return 1
    record_check generated_regression_hash test \
        "$(file_hash "$action20ma_retry_focused_regression")" = "$generated_regression_sha256" || return 1
    record_check generated_syntax /bin/bash -n \
        "$action20ma_retry_focused_inspector" "$action20ma_retry_focused_outer" \
        "$action20ma_retry_focused_regression" || return 1
    record_check generated_shellcheck shellcheck \
        "$action20ma_retry_focused_inspector" "$action20ma_retry_focused_outer" \
        "$action20ma_retry_focused_regression" || return 1
    record_check generated_canonical_format shfmt -d -i 4 -ci \
        "$action20ma_retry_focused_inspector" "$action20ma_retry_focused_outer" \
        "$action20ma_retry_focused_regression" || return 1
    record_check generated_remote_cwd_policy /bin/bash "$cwd_policy" --check \
        "$action20ma_retry_focused_outer" || return 1
    record_check exact_root_transport grep -Fq \
        "'cd / && sudo -n /bin/bash -s --'" "$action20ma_retry_focused_outer" || return 1
    record_check bare_transport_absent test \
        "$(grep -Fc "'sudo -n /bin/bash -s'" "$action20ma_retry_focused_outer" || true)" -eq 0 || return 1
    record_check generated_regression env \
        CADDY_ACTION20MA_RETRY_SOURCE_ROOT="$caddy_root" \
        /bin/bash "$action20ma_retry_focused_regression" || return 1
    # conditional-validator-explicit-failures-end
    return 0
}
run_validation() (
    local action20ma_retry_focused_root
    local action20ma_retry_focused_generated

    action20ma_retry_focused_root=$(mktemp -d /tmp/caddy-action20m-a-retry-focused.XXXXXX) || return 1
    trap 'rm -rf -- "$action20ma_retry_focused_root"' EXIT
    action20ma_retry_focused_generated=$action20ma_retry_focused_root/generated

    record_check source_outer_immutable test \
        "$(file_hash "$source_outer")" = "$source_outer_sha256" || return 1
    record_check builder_hash test "$(file_hash "$builder")" = "$builder_sha256" || return 1
    record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256" || return 1
    record_check syntax /bin/bash -n "$builder" "$outer" "$cwd_policy" \
        "$cwd_precommit" "$0" || return 1
    record_check shellcheck shellcheck "$builder" "$outer" "$cwd_policy" \
        "$cwd_precommit" "$0" || return 1
    record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" \
        --check "$builder" "$outer" "$cwd_policy" "$cwd_precommit" "$0" || return 1
    record_check collision_policy /bin/bash \
        "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
        "$builder" "$outer" "$cwd_policy" "$cwd_precommit" "$0" || return 1
    record_check executable_policy /bin/bash \
        "$test_directory/executable-wrapper-policy-regression.sh" || return 1
    record_check outer_label_policy /bin/bash \
        "$test_directory/outer-local-gate-label-policy-regression.sh" \
        --runner "$outer" || return 1
    record_check conditional_policy /bin/bash \
        "$test_directory/conditional-validator-errexit-policy-regression.sh" || return 1
    record_check output_evidence_policy /bin/bash \
        "$test_directory/transaction-output-evidence-policy-regression.sh" || return 1
    record_check multifile_grep_policy /bin/bash \
        "$test_directory/multifile-grep-count-policy.sh" --check \
        "$builder" "$outer" "$cwd_policy" "$cwd_precommit" "$0" || return 1
    record_check portable_awk_policy /bin/bash \
        "$test_directory/portable-awk-policy.sh" --check \
        "$builder" "$outer" "$cwd_policy" "$cwd_precommit" "$0" || return 1
    record_check accepted_live_hash_policy /bin/bash \
        "$test_directory/accepted-live-hash-policy.sh" --check || return 1
    record_check remote_cwd_policy_self_test /bin/bash "$cwd_policy" --self-test || return 1
    record_check historical_exception_exact /bin/bash "$cwd_precommit" "$source_outer" || return 1
    record_check builder_self_test /bin/bash "$builder" --self-test || return 1
    record_check builder_generation /bin/bash "$builder" \
        --output "$action20ma_retry_focused_generated" || return 1
    validate_generated "$action20ma_retry_focused_generated" || return 1
    record_check outer_self_test /bin/bash "$outer" --self-test || return 1
    printf '%s_node_a_contacted=false\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_helper_execution=false\n' "$prefix"
    printf '%s_keepalived_reload=false\n' "$prefix"
    printf '%s_keepalived_restart=false\n' "$prefix"
    printf '%s_service_mutation=false\n' "$prefix"
    printf '%s_vrrp_mutation=false\n' "$prefix"
    printf '%s_vip_mutation=false\n' "$prefix"
    printf '%s_action_executed=false\n' "$prefix"
    printf '%s_persistent_live_mutations=false\n' "$prefix"
    printf '%s_complete_suite_bypassed=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
)

run_validation
