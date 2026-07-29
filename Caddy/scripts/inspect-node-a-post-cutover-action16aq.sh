#!/usr/bin/env bash

set -uo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly lighttpd_live=/etc/lighttpd
readonly lighttpd_original=/etc/.lighttpd-pre-action16ap
readonly lighttpd_candidate=/var/tmp/caddy-ha-lighttpd-node-a-action16ab
readonly cutover_candidate=/etc/.lighttpd-caddy-action16ap
readonly failed_cutover=/etc/.lighttpd-caddy-action16ap.failed
readonly caddy_release=/etc/caddy/releases/bootstrap
readonly caddy_current=/etc/caddy/current
readonly caddy_environment=/etc/default/caddy-ha
readonly caddy_override=/etc/systemd/system/caddy.service.d/override.conf
readonly caddy_mask=/etc/systemd/system/caddy.service
readonly caddy_vrrp=/etc/keepalived/conf.d/caddy-ha.conf
readonly lsyncd_config=/etc/lsyncd/caddy.lua

readonly live_lighttpd_sha256=95a8752f86f1f475d7b8fd12090379c4ae46b9f4140212c7405586c222383372
readonly original_lighttpd_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_lighttpd_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly caddy_tree_sha256=6ae99faf2cb216466879f15139cdd6614234cf46d796f535387d51ecc9602161
readonly keepalived_tree_sha256=dad64e4ac7fdbaab2db3454ccf79158b6f41e4973086f9937a7c6b737f0a2f66
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly caddyfile_sha256=a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e
readonly health_sha256=05fa1d2875ee0639601447ccd31284d3df55fc8d5e8cedef4a291c61d44f4b27
readonly pihole_sha256=5621134920da9dde97122fe9968a2debdd0c980ac0e432323fb46e0c1139798c
readonly deny_sha256=9ce8430d11882f4e2008ff27f4f4a2fcad568f81081629289f64ad2450316b27
readonly caddy_override_sha256=a292487f4cbde99abce048b97ec15dbae8ef511ec845dcf5740f343e143f39df
readonly caddy_vendor_unit_sha256=6c271e030644bd36a0c8956885934f16c928f88202bc126f12cde519ef9693ff

assertion_count=0
mismatch_count=0
first_failure=none

record_result() {
    local label=$1
    local result=$2

    ((assertion_count += 1))
    if [[ "$result" == true ]]; then
        printf 'check_%s=true\n' "$label"
        return
    fi
    printf 'check_%s=false\n' "$label"
    ((mismatch_count += 1))
    if [[ "$first_failure" == none ]]; then
        first_failure=$label
    fi
}

record_command() {
    local label=$1
    shift

    if "$@" >/dev/null 2>&1; then
        record_result "$label" true
    else
        record_result "$label" false
    fi
}

record_equal() {
    local label=$1
    local actual=$2
    local expected=$3

    if [[ "$actual" == "$expected" ]]; then
        record_result "$label" true
    else
        record_result "$label" false
    fi
}

