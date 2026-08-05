#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20a_b_probe
readonly health_script=/usr/local/libexec/check-caddy.sh
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly caddyfile=/etc/caddy/current/Caddyfile
readonly keepalived_home=/home/keepalived_script
readonly caddy_home=/var/lib/caddy
readonly expected_health_sha256=c3bc1c080cd148efc0a64440a2a411ec115d0ca83f8e6a66220d7bd201971414
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128

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
    local listed_component
    local listed_phase

    printf '%s\n' \
        identity_root working_directory_root node_role_exact hostname_exact \
        architecture_arm64 health_hash_exact fragment_hash_exact \
        current_target_exact physical_ipv4_exact physical_ipv6_exact \
        caddy_ipv4_vip_absent caddy_ipv6_vip_absent \
        dns_ipv4_vip_count_supported dns_ipv6_vip_count_supported \
        dns_vip_dualstack_coherent caddy_active keepalived_active \
        lighttpd_active keepalived_home_absent before_state_hash_format \
        after_state_hash_format
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
        self_test_root=$(mktemp -d /tmp/caddy-action20ab-probe-self.XXXXXX)
        readonly self_test_root
        trap 'rm -rf -- "$self_test_root"' EXIT
        snapshot_components >"$self_test_root/components"
        expected_assertions >"$self_test_root/assertions"
        [[ "$(wc -l <"$self_test_root/components")" -eq 19 ]]
        [[ "$(LC_ALL=C sort -u "$self_test_root/components" | wc -l)" -eq 19 ]]
        [[ "$(wc -l <"$self_test_root/assertions")" -eq 79 ]]
        [[ "$(LC_ALL=C sort -u "$self_test_root/assertions" | wc -l)" -eq 79 ]]
        ! grep -Ev '^[a-z0-9_]+$' "$self_test_root/components" | grep -q .
        ! grep -Ev '^[a-z0-9_]+$' "$self_test_root/assertions" | grep -q .
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --node)
        [[ $# -eq 2 ]] || exit 64
        node_role=$2
        ;;
    *)
        printf 'Usage: %s --self-test|--snapshot-components|--expected-assertions|--node node-a|node-b\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

case "$node_role" in
    node-a)
        expected_hostname=j1-svpihole0
        expected_fragment_sha256=3a6f4c038d646bf12484d1a521a8f7fc01d05c56919ac8e6217ca50c2ab84bc5
        expected_current_target=/etc/caddy/releases/action16ar-retry-node-a-default-deny
        expected_physical_ipv4=10.1.0.53/22
        expected_physical_ipv6=fd36:5aa8:6971:1::53/64
        ;;
    node-b)
        expected_hostname=j1-svpihole00
        expected_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
        expected_current_target=/etc/caddy/releases/action15-health-follow-redirects
        expected_physical_ipv4=10.1.0.54/22
        expected_physical_ipv6=fd36:5aa8:6971:1::54/64
        ;;
    *)
        printf 'Unknown node role: %s\n' "$node_role" >&2
        exit 64
        ;;
esac
readonly node_role expected_hostname expected_fragment_sha256
readonly expected_current_target expected_physical_ipv4 expected_physical_ipv6

work_directory=$(mktemp -d /tmp/caddy-action20ab-probe.XXXXXX)
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
        if [[ "$first_failure" == none ]]; then
            first_failure=$executed_assertion_label
        fi
    fi
}
capture_snapshot() {
    local captured_component
    local captured_phase=$1
    local captured_state_path=$2
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
run_assertion node_role_exact grep -Eq '^node-[ab]$' <<<"$node_role"
run_assertion hostname_exact test "$(hostname)" = "$expected_hostname"
run_assertion architecture_arm64 test "$(dpkg --print-architecture)" = arm64
run_assertion health_hash_exact test "$(file_hash "$health_script")" = \
    "$expected_health_sha256"
run_assertion fragment_hash_exact test "$(file_hash "$fragment")" = \
    "$expected_fragment_sha256"
run_assertion current_target_exact test "$(readlink -f /etc/caddy/current)" = \
    "$expected_current_target"
run_assertion physical_ipv4_exact test \
    "$(address_count 4 "$expected_physical_ipv4")" -eq 1
run_assertion physical_ipv6_exact test \
    "$(address_count 6 "$expected_physical_ipv6")" -eq 1
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
run_assertion dns_vip_dualstack_coherent test "$dns_ipv4_count" -eq "$dns_ipv6_count"
run_assertion caddy_active test "$(unit_property caddy.service ActiveState)" = active
run_assertion keepalived_active test \
    "$(unit_property keepalived.service ActiveState)" = active
run_assertion lighttpd_active test "$(unit_property lighttpd.service ActiveState)" = active
run_assertion keepalived_home_absent test ! -e "$keepalived_home"

capture_snapshot before "$before_state"
before_state_sha256=$(file_hash "$before_state")
readonly before_state_sha256
capture_snapshot after "$after_state"
after_state_sha256=$(file_hash "$after_state")
readonly after_state_sha256
run_assertion before_state_hash_format grep -Eq '^[0-9a-f]{64}$' \
    <<<"$before_state_sha256"
run_assertion after_state_hash_format grep -Eq '^[0-9a-f]{64}$' \
    <<<"$after_state_sha256"
while IFS= read -r compared_component; do
    before_component_value=$(sed -n \
        "s/^${compared_component}=//p" "$before_state")
    after_component_value=$(sed -n \
        "s/^${compared_component}=//p" "$after_state")
    run_assertion "snapshot_${compared_component}_unchanged" test \
        "$before_component_value" = "$after_component_value"
done < <(snapshot_components)
run_assertion state_unchanged test "$before_state_sha256" = "$after_state_sha256"

printf '%s_value_node_role=%s\n' "$prefix" "$node_role"
printf '%s_value_dns_ipv4_vip_count=%s\n' "$prefix" "$dns_ipv4_count"
printf '%s_value_dns_ipv6_vip_count=%s\n' "$prefix" "$dns_ipv6_count"
printf '%s_value_before_state_sha256=%s\n' "$prefix" "$before_state_sha256"
printf '%s_value_after_state_sha256=%s\n' "$prefix" "$after_state_sha256"
printf '%s_assertion_count=79\n' "$prefix"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_installed_health_helper_invoked=false\n' "$prefix"
printf '%s_caddy_validation_invoked=false\n' "$prefix"
printf '%s_transient_filesystem_activity=true\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
rm -rf -- "$work_directory"
trap - EXIT
printf '%s_remote_cleanup_complete=true\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"
if [[ "$failed_count" -eq 0 ]]; then exit 0; fi
exit 1
