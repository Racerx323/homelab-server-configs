#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28j_a_route
readonly fqdn=pihole-admin.local.theama.co
readonly expected_ipv4=10.1.0.56
readonly expected_ipv6=fd36:5aa8:6971:1::56
readonly expected_url=https://pihole-admin.local.theama.co/admin/login.php

expected_checks() {
    printf '%s\n' identity_root working_directory_root role_valid hostname_exact \
        dig_regular curl_regular a_query_status_zero a_output_safe a_answer_exact \
        aaaa_query_status_zero aaaa_output_safe aaaa_answer_exact \
        cname_query_status_zero cname_output_safe cname_answer_absent \
        https_ipv4_status_zero https_ipv4_output_safe https_ipv4_http_200 \
        https_ipv4_url_exact https_ipv4_remote_ip_exact https_ipv4_redirect_one \
        https_ipv6_status_zero https_ipv6_output_safe https_ipv6_http_200 \
        https_ipv6_url_exact https_ipv6_remote_ip_exact https_ipv6_redirect_one
}
safe_text() {
    local action28j_a_route_text=$1

    [[ ${#action28j_a_route_text} -le 131072 ]] || return 1
    ! printf '%s' "$action28j_a_route_text" | LC_ALL=C grep -q '[^[:print:][:space:]]'
}
record_check() {
    local action28j_a_route_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28j_a_route_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28j_a_route_label"
    failed_check_count=$((failed_check_count + 1))
    [[ "$first_failure" != none ]] || first_failure=$action28j_a_route_label
    return 0
}
run_query() {
    local action28j_a_route_type=$1

    timeout 10 dig @127.0.0.1 "$fqdn" "$action28j_a_route_type" +short
}
run_https() {
    local action28j_a_route_family=$1

    timeout 15 curl --silent --show-error --location --max-redirs 3 \
        --proto '=https' --proto-redir '=https' --http1.1 "$action28j_a_route_family" \
        --connect-timeout 3 --max-time 10 --output /dev/null \
        --write-out '%{http_code}\t%{url_effective}\t%{remote_ip}\t%{num_redirects}\n' \
        "https://$fqdn/admin/"
}
parse_field() {
    local action28j_a_route_value=$1
    local action28j_a_route_field=$2

    printf '%s\n' "$action28j_a_route_value" | awk -F '\t' -v field="$action28j_a_route_field" 'NR == 1 { print $field }'
}

case "${1:-}" in
    --expected-checks)
        [[ $# -eq 1 ]] || exit 64
        expected_checks
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        labels=$(expected_checks) || exit 1
        readonly labels
        [[ "$(printf '%s\n' "$labels" | wc -l)" -eq "$(printf '%s\n' "$labels" | LC_ALL=C sort -u | wc -l)" ]] || exit 1
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    node-a | node-b)
        [[ $# -eq 1 ]] || exit 64
        readonly role=$1
        ;;
    *) exit 64 ;;
esac

case "$role" in
    node-a) readonly expected_hostname=j1-svpihole0 ;;
    node-b) readonly expected_hostname=j1-svpihole00 ;;
esac

failed_check_count=0
first_failure=none
a_status=0
a_output=$(run_query A 2>&1) || a_status=$?
aaaa_status=0
aaaa_output=$(run_query AAAA 2>&1) || aaaa_status=$?
cname_status=0
cname_output=$(run_query CNAME 2>&1) || cname_status=$?
https_ipv4_status=0
https_ipv4_output=$(run_https --ipv4 2>&1) || https_ipv4_status=$?
https_ipv6_status=0
https_ipv6_output=$(run_https --ipv6 2>&1) || https_ipv6_status=$?
readonly a_status a_output aaaa_status aaaa_output cname_status cname_output
readonly https_ipv4_status https_ipv4_output https_ipv6_status https_ipv6_output

printf '%s_value_a_answer=%s\n' "$prefix" "${a_output:-empty}"
printf '%s_value_aaaa_answer=%s\n' "$prefix" "${aaaa_output:-empty}"
printf '%s_value_cname_answer=%s\n' "$prefix" "${cname_output:-empty}"
printf '%s_value_https_ipv4_status=%s\n' "$prefix" "$https_ipv4_status"
printf '%s_value_https_ipv4_http=%s\n' "$prefix" "$(parse_field "$https_ipv4_output" 1)"
printf '%s_value_https_ipv4_url=%s\n' "$prefix" "$(parse_field "$https_ipv4_output" 2)"
printf '%s_value_https_ipv4_remote_ip=%s\n' "$prefix" "$(parse_field "$https_ipv4_output" 3)"
printf '%s_value_https_ipv4_redirects=%s\n' "$prefix" "$(parse_field "$https_ipv4_output" 4)"
printf '%s_value_https_ipv6_status=%s\n' "$prefix" "$https_ipv6_status"
printf '%s_value_https_ipv6_http=%s\n' "$prefix" "$(parse_field "$https_ipv6_output" 1)"
printf '%s_value_https_ipv6_url=%s\n' "$prefix" "$(parse_field "$https_ipv6_output" 2)"
printf '%s_value_https_ipv6_remote_ip=%s\n' "$prefix" "$(parse_field "$https_ipv6_output" 3)"
printf '%s_value_https_ipv6_redirects=%s\n' "$prefix" "$(parse_field "$https_ipv6_output" 4)"

record_check identity_root test "$(id -u)" -eq 0
record_check working_directory_root test "$(pwd -P)" = /
record_check role_valid test "$role" = node-a -o "$role" = node-b
record_check hostname_exact test "$(hostname)" = "$expected_hostname"
record_check dig_regular test -x /usr/bin/dig
record_check curl_regular test -x /usr/bin/curl
record_check a_query_status_zero test "$a_status" -eq 0
record_check a_output_safe safe_text "$a_output"
record_check a_answer_exact test "$a_output" = "$expected_ipv4"
record_check aaaa_query_status_zero test "$aaaa_status" -eq 0
record_check aaaa_output_safe safe_text "$aaaa_output"
record_check aaaa_answer_exact test "$aaaa_output" = "$expected_ipv6"
record_check cname_query_status_zero test "$cname_status" -eq 0
record_check cname_output_safe safe_text "$cname_output"
record_check cname_answer_absent test -z "$cname_output"
record_check https_ipv4_status_zero test "$https_ipv4_status" -eq 0
record_check https_ipv4_output_safe safe_text "$https_ipv4_output"
record_check https_ipv4_http_200 test "$(parse_field "$https_ipv4_output" 1)" = 200
record_check https_ipv4_url_exact test "$(parse_field "$https_ipv4_output" 2)" = "$expected_url"
record_check https_ipv4_remote_ip_exact test "$(parse_field "$https_ipv4_output" 3)" = "$expected_ipv4"
record_check https_ipv4_redirect_one test "$(parse_field "$https_ipv4_output" 4)" = 1
record_check https_ipv6_status_zero test "$https_ipv6_status" -eq 0
record_check https_ipv6_output_safe safe_text "$https_ipv6_output"
record_check https_ipv6_http_200 test "$(parse_field "$https_ipv6_output" 1)" = 200
record_check https_ipv6_url_exact test "$(parse_field "$https_ipv6_output" 2)" = "$expected_url"
record_check https_ipv6_remote_ip_exact test "$(parse_field "$https_ipv6_output" 3)" = "$expected_ipv6"
record_check https_ipv6_redirect_one test "$(parse_field "$https_ipv6_output" 4)" = 1

printf '%s_check_count=%s\n' "$prefix" "$(expected_checks | wc -l)"
printf '%s_failed_check_count=%s\n' "$prefix" "$failed_check_count"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_dns_mutations=false\n' "$prefix"
printf '%s_filesystem_mutations=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
if [[ "$failed_check_count" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$prefix"
    exit 1
fi
printf '%s_acceptance=true\n' "$prefix"