tree_hash() {
    local root=$1

    (
        cd "$root" 2>/dev/null || exit 1
        find . -type f -print0 |
            sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

unit_state() {
    local unit=$1
    local property=$2

    systemctl show "$unit" --property="$property" --value 2>/dev/null || true
}

# shellcheck disable=SC2317
listener_owned_only_by() {
    local protocol=$1
    local port=$2
    local process=$3
    local output

    if [[ "$protocol" == tcp ]]; then
        output=$(ss -H -lntp "sport = :$port" 2>/dev/null)
    else
        output=$(ss -H -lunp "sport = :$port" 2>/dev/null)
    fi
    [[ -n "$output" ]] &&
        grep -Fq "users:((\"$process\"" <<<"$output" &&
        ! grep -Fv "users:((\"$process\"" <<<"$output" >/dev/null
}

# shellcheck disable=SC2317
loopback_listener_only() {
    local port=$1
    local process=$2
    local address=$3
    local output

    output=$(ss -H -lntp "sport = :$port" 2>/dev/null)
    [[ "$(wc -l <<<"$output")" -eq 1 ]] &&
        grep -Fq "$address" <<<"$output" &&
        grep -Fq "users:((\"$process\"" <<<"$output"
}

http_code() {
    local code

    code=$(
        curl "$@" --silent --show-error \
            --connect-timeout 1 --max-time 3 \
            --output /dev/null --write-out '%{http_code}' 2>/dev/null ||
            true
    )
    printf '%s\n' "${code:-000}"
}

http_code_ok() {
    [[ "$1" =~ ^[23][0-9][0-9]$ ]]
}

# shellcheck disable=SC2317
caddy_config_valid() {
    (
        set -a
        # shellcheck disable=SC1090
        source "$caddy_environment"
        set +a
        runuser -u caddy -- \
            caddy validate --config "$caddy_current/Caddyfile" \
            --adapter caddyfile
    )
}

# shellcheck disable=SC2317
certificate_key_matches() {
    local cert_pub key_pub

    cert_pub=$(
        openssl x509 -in "$caddy_release/tls/leaf.pem" \
            -pubkey -noout 2>/dev/null |
            sha256sum |
            awk '{ print $1 }'
    )
    key_pub=$(
        openssl pkey -in "$caddy_release/tls/privkey.pem" \
            -pubout 2>/dev/null |
            sha256sum |
            awk '{ print $1 }'
    )
    [[ -n "$cert_pub" && "$cert_pub" == "$key_pub" ]]
}

leaf_der_sha256() {
    openssl x509 -in "$caddy_release/tls/leaf.pem" \
        -outform DER 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
}

served_leaf_der_sha256() {
    openssl s_client \
        -connect 10.1.0.53:443 \
        -servername pihole0.local.theama.co \
        </dev/null 2>/dev/null |
        openssl x509 -outform DER 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$live_lighttpd_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$original_lighttpd_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$candidate_lighttpd_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$caddy_tree_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$keepalived_tree_sha256" =~ ^[0-9a-f]{64}$ ]]
    http_code_ok 200
    http_code_ok 302
    if http_code_ok 421; then
        exit 1
    fi
    printf 'action_16aq_post_cutover_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_16aq_remote_reached=true\n'
record_equal root_effective_uid "$EUID" 0
record_equal node_hostname "$(hostname 2>/dev/null || true)" j1-svpihole0
record_equal node_architecture \
    "$(dpkg --print-architecture 2>/dev/null || true)" arm64
record_command node_ipv4_present grep -Fq '10.1.0.53/22' \
    <(ip -o -4 address show dev eth0 2>/dev/null)
record_command node_ipv6_present grep -Fq 'fd36:5aa8:6971:1::53/64' \
    <(ip -o -6 address show dev eth0 2>/dev/null)

for command_name in \
    awk bash caddy curl dpkg dpkg-query find grep hostname ip journalctl \
    lighttpd openssl pgrep readlink runuser sed sha256sum sort ss stat \
    systemctl wc xargs; do
    record_command "command_${command_name}_present" command -v "$command_name"
done

record_command live_lighttpd_directory test -d "$lighttpd_live"
record_command live_lighttpd_not_symlink test ! -L "$lighttpd_live"
record_equal live_lighttpd_tree \
    "$(tree_hash "$lighttpd_live" 2>/dev/null || true)" \
    "$live_lighttpd_sha256"
record_command live_lighttpd_native_parse lighttpd -tt \
    -f "$lighttpd_live/lighttpd.conf"
record_command live_lighttpd_loopback_binding grep -Fxq \
    'server.bind = "127.0.0.1"' "$lighttpd_live/conf-enabled/99-caddy-ha.conf"
record_command live_lighttpd_port grep -Fxq \
    'server.port = 8080' "$lighttpd_live/conf-enabled/99-caddy-ha.conf"
record_command live_lighttpd_ssl_disabled grep -Fxq \
    'ssl.engine = "disable"' "$lighttpd_live/conf-enabled/99-caddy-ha.conf"

record_command original_lighttpd_directory test -d "$lighttpd_original"
record_command original_lighttpd_not_symlink test ! -L "$lighttpd_original"
record_equal original_lighttpd_tree \
    "$(tree_hash "$lighttpd_original" 2>/dev/null || true)" \
    "$original_lighttpd_sha256"
record_command candidate_lighttpd_directory test -d "$lighttpd_candidate"
record_command candidate_lighttpd_not_symlink test ! -L "$lighttpd_candidate"
record_equal candidate_lighttpd_tree \
    "$(tree_hash "$lighttpd_candidate" 2>/dev/null || true)" \
    "$candidate_lighttpd_sha256"
record_command cutover_candidate_absent test ! -e "$cutover_candidate"
record_command cutover_candidate_not_symlink test ! -L "$cutover_candidate"
record_command failed_cutover_absent test ! -e "$failed_cutover"
record_command failed_cutover_not_symlink test ! -L "$failed_cutover"

record_equal caddy_current_target \
    "$(readlink "$caddy_current" 2>/dev/null || true)" "$caddy_release"
record_equal caddy_current_resolved \
    "$(readlink -e "$caddy_current" 2>/dev/null || true)" "$caddy_release"
record_equal caddy_tree \
    "$(tree_hash /etc/caddy 2>/dev/null || true)" "$caddy_tree_sha256"
record_equal keepalived_tree \
    "$(tree_hash /etc/keepalived 2>/dev/null || true)" \
    "$keepalived_tree_sha256"
record_equal caddy_environment \
    "$(sha256sum "$caddy_environment" 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$environment_sha256"
record_command caddy_node_role grep -Fxq 'NODE_ROLE=node-a' "$caddy_environment"
record_command caddy_node_fqdn grep -Fxq \
    'NODE_FQDN=pihole0.local.theama.co' "$caddy_environment"
record_equal caddyfile \
    "$(sha256sum "$caddy_release/Caddyfile" 2>/dev/null |
        awk '{ print $1 }' || true)" "$caddyfile_sha256"
record_equal caddy_health_route \
    "$(sha256sum "$caddy_release/conf.d/00-health.caddy" 2>/dev/null |
        awk '{ print $1 }' || true)" "$health_sha256"
record_equal caddy_pihole_route \
    "$(sha256sum "$caddy_release/conf.d/10-pihole-admin.caddy" 2>/dev/null |
        awk '{ print $1 }' || true)" "$pihole_sha256"
