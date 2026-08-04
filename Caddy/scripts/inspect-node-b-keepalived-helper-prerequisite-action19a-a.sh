#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_19a_a
readonly keepalived_root=/etc/keepalived
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly rollback_root=/var/backups/caddy-ha
readonly health_script=/usr/local/libexec/check-caddy.sh
readonly notification_script=/usr/local/libexec/lsyncd-ha-failover-notify.sh
readonly certificate_script=/usr/local/libexec/check-certificate-expiry.sh
readonly sync_failure_script=/usr/local/libexec/lsyncd-sync-failure-notify.sh
readonly reconcile_script=/usr/local/libexec/reconcile-release.sh
readonly sync_health_script=/usr/local/libexec/validate-sync-health.sh
readonly expected_keepalived_tree_sha256=68d2bc846ad94da2a995f52e0f7829ff1c5706f35e399e40e1a0a552f37afd4f
readonly expected_health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly expected_notification_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly expected_certificate_sha256=b4fec5ef37353aa944a3f319503b96ed60768e8bb1a204c539182f8aae1ee80f
readonly expected_sync_failure_sha256=cf59ceab47ae48e2793205c90cf39fccec236d21b1d55e39821560899dc83cd6
readonly expected_reconcile_sha256=9dcf65119599060b064ee820655f8e8d18839fdee1d1d2526d0e3e1c3eedbc1b
readonly expected_sync_health_sha256=77c5ab2ada350d24bf890eb055db58e6e46086cda6e023b533c7c793c181f56b
readonly expected_active_release=/etc/caddy/releases/action15-health-follow-redirects

readonly -a snapshot_units=(
    keepalived.service
    caddy.service
    lighttpd.service
    lsyncd.service
    caddy-lsyncd.service
    caddy-sync-reconcile.path
    caddy-sync-reconcile.service
)
readonly -a expected_assertions=(
    identity_root
    working_directory_root
    hostname_node_b
    architecture_arm64
    physical_ipv4_exact
    physical_ipv6_exact
    main_configuration_regular
    main_configuration_not_symlink
    main_configuration_excludes_fragment
    keepalived_tree_hash_exact
    fragment_absent
    fragment_not_symlink
    health_state_absent
    health_not_symlink
    notification_state_supported
    notification_not_symlink
    certificate_helper_regular
    certificate_helper_not_symlink
    certificate_helper_metadata_exact
    certificate_helper_hash_exact
    sync_failure_helper_regular
    sync_failure_helper_not_symlink
    sync_failure_helper_metadata_exact
    sync_failure_helper_hash_exact
    reconcile_helper_regular
    reconcile_helper_not_symlink
    reconcile_helper_metadata_exact
    reconcile_helper_hash_exact
    sync_health_helper_regular
    sync_health_helper_not_symlink
    sync_health_helper_metadata_exact
    sync_health_helper_hash_exact
    action19a_backup_count_zero
    action19a_run_stage_count_zero
    action19a_tmp_stage_count_zero
    action19a_install_stage_count_zero
    keepalived_active
    keepalived_enabled
    caddy_active
    lighttpd_active
    lsyncd_inactive
    lsyncd_masked
    caddy_lsyncd_inactive
    caddy_lsyncd_disabled
    reconcile_path_inactive
    reconcile_service_inactive
    current_link_exact
    current_target_exact
    caddy_ipv4_vip_absent
    caddy_ipv6_vip_absent
    dns_ipv4_vip_count_supported
    dns_ipv6_vip_count_supported
    dns_vip_dualstack_coherent
    before_state_status_zero
    before_state_stderr_empty
    before_state_hash_format
    after_state_status_zero
    after_state_stderr_empty
    after_state_hash_format
    state_unchanged
    assertion_count_nonnegative
)

assertion_count=0
failed_assertion_count=0
first_failure=none

