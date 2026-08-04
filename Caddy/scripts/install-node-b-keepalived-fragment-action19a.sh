#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_19a
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly fragment_directory=/etc/keepalived/conf.d
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly rollback_root=/var/backups/caddy-ha
readonly expected_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
readonly expected_keepalived_tree_sha256=68d2bc846ad94da2a995f52e0f7829ff1c5706f35e399e40e1a0a552f37afd4f
readonly health_script=/usr/local/libexec/check-caddy.sh
readonly notification_script=/usr/local/libexec/lsyncd-ha-failover-notify.sh
readonly expected_health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly expected_notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly vip_ipv4_cidr=10.1.0.56/22
readonly vip_ipv6_cidr=fd36:5aa8:6971:1::56/128

readonly -a continuity_units=(
    keepalived.service
    caddy.service
    lighttpd.service
    lsyncd.service
    caddy-lsyncd.service
    caddy-sync-reconcile.path
    caddy-sync-reconcile.service
)
readonly -a common_properties=(ActiveState SubState UnitFileState)
readonly -a service_properties=(MainPID NRestarts)

declare -A state_before=()
stage_directory=
rollback_directory=
install_stage=
directory_created=false
mutation_started=false
transaction_complete=false
main_sha256_before=

usage() {
    printf 'Usage: %s --stage DIRECTORY\n' "${0##*/}" >&2
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

tree_hash() {
    local tree_root=$1

    (
        cd "$tree_root"
        find . -type f -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

address_count() {
    local address_family=$1
    local expected_cidr=$2

    ip -o "-$address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$expected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}

require_check() {
    local check_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$check_label" >&2
    return 1
}

unit_property() {
    local property_name=$1
    local unit_name=$2

    if [[ "$property_name" == UnitFileState ]]; then
        systemctl is-enabled "$unit_name" 2>/dev/null || true
        return 0
    fi
    systemctl show "$unit_name" --no-pager \
        --property "$property_name" --value
}

capture_service_state() {
    local property_name
    local property_value
    local unit_label
    local unit_name

    for unit_name in "${continuity_units[@]}"; do
        unit_label=${unit_name//[-.]/_}
        for property_name in "${common_properties[@]}"; do
            property_value=$(unit_property "$property_name" "$unit_name") ||
                return 1
            require_check "pre_${unit_label}_${property_name}_observed" \
                test -n "$property_value" || return 1
            state_before["$unit_name:$property_name"]=$property_value
        done
        if [[ "$unit_name" == *.service ]]; then
            for property_name in "${service_properties[@]}"; do
                property_value=$(unit_property "$property_name" "$unit_name") ||
                    return 1
                require_check "pre_${unit_label}_${property_name}_observed" \
                    test -n "$property_value" || return 1
                state_before["$unit_name:$property_name"]=$property_value
            done
        fi
    done
}

validate_service_continuity() {
    local property_name
    local property_value
    local unit_label
    local unit_name

    for unit_name in "${continuity_units[@]}"; do
        unit_label=${unit_name//[-.]/_}
        for property_name in "${common_properties[@]}"; do
            property_value=$(unit_property "$property_name" "$unit_name") ||
                return 1
            require_check "post_${unit_label}_${property_name}_unchanged" \
                test "$property_value" = \
                "${state_before["$unit_name:$property_name"]}" || return 1
        done
        if [[ "$unit_name" == *.service ]]; then
            for property_name in "${service_properties[@]}"; do
                property_value=$(unit_property "$property_name" "$unit_name") ||
                    return 1
                require_check "post_${unit_label}_${property_name}_unchanged" \
                    test "$property_value" = \
                    "${state_before["$unit_name:$property_name"]}" || return 1
            done
        fi
    done
}

validate_fragment_contract() {
    local candidate=$1
    local phase_label=$2

    require_check "${phase_label}_regular" test -f "$candidate" || return 1
    require_check "${phase_label}_not_symlink" test ! -L "$candidate" || return 1
    require_check "${phase_label}_metadata" \
        test "$(stat -c '%U:%G:%a' "$candidate")" = root:root:644 || return 1
    require_check "${phase_label}_hash_exact" \
        test "$(file_hash "$candidate")" = "$expected_fragment_sha256" ||
        return 1
    require_check "${phase_label}_dualstack_group" grep -Fq \
        'vrrp_sync_group CADDY_DUALSTACK {' "$candidate" || return 1
    require_check "${phase_label}_ipv4_instance" grep -Fq \
        'vrrp_instance CADDY_IPV4 {' "$candidate" || return 1
    require_check "${phase_label}_ipv6_instance" grep -Fq \
        'vrrp_instance CADDY_IPV6 {' "$candidate" || return 1
    require_check "${phase_label}_ipv4_vrid" grep -Fq \
        'virtual_router_id 110' "$candidate" || return 1
    require_check "${phase_label}_ipv6_vrid" grep -Fq \
        'virtual_router_id 111' "$candidate" || return 1
    require_check "${phase_label}_priority" grep -Fq 'priority 100' "$candidate" ||
        return 1
    require_check "${phase_label}_ipv4_source" grep -Fq \
        'unicast_src_ip 10.1.0.54' "$candidate" || return 1
    require_check "${phase_label}_ipv4_peer" grep -Fq \
        '10.1.0.53 min_ttl 255 max_ttl 255' "$candidate" || return 1
    require_check "${phase_label}_ipv6_source" grep -Fq \
        'unicast_src_ip fd36:5aa8:6971:1::54' "$candidate" || return 1
    require_check "${phase_label}_ipv6_peer" grep -Fq \
        'fd36:5aa8:6971:1::53 min_ttl 255 max_ttl 255' "$candidate" ||
        return 1
    require_check "${phase_label}_ipv4_vip" grep -Fq \
        '10.1.0.56/22 dev eth0' "$candidate" || return 1
    require_check "${phase_label}_ipv6_vip" grep -Fq \
        'fd36:5aa8:6971:1::56/128 dev eth0 preferred_lft forever' \
        "$candidate" || return 1
    require_check "${phase_label}_preempt_delay_count" test \
        "$(grep -Fxc '    preempt_delay 30' "$candidate")" -eq 2 || return 1
    require_check "${phase_label}_initial_backup_count" test \
        "$(grep -Fxc '    state BACKUP' "$candidate")" -eq 2 || return 1
    require_check "${phase_label}_health_user" grep -Fq \
        'user keepalived_script' "$candidate" || return 1
    require_check "${phase_label}_health_command" grep -Fq \
        'script "/usr/local/libexec/check-caddy.sh"' "$candidate" || return 1
    require_check "${phase_label}_notify_command" grep -Fq \
        'notify "/usr/local/libexec/lsyncd-ha-failover-notify.sh"' \
        "$candidate" || return 1
}

validate_candidate_parser() {
    local candidate=$1
    local parser_directory
    local parser_log
    local sanitized_fragment
    local wrapper

    parser_directory=$(mktemp -d /tmp/caddy-action19a-parser.XXXXXX) || return 1
    parser_log=$parser_directory/keepalived.log
    sanitized_fragment=$parser_directory/caddy-ha.conf
    wrapper=$parser_directory/keepalived.conf
    sed \
        -e '/^[[:space:]]*notify "/d' \
        -e 's/user keepalived_script/user root/' \
        -e 's#script "/usr/local/libexec/check-caddy.sh"#script "/bin/true"#' \
        "$candidate" >"$sanitized_fragment" || {
        rm -rf -- "$parser_directory"
        return 1
    }
    printf '%s\n' \
        'global_defs {' \
        '    enable_script_security' \
        '}' \
        "include $sanitized_fragment" >"$wrapper"
    if ! keepalived --dont-fork --config-test="$parser_log" \
        -f "$wrapper" >/dev/null; then
        rm -rf -- "$parser_directory"
        return 1
    fi
    rm -rf -- "$parser_directory"
}

validate_prestate() {
    local candidate=$stage_directory/keepalived-caddy-ha.conf

    require_check identity_root test "$(id -u)" -eq 0 || return 1
    require_check working_directory_root test "$(pwd -P)" = / || return 1
    require_check hostname_node_b test "$(hostname)" = j1-svpihole00 || return 1
    require_check architecture_arm64 \
        test "$(dpkg --print-architecture)" = arm64 || return 1
    require_check physical_ipv4_exact test \
        "$(address_count 4 10.1.0.54/22)" -eq 1 || return 1
    require_check physical_ipv6_exact test \
        "$(address_count 6 fd36:5aa8:6971:1::54/64)" -eq 1 || return 1
    require_check stage_directory_regular test -d "$stage_directory" || return 1
    require_check stage_directory_not_symlink test ! -L "$stage_directory" ||
        return 1
    require_check stage_directory_metadata \
        test "$(stat -c '%U:%G:%a' "$stage_directory")" = root:root:700 ||
        return 1
    validate_fragment_contract "$candidate" staged_fragment || return 1
    require_check candidate_parser_valid validate_candidate_parser "$candidate" ||
        return 1
    require_check target_absent test ! -e "$fragment" || return 1
    require_check target_not_symlink test ! -L "$fragment" || return 1
    require_check main_configuration_regular test -f "$main_configuration" ||
        return 1
    require_check main_configuration_not_symlink test ! -L "$main_configuration" ||
        return 1
    # The child shell must evaluate its positional parameter.
    # shellcheck disable=SC2016
    require_check main_configuration_excludes_fragment \
        bash -c '! grep -Eq "^[[:space:]]*(include|include_dir).*conf\.d|caddy-ha\.conf" "$1"' \
        _ "$main_configuration" || return 1
    require_check accepted_keepalived_tree_hash \
        test "$(tree_hash /etc/keepalived)" = \
        "$expected_keepalived_tree_sha256" || return 1
    main_sha256_before=$(file_hash "$main_configuration") || return 1
    # The child shell validates its positional parameter.
    # shellcheck disable=SC2016
    require_check main_hash_format \
        bash -c '[[ "$1" =~ ^[0-9a-f]{64}$ ]]' _ "$main_sha256_before" ||
        return 1
    require_check health_script_regular test -f "$health_script" || return 1
    require_check health_script_not_symlink test ! -L "$health_script" || return 1
    require_check health_script_hash_exact \
        test "$(file_hash "$health_script")" = "$expected_health_sha256" ||
        return 1
    require_check notification_script_regular test -f "$notification_script" ||
        return 1
    require_check notification_script_not_symlink test ! -L "$notification_script" ||
        return 1
    require_check notification_script_hash_exact \
        test "$(file_hash "$notification_script")" = \
        "$expected_notification_sha256" || return 1
    require_check rollback_root_directory test -d "$rollback_root" || return 1
    require_check rollback_root_not_symlink test ! -L "$rollback_root" ||
        return 1
    require_check rollback_root_metadata \
        test "$(stat -c '%U:%G:%a' "$rollback_root")" = root:root:700 ||
        return 1
    require_check prior_backup_absent \
        test -z "$(find "$rollback_root" -mindepth 1 -maxdepth 1 \
            -name 'action19a-node-b-keepalived-fragment.*' -print -quit)" ||
        return 1
    require_check prior_install_stage_absent \
        test -z "$(find /etc/keepalived -mindepth 1 -maxdepth 2 \
            -name '.caddy-ha.conf.action19a.*' -print -quit)" || return 1
    require_check keepalived_active \
        test "$(systemctl is-active keepalived.service)" = active || return 1
    require_check keepalived_enabled \
        test "$(systemctl is-enabled keepalived.service)" = enabled || return 1
    require_check caddy_active \
        test "$(systemctl is-active caddy.service)" = active || return 1
    require_check lighttpd_active \
        test "$(systemctl is-active lighttpd.service)" = active || return 1
    require_check ipv4_vip_absent test \
        "$(address_count 4 "$vip_ipv4_cidr")" -eq 0 || return 1
    require_check ipv6_vip_absent test \
        "$(address_count 6 "$vip_ipv6_cidr")" -eq 0 || return 1
    capture_service_state || return 1
}

validate_poststate() {
    validate_fragment_contract "$fragment" live_fragment || return 1
    require_check live_fragment_parser_valid validate_candidate_parser "$fragment" ||
        return 1
    require_check main_configuration_hash_unchanged \
        test "$(file_hash "$main_configuration")" = "$main_sha256_before" ||
        return 1
    # The child shell must evaluate its positional parameter.
    # shellcheck disable=SC2016
    require_check main_configuration_still_excludes_fragment \
        bash -c '! grep -Eq "^[[:space:]]*(include|include_dir).*conf\.d|caddy-ha\.conf" "$1"' \
        _ "$main_configuration" || return 1
    require_check ipv4_vip_still_absent test \
        "$(address_count 4 "$vip_ipv4_cidr")" -eq 0 || return 1
    require_check ipv6_vip_still_absent test \
        "$(address_count 6 "$vip_ipv6_cidr")" -eq 0 || return 1
    validate_service_continuity || return 1
}

validate_backup() {
    local expected_manifest

    expected_manifest=$(printf '%s\n' \
        'action=action19a' \
        'node=node-b' \
        'fragment_pre_state=absent' \
        "fragment_directory_preexisting=$([[ "$directory_created" == true ]] && printf false || printf true)" \
        "main_configuration_sha256=$main_sha256_before" \
        "fragment_candidate_sha256=$expected_fragment_sha256") || return 1
    require_check backup_directory_regular test -d "$rollback_directory" ||
        return 1
    require_check backup_directory_not_symlink test ! -L "$rollback_directory" ||
        return 1
    require_check backup_directory_metadata \
        test "$(stat -c '%U:%G:%a' "$rollback_directory")" = root:root:700 ||
        return 1
    require_check backup_manifest_regular test -f "$rollback_directory/manifest" ||
        return 1
    require_check backup_manifest_not_symlink \
        test ! -L "$rollback_directory/manifest" || return 1
    require_check backup_manifest_metadata \
        test "$(stat -c '%U:%G:%a' "$rollback_directory/manifest")" = \
        root:root:600 || return 1
    require_check backup_manifest_content_exact \
        test "$(<"$rollback_directory/manifest")" = "$expected_manifest" ||
        return 1
}

rollback() {
    local original_status=$?
    local rollback_failed=false

    trap - ERR INT TERM EXIT
    if [[ "$transaction_complete" == true ]]; then
        return 0
    fi
    if [[ "$mutation_started" != true ]]; then
        exit "$original_status"
    fi
    printf '%s_rollback_started=true\n' "$prefix" >&2
    if [[ -n "$install_stage" && (-e "$install_stage" || -L "$install_stage") ]]; then
        rm -f -- "$install_stage" || rollback_failed=true
    fi
    if [[ -e "$fragment" || -L "$fragment" ]]; then
        rm -f -- "$fragment" || rollback_failed=true
    fi
    if [[ "$directory_created" == true && -d "$fragment_directory" &&
        ! -L "$fragment_directory" ]]; then
        rmdir -- "$fragment_directory" || rollback_failed=true
    fi
    if [[ -n "$rollback_directory" && -d "$rollback_directory" &&
        ! -L "$rollback_directory" ]]; then
        rm -rf -- "$rollback_directory" || rollback_failed=true
    else
        rollback_failed=true
    fi
    [[ ! -e "$fragment" && ! -L "$fragment" ]] || rollback_failed=true
    [[ "$(tree_hash /etc/keepalived)" = "$expected_keepalived_tree_sha256" ]] || rollback_failed=true
    [[ "$(file_hash "$main_configuration")" = "$main_sha256_before" ]] ||
        rollback_failed=true
    validate_service_continuity >/dev/null 2>&1 || rollback_failed=true
    if [[ "$rollback_failed" == true ]]; then
        printf '%s_rollback_complete=false\n' "$prefix" >&2
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        exit 125
    fi
    printf '%s_rollback_complete=true\n' "$prefix" >&2
    exit "$original_status"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$expected_fragment_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_keepalived_tree_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_health_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_notification_sha256" =~ ^[0-9a-f]{64}$ ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --stage)
        [[ $# -eq 2 ]] || exit 64
        stage_directory=$2
        ;;
    *)
        usage
        exit 64
        ;;
esac

trap rollback ERR INT TERM EXIT
validate_prestate
printf '%s_preflight_complete=true\n' "$prefix"

mutation_started=true
printf '%s_mutation_started=true\n' "$prefix"
rollback_directory=$(mktemp -d \
    "$rollback_root/action19a-node-b-keepalived-fragment.XXXXXX")
chmod 0700 "$rollback_directory"
if [[ ! -d "$fragment_directory" ]]; then
    install -d -o root -g root -m 0755 "$fragment_directory"
    directory_created=true
fi
printf '%s\n' \
    'action=action19a' \
    'node=node-b' \
    'fragment_pre_state=absent' \
    "fragment_directory_preexisting=$([[ "$directory_created" == true ]] && printf false || printf true)" \
    "main_configuration_sha256=$main_sha256_before" \
    "fragment_candidate_sha256=$expected_fragment_sha256" \
    >"$rollback_directory/manifest"
chmod 0600 "$rollback_directory/manifest"
install_stage=$(mktemp "$fragment_directory/.caddy-ha.conf.action19a.XXXXXX")
install -o root -g root -m 0644 \
    "$stage_directory/keepalived-caddy-ha.conf" "$install_stage"
mv -- "$install_stage" "$fragment"
install_stage=

validate_backup
validate_poststate
transaction_complete=true
trap - ERR INT TERM EXIT

printf '%s_fragment_installed=true\n' "$prefix"
printf '%s_main_configuration_mutated=false\n' "$prefix"
printf '%s_keepalived_reloaded=false\n' "$prefix"
printf '%s_keepalived_restarted=false\n' "$prefix"
printf '%s_vrrp_transition_requested=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_backup_path=%s\n' "$prefix" "$rollback_directory"
printf '%s_persistent_mutation_scope=fragment,rollback_backup\n' "$prefix"
printf '%s_install_complete=true\n' "$prefix"
