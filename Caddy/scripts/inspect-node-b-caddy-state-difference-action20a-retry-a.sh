#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20a_retry_a_probe
readonly health_script=/usr/local/libexec/check-caddy.sh
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly caddyfile=/etc/caddy/current/Caddyfile
readonly keepalived_home=/home/keepalived_script
readonly caddy_home=/var/lib/caddy
readonly expected_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly expected_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
readonly expected_current_target=/etc/caddy/releases/action15-health-follow-redirects
readonly physical_ipv4_cidr=10.1.0.54/22
readonly physical_ipv6_cidr=fd36:5aa8:6971:1::54/64
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
sanitize_value() {
    tr '\t\r\n' '   ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}
address_count() {
    local address_family=$1
    local expected_cidr=$2

    ip -o "-$address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$expected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}
normalized_addresses() {
    ip -o address show dev eth0 2>/dev/null |
        awk '{
            scope = "none"
            for (field = 5; field <= NF; field++) {
                if ($field == "scope" && field < NF) {
                    scope = $(field + 1)
                }
            }
            print $3 "|" $4 "|" scope
        }' |
        LC_ALL=C sort -u | paste -sd, -
}
legacy_addresses_raw() {
    ip -o address show dev eth0 2>/dev/null |
        LC_ALL=C sort | paste -sd, - | sanitize_value
}
legacy_addresses_sha256() {
    ip -o address show dev eth0 2>/dev/null | sha256sum | awk '{ print $1 }'
}
normalized_path_state() {
    local inspected_path=$1

    stat -c '%F|%U:%G:%a' "$inspected_path" 2>/dev/null || printf absent
}
unit_property() {
    local inspected_unit=$1
    local inspected_property=$2

    systemctl show "$inspected_unit" --no-pager \
        --property="$inspected_property" --value 2>/dev/null | sanitize_value
}
snapshot_components() {
    printf '%s\n' \
        health_sha256 fragment_sha256 caddyfile_sha256 current_target \
        keepalived_home_state caddy_home_state addresses_normalized \
        legacy_addresses_sha256 legacy_addresses_raw \
        caddy_active_state caddy_sub_state caddy_main_pid caddy_n_restarts \
        keepalived_active_state keepalived_sub_state keepalived_main_pid \
        keepalived_n_restarts lighttpd_active_state lighttpd_sub_state \
        lighttpd_main_pid lighttpd_n_restarts
}
component_value() {
    local requested_component=$1

    case "$requested_component" in
        health_sha256) file_hash "$health_script" ;;
        fragment_sha256) file_hash "$fragment" ;;
        caddyfile_sha256) file_hash "$caddyfile" ;;
        current_target) readlink -f /etc/caddy/current ;;
        keepalived_home_state) normalized_path_state "$keepalived_home" ;;
        caddy_home_state) normalized_path_state "$caddy_home" ;;
        addresses_normalized) normalized_addresses ;;
        legacy_addresses_sha256) legacy_addresses_sha256 ;;
        legacy_addresses_raw) legacy_addresses_raw ;;
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
        *) return 64 ;;
    esac
}
expected_assertions() {
    local expected_component
    local expected_phase

    printf '%s\n' \
        identity_root working_directory_root hostname_node_b architecture_arm64 \
        health_hash_exact fragment_hash_exact current_target_exact \
        physical_ipv4_exact physical_ipv6_exact caddy_ipv4_vip_absent \
        caddy_ipv6_vip_absent dns_ipv4_vip_count_supported \
        dns_ipv6_vip_count_supported dns_vip_dualstack_coherent \
        caddy_active keepalived_active lighttpd_active keepalived_home_absent \
        before_state_hash_format after_state_hash_format \
        classification_supported changed_inventory_consistent
    for expected_phase in before after; do
        while IFS= read -r expected_component; do
            printf 'snapshot_%s_%s_captured\n' "$expected_phase" \
                "$expected_component"
        done < <(snapshot_components)
    done
    while IFS= read -r expected_component; do
        printf 'snapshot_%s_comparison_recorded\n' "$expected_component"
    done < <(snapshot_components)
}
record_command() {
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
        self_test_root=$(mktemp -d /tmp/caddy-action20a-retry-a-probe-self.XXXXXX)
        readonly self_test_root
        trap 'rm -rf -- "$self_test_root"' EXIT
        snapshot_components >"$self_test_root/components"
        expected_assertions >"$self_test_root/assertions"
        [[ "$(wc -l <"$self_test_root/components")" -eq 21 ]]
        [[ "$(LC_ALL=C sort -u "$self_test_root/components" | wc -l)" -eq 21 ]]
        [[ "$(wc -l <"$self_test_root/assertions")" -eq 85 ]]
        [[ "$(LC_ALL=C sort -u "$self_test_root/assertions" | wc -l)" -eq 85 ]]
        ! grep -Ev '^[a-z0-9_]+$' "$self_test_root/components" | grep -q .
        ! grep -Ev '^[a-z0-9_]+$' "$self_test_root/assertions" | grep -q .
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--self-test|--snapshot-components|--expected-assertions]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

