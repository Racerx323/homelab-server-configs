#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20e_b
readonly installed_config=/etc/tmpfiles.d/caddy-ha.conf
readonly state_directory=/run/caddy-ha
readonly notify_directory=/run/caddy-ha-notify
readonly notifier=/usr/local/libexec/lsyncd-ha-failover-notify.sh
readonly expected_notifier_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly caddy_ipv4=10.1.0.56/22
readonly caddy_ipv6=fd36:5aa8:6971:1::56/128
readonly dns_ipv4=10.1.0.55/22
readonly dns_ipv6=fd36:5aa8:6971:1::55/128

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
sanitize_value() {
    tr '\t\r\n' '   ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}
address_count() {
    local inspected_family=$1
    local inspected_cidr=$2

    ip -o "-$inspected_family" address show dev eth0 2>/dev/null |
        awk -v expected="$inspected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}
unit_property() {
    local inspected_property=$2
    local inspected_unit=$1

    systemctl show "$inspected_unit" --no-pager \
        --property="$inspected_property" --value 2>/dev/null | sanitize_value
}
normalized_path_state() {
    local inspected_path=$1

    stat -c '%F|%U:%G:%a|%u:%g:%a' "$inspected_path" 2>/dev/null || printf absent
}
residue_count() {
    local residue_pattern=$1

    find /run -mindepth 1 -maxdepth 1 -name "$residue_pattern" -printf '.\n' |
        awk 'END { print NR + 0 }'
}
backup_count() {
    find /var/backups/caddy-ha -mindepth 1 -maxdepth 1 -type d \
        -name 'action20e-node-b-runtime-directories.*' -printf '.\n' 2>/dev/null |
        awk 'END { print NR + 0 }'
}
create_shadow_tree() {
    local created_group=$2
    local created_owner=$1
    local created_path=$3

    install -d -o "$created_owner" -g "$created_group" -m 0700 "$created_path"
}
classify_shadow_tree() {
    local classified_etc=$2
    local classified_root=$1

    if [[ "$classified_root" =~ :755$ && "$classified_etc" =~ :755$ ]]; then
        printf intermediate_parents_default_0755
    elif [[ "$classified_root" =~ :700$ && "$classified_etc" =~ :700$ ]]; then
        printf all_requested_mode_0700
    else
        printf unexpected
    fi
}
snapshot_components() {
    printf '%s\n' \
        keepalived_main_sha256 keepalived_fragment_sha256 notifier_sha256 \
        current_target addresses_normalized caddy_active_state caddy_sub_state \
        caddy_main_pid caddy_n_restarts keepalived_active_state \
        keepalived_sub_state keepalived_main_pid keepalived_n_restarts \
        lighttpd_active_state lighttpd_sub_state lighttpd_main_pid \
        lighttpd_n_restarts installed_config_state runtime_state notify_state \
        original_stage_count retry_stage_count backup_count
}
component_value() {
    local requested_component=$1

    case "$requested_component" in
        keepalived_main_sha256) file_hash /etc/keepalived/keepalived.conf ;;
        keepalived_fragment_sha256) file_hash /etc/keepalived/conf.d/caddy-ha.conf ;;
        notifier_sha256) file_hash "$notifier" ;;
        current_target) readlink -f /etc/caddy/current ;;
        addresses_normalized)
            ip -o address show dev eth0 2>/dev/null |
                awk '{ print $3 "|" $4 }' | LC_ALL=C sort -u | paste -sd, -
            ;;
        caddy_active_state) unit_property caddy.service ActiveState ;;
        caddy_sub_state) unit_property caddy.service SubState ;;
        caddy_main_pid) unit_property caddy.service MainPID ;;
        caddy_n_restarts) unit_property caddy.service NRestarts ;;
        keepalived_active_state) unit_property keepalived.service ActiveState ;;
        keepalived_sub_state) unit_property keepalived.service SubState ;;
        keepalived_main_pid) unit_property keepalived.service MainPID ;;
        keepalived_n_restarts) unit_property keepalived.service NRestarts ;;
        lighttpd_active_state) unit_property lighttpd.service ActiveState ;;
        lighttpd_sub_state) unit_property lighttpd.service SubState ;;
        lighttpd_main_pid) unit_property lighttpd.service MainPID ;;
        lighttpd_n_restarts) unit_property lighttpd.service NRestarts ;;
        installed_config_state) normalized_path_state "$installed_config" ;;
        runtime_state) normalized_path_state "$state_directory" ;;
        notify_state) normalized_path_state "$notify_directory" ;;
        original_stage_count) residue_count 'caddy-action20e-node.*' ;;
        retry_stage_count) residue_count 'caddy-action20e-retry-node.*' ;;
        backup_count) backup_count ;;
        *) return 64 ;;
    esac
}
expected_assertions() {
    local listed_component
    local listed_phase

    printf '%s\n' \
        identity_root working_directory_root hostname_exact architecture_arm64 \
        config_absent runtime_absent notify_absent original_stage_absent \
        retry_stage_absent historical_backup_absent notifier_regular \
        notifier_not_symlink notifier_metadata_exact notifier_hash_exact \
        caddy_active keepalived_active lighttpd_active caddy_ipv4_absent \
        caddy_ipv6_absent dns_ipv4_absent_on_node_b dns_ipv6_absent_on_node_b \
        before_state_hash_format diagnostic_root_regular \
        diagnostic_root_not_symlink diagnostic_root_metadata_exact \
        shadow_root_regular shadow_root_not_symlink shadow_root_owner_exact \
        shadow_root_mode_observed shadow_etc_regular shadow_etc_not_symlink \
        shadow_etc_owner_exact shadow_etc_mode_observed shadow_tmpfiles_regular \
        shadow_tmpfiles_not_symlink shadow_tmpfiles_metadata_exact \
        reproduction_classification_known failure_boundary_reproduced \
        after_state_hash_format diagnostic_cleanup_status_zero \
        diagnostic_stage_residue_absent
    for listed_phase in before after; do
        while IFS= read -r listed_component; do
            printf 'snapshot_%s_%s_captured\n' "$listed_phase" "$listed_component"
        done < <(snapshot_components)
    done
    while IFS= read -r listed_component; do
        printf 'snapshot_%s_unchanged\n' "$listed_component"
    done < <(snapshot_components)
    printf '%s\n' state_unchanged
}
record_assertion() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$assertion_label"
    return 1
}