record_equal caddy_default_deny \
    "$(sha256sum "$caddy_release/conf.d/90-default-deny.caddy" 2>/dev/null |
        awk '{ print $1 }' || true)" "$deny_sha256"
record_equal caddy_override \
    "$(sha256sum "$caddy_override" 2>/dev/null |
        awk '{ print $1 }' || true)" "$caddy_override_sha256"
record_equal caddy_vendor_unit \
    "$(sha256sum /lib/systemd/system/caddy.service 2>/dev/null |
        awk '{ print $1 }' || true)" "$caddy_vendor_unit_sha256"
record_equal caddy_package \
    "$(dpkg-query -W \
        -f='${Status}|${binary:Package}|${Version}|${Architecture}' \
        caddy 2>/dev/null || true)" \
    'install ok installed|caddy|2.11.4|arm64'
record_command caddy_config_valid caddy_config_valid

record_command certificate_valid_30_days openssl x509 \
    -checkend 2592000 -noout -in "$caddy_release/tls/leaf.pem"
# shellcheck disable=SC2016
record_command certificate_wildcard_san bash -c \
    'openssl x509 -in "$1" -noout -ext subjectAltName |
        grep -Fq "DNS:*.local.theama.co"' \
    bash "$caddy_release/tls/leaf.pem"
record_command certificate_key_match certificate_key_matches