record_assertion() {
    local assertion_label=$1
    local assertion_value=$2

    assertion_count=$((assertion_count + 1))
    printf '%s_assertion_%s=%s\n' "$prefix" "$assertion_label" \
        "$assertion_value"
    if [[ "$assertion_value" != true ]]; then
        failed_assertion_count=$((failed_assertion_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$assertion_label
        fi
    fi
}

record_command() {
    local command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_assertion "$command_label" true
    else
        record_assertion "$command_label" false
    fi
}

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

tree_hash() {
    local tree_root=$1

    (
        cd "$tree_root" || exit
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

helper_state() {
    local expected_hash=$1
    local helper_path=$2
    local observed_metadata

    if [[ ! -e "$helper_path" && ! -L "$helper_path" ]]; then
        printf absent
        return 0
    fi
    if [[ ! -f "$helper_path" || -L "$helper_path" ]]; then
        printf unexpected_type
        return 0
    fi
    observed_metadata=$(stat -c '%U:%G:%a' "$helper_path" 2>/dev/null || true)
    if [[ "$observed_metadata" != root:root:755 ]]; then
        printf unexpected_metadata
        return 0
    fi
    if [[ "$(file_hash "$helper_path" 2>/dev/null || true)" != "$expected_hash" ]]; then
        printf unexpected_hash
        return 0
    fi
    printf exact
}

# These predicates are invoked indirectly through record_command.
# shellcheck disable=SC2317
state_supported() { [[ "$1" == absent || "$1" == exact ]]; }
# shellcheck disable=SC2317
is_nonnegative_integer() { [[ "$1" =~ ^[0-9]+$ ]]; }
is_sha256() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }

validate_exact_helper() {
    local expected_hash=$1
    local helper_label=$2
    local helper_path=$3

    record_command "${helper_label}_regular" test -f "$helper_path"
    record_command "${helper_label}_not_symlink" test ! -L "$helper_path"
    record_command "${helper_label}_metadata_exact" test \
        "$(stat -c '%U:%G:%a' "$helper_path" 2>/dev/null || true)" = \
        root:root:755
    record_command "${helper_label}_hash_exact" test \
        "$(file_hash "$helper_path" 2>/dev/null || true)" = "$expected_hash"
}

stable_state_snapshot() {
    local snapshot_unit

    stat -c '%n|%F|%U:%G:%a:%s:%i' \
        "$main_configuration" "$keepalived_root" "$rollback_root" \
        /etc/caddy/current
    for snapshot_helper in \
        "$health_script" "$notification_script" "$certificate_script" \
        "$sync_failure_script" "$reconcile_script" "$sync_health_script"; do
        if [[ -e "$snapshot_helper" || -L "$snapshot_helper" ]]; then
            stat -c '%n|%F|%U:%G:%a:%s:%i' "$snapshot_helper"
            if [[ -f "$snapshot_helper" && ! -L "$snapshot_helper" ]]; then
                printf 'helper_sha256=%s|%s\n' "$snapshot_helper" \
                    "$(file_hash "$snapshot_helper")"
            fi
        else
            printf 'helper_absent=%s\n' "$snapshot_helper"
        fi
    done
    printf 'keepalived_tree_sha256=%s\n' "$(tree_hash "$keepalived_root")"
    printf 'current_link=%s\n' "$(readlink /etc/caddy/current)"
    printf 'current_target=%s\n' "$(readlink -e /etc/caddy/current)"
    printf 'ipv4_physical=%s\n' "$(address_count 4 10.1.0.54/22)"
    printf 'ipv6_physical=%s\n' \
        "$(address_count 6 fd36:5aa8:6971:1::54/64)"
    printf 'ipv4_dns_vip=%s\n' "$(address_count 4 10.1.0.55/22)"
    printf 'ipv6_dns_vip=%s\n' \
        "$(address_count 6 fd36:5aa8:6971:1::55/128)"
    printf 'ipv4_caddy_vip=%s\n' "$(address_count 4 10.1.0.56/22)"
    printf 'ipv6_caddy_vip=%s\n' \
        "$(address_count 6 fd36:5aa8:6971:1::56/128)"
    for snapshot_unit in "${snapshot_units[@]}"; do
        printf 'unit=%s\n' "$snapshot_unit"
        systemctl show "$snapshot_unit" --no-pager \
            -p LoadState -p ActiveState -p SubState -p FragmentPath
        if [[ "$snapshot_unit" == *.service ]]; then
            systemctl show "$snapshot_unit" --no-pager \
                -p MainPID -p NRestarts
        fi
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$snapshot_unit" 2>/dev/null || true)"
    done
}

if [[ "${1:-}" == --expected-assertions && $# -eq 1 ]]; then
    printf '%s\n' "${expected_assertions[@]}"
    exit 0
elif [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    for self_test_hash in \
        "$expected_keepalived_tree_sha256" "$expected_health_sha256" \
        "$expected_notification_sha256" "$expected_certificate_sha256" \
        "$expected_sync_failure_sha256" "$expected_reconcile_sha256" \
        "$expected_sync_health_sha256"; do
        is_sha256 "$self_test_hash" || exit 1
    done
    [[ "${#expected_assertions[@]}" -eq 61 ]]
    [[ "$(printf '%s\n' "${expected_assertions[@]}" | sort -u | wc -l)" -eq 61 ]]
    printf '%s_inspector_self_test_complete=true\n' "$prefix"
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test|--expected-assertions]\n' "${0##*/}" >&2
    exit 64
fi

work_directory=$(mktemp -d /tmp/caddy-action19a-a-inspector.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly before_state="$work_directory/state.before"
readonly before_error="$work_directory/state.before.err"
readonly after_state="$work_directory/state.after"
readonly after_error="$work_directory/state.after.err"

record_command identity_root test "$(id -u)" -eq 0
record_command working_directory_root test "$(pwd -P)" = /
record_command hostname_node_b test "$(hostname)" = j1-svpihole00
record_command architecture_arm64 test \
    "$(dpkg --print-architecture 2>/dev/null || true)" = arm64
record_command physical_ipv4_exact test \
    "$(address_count 4 10.1.0.54/22)" -eq 1
record_command physical_ipv6_exact test \
    "$(address_count 6 fd36:5aa8:6971:1::54/64)" -eq 1
record_command main_configuration_regular test -f "$main_configuration"
record_command main_configuration_not_symlink test ! -L "$main_configuration"
# The child shell evaluates the supplied production path.
# shellcheck disable=SC2016
record_command main_configuration_excludes_fragment bash -c \
    '! grep -Eq "^[[:space:]]*(include|include_dir).*conf\.d|caddy-ha\.conf" "$1"' \
    _ "$main_configuration"
record_command keepalived_tree_hash_exact test \
    "$(tree_hash "$keepalived_root" 2>/dev/null || true)" = \
    "$expected_keepalived_tree_sha256"
record_command fragment_absent test ! -e "$fragment"
record_command fragment_not_symlink test ! -L "$fragment"

health_state=$(helper_state "$expected_health_sha256" "$health_script")
readonly health_state
notification_state=$(helper_state \
    "$expected_notification_sha256" "$notification_script")
readonly notification_state
record_command health_state_absent test "$health_state" = absent
record_command health_not_symlink test ! -L "$health_script"
record_command notification_state_supported state_supported "$notification_state"
record_command notification_not_symlink test ! -L "$notification_script"

validate_exact_helper "$expected_certificate_sha256" certificate_helper \
    "$certificate_script"
validate_exact_helper "$expected_sync_failure_sha256" sync_failure_helper \
    "$sync_failure_script"
validate_exact_helper "$expected_reconcile_sha256" reconcile_helper \
    "$reconcile_script"
validate_exact_helper "$expected_sync_health_sha256" sync_health_helper \
    "$sync_health_script"

action19a_backup_count=$(find "$rollback_root" -mindepth 1 -maxdepth 1 \
    -type d -name 'action19a-node-b-keepalived-fragment.*' -printf '.' \
    2>/dev/null | wc -c)
readonly action19a_backup_count
action19a_run_stage_count=$(find /run -mindepth 1 -maxdepth 1 -type d \
    -name 'caddy-action19a-*' -printf '.' 2>/dev/null | wc -c)
readonly action19a_run_stage_count
action19a_tmp_stage_count=$(find /tmp -mindepth 1 -maxdepth 1 -type d \
    -name 'caddy-action19a-*' ! -path "$work_directory" -printf '.' \
    2>/dev/null | wc -c)
readonly action19a_tmp_stage_count
action19a_install_stage_count=$(find "$keepalived_root" -mindepth 1 \
    -maxdepth 2 -name '.caddy-ha.conf.action19a.*' -printf '.' \
    2>/dev/null | wc -c)
readonly action19a_install_stage_count
record_command action19a_backup_count_zero test "$action19a_backup_count" -eq 0
record_command action19a_run_stage_count_zero test \
    "$action19a_run_stage_count" -eq 0
record_command action19a_tmp_stage_count_zero test \
    "$action19a_tmp_stage_count" -eq 0
record_command action19a_install_stage_count_zero test \
    "$action19a_install_stage_count" -eq 0

record_command keepalived_active test \
    "$(systemctl is-active keepalived.service 2>/dev/null || true)" = active
record_command keepalived_enabled test \
    "$(systemctl is-enabled keepalived.service 2>/dev/null || true)" = enabled
record_command caddy_active test \
    "$(systemctl is-active caddy.service 2>/dev/null || true)" = active
record_command lighttpd_active test \
    "$(systemctl is-active lighttpd.service 2>/dev/null || true)" = active
record_command lsyncd_inactive test \
    "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
record_command lsyncd_masked test \
    "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" = masked
record_command caddy_lsyncd_inactive test \
    "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = inactive
record_command caddy_lsyncd_disabled test \
    "$(systemctl is-enabled caddy-lsyncd.service 2>/dev/null || true)" = disabled
record_command reconcile_path_inactive test \
    "$(systemctl is-active caddy-sync-reconcile.path 2>/dev/null || true)" = \
    inactive
record_command reconcile_service_inactive test \
    "$(systemctl is-active caddy-sync-reconcile.service 2>/dev/null || true)" = \
    inactive
record_command current_link_exact test \
    "$(readlink /etc/caddy/current 2>/dev/null || true)" = \
    "$expected_active_release"
record_command current_target_exact test \
    "$(readlink -e /etc/caddy/current 2>/dev/null || true)" = \
    "$expected_active_release"
record_command caddy_ipv4_vip_absent test \
    "$(address_count 4 10.1.0.56/22)" -eq 0
record_command caddy_ipv6_vip_absent test \
    "$(address_count 6 fd36:5aa8:6971:1::56/128)" -eq 0

dns_ipv4_vip_count=$(address_count 4 10.1.0.55/22)
readonly dns_ipv4_vip_count
dns_ipv6_vip_count=$(address_count 6 fd36:5aa8:6971:1::55/128)
readonly dns_ipv6_vip_count
record_command dns_ipv4_vip_count_supported test "$dns_ipv4_vip_count" -le 1
record_command dns_ipv6_vip_count_supported test "$dns_ipv6_vip_count" -le 1
record_command dns_vip_dualstack_coherent test \
    "$dns_ipv4_vip_count" -eq "$dns_ipv6_vip_count"

before_status=0
stable_state_snapshot >"$before_state" 2>"$before_error" || before_status=$?
readonly before_status
record_command before_state_status_zero test "$before_status" -eq 0
record_command before_state_stderr_empty test ! -s "$before_error"
before_state_sha256=unavailable
if [[ "$before_status" -eq 0 ]]; then
    before_state_sha256=$(file_hash "$before_state")
fi
readonly before_state_sha256
record_command before_state_hash_format is_sha256 "$before_state_sha256"

after_status=0
stable_state_snapshot >"$after_state" 2>"$after_error" || after_status=$?
readonly after_status
record_command after_state_status_zero test "$after_status" -eq 0
record_command after_state_stderr_empty test ! -s "$after_error"
after_state_sha256=unavailable
if [[ "$after_status" -eq 0 ]]; then
    after_state_sha256=$(file_hash "$after_state")
fi
readonly after_state_sha256
record_command after_state_hash_format is_sha256 "$after_state_sha256"
record_command state_unchanged test "$after_state_sha256" = "$before_state_sha256"
record_command assertion_count_nonnegative is_nonnegative_integer "$assertion_count"

printf '%s_value_health_state=%s\n' "$prefix" "$health_state"
printf '%s_value_health_observed_sha256=%s\n' "$prefix" \
    "$(file_hash "$health_script" 2>/dev/null || printf absent)"
printf '%s_value_notification_state=%s\n' "$prefix" "$notification_state"
printf '%s_value_notification_observed_sha256=%s\n' "$prefix" \
    "$(file_hash "$notification_script" 2>/dev/null || printf absent)"
printf '%s_value_action19a_backup_count=%s\n' "$prefix" \
    "$action19a_backup_count"
printf '%s_value_action19a_run_stage_count=%s\n' "$prefix" \
    "$action19a_run_stage_count"
printf '%s_value_action19a_tmp_stage_count=%s\n' "$prefix" \
    "$action19a_tmp_stage_count"
printf '%s_value_action19a_install_stage_count=%s\n' "$prefix" \
    "$action19a_install_stage_count"
printf '%s_value_dns_ipv4_vip_count=%s\n' "$prefix" "$dns_ipv4_vip_count"
printf '%s_value_dns_ipv6_vip_count=%s\n' "$prefix" "$dns_ipv6_vip_count"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state_sha256"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state_sha256"
printf '%s_assertion_count=%s\n' "$prefix" "$assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_helper_execution=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

if [[ "$failed_assertion_count" -eq 0 ]]; then
    exit 0
fi
exit 1
