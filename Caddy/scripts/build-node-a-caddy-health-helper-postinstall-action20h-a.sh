#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_a_builder
readonly source_inspector_sha256=2904f0e0d6cfbe87d4f041998c7bad294215f93522b37995c93fa57a4b3c18ff
readonly source_runner_sha256=32ea404878c42b843406dc39054f34186e6b169cd2b2a5e02d0c8ba59f79eebb
readonly source_regression_sha256=28a154003497ab537dfce9f3ec33bcf6ecbec47c958799656b778ce1680fa272
readonly source_health_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly source_old_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly expected_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly expected_old_health_sha256=d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810
readonly expected_backup_path=/var/backups/caddy-ha/action20h-node-a-health-instrumentation.lfB0lj

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly source_inspector=$script_directory/inspect-node-a-caddy-health-instrumentation-postinstall-action20d-retry10-d-retry2-a.sh
readonly source_runner=$script_directory/run-node-a-caddy-health-instrumentation-postinstall-action20d-retry10-d-retry2-a.sh
readonly source_regression=$caddy_root/tests/action20d-retry10-d-retry2-a-postinstall-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20h_a_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20h_a_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20h_a_builder_label" >&2
    return 1
}
render_inspector_structure() {
    local action20h_a_builder_output=$1

    awk '
        NR == 144 { next }
        NR == 149 {
            print "    run_assertion health_validation_check_absent test \\"
            print "        \"$(grep -Fc '\''caddy validate'\'' \"$health_helper\" || true)\" -eq 0"
            next
        }
        NR == 150 { next }
        NR == 156 || NR == 157 { next }
        NR == 160 {
            print "    run_assertion health_check_order_exact test \\"
            print "        \"$action20d_retry2_a_service_line\" -lt \"$action20d_retry2_a_endpoint_line\""
            next
        }
        NR == 161 || NR == 162 { next }
        { print }
    ' "$source_inspector" >"$action20h_a_builder_output"
}
apply_common_substitutions() {
    local action20h_a_builder_input=$1
    local action20h_a_builder_output=$2

    sed \
        -e 's/action_20d_retry10_d_retry2_a/action_20h_a/g' \
        -e 's/action20d-retry10-d-retry2-node-a-health-instrumentation\.18d7kI/action20h-node-a-health-instrumentation.lfB0lj/g' \
        -e 's/action20d-retry10-d-retry2-node-a-health-instrumentation/action20h-node-a-health-instrumentation/g' \
        -e 's/caddy-action20d-retry10-d-retry2/caddy-action20h/g' \
        -e 's/\.check-caddy\.action20d-retry10-d-retry2/\.check-caddy.action20h/g' \
        -e 's/action=20d-retry10-d/action=20h/g' \
        -e 's/health_validation_check_preserved/health_validation_check_absent/g' \
        -e 's/caddy_ha_health_instrumentation_self_test_complete/caddy_ha_vrrp_health_self_test_complete/g' \
        -e "s/$source_health_sha256/$expected_health_sha256/g" \
        -e "s/$source_old_health_sha256/$expected_old_health_sha256/g" \
        "$action20h_a_builder_input" >"$action20h_a_builder_output"
}
build() (
    local action20h_a_builder_output_root=$1
    local action20h_a_builder_structured
    local action20h_a_builder_inspector
    local action20h_a_builder_runner_stage
    local action20h_a_builder_runner
    local action20h_a_builder_regression_stage
    local action20h_a_builder_regression
    local action20h_a_builder_inspector_hash
    local action20h_a_builder_runner_hash

    install -d -m 0700 \
        "$action20h_a_builder_output_root" \
        "$action20h_a_builder_output_root/scripts" \
        "$action20h_a_builder_output_root/tests"
    action20h_a_builder_structured=$action20h_a_builder_output_root/inspector.structured
    action20h_a_builder_inspector=$action20h_a_builder_output_root/scripts/inspect-node-a-caddy-health-helper-postinstall-action20h-a.sh
    action20h_a_builder_runner_stage=$action20h_a_builder_output_root/runner.stage
    action20h_a_builder_runner=$action20h_a_builder_output_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a.sh
    action20h_a_builder_regression_stage=$action20h_a_builder_output_root/regression.stage
    action20h_a_builder_regression=$action20h_a_builder_output_root/tests/action20h-a-postinstall-regression.sh

    record_check source_inspector_hash test "$(file_hash "$source_inspector")" = "$source_inspector_sha256" || return 1
    record_check source_runner_hash test "$(file_hash "$source_runner")" = "$source_runner_sha256" || return 1
    record_check source_regression_hash test "$(file_hash "$source_regression")" = "$source_regression_sha256" || return 1

    render_inspector_structure "$action20h_a_builder_structured"
    apply_common_substitutions "$action20h_a_builder_structured" "$action20h_a_builder_inspector"
    rm -f -- "$action20h_a_builder_structured"
    chmod 0755 "$action20h_a_builder_inspector"
    action20h_a_builder_inspector_hash=$(file_hash "$action20h_a_builder_inspector")

    apply_common_substitutions "$source_runner" "$action20h_a_builder_runner_stage"
    sed \
        -e 's/inspect-node-a-caddy-health-instrumentation-postinstall-action20d-retry10-d-retry2-a\.sh/inspect-node-a-caddy-health-helper-postinstall-action20h-a.sh/g' \
        -e "s/$source_inspector_sha256/$action20h_a_builder_inspector_hash/g" \
        "$action20h_a_builder_runner_stage" >"$action20h_a_builder_runner"
    rm -f -- "$action20h_a_builder_runner_stage"
    chmod 0755 "$action20h_a_builder_runner"
    action20h_a_builder_runner_hash=$(file_hash "$action20h_a_builder_runner")

    apply_common_substitutions "$source_regression" "$action20h_a_builder_regression_stage"
    sed \
        -e 's/inspect-node-a-caddy-health-instrumentation-postinstall-action20d-retry10-d-retry2-a\.sh/inspect-node-a-caddy-health-helper-postinstall-action20h-a.sh/g' \
        -e 's/run-node-a-caddy-health-instrumentation-postinstall-action20d-retry10-d-retry2-a\.sh/run-node-a-caddy-health-helper-postinstall-action20h-a.sh/g' \
        -e "s/$source_inspector_sha256/$action20h_a_builder_inspector_hash/g" \
        "$action20h_a_builder_regression_stage" >"$action20h_a_builder_regression"
    rm -f -- "$action20h_a_builder_regression_stage"
    chmod 0755 "$action20h_a_builder_regression"

    record_check inspector_syntax /bin/bash -n "$action20h_a_builder_inspector" || return 1
    record_check runner_syntax /bin/bash -n "$action20h_a_builder_runner" || return 1
    record_check regression_syntax /bin/bash -n "$action20h_a_builder_regression" || return 1
    record_check installed_hash_exact grep -Fqx \
        "readonly expected_health_sha256=$expected_health_sha256" "$action20h_a_builder_inspector" || return 1
    record_check backup_path_exact grep -Fqx \
        "readonly expected_backup_path=$expected_backup_path" "$action20h_a_builder_inspector" || return 1
    record_check backup_old_hash_exact grep -Fqx \
        "readonly expected_old_health_sha256=$expected_old_health_sha256" "$action20h_a_builder_inspector" || return 1
    record_check validation_absent_contract grep -Fq \
        'run_assertion health_validation_check_absent test' "$action20h_a_builder_inspector" || return 1
    record_check validation_preserved_contract_absent test \
        "$(grep -Fc health_validation_check_preserved "$action20h_a_builder_inspector" || true)" -eq 0 || return 1
    record_check backup_manifest_action_exact grep -Fq \
        "'action=20h'" "$action20h_a_builder_inspector" || return 1
    /bin/bash "$action20h_a_builder_inspector" --self-test >/dev/null || return 1
    /bin/bash "$action20h_a_builder_runner" --self-test >/dev/null || return 1
    /bin/bash "$action20h_a_builder_regression" >/dev/null || return 1
    printf '%s_inspector_sha256=%s\n' "$prefix" "$action20h_a_builder_inspector_hash"
    printf '%s_runner_sha256=%s\n' "$prefix" "$action20h_a_builder_runner_hash"
    printf '%s_regression_sha256=%s\n' "$prefix" "$(file_hash "$action20h_a_builder_regression")"
    printf '%s_complete=true\n' "$prefix"
)

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        build "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        action20h_a_builder_test_root=$(mktemp -d /tmp/caddy-action20h-a-builder.XXXXXX)
        readonly action20h_a_builder_test_root
        trap 'rm -rf -- "$action20h_a_builder_test_root"' EXIT
        build "$action20h_a_builder_test_root/output"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
