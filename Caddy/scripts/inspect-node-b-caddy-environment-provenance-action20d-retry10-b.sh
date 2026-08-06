#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry10_b_probe
readonly environment_file=/etc/default/caddy-ha
readonly caddy_override=/etc/systemd/system/caddy.service.d/override.conf
readonly health_helper=/usr/local/libexec/check-caddy.sh
readonly main_configuration=/etc/keepalived/keepalived.conf
readonly fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly expected_node_b_environment_sha256=f692d5b7e0a7e0f0ab142e36face6a8cc8c6680a44a2bcaf6a992247ec4c8113
readonly rejected_node_a_environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly expected_main_sha256=e8473427d9fe167777ca910d740035d5a73b27f9f909999a8d32c5a0a60722b6
readonly expected_fragment_sha256=294d5ba44d903ba4ab3ab4330ae3ae05e0160e2b134d71e91a787b65dd96dc4d
readonly expected_health_sha256=9bf531ab7cbb047f8f09ce5956b597d5c8b6ede397c166f0b040e2e92fe8bbab
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128

readonly -a expected_keys=(
    NODE_ROLE
    NODE_FQDN
    NODE_IPV4
    NODE_IPV6
    PEER_ROLE
    PEER_IPV4
    PEER_IPV6
    CADDY_PRIORITY
    NETWORK_INTERFACE
    SYNC_TARGET
)

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local address_family=$1
    local expected_cidr=$2

    ip -o "-$address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$expected_cidr" '$4 == expected { count++ }
            END { print count + 0 }'
}
expected_key_inventory() { printf '%s\n' "${expected_keys[@]}"; }
observed_key_inventory() { sed -n 's/^\([A-Z][A-Z0-9_]*\)=.*/\1/p' "$environment_file"; }
assignment_syntax_valid() {
    [[ "$(grep -Evc '^[A-Z][A-Z0-9_]*=[^[:space:]]+$' "$environment_file")" -eq 0 ]]
}
key_order_exact() { cmp -s <(expected_key_inventory) <(observed_key_inventory); }
keys_unique() {
    [[ "$(observed_key_inventory | LC_ALL=C sort | uniq -d | wc -l)" -eq 0 ]]
}
source_classification() {
    local observed_environment_hash=$1

    case "$observed_environment_hash" in
        "$expected_node_b_environment_sha256") printf 'rendered_node_b_candidate\n' ;;
        "$rejected_node_a_environment_sha256") printf 'rendered_node_a_candidate\n' ;;
        *) printf 'unrecognized\n' ;;
    esac
}
package_owner_classification() {
    local package_query_status=0

    dpkg-query -S "$environment_file" >/dev/null 2>&1 || package_query_status=$?
    case "$package_query_status" in
        0) printf 'package_owned\n' ;;
        1) printf 'locally_managed\n' ;;
        *) printf 'query_error\n' ;;
    esac
}
snapshot_state() {
    printf 'environment_sha256=%s\n' "$(file_hash "$environment_file" 2>/dev/null || true)"
    printf 'environment_metadata=%s\n' \
        "$(stat -c '%U:%G:%a:%s:%Y:%Z:%i' "$environment_file" 2>/dev/null || true)"
    printf 'main_sha256=%s\n' "$(file_hash "$main_configuration" 2>/dev/null || true)"
    printf 'fragment_sha256=%s\n' "$(file_hash "$fragment" 2>/dev/null || true)"
    printf 'health_sha256=%s\n' "$(file_hash "$health_helper" 2>/dev/null || true)"
    printf 'keepalived=%s\n' "$(systemctl is-active keepalived.service 2>/dev/null || true)"
    printf 'caddy=%s\n' "$(systemctl is-active caddy.service 2>/dev/null || true)"
    printf 'lighttpd=%s\n' "$(systemctl is-active lighttpd.service 2>/dev/null || true)"
    printf 'lsyncd=%s\n' "$(systemctl is-active lsyncd.service 2>/dev/null || true)"
    printf 'caddy_ipv4=%s\n' "$(address_count 4 "$caddy_ipv4_cidr")"
    printf 'caddy_ipv6=%s\n' "$(address_count 6 "$caddy_ipv6_cidr")"
    printf 'dns_ipv4=%s\n' "$(address_count 4 "$dns_ipv4_cidr")"
    printf 'dns_ipv6=%s\n' "$(address_count 6 "$dns_ipv6_cidr")"
}
expected_assertions() {
    printf '%s\n' \
        identity_root working_directory_root hostname_node_b \
        environment_regular environment_not_symlink environment_metadata_exact \
        environment_hash_format environment_line_count_exact \
        environment_assignment_syntax_exact environment_key_order_exact \
        environment_keys_unique environment_no_blank_lines \
        environment_no_comment_lines environment_no_carriage_returns \
        source_classification_supported package_classification_supported \
        caddy_override_regular caddy_override_not_symlink \
        caddy_override_environment_consumer_exact \
        health_helper_regular health_helper_not_symlink \
        health_helper_environment_consumer_exact main_hash_exact fragment_hash_exact \
        health_hash_exact keepalived_active caddy_active lighttpd_active \
        lsyncd_inactive caddy_ipv4_absent caddy_ipv6_absent dns_ipv4_absent \
        dns_ipv6_absent before_snapshot_complete after_snapshot_complete \
        state_unchanged
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
is_sha256() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }
classification_supported() {
    case "$1" in
        rendered_node_b_candidate | rendered_node_a_candidate | unrecognized) return 0 ;;
        *) return 1 ;;
    esac
}
package_classification_supported() {
    case "$1" in
        package_owned | locally_managed | query_error) return 0 ;;
        *) return 1 ;;
    esac
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --expected-keys)
        [[ $# -eq 1 ]] || exit 64
        expected_key_inventory
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$(expected_assertions | wc -l)" -eq 36 ]]
        [[ "$(expected_assertions | LC_ALL=C sort -u | wc -l)" -eq 36 ]]
        [[ "$(expected_key_inventory | wc -l)" -eq 10 ]]
        [[ "$(expected_key_inventory | LC_ALL=C sort -u | wc -l)" -eq 10 ]]
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "") [[ $# -eq 0 ]] || exit 64 ;;
    *)
        printf 'Usage: %s [--expected-assertions|--expected-keys|--self-test]\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac

before_snapshot=$(snapshot_state)
before_snapshot_status=$?
before_snapshot_sha256=$(printf '%s\n' "$before_snapshot" | sha256sum | awk '{ print $1 }')
readonly before_snapshot before_snapshot_status before_snapshot_sha256

observed_environment_sha256=$(file_hash "$environment_file" 2>/dev/null || true)
readonly observed_environment_sha256
observed_source_classification=$(source_classification "$observed_environment_sha256")
readonly observed_source_classification
observed_package_classification=$(package_owner_classification)
readonly observed_package_classification

failed_assertion_count=0
first_failure=none
run_assertion() {
    local run_label=$1

    shift
    if ! record_assertion "$run_label" "$@"; then
        failed_assertion_count=$((failed_assertion_count + 1))
        if [[ "$first_failure" = none ]]; then first_failure=$run_label; fi
    fi
}

run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$(pwd -P)" = /
run_assertion hostname_node_b test "$(hostname -s)" = j1-svpihole00
run_assertion environment_regular test -f "$environment_file"
run_assertion environment_not_symlink test ! -L "$environment_file"
run_assertion environment_metadata_exact test \
    "$(stat -c '%U:%G:%a' "$environment_file" 2>/dev/null || true)" = root:caddy-tls:640
run_assertion environment_hash_format is_sha256 "$observed_environment_sha256"
run_assertion environment_line_count_exact test "$(line_count "$environment_file")" -eq 10
run_assertion environment_assignment_syntax_exact assignment_syntax_valid
run_assertion environment_key_order_exact key_order_exact
run_assertion environment_keys_unique keys_unique
run_assertion environment_no_blank_lines test "$(grep -c '^$' "$environment_file" || true)" -eq 0
run_assertion environment_no_comment_lines test "$(grep -c '^[[:space:]]*#' "$environment_file" || true)" -eq 0
run_assertion environment_no_carriage_returns test "$(LC_ALL=C tr -cd '\r' <"$environment_file" | wc -c)" -eq 0
run_assertion source_classification_supported classification_supported "$observed_source_classification"
run_assertion package_classification_supported package_classification_supported \
    "$observed_package_classification"
run_assertion caddy_override_regular test -f "$caddy_override"
run_assertion caddy_override_not_symlink test ! -L "$caddy_override"
run_assertion caddy_override_environment_consumer_exact test \
    "$(grep -Fxc 'EnvironmentFile=-/etc/default/caddy-ha' "$caddy_override" 2>/dev/null || true)" -eq 1
run_assertion health_helper_regular test -f "$health_helper"
run_assertion health_helper_not_symlink test ! -L "$health_helper"
run_assertion health_helper_environment_consumer_exact test \
    "$(grep -Fxc 'source /etc/default/caddy-ha' "$health_helper" 2>/dev/null || true)" -eq 1
run_assertion main_hash_exact test \
    "$(file_hash "$main_configuration" 2>/dev/null || true)" = "$expected_main_sha256"
run_assertion fragment_hash_exact test \
    "$(file_hash "$fragment" 2>/dev/null || true)" = "$expected_fragment_sha256"
run_assertion health_hash_exact test \
    "$(file_hash "$health_helper" 2>/dev/null || true)" = "$expected_health_sha256"
run_assertion keepalived_active test "$(systemctl is-active keepalived.service)" = active
run_assertion caddy_active test "$(systemctl is-active caddy.service)" = active
run_assertion lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
run_assertion lsyncd_inactive test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
run_assertion caddy_ipv4_absent test "$(address_count 4 "$caddy_ipv4_cidr")" -eq 0
run_assertion caddy_ipv6_absent test "$(address_count 6 "$caddy_ipv6_cidr")" -eq 0
run_assertion dns_ipv4_absent test "$(address_count 4 "$dns_ipv4_cidr")" -eq 0
run_assertion dns_ipv6_absent test "$(address_count 6 "$dns_ipv6_cidr")" -eq 0
run_assertion before_snapshot_complete test "$before_snapshot_status" -eq 0

after_snapshot=$(snapshot_state)
after_snapshot_status=$?
after_snapshot_sha256=$(printf '%s\n' "$after_snapshot" | sha256sum | awk '{ print $1 }')
readonly after_snapshot after_snapshot_status after_snapshot_sha256
run_assertion after_snapshot_complete test "$after_snapshot_status" -eq 0
run_assertion state_unchanged test "$before_snapshot_sha256" = "$after_snapshot_sha256"

printf '%s_value_environment_sha256=%s\n' "$prefix" "$observed_environment_sha256"
printf '%s_value_expected_node_b_environment_sha256=%s\n' \
    "$prefix" "$expected_node_b_environment_sha256"
printf '%s_value_rejected_node_a_environment_sha256=%s\n' \
    "$prefix" "$rejected_node_a_environment_sha256"
printf '%s_value_source_classification=%s\n' "$prefix" "$observed_source_classification"
printf '%s_value_package_classification=%s\n' "$prefix" "$observed_package_classification"
printf '%s_value_environment_metadata=%s\n' "$prefix" \
    "$(stat -c '%U:%G:%a:%s:%Y:%Z:%i' "$environment_file" 2>/dev/null || true)"
while IFS= read -r environment_key; do
    environment_line=$(grep -E "^${environment_key}=" "$environment_file" 2>/dev/null || true)
    printf '%s_value_line_%s_sha256=%s\n' "$prefix" "${environment_key,,}" \
        "$(printf '%s\n' "$environment_line" | sha256sum | awk '{ print $1 }')"
done < <(expected_key_inventory)
printf '%s_value_before_snapshot_sha256=%s\n' "$prefix" "$before_snapshot_sha256"
printf '%s_value_after_snapshot_sha256=%s\n' "$prefix" "$after_snapshot_sha256"
printf '%s_assertion_count=%s\n' "$prefix" "$(expected_assertions | wc -l)"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failed_assertion_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_environment_values_emitted=false\n' "$prefix"
printf '%s_health_helper_invoked=false\n' "$prefix"
printf '%s_notification_helper_invoked=false\n' "$prefix"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_keepalived_mutations=false\n' "$prefix"
printf '%s_vrrp_mutations=false\n' "$prefix"
printf '%s_vip_mutations=false\n' "$prefix"
printf '%s_network_mutations=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_remote_complete=true\n' "$prefix"

[[ "$failed_assertion_count" -eq 0 ]]