work_directory=$(mktemp -d /tmp/caddy-action20a-retry-a-probe.XXXXXX)
readonly work_directory
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$work_directory"
}
trap cleanup EXIT
readonly before_state=$work_directory/before.state
readonly after_state=$work_directory/after.state
: >"$before_state"
: >"$after_state"
chmod 0600 "$before_state" "$after_state"

failed_count=0
first_failure=none
run_assertion() {
    local executed_assertion_label=$1

    shift
    if ! record_command "$executed_assertion_label" "$@"; then
        failed_count=$((failed_count + 1))
        if [[ "$first_failure" = none ]]; then
            first_failure=$executed_assertion_label
        fi
    fi
}
capture_snapshot() {
    local captured_phase=$1
    local captured_state_path=$2
    local captured_component
    local captured_status
    local captured_value

    while IFS= read -r captured_component; do
        captured_status=0
        captured_value=$(component_value "$captured_component") || captured_status=$?
        captured_value=$(printf '%s' "$captured_value" | sanitize_value)
        printf '%s=%s\n' "$captured_component" "$captured_value" \
            >>"$captured_state_path"
        printf '%s_value_%s_%s=%s\n' "$prefix" "$captured_phase" \
            "$captured_component" "$captured_value"
        run_assertion "snapshot_${captured_phase}_${captured_component}_captured" \
            test "$captured_status" -eq 0
    done < <(snapshot_components)
}

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$PWD" = /
run_assertion hostname_node_b test "$(hostname)" = j1-svpihole00
run_assertion architecture_arm64 test "$(dpkg --print-architecture)" = arm64
run_assertion health_hash_exact test "$(file_hash "$health_script")" = \
    "$expected_health_sha256"
run_assertion fragment_hash_exact test "$(file_hash "$fragment")" = \
    "$expected_fragment_sha256"
run_assertion current_target_exact test "$(readlink -f /etc/caddy/current)" = \
    "$expected_current_target"
run_assertion physical_ipv4_exact test \
    "$(address_count 4 "$physical_ipv4_cidr")" -eq 1
run_assertion physical_ipv6_exact test \
    "$(address_count 6 "$physical_ipv6_cidr")" -eq 1
run_assertion caddy_ipv4_vip_absent test \
    "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0
run_assertion caddy_ipv6_vip_absent test \
    "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0
dns_ipv4_count=$(address_count 4 "$dns_ipv4_cidr")
readonly dns_ipv4_count
dns_ipv6_count=$(address_count 6 "$dns_ipv6_cidr")
readonly dns_ipv6_count
run_assertion dns_ipv4_vip_count_supported test "$dns_ipv4_count" -le 1
run_assertion dns_ipv6_vip_count_supported test "$dns_ipv6_count" -le 1
run_assertion dns_vip_dualstack_coherent test "$dns_ipv4_count" -eq \
    "$dns_ipv6_count"