record_equal caddy_active "$(unit_state caddy.service ActiveState)" active
record_equal caddy_substate "$(unit_state caddy.service SubState)" running
record_equal caddy_result "$(unit_state caddy.service Result)" success
record_equal caddy_enabled \
    "$(systemctl is-enabled caddy.service 2>/dev/null || true)" disabled
record_equal caddy_type "$(unit_state caddy.service Type)" notify
record_equal caddy_stop_timeout \
    "$(unit_state caddy.service TimeoutStopUSec)" 30s
record_equal caddy_main_status \
    "$(unit_state caddy.service ExecMainStatus)" 0
record_command caddy_mask_absent test ! -e "$caddy_mask"
record_command caddy_mask_not_symlink test ! -L "$caddy_mask"
record_equal lighttpd_active \
    "$(unit_state lighttpd.service ActiveState)" active
record_equal lighttpd_enabled \
    "$(systemctl is-enabled lighttpd.service 2>/dev/null || true)" enabled
record_equal keepalived_active \
    "$(unit_state keepalived.service ActiveState)" active
record_equal keepalived_enabled \
    "$(systemctl is-enabled keepalived.service 2>/dev/null || true)" enabled
record_equal caddy_api_active \
    "$(unit_state caddy-api.service ActiveState)" inactive
record_equal caddy_api_enabled \
    "$(systemctl is-enabled caddy-api.service 2>/dev/null || true)" masked
record_equal lsyncd_active "$(unit_state lsyncd.service ActiveState)" inactive
record_equal lsyncd_enabled \
    "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" masked
record_equal caddy_lsyncd_active \
    "$(unit_state caddy-lsyncd.service ActiveState)" inactive
record_equal caddy_lsyncd_enabled \
    "$(systemctl is-enabled caddy-lsyncd.service 2>/dev/null || true)" disabled
record_command caddy_vrrp_absent test ! -e "$caddy_vrrp"
record_command lsyncd_configuration_absent test ! -e "$lsyncd_config"

record_command tcp_80_caddy_only listener_owned_only_by tcp 80 caddy
record_command tcp_443_caddy_only listener_owned_only_by tcp 443 caddy
record_command udp_443_caddy_only listener_owned_only_by udp 443 caddy
record_command tcp_8080_lighttpd_only \
    loopback_listener_only 8080 lighttpd 127.0.0.1:8080
record_command tcp_2019_caddy_only \
    loopback_listener_only 2019 caddy 127.0.0.1:2019
record_equal caddy_process_count "$(pgrep -xc caddy 2>/dev/null || true)" 1
record_equal lighttpd_process_count \
    "$(pgrep -xc lighttpd 2>/dev/null || true)" 1
record_equal lsyncd_process_count "$(pgrep -xc lsyncd 2>/dev/null || true)" 0

