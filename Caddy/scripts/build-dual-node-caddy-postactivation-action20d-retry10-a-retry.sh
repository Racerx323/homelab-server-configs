#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_a_retry_builder
readonly historical_probe_sha256=564380f2753950716612518fbbedbd43c7461d33e0695b0d3c2162b70f30fb84
readonly historical_runner_sha256=f9006403f30644b58a96474979aa8c88083ca14ad79ba97e77c4185e5de7e978
readonly node_a_environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly node_b_environment_sha256=f692d5b7e0a7e0f0ab142e36face6a8cc8c6680a44a2bcaf6a992247ec4c8113
readonly historical_probe_prefix_record='readonly prefix=action_20d_retry10_a_probe'
readonly corrected_probe_prefix_record='readonly prefix=action_20d_retry10_a_retry_probe'
readonly historical_runner_prefix_record='readonly prefix=action_20d_retry10_a'
readonly corrected_runner_prefix_record='readonly prefix=action_20d_retry10_a_retry'
readonly historical_environment_record="readonly environment_sha256=$node_a_environment_sha256"

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly historical_probe=$script_directory/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh
readonly historical_runner=$script_directory/run-dual-node-caddy-postactivation-action20d-retry10-a.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$check_label" >&2
    return 1
}
require_historical_sources() {
    record_check historical_probe_regular test -f "$historical_probe" || return 1
    record_check historical_probe_not_symlink test ! -L "$historical_probe" || return 1
    record_check historical_probe_executable test -x "$historical_probe" || return 1
    record_check historical_runner_regular test -f "$historical_runner" || return 1
    record_check historical_runner_not_symlink test ! -L "$historical_runner" || return 1
    record_check historical_runner_executable test -x "$historical_runner" || return 1
    record_check historical_probe_hash_exact test \
        "$(file_hash "$historical_probe")" = "$historical_probe_sha256" || return 1
    record_check historical_runner_hash_exact test \
        "$(file_hash "$historical_runner")" = "$historical_runner_sha256" || return 1
    record_check historical_probe_prefix_once test \
        "$(grep -Fxc "$historical_probe_prefix_record" "$historical_probe")" -eq 1 || return 1
    record_check historical_probe_environment_once test \
        "$(grep -Fxc "$historical_environment_record" "$historical_probe")" -eq 1 || return 1
    record_check historical_runner_prefix_once test \
        "$(grep -Fxc "$historical_runner_prefix_record" "$historical_runner")" -eq 1 || return 1
    record_check historical_runner_probe_pin_once test \
        "$(grep -Fxc "readonly probe_sha256=$historical_probe_sha256" \
            "$historical_runner")" -eq 1
}
build_probe() {
    local output_probe=$1

    awk -v historical_prefix="$historical_probe_prefix_record" \
        -v corrected_prefix="$corrected_probe_prefix_record" \
        -v historical_environment="$historical_environment_record" \
        -v node_a_hash="$node_a_environment_sha256" \
        -v node_b_hash="$node_b_environment_sha256" '
        $0 == historical_prefix {
            print corrected_prefix
            next
        }
        $0 == historical_environment {
            print "case \"${2:-}\" in"
            print "    node-a) readonly environment_sha256=" node_a_hash " ;;"
            print "    node-b) readonly environment_sha256=" node_b_hash " ;;"
            print "    *) readonly environment_sha256=invalid ;;"
            print "esac"
            next
        }
        { print }
    ' "$historical_probe" >"$output_probe"
    chmod 0700 "$output_probe"
}
build_runner() {
    local corrected_probe_hash=$1
    local output_runner=$2

    sed \
        -e 's/action_20d_retry10_a/action_20d_retry10_a_retry/g' \
        -e "s/readonly probe_sha256=$historical_probe_sha256/readonly probe_sha256=$corrected_probe_hash/" \
        "$historical_runner" >"$output_runner"
    chmod 0700 "$output_runner"
}
validate_outputs() {
    local output_probe=$1
    local output_runner=$2
    local corrected_probe_hash

    corrected_probe_hash=$(file_hash "$output_probe") || return 1
    record_check output_probe_regular test -f "$output_probe" || return 1
    record_check output_probe_not_symlink test ! -L "$output_probe" || return 1
    record_check output_probe_executable test -x "$output_probe" || return 1
    record_check output_runner_regular test -f "$output_runner" || return 1
    record_check output_runner_not_symlink test ! -L "$output_runner" || return 1
    record_check output_runner_executable test -x "$output_runner" || return 1
    record_check output_probe_mode_exact test "$(stat -c '%a' "$output_probe")" = 700 || return 1
    record_check output_runner_mode_exact test "$(stat -c '%a' "$output_runner")" = 700 || return 1
    record_check output_probe_corrected_prefix_once test \
        "$(grep -Fxc "$corrected_probe_prefix_record" "$output_probe")" -eq 1 || return 1
    record_check output_runner_corrected_prefix_once test \
        "$(grep -Fxc "$corrected_runner_prefix_record" "$output_runner")" -eq 1 || return 1
    record_check output_probe_node_a_hash_once test \
        "$(grep -Fxc "    node-a) readonly environment_sha256=$node_a_environment_sha256 ;;" \
            "$output_probe")" -eq 1 || return 1
    record_check output_probe_node_b_hash_once test \
        "$(grep -Fxc "    node-b) readonly environment_sha256=$node_b_environment_sha256 ;;" \
            "$output_probe")" -eq 1 || return 1
    record_check output_runner_probe_pin_once test \
        "$(grep -Fxc "readonly probe_sha256=$corrected_probe_hash" \
            "$output_runner")" -eq 1 || return 1
    record_check output_probe_corrected_label_count test \
        "$(grep -Fc action_20d_retry10_a_retry "$output_probe")" -eq 1 || return 1
    record_check output_runner_corrected_labels_present test \
        "$(grep -Fc action_20d_retry10_a_retry "$output_runner")" -gt 1 || return 1
    record_check output_probe_historical_prefix_absent test \
        "$(grep -Fxc "$historical_probe_prefix_record" "$output_probe" || true)" -eq 0 || return 1
    record_check output_runner_historical_prefix_absent test \
        "$(grep -Fxc "$historical_runner_prefix_record" "$output_runner" || true)" -eq 0 || return 1
    record_check output_syntax /bin/bash -n "$output_probe" "$output_runner" || return 1
    record_check output_probe_self_test /bin/bash "$output_probe" --self-test || return 1
    record_check output_runner_self_test /bin/bash "$output_runner" --self-test || return 1
    record_check output_runner_contract_test /bin/bash "$output_runner" --contract-test
}
build_outputs() {
    local output_directory=$1
    local output_probe=$output_directory/inspect-dual-node-caddy-postactivation-action20d-retry10-a.sh
    local output_runner=$output_directory/run-dual-node-caddy-postactivation-action20d-retry10-a.sh
    local corrected_probe_hash

    record_check output_directory_regular test -d "$output_directory" || return 1
    record_check output_directory_not_symlink test ! -L "$output_directory" || return 1
    record_check output_directory_mode_exact test \
        "$(stat -c '%a' "$output_directory")" = 700 || return 1
    record_check output_probe_initially_absent test ! -e "$output_probe" || return 1
    record_check output_probe_initially_not_symlink test ! -L "$output_probe" || return 1
    record_check output_runner_initially_absent test ! -e "$output_runner" || return 1
    record_check output_runner_initially_not_symlink test ! -L "$output_runner" || return 1
    require_historical_sources || return 1
    build_probe "$output_probe" || return 1
    corrected_probe_hash=$(file_hash "$output_probe") || return 1
    build_runner "$corrected_probe_hash" "$output_runner" || return 1
    validate_outputs "$output_probe" "$output_runner" || return 1
    printf '%s_probe_sha256=%s\n' "$prefix" "$corrected_probe_hash"
    printf '%s_runner_sha256=%s\n' "$prefix" "$(file_hash "$output_runner")"
    printf '%s_historical_sources_unchanged=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        build_outputs "$2"
        ;;
    --self-test | --contract-test)
        [[ $# -eq 1 ]] || exit 64
        test_root=$(mktemp -d /tmp/caddy-action20d-retry10-a-retry-builder.XXXXXX)
        readonly test_root
        cleanup() { rm -rf -- "$test_root"; }
        trap cleanup EXIT
        readonly test_output=$test_root/output
        install -d -m 0700 "$test_output"
        build_outputs "$test_output"
        printf '%s_%s_complete=true\n' "$prefix" "${1#--}"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test|--contract-test\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