run_assertion caddy_active test \
    "$(unit_property caddy.service ActiveState)" = active
run_assertion keepalived_active test \
    "$(unit_property keepalived.service ActiveState)" = active
run_assertion lighttpd_active test \
    "$(unit_property lighttpd.service ActiveState)" = active
run_assertion keepalived_home_absent test ! -e "$keepalived_home"

capture_snapshot before "$before_state"
before_state_sha256=$(file_hash "$before_state")
readonly before_state_sha256
/bin/sleep 2
capture_snapshot after "$after_state"
after_state_sha256=$(file_hash "$after_state")
readonly after_state_sha256
run_assertion before_state_hash_format grep -Eq '^[0-9a-f]{64}$' \
    <<<"$before_state_sha256"
run_assertion after_state_hash_format grep -Eq '^[0-9a-f]{64}$' \
    <<<"$after_state_sha256"

changed_components=none
changed_component_count=0
while IFS= read -r compared_component; do
    before_component_value=$(sed -n \
        "s/^${compared_component}=//p" "$before_state")
    after_component_value=$(sed -n \
        "s/^${compared_component}=//p" "$after_state")
    if [[ "$before_component_value" = "$after_component_value" ]]; then
        component_classification=unchanged
    else
        component_classification=changed
        changed_component_count=$((changed_component_count + 1))
        if [[ "$changed_components" = none ]]; then
            changed_components=$compared_component
        else
            changed_components+=,$compared_component
        fi
    fi
    printf '%s_value_component_%s_classification=%s\n' "$prefix" \
        "$compared_component" "$component_classification"
    run_assertion "snapshot_${compared_component}_comparison_recorded" \
        grep -Eq '^(unchanged|changed)$' <<<"$component_classification"
done < <(snapshot_components)

case "$changed_components" in
    none) state_difference_classification=no_difference_observed ;;
    legacy_addresses_sha256 | legacy_addresses_raw | \
        legacy_addresses_sha256,legacy_addresses_raw)
        state_difference_classification=legacy_address_lifetime_drift_only
        ;;
    *) state_difference_classification=persistent_component_difference_observed ;;
esac
run_assertion classification_supported grep -Eq \
    '^(no_difference_observed|legacy_address_lifetime_drift_only|persistent_component_difference_observed)$' \
    <<<"$state_difference_classification"
observed_inventory_count=$(awk -F, '{ if ($0 == "none") print 0; else print NF }' \
    <<<"$changed_components")
readonly observed_inventory_count
run_assertion changed_inventory_consistent test "$changed_component_count" -eq \
    "$observed_inventory_count"

expected_assertion_count=$(expected_assertions | wc -l)
readonly expected_assertion_count
printf '%s_value_node_role=node-b\n' "$prefix"
printf '%s_value_dns_ipv4_vip_count=%s\n' "$prefix" "$dns_ipv4_count"
printf '%s_value_dns_ipv6_vip_count=%s\n' "$prefix" "$dns_ipv6_count"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state_sha256"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state_sha256"
printf '%s_value_changed_component_count=%s\n' "$prefix" \
    "$changed_component_count"
printf '%s_value_changed_components=%s\n' "$prefix" "$changed_components"
printf '%s_value_state_difference_classification=%s\n' "$prefix" \
    "$state_difference_classification"
printf '%s_assertion_count=%s\n' "$prefix" "$expected_assertion_count"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_health_helper_invoked=false\n' "$prefix"
printf '%s_notification_helper_invoked=false\n' "$prefix"
printf '%s_caddy_validation_invoked=false\n' "$prefix"
printf '%s_transient_filesystem_activity=true\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_remote_cleanup_complete=true\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"
if [[ "$failed_count" -eq 0 ]]; then exit 0; fi
exit 1
