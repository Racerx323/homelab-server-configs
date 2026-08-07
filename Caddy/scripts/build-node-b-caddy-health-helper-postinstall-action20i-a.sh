#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20i_a_builder
readonly source_builder_sha256=dd59e60ebc384e25b4d4faabc718cface0044a079413a3954295d39c08ca3e3f
readonly source_inspector_sha256=9bef62fec313eb8565abc148d9f6741c8ef2c4ac80c72e1f68a97ea80100b4cf
readonly source_runner_sha256=728397374d6984a710b7de19f5800d4dca56b7239f5df69b3cc96b53fa860dc5
readonly source_regression_sha256=1eb5c1dd507bd1081324093e96869ea71789e6e1c2b7722f559f3eacb6641c90
readonly expected_health_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly expected_old_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly expected_backup_path=/var/backups/caddy-ha/action20i-node-b-health-helper.FWqxp7
readonly expected_main_sha256=e8473427d9fe167777ca910d740035d5a73b27f9f909999a8d32c5a0a60722b6
readonly expected_fragment_sha256=7b42e1296bd06768b96e1097fe1e6546fcdc9fb4e249eaa7b0bbaffa85b3b270

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_builder=$script_directory/build-node-a-caddy-health-helper-postinstall-action20h-a.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20i_a_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20i_a_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20i_a_builder_label" >&2
    return 1
}
common_transform() {
    local action20i_a_builder_input=$1
    local action20i_a_builder_output=$2

    sed \
        -e 's/action_20h_a/action_20i_a/g' \
        -e 's/action20h-a/action20i-a/g' \
        -e 's/action20h-node-a-health-instrumentation\.lfB0lj/action20i-node-b-health-helper.FWqxp7/g' \
        -e 's/action20h-node-a-health-instrumentation/action20i-node-b-health-helper/g' \
        -e 's/action20h/action20i/g' \
        -e 's/action=20h/action=20i/g' \
        -e 's/node-a/node-b/g' \
        -e 's/hostname_node_a/hostname_node_b/g' \
        -e 's/j1-svpihole0/j1-svpihole00/g' \
        -e 's/pi@10\.1\.0\.53/pi@10.1.0.54/g' \
        -e 's/-eq 993/-eq 992/g' \
        -e 's/-eq 991/-eq 990/g' \
        -e "s/d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810/$expected_old_health_sha256/g" \
        -e "s/c54624ec3637e76415fbda315ad2aa937433939ee97203051de705d40bf84f2c/47a637e472df9dad2de5762b254c32758236b9131fbcdcd26f46ec0d9bf48b76/g" \
        -e 's/-eq 56/-eq 45/g' \
        -e 's/bytes=56/bytes=45/g' \
        -e 's/node_a_contacted=true/node_a_contacted=false/g' \
        -e 's/node_b_contacted=false/node_b_contacted=true/g' \
        -e 's/production_runner_node_a_contact/production_runner_node_b_contact/g' \
        -e 's/production_runner_node_b_absent/production_runner_node_a_absent/g' \
        "$action20i_a_builder_input" >"$action20i_a_builder_output"
}
render_inspector() {
    local action20i_a_builder_input=$1
    local action20i_a_builder_output=$2

    awk -v main_hash="$expected_main_sha256" -v fragment_hash="$expected_fragment_sha256" '
        /^readonly maximum_stream_bytes=/ {
            print "readonly main_configuration=/etc/keepalived/keepalived.conf"
            print "readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf"
            print "readonly expected_main_sha256=" main_hash
            print "readonly expected_fragment_sha256=" fragment_hash
        }
        /health_regular health_not_symlink health_metadata_exact health_hash_exact/ {
            sub(/health_regular/, "main_configuration_regular main_configuration_not_symlink \\\n        main_configuration_hash_exact main_configuration_excludes_fragment \\\n        fragment_regular fragment_not_symlink fragment_hash_exact health_regular")
        }
        { gsub(/vrrp_state_master/, "fragment_inactive") }
        /printf '\''health_metadata=%s\\n'\''/ {
            print
            getline
            print
            print "    printf '\''main=%s\\n'\'' \"$(file_hash \"$main_configuration\" 2>/dev/null || true)\""
            print "    printf '\''fragment=%s\\n'\'' \"$(file_hash \"$fragment\" 2>/dev/null || true)\""
            next
        }
        /run_assertion architecture_arm64/ {
            print
            print "run_assertion main_configuration_regular test -f \"$main_configuration\""
            print "run_assertion main_configuration_not_symlink test ! -L \"$main_configuration\""
            print "run_assertion main_configuration_hash_exact test \\\n    \"$(file_hash \"$main_configuration\" 2>/dev/null || true)\" = \"$expected_main_sha256\""
            print "# The child Bash expands its positional parameter."
            print "# shellcheck disable=SC2016"
            print "run_assertion main_configuration_excludes_fragment /bin/bash -c \\\n    '\''! grep -Eq \"^[[:space:]]*(include|include_dir).*conf\\\\.d|caddy-ha\\\\.conf\" \"$1\"'\'' \\\n    _ \"$main_configuration\""
            print "run_assertion fragment_regular test -f \"$fragment\""
            print "run_assertion fragment_not_symlink test ! -L \"$fragment\""
            print "run_assertion fragment_hash_exact test \\\n    \"$(file_hash \"$fragment\" 2>/dev/null || true)\" = \"$expected_fragment_sha256\""
            next
        }
        /run_assertion caddy_ipv4_count_exact/ { gsub(/-eq 1/, "-eq 0") }
        /run_assertion caddy_ipv6_count_exact/ { gsub(/-eq 1/, "-eq 0") }
        /run_assertion dns_ipv4_count_exact/ { gsub(/-eq 1/, "-eq 0") }
        /run_assertion dns_ipv6_count_exact/ { gsub(/-eq 1/, "-eq 0") }
        /run_assertion fragment_inactive test/ {
            print "run_assertion fragment_inactive /bin/bash -c \\\n    '\''! grep -Eq \"^[[:space:]]*(include|include_dir).*conf\\\\.d|caddy-ha\\\\.conf\" \"$1\"'\'' \\\n    _ \"$main_configuration\""
            getline
            next
        }
        { print }
    ' "$action20i_a_builder_input" >"$action20i_a_builder_output"
}
build() (
    local action20i_a_builder_output_root=$1
    local action20i_a_builder_source_root=$action20i_a_builder_output_root/source
    local action20i_a_builder_inspector_common=$action20i_a_builder_output_root/inspector.common
    local action20i_a_builder_inspector=$action20i_a_builder_output_root/scripts/inspect-node-b-caddy-health-helper-postinstall-action20i-a.sh
    local action20i_a_builder_runner_common=$action20i_a_builder_output_root/runner.common
    local action20i_a_builder_runner=$action20i_a_builder_output_root/scripts/run-node-b-caddy-health-helper-postinstall-action20i-a.sh
    local action20i_a_builder_regression_common=$action20i_a_builder_output_root/regression.common
    local action20i_a_builder_regression=$action20i_a_builder_output_root/tests/action20i-a-postinstall-regression.sh
    local action20i_a_builder_inspector_hash
    local action20i_a_builder_runner_hash

    install -d -m 0700 "$action20i_a_builder_output_root" \
        "$action20i_a_builder_output_root/scripts" \
        "$action20i_a_builder_output_root/tests"
    record_check source_builder_hash test "$(file_hash "$source_builder")" = \
        "$source_builder_sha256" || return 1
    /bin/bash "$source_builder" --output "$action20i_a_builder_source_root" >/dev/null || return 1
    record_check source_inspector_hash test \
        "$(file_hash "$action20i_a_builder_source_root/scripts/inspect-node-a-caddy-health-helper-postinstall-action20h-a.sh")" = \
        "$source_inspector_sha256" || return 1
    record_check source_runner_hash test \
        "$(file_hash "$action20i_a_builder_source_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a.sh")" = \
        "$source_runner_sha256" || return 1
    record_check source_regression_hash test \
        "$(file_hash "$action20i_a_builder_source_root/tests/action20h-a-postinstall-regression.sh")" = \
        "$source_regression_sha256" || return 1

    common_transform \
        "$action20i_a_builder_source_root/scripts/inspect-node-a-caddy-health-helper-postinstall-action20h-a.sh" \
        "$action20i_a_builder_inspector_common"
    render_inspector "$action20i_a_builder_inspector_common" \
        "$action20i_a_builder_inspector"
    chmod 0755 "$action20i_a_builder_inspector"
    action20i_a_builder_inspector_hash=$(file_hash "$action20i_a_builder_inspector")

    common_transform \
        "$action20i_a_builder_source_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a.sh" \
        "$action20i_a_builder_runner_common"
    sed \
        -e 's/inspect-node-a-caddy-health-helper-postinstall-action20i-a\.sh/inspect-node-b-caddy-health-helper-postinstall-action20i-a.sh/g' \
        -e "s/$source_inspector_sha256/$action20i_a_builder_inspector_hash/g" \
        "$action20i_a_builder_runner_common" >"$action20i_a_builder_runner"
    chmod 0755 "$action20i_a_builder_runner"
    action20i_a_builder_runner_hash=$(file_hash "$action20i_a_builder_runner")

    common_transform \
        "$action20i_a_builder_source_root/tests/action20h-a-postinstall-regression.sh" \
        "$action20i_a_builder_regression_common"
    sed \
        -e 's/inspect-node-a-caddy-health-helper-postinstall-action20i-a\.sh/inspect-node-b-caddy-health-helper-postinstall-action20i-a.sh/g' \
        -e 's/run-node-a-caddy-health-helper-postinstall-action20i-a\.sh/run-node-b-caddy-health-helper-postinstall-action20i-a.sh/g' \
        -e "s/$source_inspector_sha256/$action20i_a_builder_inspector_hash/g" \
        "$action20i_a_builder_regression_common" >"$action20i_a_builder_regression"
    chmod 0755 "$action20i_a_builder_regression"
    rm -rf -- "$action20i_a_builder_source_root" \
        "$action20i_a_builder_inspector_common" \
        "$action20i_a_builder_runner_common" \
        "$action20i_a_builder_regression_common"

    record_check inspector_syntax /bin/bash -n "$action20i_a_builder_inspector" || return 1
    record_check runner_syntax /bin/bash -n "$action20i_a_builder_runner" || return 1
    record_check regression_syntax /bin/bash -n "$action20i_a_builder_regression" || return 1
    record_check helper_hash_exact grep -Fqx \
        "readonly expected_health_sha256=$expected_health_sha256" \
        "$action20i_a_builder_inspector" || return 1
    record_check backup_path_exact grep -Fqx \
        "readonly expected_backup_path=$expected_backup_path" \
        "$action20i_a_builder_inspector" || return 1
    record_check backup_old_hash_exact grep -Fqx \
        "readonly expected_old_health_sha256=$expected_old_health_sha256" \
        "$action20i_a_builder_inspector" || return 1
    record_check main_hash_exact grep -Fqx \
        "readonly expected_main_sha256=$expected_main_sha256" \
        "$action20i_a_builder_inspector" || return 1
    record_check fragment_hash_exact grep -Fqx \
        "readonly expected_fragment_sha256=$expected_fragment_sha256" \
        "$action20i_a_builder_inspector" || return 1
    record_check node_b_target grep -Fq hostname_node_b "$action20i_a_builder_inspector" || return 1
    record_check node_a_target_absent test \
        "$(grep -Fc hostname_node_a "$action20i_a_builder_inspector" || true)" -eq 0 || return 1
    record_check inactive_contract grep -Fq fragment_inactive "$action20i_a_builder_inspector" || return 1
    record_check inspector_activation_absent test \
        "$(grep -Ec 'systemctl (reload|restart) keepalived|vrrp_activation=true|persistent_mutations=true' \
            "$action20i_a_builder_inspector" || true)" -eq 0 || return 1
    record_check runner_activation_absent test \
        "$(grep -Ec 'systemctl (reload|restart) keepalived|vrrp_activation=true|persistent_mutations=true' \
            "$action20i_a_builder_runner" || true)" -eq 0 || return 1
    /bin/bash "$action20i_a_builder_inspector" --self-test >/dev/null || return 1
    /bin/bash "$action20i_a_builder_runner" --self-test >/dev/null || return 1
    /bin/bash "$action20i_a_builder_regression" >/dev/null || return 1
    printf '%s_inspector_sha256=%s\n' "$prefix" "$action20i_a_builder_inspector_hash"
    printf '%s_runner_sha256=%s\n' "$prefix" "$action20i_a_builder_runner_hash"
    printf '%s_regression_sha256=%s\n' "$prefix" \
        "$(file_hash "$action20i_a_builder_regression")"
    printf '%s_complete=true\n' "$prefix"
)

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        build "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        test_root=$(mktemp -d /tmp/caddy-action20i-a-builder.XXXXXX)
        readonly test_root
        trap 'rm -rf -- "$test_root"' EXIT
        build "$test_root/output"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