case "${1:-}" in
    --snapshot-components)
        [[ $# -eq 1 ]] || exit 64
        snapshot_components
        exit 0
        ;;
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_root=$(mktemp -d /tmp/caddy-action20e-b-self.XXXXXX)
        readonly self_root
        trap 'rm -rf -- "$self_root"' EXIT
        snapshot_components >"$self_root/components"
        expected_assertions >"$self_root/assertions"
        [[ "$(wc -l <"$self_root/components")" -eq 23 ]]
        [[ "$(LC_ALL=C sort -u "$self_root/components" | wc -l)" -eq 23 ]]
        [[ "$(wc -l <"$self_root/assertions")" -eq 111 ]]
        [[ "$(LC_ALL=C sort -u "$self_root/assertions" | wc -l)" -eq 111 ]]
        ! grep -Ev '^[a-z0-9_]+$' "$self_root/assertions" | grep -q .
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --reproduction-test)
        [[ $# -eq 2 ]] || exit 64
        reproduction_test_root=$2
        case "$reproduction_test_root" in
            /tmp/caddy-action20e-b-reproduction.*) ;;
            *) exit 64 ;;
        esac
        [[ -d "$reproduction_test_root" && ! -L "$reproduction_test_root" ]] || exit 64
        [[ -z "$(find "$reproduction_test_root" -mindepth 1 -print -quit)" ]] || exit 64
        reproduction_test_owner=$(id -un)
        readonly reproduction_test_owner
        reproduction_test_group=$(id -gn)
        readonly reproduction_test_group
        create_shadow_tree "$reproduction_test_owner" "$reproduction_test_group" \
            "$reproduction_test_root/shadow-root/etc/tmpfiles.d"
        reproduction_root_state=$(stat -c '%U:%G:%a' "$reproduction_test_root/shadow-root")
        readonly reproduction_root_state
        reproduction_etc_state=$(stat -c '%U:%G:%a' "$reproduction_test_root/shadow-root/etc")
        readonly reproduction_etc_state
        reproduction_leaf_state=$(stat -c '%U:%G:%a' "$reproduction_test_root/shadow-root/etc/tmpfiles.d")
        readonly reproduction_leaf_state
        printf '%s_reproduction_test_root=%s\n' "$prefix" "$reproduction_root_state"
        printf '%s_reproduction_test_etc=%s\n' "$prefix" "$reproduction_etc_state"
        printf '%s_reproduction_test_leaf=%s\n' "$prefix" "$reproduction_leaf_state"
        printf '%s_reproduction_test_classification=%s\n' "$prefix" \
            "$(classify_shadow_tree "$reproduction_root_state" "$reproduction_etc_state")"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--snapshot-components|--expected-assertions|--reproduction-test ROOT]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