backend_code=$(http_code http://127.0.0.1:8080/admin/)
localhost_code=$(http_code --insecure --head https://localhost/)
management_ipv4_http1_code=$(
    http_code --http1.1 --insecure \
        --resolve pihole0.local.theama.co:443:10.1.0.53 \
        https://pihole0.local.theama.co/admin/
)
management_ipv4_http2_code=$(
    http_code --http2 --insecure \
        --resolve pihole0.local.theama.co:443:10.1.0.53 \
        https://pihole0.local.theama.co/admin/
)
management_ipv6_http1_code=$(
    http_code --http1.1 --insecure \
        --resolve 'pihole0.local.theama.co:443:[fd36:5aa8:6971:1::53]' \
        https://pihole0.local.theama.co/admin/
)
management_ipv6_http2_code=$(
    http_code --http2 --insecure \
        --resolve 'pihole0.local.theama.co:443:[fd36:5aa8:6971:1::53]' \
        https://pihole0.local.theama.co/admin/
)
unknown_host_code=$(
    http_code --insecure \
        --resolve unexpected.local.theama.co:443:10.1.0.53 \
        https://unexpected.local.theama.co/
)

record_command backend_http http_code_ok "$backend_code"
record_equal localhost_https "$localhost_code" 204
record_command management_ipv4_http1 \
    http_code_ok "$management_ipv4_http1_code"
record_command management_ipv4_http2 \
    http_code_ok "$management_ipv4_http2_code"
record_command management_ipv6_http1 \
    http_code_ok "$management_ipv6_http1_code"
record_command management_ipv6_http2 \
    http_code_ok "$management_ipv6_http2_code"
record_equal unknown_host_rejected "$unknown_host_code" 421

local_leaf_sha256=$(leaf_der_sha256 2>/dev/null || true)
served_leaf_sha256=$(served_leaf_der_sha256 2>/dev/null || true)
record_command local_leaf_sha256_valid grep -Eq '^[0-9a-f]{64}$' \
    <<<"$local_leaf_sha256"
record_equal served_certificate_matches \
    "$served_leaf_sha256" "$local_leaf_sha256"

journal_output=$(
    journalctl --unit=caddy.service \
        --since='2026-07-29 05:39:00 UTC' \
        --no-pager --quiet --output=short-iso --lines=160 2>/dev/null || true
)
journal_record_count=$(wc -l <<<"$journal_output")
if [[ -z "$journal_output" ]]; then
    journal_record_count=0
fi
record_command journal_no_health_tolerance_failure \
    test "$(grep -Fc 'status code out of tolerances' <<<"$journal_output")" -eq 0
record_command journal_no_trust_install_attempt \
    test "$(grep -Fc 'installing root certificate' <<<"$journal_output")" -eq 0

printf 'backend_http_code=%s\n' "$backend_code"
printf 'localhost_https_code=%s\n' "$localhost_code"
printf 'management_ipv4_http1_code=%s\n' "$management_ipv4_http1_code"
printf 'management_ipv4_http2_code=%s\n' "$management_ipv4_http2_code"
printf 'management_ipv6_http1_code=%s\n' "$management_ipv6_http1_code"
printf 'management_ipv6_http2_code=%s\n' "$management_ipv6_http2_code"
printf 'unknown_host_code=%s\n' "$unknown_host_code"
printf 'served_leaf_sha256=%s\n' "$served_leaf_sha256"
printf 'certificate_not_after=%s\n' \
    "$(openssl x509 -in "$caddy_release/tls/leaf.pem" \
        -noout -enddate 2>/dev/null |
        sed 's/^notAfter=//')"
printf 'live_lighttpd_tree_sha256=%s\n' \
    "$(tree_hash "$lighttpd_live" 2>/dev/null || true)"
printf 'original_lighttpd_tree_sha256=%s\n' \
    "$(tree_hash "$lighttpd_original" 2>/dev/null || true)"
printf 'candidate_lighttpd_tree_sha256=%s\n' \
    "$(tree_hash "$lighttpd_candidate" 2>/dev/null || true)"
printf 'caddy_tree_sha256=%s\n' \
    "$(tree_hash /etc/caddy 2>/dev/null || true)"
printf 'keepalived_tree_sha256=%s\n' \
    "$(tree_hash /etc/keepalived 2>/dev/null || true)"
printf 'journal_record_count=%s\n' "$journal_record_count"
printf 'postcutover_assertion_count=%s\n' "$assertion_count"
printf 'postcutover_mismatch_count=%s\n' "$mismatch_count"
printf 'first_failure=%s\n' "$first_failure"
printf 'peer_connections=false\n'
printf 'installed_helper_execution=false\n'
printf 'systemd_daemon_reload_performed=false\n'
printf 'service_mutations=false\n'
printf 'filesystem_mutations=false\n'
if [[ "$mismatch_count" -eq 0 ]]; then
    printf 'action_16aq_post_cutover_valid=true\n'
    printf 'action_16aq_inspection_complete=true\n'
    exit 0
fi
printf 'action_16aq_post_cutover_valid=false\n'
printf 'action_16aq_inspection_complete=true\n'
exit 1
