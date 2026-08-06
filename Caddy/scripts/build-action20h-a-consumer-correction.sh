#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_a_consumer_builder
readonly source_builder_sha256=dd59e60ebc384e25b4d4faabc718cface0044a079413a3954295d39c08ca3e3f
readonly source_inspector_sha256=9bef62fec313eb8565abc148d9f6741c8ef2c4ac80c72e1f68a97ea80100b4cf
readonly source_runner_sha256=728397374d6984a710b7de19f5800d4dca56b7239f5df69b3cc96b53fa860dc5
readonly source_regression_sha256=1eb5c1dd507bd1081324093e96869ea71789e6e1c2b7722f559f3eacb6641c90
readonly corrected_runner_sha256=7abd7f22819a955462deb423764da334e5892a3431b4b9435bcbb50d7c41710c
readonly corrected_regression_sha256=c11af8e8dce950a6ae234bbfbee8a7cf22291c219a24c5cbe055db1fe0fbadb3
readonly stale_capture_bytes=56
readonly observed_capture_bytes=45
readonly stale_capture_sha256=c54624ec3637e76415fbda315ad2aa937433939ee97203051de705d40bf84f2c
readonly observed_capture_sha256=47a637e48be25fe61fa831f7212b5e88a754672eeb89ca3494a9464941668b76

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_builder=$script_directory/build-node-a-caddy-health-helper-postinstall-action20h-a.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action20h_a_consumer_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20h_a_consumer_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20h_a_consumer_builder_label" >&2
    return 1
}
build() (
    local action20h_a_consumer_builder_output_root=$1
    local action20h_a_consumer_builder_source_root
    local action20h_a_consumer_builder_source_inspector
    local action20h_a_consumer_builder_source_runner
    local action20h_a_consumer_builder_source_regression
    local action20h_a_consumer_builder_inspector
    local action20h_a_consumer_builder_runner
    local action20h_a_consumer_builder_regression

    install -d -m 0700 \
        "$action20h_a_consumer_builder_output_root" \
        "$action20h_a_consumer_builder_output_root/scripts" \
        "$action20h_a_consumer_builder_output_root/tests"
    action20h_a_consumer_builder_source_root=$action20h_a_consumer_builder_output_root/source
    check source_builder_hash test "$(file_hash "$source_builder")" = \
        "$source_builder_sha256" || return 1
    /bin/bash "$source_builder" --output \
        "$action20h_a_consumer_builder_source_root" >/dev/null || return 1
    action20h_a_consumer_builder_source_inspector=$action20h_a_consumer_builder_source_root/scripts/inspect-node-a-caddy-health-helper-postinstall-action20h-a.sh
    action20h_a_consumer_builder_source_runner=$action20h_a_consumer_builder_source_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a.sh
    action20h_a_consumer_builder_source_regression=$action20h_a_consumer_builder_source_root/tests/action20h-a-postinstall-regression.sh
    action20h_a_consumer_builder_inspector=$action20h_a_consumer_builder_output_root/scripts/inspect-node-a-caddy-health-helper-postinstall-action20h-a.sh
    action20h_a_consumer_builder_runner=$action20h_a_consumer_builder_output_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a-consumer-corrected.sh
    action20h_a_consumer_builder_regression=$action20h_a_consumer_builder_output_root/tests/action20h-a-consumer-correction-regression.sh

    check source_inspector_hash test \
        "$(file_hash "$action20h_a_consumer_builder_source_inspector")" = \
        "$source_inspector_sha256" || return 1
    check source_runner_hash test \
        "$(file_hash "$action20h_a_consumer_builder_source_runner")" = \
        "$source_runner_sha256" || return 1
    check source_regression_hash test \
        "$(file_hash "$action20h_a_consumer_builder_source_regression")" = \
        "$source_regression_sha256" || return 1
    check runner_stale_byte_pin_count test \
        "$(awk -v needle="-eq $stale_capture_bytes" \
            'index($0, needle) { count++ } END { print count + 0 }' \
            "$action20h_a_consumer_builder_source_runner")" -eq 1 || return 1
    check runner_stale_hash_pin_count test \
        "$(grep -Fc "$stale_capture_sha256" \
            "$action20h_a_consumer_builder_source_runner")" -eq 1 || return 1
    check regression_stale_byte_pin_count test \
        "$(grep -Fc "bytes=$stale_capture_bytes" \
            "$action20h_a_consumer_builder_source_regression")" -eq 1 || return 1
    check regression_stale_hash_pin_count test \
        "$(grep -Fc "$stale_capture_sha256" \
            "$action20h_a_consumer_builder_source_regression")" -eq 2 || return 1

    cp -- "$action20h_a_consumer_builder_source_inspector" \
        "$action20h_a_consumer_builder_inspector"
    sed \
        -e "s/-eq $stale_capture_bytes/-eq $observed_capture_bytes/g" \
        -e "s/$stale_capture_sha256/$observed_capture_sha256/g" \
        "$action20h_a_consumer_builder_source_runner" \
        >"$action20h_a_consumer_builder_runner"
    sed \
        -e "s/bytes=$stale_capture_bytes/bytes=$observed_capture_bytes/g" \
        -e "s/$stale_capture_sha256/$observed_capture_sha256/g" \
        -e 's/run-node-a-caddy-health-helper-postinstall-action20h-a\.sh/run-node-a-caddy-health-helper-postinstall-action20h-a-consumer-corrected.sh/g' \
        "$action20h_a_consumer_builder_source_regression" \
        >"$action20h_a_consumer_builder_regression"
    chmod 0755 \
        "$action20h_a_consumer_builder_inspector" \
        "$action20h_a_consumer_builder_runner" \
        "$action20h_a_consumer_builder_regression"
    rm -rf -- "$action20h_a_consumer_builder_source_root"

    check inspector_unchanged test \
        "$(file_hash "$action20h_a_consumer_builder_inspector")" = \
        "$source_inspector_sha256" || return 1
    check corrected_runner_hash test \
        "$(file_hash "$action20h_a_consumer_builder_runner")" = \
        "$corrected_runner_sha256" || return 1
    check corrected_regression_hash test \
        "$(file_hash "$action20h_a_consumer_builder_regression")" = \
        "$corrected_regression_sha256" || return 1
    check corrected_runner_syntax /bin/bash -n \
        "$action20h_a_consumer_builder_runner" || return 1
    check corrected_regression_syntax /bin/bash -n \
        "$action20h_a_consumer_builder_regression" || return 1
    check stale_runner_hash_absent test \
        "$(grep -Fc "$stale_capture_sha256" \
            "$action20h_a_consumer_builder_runner" || true)" -eq 0 || return 1
    check stale_regression_hash_absent test \
        "$(grep -Fc "$stale_capture_sha256" \
            "$action20h_a_consumer_builder_regression" || true)" -eq 0 || return 1
    check corrected_runner_hash_present grep -Fq \
        "$observed_capture_sha256" "$action20h_a_consumer_builder_runner" || return 1
    check corrected_regression_hash_present grep -Fq \
        "$observed_capture_sha256" "$action20h_a_consumer_builder_regression" || return 1
    printf '%s_inspector_sha256=%s\n' "$prefix" \
        "$(file_hash "$action20h_a_consumer_builder_inspector")"
    printf '%s_runner_sha256=%s\n' "$prefix" \
        "$(file_hash "$action20h_a_consumer_builder_runner")"
    printf '%s_regression_sha256=%s\n' "$prefix" \
        "$(file_hash "$action20h_a_consumer_builder_regression")"
    printf '%s_complete=true\n' "$prefix"
)

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        build "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        action20h_a_consumer_builder_test_root=$(mktemp -d \
            /tmp/caddy-action20h-a-consumer-builder.XXXXXX)
        readonly action20h_a_consumer_builder_test_root
        trap 'rm -rf -- "$action20h_a_consumer_builder_test_root"' EXIT INT TERM
        build "$action20h_a_consumer_builder_test_root/output"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