diagnostic_root=$(mktemp -d /run/caddy-action20e-b-node.XXXXXX)
readonly diagnostic_root
case "$diagnostic_root" in
    /run/caddy-action20e-b-node.*) ;;
    *) exit 125 ;;
esac
cleanup() {
    # shellcheck disable=SC2317
    case "$diagnostic_root" in
        /run/caddy-action20e-b-node.*) rm -rf -- "$diagnostic_root" ;;
        *) return 125 ;;
    esac
}
trap cleanup EXIT
readonly before_state=$diagnostic_root/before.state
readonly after_state=$diagnostic_root/after.state
readonly shadow_root=$diagnostic_root/shadow-root
readonly shadow_etc=$shadow_root/etc
readonly shadow_tmpfiles=$shadow_etc/tmpfiles.d
: >"$before_state"
: >"$after_state"
chmod 0600 "$before_state" "$after_state"

failed_count=0
first_failure=none
run_assertion() {
    local executed_label=$1

    shift
    if ! record_assertion "$executed_label" "$@"; then
        failed_count=$((failed_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$executed_label
        fi
    fi
}
capture_snapshot() {
    local captured_component
    local captured_phase=$1
    local captured_state=$2
    local captured_status
    local captured_value

    while IFS= read -r captured_component; do
        captured_status=0
        captured_value=$(component_value "$captured_component") || captured_status=$?
        captured_value=$(printf '%s' "$captured_value" | sanitize_value)
        printf '%s=%s\n' "$captured_component" "$captured_value" >>"$captured_state"
        printf '%s_value_%s_%s=%s\n' "$prefix" "$captured_phase" \
            "$captured_component" "$captured_value"
        run_assertion "snapshot_${captured_phase}_${captured_component}_captured" \
            test "$captured_status" -eq 0
    done < <(snapshot_components)
}

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$PWD" = /
run_assertion hostname_exact test "$(hostname)" = j1-svpihole00
run_assertion architecture_arm64 test "$(dpkg --print-architecture)" = arm64
run_assertion config_absent test ! -e "$installed_config"
run_assertion runtime_absent test ! -e "$state_directory"
run_assertion notify_absent test ! -e "$notify_directory"
run_assertion original_stage_absent test "$(residue_count 'caddy-action20e-node.*')" -eq 0
run_assertion retry_stage_absent test "$(residue_count 'caddy-action20e-retry-node.*')" -eq 0
run_assertion historical_backup_absent test "$(backup_count)" -eq 0
run_assertion notifier_regular test -f "$notifier"
run_assertion notifier_not_symlink test ! -L "$notifier"
run_assertion notifier_metadata_exact test "$(stat -c '%U:%G:%a' "$notifier")" = root:root:755
run_assertion notifier_hash_exact test "$(file_hash "$notifier")" = "$expected_notifier_sha256"
run_assertion caddy_active test "$(systemctl is-active caddy.service)" = active
run_assertion keepalived_active test "$(systemctl is-active keepalived.service)" = active
run_assertion lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
run_assertion caddy_ipv4_absent test "$(address_count 4 "$caddy_ipv4")" -eq 0
run_assertion caddy_ipv6_absent test "$(address_count 6 "$caddy_ipv6")" -eq 0
run_assertion dns_ipv4_absent_on_node_b test "$(address_count 4 "$dns_ipv4")" -eq 0
run_assertion dns_ipv6_absent_on_node_b test "$(address_count 6 "$dns_ipv6")" -eq 0

capture_snapshot before "$before_state"
before_hash=$(file_hash "$before_state")
readonly before_hash
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_hash"
run_assertion before_state_hash_format grep -Eq '^[0-9a-f]{64}$' <<<"$before_hash"

run_assertion diagnostic_root_regular test -d "$diagnostic_root"
run_assertion diagnostic_root_not_symlink test ! -L "$diagnostic_root"
run_assertion diagnostic_root_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$diagnostic_root")" = root:root:700
create_shadow_tree root root "$shadow_tmpfiles"

shadow_root_symbolic=$(stat -c '%U:%G:%a' "$shadow_root" | sanitize_value)
readonly shadow_root_symbolic
shadow_root_numeric=$(stat -c '%u:%g:%a' "$shadow_root" | sanitize_value)
readonly shadow_root_numeric
shadow_etc_symbolic=$(stat -c '%U:%G:%a' "$shadow_etc" | sanitize_value)
readonly shadow_etc_symbolic
shadow_etc_numeric=$(stat -c '%u:%g:%a' "$shadow_etc" | sanitize_value)
readonly shadow_etc_numeric
shadow_tmpfiles_symbolic=$(stat -c '%U:%G:%a' "$shadow_tmpfiles" | sanitize_value)
readonly shadow_tmpfiles_symbolic
shadow_tmpfiles_numeric=$(stat -c '%u:%g:%a' "$shadow_tmpfiles" | sanitize_value)
readonly shadow_tmpfiles_numeric
printf '%s_value_expected_shadow_root_metadata=root:root:700\n' "$prefix"
printf '%s_value_observed_shadow_root_symbolic=%s\n' "$prefix" "$shadow_root_symbolic"
printf '%s_value_observed_shadow_root_numeric=%s\n' "$prefix" "$shadow_root_numeric"
printf '%s_value_observed_shadow_etc_symbolic=%s\n' "$prefix" "$shadow_etc_symbolic"
printf '%s_value_observed_shadow_etc_numeric=%s\n' "$prefix" "$shadow_etc_numeric"
printf '%s_value_observed_shadow_tmpfiles_symbolic=%s\n' "$prefix" "$shadow_tmpfiles_symbolic"
printf '%s_value_observed_shadow_tmpfiles_numeric=%s\n' "$prefix" "$shadow_tmpfiles_numeric"

run_assertion shadow_root_regular test -d "$shadow_root"
run_assertion shadow_root_not_symlink test ! -L "$shadow_root"
run_assertion shadow_root_owner_exact test "${shadow_root_symbolic%:*}" = root:root
run_assertion shadow_root_mode_observed grep -Eq '^(700|755)$' <<<"${shadow_root_symbolic##*:}"
run_assertion shadow_etc_regular test -d "$shadow_etc"
run_assertion shadow_etc_not_symlink test ! -L "$shadow_etc"
run_assertion shadow_etc_owner_exact test "${shadow_etc_symbolic%:*}" = root:root
run_assertion shadow_etc_mode_observed grep -Eq '^(700|755)$' <<<"${shadow_etc_symbolic##*:}"
run_assertion shadow_tmpfiles_regular test -d "$shadow_tmpfiles"
run_assertion shadow_tmpfiles_not_symlink test ! -L "$shadow_tmpfiles"
run_assertion shadow_tmpfiles_metadata_exact test "$shadow_tmpfiles_symbolic" = root:root:700

reproduction_classification=$(classify_shadow_tree \
    "$shadow_root_symbolic" "$shadow_etc_symbolic")
readonly reproduction_classification
printf '%s_value_reproduction_classification=%s\n' "$prefix" "$reproduction_classification"
run_assertion reproduction_classification_known grep -Eq \
    '^(intermediate_parents_default_0755|all_requested_mode_0700)$' \
    <<<"$reproduction_classification"
run_assertion failure_boundary_reproduced test "$reproduction_classification" = \
    intermediate_parents_default_0755

capture_snapshot after "$after_state"
after_hash=$(file_hash "$after_state")
readonly after_hash
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_hash"
run_assertion after_state_hash_format grep -Eq '^[0-9a-f]{64}$' <<<"$after_hash"
while IFS= read -r compared_component; do
    before_value=$(sed -n "s/^${compared_component}=//p" "$before_state")
    after_value=$(sed -n "s/^${compared_component}=//p" "$after_state")
    run_assertion "snapshot_${compared_component}_unchanged" test \
        "$after_value" = "$before_value"
done < <(snapshot_components)
run_assertion state_unchanged test "$after_hash" = "$before_hash"

diagnostic_cleanup_status=0
rm -rf -- "$diagnostic_root" || diagnostic_cleanup_status=$?
readonly diagnostic_cleanup_status
run_assertion diagnostic_cleanup_status_zero test "$diagnostic_cleanup_status" -eq 0
run_assertion diagnostic_stage_residue_absent test \
    "$(residue_count 'caddy-action20e-b-node.*')" -eq 0
if [[ "$diagnostic_cleanup_status" -eq 0 ]]; then
    trap - EXIT
fi

assertion_count=$(expected_assertions | wc -l)
readonly assertion_count
printf '%s_assertion_count=%s\n' "$prefix" "$assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_systemd_tmpfiles_invoked=false\n' "$prefix"
printf '%s_transient_filesystem_activity=true\n' "$prefix"
printf '%s_persistent_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_service_mutations=false\n' "$prefix"
printf '%s_notifier_invoked=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"
[[ "$failed_count" -eq 0 ]]
