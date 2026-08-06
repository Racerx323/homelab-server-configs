#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20i_builder
readonly source_builder_sha256=1097a1c6958bce9145efa94a1f936536218de81fc1a3c617342a461f7566bfe7
readonly source_candidate_sha256=5cb42ba05b36fecd0c0cf5bc649741661b847e8f8dce94a19288d21874d87fb3
readonly source_installer_sha256=21ad902d76816334c7c0ce0893f4d9f64ef0e44a1ffbeb9d0beea8f79bfd58a2
readonly source_stager_sha256=41ef10df5c02a058742b2e4c2d5183cd1c35c74ec63d103d1b5ff0ed8ba52e71
readonly source_runner_sha256=ca7c63d100e1d9ef76ddadac83cd3d7ff444f76be033d420ddee937036004f99
readonly old_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly node_b_main_sha256=e8473427d9fe167777ca910d740035d5a73b27f9f909999a8d32c5a0a60722b6
readonly node_b_fragment_sha256=7b42e1296bd06768b96e1097fe1e6546fcdc9fb4e249eaa7b0bbaffa85b3b270
readonly node_b_environment_sha256=f692d5b7e0a7e0f0ab142e36face6a8cc8c6680a44a2bcaf6a992247ec4c8113

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly source_builder=$script_directory/build-node-a-caddy-health-helper-action20h-retry3.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action20i_builder_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action20i_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20i_builder_label" >&2
    return 1
}
common_transform() {
    local action20i_builder_input=$1
    local action20i_builder_output=$2

    sed \
        -e 's/action_20h/action_20i/g' \
        -e 's/action20h/action20i/g' \
        -e 's/node-a/node-b/g' \
        -e 's/hostname_node_a/hostname_node_b/g' \
        -e 's/j1-svpihole0/j1-svpihole00/g' \
        -e "s/d1dd8f030fe0a03742ff9c5e0458302cea81ff65a256203f9c07ab5ff022d810/$old_health_sha256/g" \
        -e "s/357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2/$node_b_main_sha256/g" \
        -e "s/6f5a58ca8fd39a1218de6fc964f54aef69f374351c0727bbb0fabf899a80ef39/$node_b_fragment_sha256/g" \
        -e "s/2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8/$node_b_environment_sha256/g" \
        -e 's/-eq 993/-eq 992/g' \
        -e 's/-eq 989/-eq 988/g' \
        -e 's/-eq 991/-eq 990/g' \
        -e "s/'action=20h'/'action=20i'/g" \
        "$action20i_builder_input" >"$action20i_builder_output"
}
render_installer_structure() {
    local action20i_builder_input=$1
    local action20i_builder_output=$2

    awk '
        NR == 32 || NR == 33 { next }
        NR == 55 {
            print "expected_checks() {"
            print "    printf '\''%s\\n'\'' \\"
            print "        identity_root working_directory_root hostname_node_b architecture_arm64 \\"
            print "        stage_directory_regular stage_directory_not_symlink stage_directory_metadata \\"
            print "        candidate_regular candidate_not_symlink candidate_metadata candidate_hash_exact \\"
            print "        candidate_syntax candidate_self_test candidate_preserves_service_check \\"
            print "        candidate_excludes_validation_check candidate_preserves_endpoint_check \\"
            print "        candidate_check_order_exact full_caddy_validation_exact_context \\"
            print "        candidate_journald_logger_exact candidate_slow_only_logging_exact \\"
            print "        candidate_term_trap_exact candidate_int_trap_exact candidate_no_internal_timeout \\"
            print "        live_helper_regular live_helper_not_symlink live_helper_metadata \\"
            print "        live_helper_old_hash_exact main_hash_exact main_excludes_fragment \\"
            print "        fragment_hash_exact environment_hash_exact keepalived_active caddy_active \\"
            print "        lighttpd_active caddy_ipv4_absent caddy_ipv6_absent dns_ipv4_absent \\"
            print "        dns_ipv6_absent script_user_identity script_user_uid_exact \\"
            print "        script_user_primary_gid_exact caddy_tls_group_identity caddy_tls_gid_exact \\"
            print "        script_user_caddy_tls_member candidate_readable_by_script_user \\"
            print "        candidate_self_test_as_script_context backup_root_regular \\"
            print "        backup_root_not_symlink backup_root_metadata backup_prior_absent \\"
            print "        install_stage_absent backup_directory_regular backup_directory_not_symlink \\"
            print "        backup_directory_metadata backup_helper_hash_exact backup_manifest_exact \\"
            print "        installed_helper_regular installed_helper_not_symlink installed_helper_metadata \\"
            print "        installed_helper_hash_exact installed_helper_self_test \\"
            print "        installed_helper_self_test_as_script_context \\"
            print "        installed_helper_execution_exact_context caddy_pid_unchanged \\"
            print "        keepalived_pid_unchanged lighttpd_pid_unchanged keepalived_still_active \\"
            print "        caddy_still_active lighttpd_still_active caddy_ipv4_still_absent \\"
            print "        caddy_ipv6_still_absent dns_ipv4_still_absent dns_ipv6_still_absent \\"
            print "        main_still_excludes_fragment install_stage_clean \\"
            print "        helper_invoked_by_transaction keepalived_not_reloaded \\"
            print "        service_mutations_absent vrrp_mutations_absent vip_mutations_absent"
            print "}"
            skip_expected=1
            next
        }
        skip_expected && NR <= 88 { next }
        NR == 206 {
            print "    # shellcheck disable=SC2016"
            print "    record_check main_excludes_fragment /bin/bash -c \\"
            print "        '\''! grep -Eq \"^[[:space:]]*(include|include_dir).*conf\\\\.d|caddy-ha\\\\.conf\" \"$1\"'\'' \\"
            print "        _ /etc/keepalived/keepalived.conf || return 1"
        }
        NR == 213 {
            print "    record_check caddy_ipv4_absent test \"$(address_count -4 \"$caddy_ipv4\")\" -eq 0 || return 1"
            print "    record_check caddy_ipv6_absent test \"$(address_count -6 \"$caddy_ipv6\")\" -eq 0 || return 1"
            print "    record_check dns_ipv4_absent test \"$(address_count -4 \"$dns_ipv4\")\" -eq 0 || return 1"
            print "    record_check dns_ipv6_absent test \"$(address_count -6 \"$dns_ipv6\")\" -eq 0 || return 1"
            next
        }
        NR >= 214 && NR <= 217 { next }
        NR == 245 {
            print "    record_check backup_prior_absent test -z \\"
            print "        \"$(find \"$backup_root\" -mindepth 1 -maxdepth 1 -name '\''action20i-node-b-health-helper.*'\'' -print -quit)\" || return 1"
        }
        NR == 277 {
            print "    record_check installed_helper_execution_exact_context setpriv \\"
            print "        --reuid \"$action20i_script_uid\" --regid \"$action20i_tls_gid\" \\"
            print "        --clear-groups -- /bin/bash \"$health_target\" || return 1"
            next
        }
        NR >= 278 && NR <= 289 { next }
        NR == 299 {
            print "    record_check caddy_ipv4_still_absent test \"$(address_count -4 \"$caddy_ipv4\")\" -eq 0 || return 1"
            print "    record_check caddy_ipv6_still_absent test \"$(address_count -6 \"$caddy_ipv6\")\" -eq 0 || return 1"
            print "    record_check dns_ipv4_still_absent test \"$(address_count -4 \"$dns_ipv4\")\" -eq 0 || return 1"
            print "    record_check dns_ipv6_still_absent test \"$(address_count -6 \"$dns_ipv6\")\" -eq 0 || return 1"
            print "    # shellcheck disable=SC2016"
            print "    record_check main_still_excludes_fragment /bin/bash -c \\"
            print "        '\''! grep -Eq \"^[[:space:]]*(include|include_dir).*conf\\\\.d|caddy-ha\\\\.conf\" \"$1\"'\'' \\"
            print "        _ /etc/keepalived/keepalived.conf || return 1"
            next
        }
        NR >= 300 && NR <= 303 { next }
        NR == 308 {
            print "    record_check helper_invoked_by_transaction test true || return 1"
            next
        }
        NR == 321 { next }
        NR == 348 { next }
        NR == 352 || NR == 353 || NR == 354 || NR == 355 {
            gsub(/-eq 1/, "-eq 0")
        }
        NR >= 390 && NR <= 392 { next }
        NR == 396 {
            print "backup_directory=$(mktemp -d \"$backup_root/action20i-node-b-health-helper.XXXXXX\")"
            next
        }
        NR == 400 {
            print "    '\''action=20i'\'' \\"
            next
        }
        NR == 412 || NR == 413 { next }
        NR == 416 {
            print "printf '\''%s_helper_invoked_by_transaction=true\\n'\'' \"$prefix\""
            next
        }
        { print }
    ' "$action20i_builder_input" >"$action20i_builder_output"
}
build() (
    local action20i_builder_output_root=$1
    local action20i_builder_source_root=$action20i_builder_output_root/source
    local action20i_builder_installer_common=$action20i_builder_output_root/installer.common
    local action20i_builder_installer=$action20i_builder_output_root/install-node-b-caddy-health-helper-action20i.sh
    local action20i_builder_candidate=$action20i_builder_output_root/check-caddy-vrrp-action20i.sh
    local action20i_builder_stager=$action20i_builder_output_root/stage-node-b-caddy-health-helper-action20i.sh
    local action20i_builder_runner_common=$action20i_builder_output_root/runner.common
    local action20i_builder_runner=$action20i_builder_output_root/run-node-b-caddy-health-helper-action20i.sh
    local action20i_builder_installer_hash
    local action20i_builder_stager_hash

    install -d -m 0700 "$action20i_builder_output_root"
    check source_builder_hash test "$(file_hash "$source_builder")" = \
        "$source_builder_sha256" || return 1
    /bin/bash "$source_builder" --output "$action20i_builder_source_root" >/dev/null || return 1
    check source_candidate_hash test \
        "$(file_hash "$action20i_builder_source_root/check-caddy-vrrp-action20h.sh")" = \
        "$source_candidate_sha256" || return 1
    check source_installer_hash test \
        "$(file_hash "$action20i_builder_source_root/install-node-a-caddy-health-helper-action20h-retry3.sh")" = \
        "$source_installer_sha256" || return 1
    check source_stager_hash test \
        "$(file_hash "$action20i_builder_source_root/stage-node-a-caddy-health-helper-action20h.sh")" = \
        "$source_stager_sha256" || return 1
    check source_runner_hash test \
        "$(file_hash "$action20i_builder_source_root/run-node-a-caddy-health-helper-action20h-retry3.sh")" = \
        "$source_runner_sha256" || return 1

    cp -- "$action20i_builder_source_root/check-caddy-vrrp-action20h.sh" \
        "$action20i_builder_candidate"
    sed 's/check-caddy-vrrp-action20h/check-caddy-vrrp-action20i/g; s/action20h/action20i/g' \
        "$action20i_builder_source_root/stage-node-a-caddy-health-helper-action20h.sh" \
        >"$action20i_builder_stager"
    common_transform \
        "$action20i_builder_source_root/install-node-a-caddy-health-helper-action20h-retry3.sh" \
        "$action20i_builder_installer_common"
    render_installer_structure "$action20i_builder_installer_common" \
        "$action20i_builder_installer"
    action20i_builder_installer_hash=$(file_hash "$action20i_builder_installer")
    action20i_builder_stager_hash=$(file_hash "$action20i_builder_stager")
    common_transform \
        "$action20i_builder_source_root/run-node-a-caddy-health-helper-action20h-retry3.sh" \
        "$action20i_builder_runner_common"
    sed \
        -e 's/pi@10\.1\.0\.53/pi@10.1.0.54/g' \
        -e 's/pihole0\.local\.theama\.co/pihole00.local.theama.co/g' \
        -e 's/CADDY_ACTION20H/CADDY_ACTION20I/g' \
        -e 's/install-node-b-caddy-health-helper-action20i-retry3\.sh/install-node-b-caddy-health-helper-action20i.sh/g' \
        -e "s/$source_installer_sha256/$action20i_builder_installer_hash/g" \
        -e "s/$source_stager_sha256/$action20i_builder_stager_hash/g" \
        -e 's/helper_invoked_by_transaction=false/helper_invoked_by_transaction=true/g' \
        -e 's/node_a_contacted=true/node_a_contacted=false/g' \
        -e 's/node_b_contacted=false/node_b_contacted=true/g' \
        "$action20i_builder_runner_common" >"$action20i_builder_runner"
    rm -rf -- "$action20i_builder_source_root" "$action20i_builder_installer_common" \
        "$action20i_builder_runner_common"
    chmod 0755 "$action20i_builder_candidate" "$action20i_builder_stager" \
        "$action20i_builder_installer" "$action20i_builder_runner"

    check candidate_hash test "$(file_hash "$action20i_builder_candidate")" = \
        "$source_candidate_sha256" || return 1
    check installer_syntax /bin/bash -n "$action20i_builder_installer" || return 1
    check stager_syntax /bin/bash -n "$action20i_builder_stager" || return 1
    check runner_syntax /bin/bash -n "$action20i_builder_runner" || return 1
    check installer_self_test /bin/bash "$action20i_builder_installer" --self-test || return 1
    check runner_self_test /bin/bash "$action20i_builder_runner" --self-test || return 1
    check installer_labels_unique /bin/bash -c \
        'test "$("$1" --expected-checks | wc -l)" -eq "$("$1" --expected-checks | LC_ALL=C sort -u | wc -l)"' \
        _ "$action20i_builder_installer" || return 1
    check node_b_target grep -Fq 'hostname_node_b' "$action20i_builder_installer" || return 1
    check node_a_target_absent test \
        "$(grep -Fc 'node-a' "$action20i_builder_installer" || true)" -eq 0 || return 1
    check caddy_vip_present_checks_absent test \
        "$(grep -Fc 'caddy_ipv4_present' "$action20i_builder_installer" || true)" -eq 0 || return 1
    check caddy_vip_absent_checks_present grep -Fq \
        'caddy_ipv4_still_absent' "$action20i_builder_installer" || return 1
    check validation_check_outside_helper grep -Fq \
        'full_caddy_validation_exact_context' "$action20i_builder_installer" || return 1
    check helper_execution_present grep -Fq \
        'installed_helper_execution_exact_context' "$action20i_builder_installer" || return 1
    check runner_node_b_target grep -Fqx \
        'readonly expected_target=pi@10.1.0.54' "$action20i_builder_runner" || return 1
    check runner_node_b_alias grep -Fqx \
        'readonly expected_host_alias=pihole00.local.theama.co' \
        "$action20i_builder_runner" || return 1
    check runner_helper_invocation_marker grep -Fq \
        '"${prefix}_helper_invoked_by_transaction=true"' \
        "$action20i_builder_runner" || return 1
    check runner_node_a_contact_false grep -Fqx \
        "printf '%s_node_a_contacted=false\\n' \"\$prefix\"" \
        "$action20i_builder_runner" || return 1
    check runner_node_b_contact_true grep -Fqx \
        "printf '%s_node_b_contacted=true\\n' \"\$prefix\"" \
        "$action20i_builder_runner" || return 1
    check activation_absent test \
        "$(grep -Ec 'systemctl (reload|restart) keepalived|vrrp_mutations=true|vip_mutations=true' \
            "$action20i_builder_installer" || true)" -eq 0 || return 1
    printf '%s_candidate_sha256=%s\n' "$prefix" \
        "$(file_hash "$action20i_builder_candidate")"
    printf '%s_stager_sha256=%s\n' "$prefix" \
        "$(file_hash "$action20i_builder_stager")"
    printf '%s_installer_sha256=%s\n' "$prefix" \
        "$(file_hash "$action20i_builder_installer")"
    printf '%s_runner_sha256=%s\n' "$prefix" \
        "$(file_hash "$action20i_builder_runner")"
    printf '%s_complete=true\n' "$prefix"
)

case "${1:-}" in
    --output)
        [[ $# -eq 2 ]] || exit 64
        build "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        action20i_builder_test_root=$(mktemp -d /tmp/caddy-action20i-builder.XXXXXX)
        readonly action20i_builder_test_root
        trap 'rm -rf -- "$action20i_builder_test_root"' EXIT INT TERM
        build "$action20i_builder_test_root/output"
        ;;
    *)
        printf 'Usage: %s --output DIRECTORY|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
