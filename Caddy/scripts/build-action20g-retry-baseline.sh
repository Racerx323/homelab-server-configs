#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20g_retry_baseline_builder
readonly source_builder_sha256=b23a75e6bd1b17803f79d2824065c58c7ed7f1b350593d50f6c86469e69929c3
readonly source_probe_sha256=aa86451cea27a257ff9b14ca10e774a6189e4859df3fcf9bb1449f889bff54e2
readonly source_runner_sha256=5c7d5b9c3732371b6b3e0b5422b7e1772f723887103f168d827fe1c95cac50a8
readonly old_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly node_a_health_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly node_b_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_builder=$script_directory/build-dual-node-caddy-postactivation-action20d-retry10-a-retry.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20g_retry_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20g_retry_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20g_retry_builder_label" >&2
    return 1
}
build_outputs() {
    local action20g_retry_output=$1
    local action20g_retry_source=$action20g_retry_output/source
    local action20g_retry_probe=$action20g_retry_output/inspect-dual-node-caddy-postactivation-action20g-retry.sh
    local action20g_retry_runner=$action20g_retry_output/run-dual-node-caddy-postactivation-action20g-retry.sh
    local action20g_retry_source_probe=$action20g_retry_source/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh
    local action20g_retry_source_runner=$action20g_retry_source/run-dual-node-caddy-postactivation-action20d-retry10-a.sh
    local action20g_retry_probe_hash

    record_check output_directory_regular test -d "$action20g_retry_output" || return 1
    record_check output_directory_not_symlink test ! -L "$action20g_retry_output" || return 1
    record_check source_builder_hash test "$(file_hash "$source_builder")" = "$source_builder_sha256" || return 1
    install -d -m 0700 "$action20g_retry_source"
    /bin/bash "$source_builder" --output "$action20g_retry_source" >/dev/null || return 1
    record_check source_probe_hash test "$(file_hash "$action20g_retry_source_probe")" = "$source_probe_sha256" || return 1
    record_check source_runner_hash test "$(file_hash "$action20g_retry_source_runner")" = "$source_runner_sha256" || return 1
    awk -v old_hash="$old_health_sha256" -v node_a_hash="$node_a_health_sha256" \
        -v node_b_hash="$node_b_health_sha256" '
        $0 == "readonly prefix=action_20d_retry10_a_retry_probe" {
            print "readonly prefix=action_20g_retry_baseline_probe"
            next
        }
        $0 == "readonly health_sha256=" old_hash {
            print "case \"${2:-}\" in"
            print "    node-a) readonly health_sha256=" node_a_hash " ;;"
            print "    node-b) readonly health_sha256=" node_b_hash " ;;"
            print "    *) readonly health_sha256=invalid ;;"
            print "esac"
            next
        }
        { print }
    ' "$action20g_retry_source_probe" >"$action20g_retry_probe"
    chmod 0700 "$action20g_retry_probe"
    action20g_retry_probe_hash=$(file_hash "$action20g_retry_probe") || return 1
    sed -e 's/action_20d_retry10_a_retry/action_20g_retry_baseline/g' \
        -e 's/inspect-dual-node-caddy-postactivation-action20d-retry10-a\.sh/inspect-dual-node-caddy-postactivation-action20g-retry.sh/g' \
        -e "s/readonly probe_sha256=$source_probe_sha256/readonly probe_sha256=$action20g_retry_probe_hash/" \
        "$action20g_retry_source_runner" >"$action20g_retry_runner"
    chmod 0700 "$action20g_retry_runner"
    rm -rf -- "$action20g_retry_source"
    record_check probe_syntax /bin/bash -n "$action20g_retry_probe" || return 1
    record_check runner_syntax /bin/bash -n "$action20g_retry_runner" || return 1
    record_check node_a_hash_once test "$(grep -Fxc \
        "    node-a) readonly health_sha256=$node_a_health_sha256 ;;" \
        "$action20g_retry_probe")" -eq 1 || return 1
    record_check node_b_hash_once test "$(grep -Fxc \
        "    node-b) readonly health_sha256=$node_b_health_sha256 ;;" \
        "$action20g_retry_probe")" -eq 1 || return 1
    record_check runner_probe_pin test "$(grep -Fxc \
        "readonly probe_sha256=$action20g_retry_probe_hash" \
        "$action20g_retry_runner")" -eq 1 || return 1
    record_check runner_probe_path test "$(grep -Fxc \
        "readonly probe=\$script_directory/inspect-dual-node-caddy-postactivation-action20g-retry.sh" \
        "$action20g_retry_runner")" -eq 1 || return 1
    record_check historical_health_record_absent test "$(grep -Fxc \
        "readonly health_sha256=$old_health_sha256" "$action20g_retry_probe" || true)" -eq 0 || return 1
    record_check probe_self_test /bin/bash "$action20g_retry_probe" --self-test || return 1
    record_check runner_self_test /bin/bash "$action20g_retry_runner" --self-test || return 1
    record_check runner_contract_test /bin/bash "$action20g_retry_runner" --contract-test || return 1
    printf '%s_probe_sha256=%s\n' "$prefix" "$action20g_retry_probe_hash"
    printf '%s_runner_sha256=%s\n' "$prefix" "$(file_hash "$action20g_retry_runner")"
    printf '%s_source_artifacts_unchanged=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        build_outputs "$2"
        ;;
    --self-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        action20g_retry_test_root=$(mktemp -d /tmp/caddy-action20g-retry-baseline.XXXXXX)
        readonly action20g_retry_test_root
        trap 'rm -rf -- "$action20g_retry_test_root"' EXIT
        install -d -m 0700 "$action20g_retry_test_root/output"
        build_outputs "$action20g_retry_test_root/output"
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test|--contract-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
