#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_19b
readonly health_target=/usr/local/libexec/check-caddy.sh
readonly notification_target=/usr/local/libexec/lsyncd-ha-failover-notify.sh
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly keepalived_main=/etc/keepalived/keepalived.conf
readonly rollback_root=/var/backups/caddy-ha
readonly active_release=/etc/caddy/releases/action15-health-follow-redirects
readonly expected_health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly expected_notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly expected_inspector_sha256=162f153d116e53aba95775836c4a5cb6677ad7fd080c673ca6c5ac8fb0092a0f

readonly -a continuity_units=(
    caddy.service
    lighttpd.service
    keepalived.service
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
health_install_stage=
notification_install_stage=
keepalived_main_before=
keepalived_tree_before=
current_link_before=
current_target_before=
physical_ipv4_count_before=
physical_ipv6_count_before=
dns_ipv4_count_before=
dns_ipv6_count_before=
caddy_ipv4_count_before=
caddy_ipv6_count_before=
mutation_started=false
transaction_complete=false

usage() {
    printf 'Usage: %s --stage DIRECTORY\n' "${0##*/}" >&2
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
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

tree_digest() {
    local digest_root=$1

    (
        cd "$digest_root"
        find . -printf '%P|%y|%U:%G:%m:%s\n' | LC_ALL=C sort
        find . -type f -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

address_count() {
    local address_value=$1

    ip -o address show | awk -v address="$address_value" \
        '$4 == address { count++ } END { print count + 0 }'
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

validate_source() {
    local expected_hash=$1
    local source_label=$2
    local source_path=$3

    require_check "stage_${source_label}_regular" test -f "$source_path" ||
        return 1
    require_check "stage_${source_label}_not_symlink" test ! -L "$source_path" ||
        return 1
    require_check "stage_${source_label}_metadata" \
        test "$(stat -c '%U:%G:%a' "$source_path")" = root:root:700 ||
        return 1
    require_check "stage_${source_label}_hash_exact" \
        test "$(file_hash "$source_path")" = "$expected_hash" || return 1
    require_check "stage_${source_label}_syntax" bash -n "$source_path" ||
        return 1
}

validate_action19a_a_baseline() {
    local baseline_error=$stage_directory/action19a-a.stderr
    local baseline_output=$stage_directory/action19a-a.stdout
    local baseline_status=0
    local check_count
    local unique_count

    : >"$baseline_output"
    : >"$baseline_error"
    chmod 0600 "$baseline_output" "$baseline_error"
    /bin/bash "$stage_directory/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh" \
        >"$baseline_output" 2>"$baseline_error" || baseline_status=$?
    require_check action19a_a_status_zero test "$baseline_status" -eq 0 ||
        return 1
    require_check action19a_a_stderr_empty test ! -s "$baseline_error" ||
        return 1
    check_count=$(grep -Ec '^action_19a_a_check_[a-z0-9_]+=true$' \
        "$baseline_output" || true)
    require_check action19a_a_check_count_exact test "$check_count" -eq 61 ||
        return 1
    unique_count=$(sed -n \
        's/^\(action_19a_a_check_[a-z0-9_]*\)=true$/\1/p' \
        "$baseline_output" | LC_ALL=C sort -u | wc -l)
    require_check action19a_a_check_labels_unique \
        test "$unique_count" -eq 61 || return 1
    require_check action19a_a_false_assertions_absent \
        test "$(grep -Ec '^action_19a_a_check_[a-z0-9_]+=false$' \
            "$baseline_output" || true)" -eq 0 || return 1
    require_check action19a_a_helper_invocation_false grep -Fxq \
        'action_19a_a_helper_invoked=false' "$baseline_output" || return 1
    require_check action19a_a_persistent_mutation_false grep -Fxq \
        'action_19a_a_persistent_mutation=false' "$baseline_output" || return 1
    require_check action19a_a_state_unchanged grep -Fxq \
        'action_19a_a_state_unchanged=true' "$baseline_output" || return 1
}

capture_continuity_state() {
    keepalived_main_before=$(file_hash "$keepalived_main") || return 1
    keepalived_tree_before=$(tree_digest /etc/keepalived) || return 1
    current_link_before=$(readlink /etc/caddy/current) || return 1
    current_target_before=$(readlink -e /etc/caddy/current) || return 1
    physical_ipv4_count_before=$(address_count 10.1.0.54/22) || return 1
    physical_ipv6_count_before=$(address_count fd36:5aa8:6971:1::54/64) ||
        return 1
    dns_ipv4_count_before=$(address_count 10.1.0.55/22) || return 1
    dns_ipv6_count_before=$(address_count fd36:5aa8:6971:1::55/128) ||
        return 1
    caddy_ipv4_count_before=$(address_count 10.1.0.56/22) || return 1
    caddy_ipv6_count_before=$(address_count fd36:5aa8:6971:1::56/128) ||
        return 1
    capture_service_state
}

validate_prestate() {
    require_check identity_root test "$(id -u)" -eq 0 || return 1
    require_check working_directory_root test "$(pwd -P)" = / || return 1
    require_check hostname_node_b test "$(hostname)" = j1-svpihole00 || return 1
    require_check architecture_arm64 test "$(dpkg --print-architecture)" = arm64 ||
        return 1
    require_check stage_directory_regular test -d "$stage_directory" || return 1
    require_check stage_directory_not_symlink test ! -L "$stage_directory" ||
        return 1
    require_check stage_directory_metadata \
        test "$(stat -c '%U:%G:%a' "$stage_directory")" = root:root:700 ||
        return 1
    validate_source "$expected_health_sha256" health \
        "$stage_directory/check-caddy.sh" || return 1
    validate_source "$expected_notification_sha256" notification \
        "$stage_directory/lsyncd-ha-failover-notify.sh" || return 1
    validate_source "$expected_inspector_sha256" action19a_a_inspector \
        "$stage_directory/inspect-node-b-keepalived-helper-prerequisite-action19a-a.sh" ||
        return 1
    validate_action19a_a_baseline || return 1
    require_check libexec_directory_metadata \
        test "$(stat -c '%U:%G:%a' /usr/local/libexec)" = root:root:755 ||
        return 1
    require_check rollback_root_directory test -d "$rollback_root" || return 1
    require_check rollback_root_not_symlink test ! -L "$rollback_root" ||
        return 1
    require_check rollback_root_metadata \
        test "$(stat -c '%U:%G:%a' "$rollback_root")" = root:root:700 ||
        return 1
    require_check prior_action19b_backup_absent \
        test -z "$(find "$rollback_root" -mindepth 1 -maxdepth 1 \
            -name 'action19b-node-b-keepalived-helpers.*' -print -quit)" ||
        return 1
    require_check prior_health_install_stage_absent \
        test -z "$(find /usr/local/libexec -mindepth 1 -maxdepth 1 \
            -name '.check-caddy.action19b.*' -print -quit)" || return 1
    require_check prior_notification_install_stage_absent \
        test -z "$(find /usr/local/libexec -mindepth 1 -maxdepth 1 \
            -name '.lsyncd-ha-failover-notify.action19b.*' -print -quit)" ||
        return 1
    capture_continuity_state
}

validate_backup() {
    local expected_manifest

    expected_manifest=$(printf '%s\n' \
        'action=action19b' \
        'health_pre_state=absent' \
        'notification_pre_state=absent' \
        "health_candidate_sha256=$expected_health_sha256" \
        "notification_candidate_sha256=$expected_notification_sha256") ||
        return 1
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

validate_installed_helper() {
    local expected_hash=$1
    local helper_label=$2
    local helper_path=$3

    require_check "live_${helper_label}_regular" test -f "$helper_path" ||
        return 1
    require_check "live_${helper_label}_not_symlink" test ! -L "$helper_path" ||
        return 1
    require_check "live_${helper_label}_metadata" \
        test "$(stat -c '%U:%G:%a' "$helper_path")" = root:root:755 ||
        return 1
    require_check "live_${helper_label}_hash_exact" \
        test "$(file_hash "$helper_path")" = "$expected_hash" || return 1
    require_check "live_${helper_label}_syntax" bash -n "$helper_path" ||
        return 1
}

validate_poststate() {
    validate_installed_helper "$expected_health_sha256" health "$health_target" ||
        return 1
    validate_installed_helper "$expected_notification_sha256" notification \
        "$notification_target" || return 1
    require_check health_default_file_regular test -f /etc/default/caddy-ha ||
        return 1
    require_check health_caddy_command_available command -v caddy || return 1
    require_check health_curl_command_available command -v curl || return 1
    require_check notification_jq_command_available command -v jq || return 1
    require_check notification_logger_command_available command -v logger ||
        return 1
    require_check notification_endpoint_exact grep -Fq \
        "readonly apprise_endpoint='http://10.1.3.83:8000/notify/apprise'" \
        "$notification_target" || return 1
    validate_backup || return 1
    require_check keepalived_main_hash_unchanged \
        test "$(file_hash "$keepalived_main")" = "$keepalived_main_before" ||
        return 1
    require_check keepalived_tree_hash_unchanged \
        test "$(tree_digest /etc/keepalived)" = "$keepalived_tree_before" ||
        return 1
    require_check caddy_fragment_still_absent test ! -e "$fragment" || return 1
    require_check caddy_fragment_still_not_symlink test ! -L "$fragment" ||
        return 1
    require_check current_link_unchanged \
        test "$(readlink /etc/caddy/current)" = "$current_link_before" ||
        return 1
    require_check current_target_unchanged \
        test "$(readlink -e /etc/caddy/current)" = "$current_target_before" ||
        return 1
    require_check active_release_still_exact \
        test "$current_target_before" = "$active_release" || return 1
    require_check physical_ipv4_count_unchanged \
        test "$(address_count 10.1.0.54/22)" = "$physical_ipv4_count_before" ||
        return 1
    require_check physical_ipv6_count_unchanged \
        test "$(address_count fd36:5aa8:6971:1::54/64)" = \
        "$physical_ipv6_count_before" || return 1
    require_check dns_ipv4_count_unchanged \
        test "$(address_count 10.1.0.55/22)" = "$dns_ipv4_count_before" ||
        return 1
    require_check dns_ipv6_count_unchanged \
        test "$(address_count fd36:5aa8:6971:1::55/128)" = \
        "$dns_ipv6_count_before" || return 1
    require_check caddy_ipv4_count_unchanged \
        test "$(address_count 10.1.0.56/22)" = "$caddy_ipv4_count_before" ||
        return 1
    require_check caddy_ipv6_count_unchanged \
        test "$(address_count fd36:5aa8:6971:1::56/128)" = \
        "$caddy_ipv6_count_before" || return 1
    require_check action19a_backup_still_absent \
        test -z "$(find "$rollback_root" -mindepth 1 -maxdepth 1 \
            -name 'action19a-node-b-keepalived-fragment.*' -print -quit)" ||
        return 1
    validate_service_continuity
}

cleanup_install_stages() {
    local stage_path

    for stage_path in "$health_install_stage" "$notification_install_stage"; do
        if [[ -n "$stage_path" && (-e "$stage_path" || -L "$stage_path") ]]; then
            rm -f -- "$stage_path" || return 1
        fi
    done
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
    cleanup_install_stages || rollback_failed=true
    rm -f -- "$health_target" "$notification_target" || rollback_failed=true
    [[ ! -e "$health_target" && ! -L "$health_target" ]] ||
        rollback_failed=true
    [[ ! -e "$notification_target" && ! -L "$notification_target" ]] ||
        rollback_failed=true
    if [[ -n "$rollback_directory" && -d "$rollback_directory" &&
        ! -L "$rollback_directory" ]]; then
        rm -rf -- "$rollback_directory" || rollback_failed=true
    elif [[ -n "$rollback_directory" &&
        (-e "$rollback_directory" || -L "$rollback_directory") ]]; then
        rollback_failed=true
    fi
    [[ "$(file_hash "$keepalived_main")" = "$keepalived_main_before" ]] ||
        rollback_failed=true
    [[ "$(tree_digest /etc/keepalived)" = "$keepalived_tree_before" ]] ||
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
        [[ "$expected_health_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_notification_sha256" =~ ^[0-9a-f]{64}$ ]]
        [[ "$expected_inspector_sha256" =~ ^[0-9a-f]{64}$ ]]
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
    "$rollback_root/action19b-node-b-keepalived-helpers.XXXXXX")
chmod 0700 "$rollback_directory"
printf '%s\n' \
    'action=action19b' \
    'health_pre_state=absent' \
    'notification_pre_state=absent' \
    "health_candidate_sha256=$expected_health_sha256" \
    "notification_candidate_sha256=$expected_notification_sha256" \
    >"$rollback_directory/manifest"
chmod 0600 "$rollback_directory/manifest"

health_install_stage=$(mktemp /usr/local/libexec/.check-caddy.action19b.XXXXXX)
notification_install_stage=$(mktemp \
    /usr/local/libexec/.lsyncd-ha-failover-notify.action19b.XXXXXX)
install -o root -g root -m 0755 "$stage_directory/check-caddy.sh" \
    "$health_install_stage"
install -o root -g root -m 0755 \
    "$stage_directory/lsyncd-ha-failover-notify.sh" \
    "$notification_install_stage"
mv -- "$health_install_stage" "$health_target"
health_install_stage=
mv -- "$notification_install_stage" "$notification_target"
notification_install_stage=

validate_poststate
transaction_complete=true
trap - ERR INT TERM EXIT

printf '%s_helpers_invoked=false\n' "$prefix"
printf '%s_fragment_mutated=false\n' "$prefix"
printf '%s_keepalived_mutated=false\n' "$prefix"
printf '%s_vrrp_mutated=false\n' "$prefix"
printf '%s_vip_mutated=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_backup_path=%s\n' "$prefix" "$rollback_directory"
printf '%s_persistent_mutation_scope=two_helpers,rollback_backup\n' "$prefix"
printf '%s_install_complete=true\n' "$prefix"
