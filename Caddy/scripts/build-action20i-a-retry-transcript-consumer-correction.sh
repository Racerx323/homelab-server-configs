#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20i_a_retry_consumer_correction_builder
readonly source_builder_sha256=9306f430153e2c5083ddf263893a1b692b2ae3e6dbfac66d89b5d2f2ce93e01a
readonly source_inspector_sha256=7497358ba86fa72fbf7b25fa699c7cfdb71b98be90e452674e4f403e56d19423
readonly source_runner_sha256=d5b91e604123ad7e59e44d98062494cc80e2da8e153fb4e0fb4af3e67365c961
readonly source_regression_sha256=8ecbbe8fdc7e48c48636cee80c2021fe7988f239e465ecb3f5c89d8cba18d799
readonly stale_capture_sha256=47a637e472df9dad2de5762b254c32758236b9131fbcdcd26f46ec0d9bf48b76
readonly observed_capture_sha256=47a637e48be25fe61fa831f7212b5e88a754672eeb89ca3494a9464941668b76

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_builder=$script_directory/build-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20i_a_consumer_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20i_a_consumer_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" \
        "$action20i_a_consumer_builder_label" >&2
    return 1
}
occurrence_count() {
    local action20i_a_consumer_builder_needle=$1
    local action20i_a_consumer_builder_path=$2

    awk -v needle="$action20i_a_consumer_builder_needle" '
        { text = text $0 "\n" }
        END {
            count = 0
            while ((offset = index(text, needle)) != 0) {
                count++
                text = substr(text, offset + length(needle))
            }
            print count
        }
    ' "$action20i_a_consumer_builder_path"
}
reverse_matches_source() {
    local action20i_a_consumer_builder_corrected=$1
    local action20i_a_consumer_builder_source=$2
    local action20i_a_consumer_builder_reversed=$3

    sed "s/$observed_capture_sha256/$stale_capture_sha256/g" \
        "$action20i_a_consumer_builder_corrected" \
        >"$action20i_a_consumer_builder_reversed" || return 1
    cmp -s "$action20i_a_consumer_builder_reversed" \
        "$action20i_a_consumer_builder_source"
}
build() (
    local action20i_a_consumer_builder_output_root=$1
    local action20i_a_consumer_builder_source_root=$action20i_a_consumer_builder_output_root/source
    local action20i_a_consumer_builder_inspector=$action20i_a_consumer_builder_output_root/scripts/inspect-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh
    local action20i_a_consumer_builder_runner=$action20i_a_consumer_builder_output_root/scripts/run-node-b-caddy-health-helper-postinstall-action20i-a-retry-consumer-corrected.sh
    local action20i_a_consumer_builder_regression=$action20i_a_consumer_builder_output_root/tests/action20i-a-retry-consumer-correction-regression.sh
    local action20i_a_consumer_builder_source_inspector
    local action20i_a_consumer_builder_source_runner
    local action20i_a_consumer_builder_source_regression
    local action20i_a_consumer_builder_reverse_runner=$action20i_a_consumer_builder_output_root/reverse.runner
    local action20i_a_consumer_builder_reverse_regression=$action20i_a_consumer_builder_output_root/reverse.regression

    install -d -m 0700 "$action20i_a_consumer_builder_output_root" \
        "$action20i_a_consumer_builder_output_root/scripts" \
        "$action20i_a_consumer_builder_output_root/tests"
    record_check source_builder_hash test "$(file_hash "$source_builder")" = \
        "$source_builder_sha256" || return 1
    /bin/bash "$source_builder" --output \
        "$action20i_a_consumer_builder_source_root" >/dev/null || return 1
    action20i_a_consumer_builder_source_inspector=$action20i_a_consumer_builder_source_root/scripts/inspect-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh
    action20i_a_consumer_builder_source_runner=$action20i_a_consumer_builder_source_root/scripts/run-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh
    action20i_a_consumer_builder_source_regression=$action20i_a_consumer_builder_source_root/tests/action20i-a-retry-postinstall-regression.sh
    record_check source_inspector_hash test \
        "$(file_hash "$action20i_a_consumer_builder_source_inspector")" = \
        "$source_inspector_sha256" || return 1
    record_check source_runner_hash test \
        "$(file_hash "$action20i_a_consumer_builder_source_runner")" = \
        "$source_runner_sha256" || return 1
    record_check source_regression_hash test \
        "$(file_hash "$action20i_a_consumer_builder_source_regression")" = \
        "$source_regression_sha256" || return 1
    record_check source_runner_stale_count test \
        "$(occurrence_count "$stale_capture_sha256" \
            "$action20i_a_consumer_builder_source_runner")" -eq 1 || return 1
    record_check source_regression_stale_count test \
        "$(occurrence_count "$stale_capture_sha256" \
            "$action20i_a_consumer_builder_source_regression")" -eq 2 || return 1

    install -m 0755 "$action20i_a_consumer_builder_source_inspector" \
        "$action20i_a_consumer_builder_inspector"
    sed "s/$stale_capture_sha256/$observed_capture_sha256/g" \
        "$action20i_a_consumer_builder_source_runner" \
        >"$action20i_a_consumer_builder_runner"
    sed \
        -e "s/$stale_capture_sha256/$observed_capture_sha256/g" \
        -e 's#run-node-b-caddy-health-helper-postinstall-action20i-a-retry\.sh#run-node-b-caddy-health-helper-postinstall-action20i-a-retry-consumer-corrected.sh#g' \
        -e 's/action_20i_a_retry_regression/action_20i_a_retry_consumer_correction_regression/g' \
        "$action20i_a_consumer_builder_source_regression" \
        >"$action20i_a_consumer_builder_regression"
    chmod 0755 "$action20i_a_consumer_builder_runner" \
        "$action20i_a_consumer_builder_regression"

    record_check runner_observed_count test \
        "$(occurrence_count "$observed_capture_sha256" \
            "$action20i_a_consumer_builder_runner")" -eq 1 || return 1
    record_check runner_stale_absent test \
        "$(occurrence_count "$stale_capture_sha256" \
            "$action20i_a_consumer_builder_runner")" -eq 0 || return 1
    record_check regression_observed_count test \
        "$(occurrence_count "$observed_capture_sha256" \
            "$action20i_a_consumer_builder_regression")" -eq 2 || return 1
    record_check regression_stale_absent test \
        "$(occurrence_count "$stale_capture_sha256" \
            "$action20i_a_consumer_builder_regression")" -eq 0 || return 1
    record_check runner_only_hash_changed reverse_matches_source \
        "$action20i_a_consumer_builder_runner" \
        "$action20i_a_consumer_builder_source_runner" \
        "$action20i_a_consumer_builder_reverse_runner" || return 1
    sed \
        -e 's#run-node-b-caddy-health-helper-postinstall-action20i-a-retry-consumer-corrected\.sh#run-node-b-caddy-health-helper-postinstall-action20i-a-retry.sh#g' \
        -e 's/action_20i_a_retry_consumer_correction_regression/action_20i_a_retry_regression/g' \
        "$action20i_a_consumer_builder_regression" \
        >"$action20i_a_consumer_builder_reverse_regression"
    record_check regression_only_contract_changes reverse_matches_source \
        "$action20i_a_consumer_builder_reverse_regression" \
        "$action20i_a_consumer_builder_source_regression" \
        "$action20i_a_consumer_builder_output_root/reverse.regression.hash" || return 1
    record_check inspector_unchanged test \
        "$(file_hash "$action20i_a_consumer_builder_inspector")" = \
        "$source_inspector_sha256" || return 1
    record_check runner_syntax /bin/bash -n \
        "$action20i_a_consumer_builder_runner" || return 1
    record_check regression_syntax /bin/bash -n \
        "$action20i_a_consumer_builder_regression" || return 1
    /bin/bash "$action20i_a_consumer_builder_runner" --self-test >/dev/null || return 1
    /bin/bash "$action20i_a_consumer_builder_regression" >/dev/null || return 1
    rm -rf -- "$action20i_a_consumer_builder_source_root" \
        "$action20i_a_consumer_builder_reverse_runner" \
        "$action20i_a_consumer_builder_reverse_regression" \
        "$action20i_a_consumer_builder_output_root/reverse.regression.hash"
    printf '%s_inspector_sha256=%s\n' "$prefix" \
        "$(file_hash "$action20i_a_consumer_builder_inspector")"
    printf '%s_runner_sha256=%s\n' "$prefix" \
        "$(file_hash "$action20i_a_consumer_builder_runner")"
    printf '%s_regression_sha256=%s\n' "$prefix" \
        "$(file_hash "$action20i_a_consumer_builder_regression")"
    printf '%s_complete=true\n' "$prefix"
)

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        build "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        test_root=$(mktemp -d /tmp/caddy-action20i-a-consumer-builder.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT
        build "$test_root/output"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
