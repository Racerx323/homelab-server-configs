#!/usr/bin/env bash

set -uo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly lighttpd_live=/etc/lighttpd
readonly lighttpd_candidate=/var/tmp/caddy-ha-lighttpd-node-a-action16ab
readonly caddy_release=/etc/caddy/releases/bootstrap
readonly caddy_current=/etc/caddy/current
readonly caddy_environment=/etc/default/caddy-ha
readonly rollback_baseline=/var/backups/caddy-ha/predeploy-node-a-20260728T184626Z
readonly caddy_mask=/etc/systemd/system/caddy.service
readonly caddy_vendor_unit=/lib/systemd/system/caddy.service
readonly caddy_vendor_canonical=/usr/lib/systemd/system/caddy.service

readonly live_lighttpd_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_lighttpd_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly candidate_main_sha256=c48b3f0a8c256185233b302952f0b4ee138e745fb17ede92ae3f16d7fa4a6a99
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly caddyfile_sha256=a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e
readonly health_sha256=05fa1d2875ee0639601447ccd31284d3df55fc8d5e8cedef4a291c61d44f4b27
readonly pihole_sha256=5621134920da9dde97122fe9968a2debdd0c980ac0e432323fb46e0c1139798c
readonly deny_sha256=9ce8430d11882f4e2008ff27f4f4a2fcad568f81081629289f64ad2450316b27
readonly caddy_unit_sha256=3a5f3f84e08686a1cb6d247ee84698b896bf025203a2f74ab4cd578dee731a40
readonly lighttpd_unit_sha256=ad6c381129068d4a3e44d152272214f983bd3e5e6b5a3485d91a7a829b5375ca
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

listener_count() {
    local protocol=$1
    local port=$2

    if [[ "$protocol" == tcp ]]; then
        ss -H -lntp 2>/dev/null |
            awk -v port="$port" '$4 ~ (":" port "$") { count++ } END { print count + 0 }'
    else
        ss -H -lunp 2>/dev/null |
            awk -v port="$port" '$4 ~ (":" port "$") { count++ } END { print count + 0 }'
    fi
}

# shellcheck disable=SC2317
tcp_owned_only_by_lighttpd() {
    local port=$1
    local output

    output=$(ss -H -lntp 2>/dev/null |
        awk -v port="$port" '$4 ~ (":" port "$") { print }')
    [[ -n "$output" ]] &&
        grep -Fq 'users:(("lighttpd"' <<<"$output" &&
        ! grep -Fv 'users:(("lighttpd"' <<<"$output" >/dev/null
}

# shellcheck disable=SC2317
tcp_80_output_is_dualstack_lighttpd() {
    local output=$1
    local ipv4_count ipv6_count

    ipv4_count=$(
        awk '$4 == "0.0.0.0:80" && /users:\(\("lighttpd"/ { count++ }
            END { print count + 0 }' <<<"$output"
    )
    ipv6_count=$(
        awk '$4 == "[::]:80" && /users:\(\("lighttpd"/ { count++ }
            END { print count + 0 }' <<<"$output"
    )
    [[ "$ipv4_count" -eq 1 && "$ipv6_count" -eq 1 ]]
}

# shellcheck disable=SC2317
tcp_80_dualstack_lighttpd() {
    local output

    output=$(ss -H -lntp 'sport = :80' 2>/dev/null)
    tcp_80_output_is_dualstack_lighttpd "$output"
}

# shellcheck disable=SC2317
http_code_ok() {
    local scheme=$1
    local code
    local -a insecure=()

    if [[ "$scheme" == https ]]; then
        insecure=(--insecure)
    fi
    code=$(
        curl "${insecure[@]}" --silent --show-error \
            --connect-timeout 1 --max-time 3 \
            --resolve "pihole0.local.theama.co:$([[ "$scheme" == https ]] && printf 443 || printf 80):10.1.0.53" \
            --output /dev/null --write-out '%{http_code}' \
            "$scheme://pihole0.local.theama.co/admin/" 2>/dev/null ||
            true
    )
    [[ "$code" =~ ^[23][0-9][0-9]$ ]]
}

# shellcheck disable=SC2317
certificate_key_matches() {
    local cert_pub key_pub

    cert_pub=$(
        openssl x509 -in "$caddy_release/tls/leaf.pem" -pubkey -noout 2>/dev/null |
            sha256sum |
            awk '{ print $1 }'
    )
    key_pub=$(
        openssl pkey -in "$caddy_release/tls/privkey.pem" -pubout 2>/dev/null |
            sha256sum |
            awk '{ print $1 }'
    )
    [[ -n "$cert_pub" && "$cert_pub" == "$key_pub" ]]
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    sample_tcp80=$(
        printf '%s\n' \
            'LISTEN 0 1024 0.0.0.0:80 0.0.0.0:* users:(("lighttpd",pid=916,fd=6))' \
            'LISTEN 0 1024 [::]:80 [::]:* users:(("lighttpd",pid=916,fd=4))'
    )
    [[ "$candidate_lighttpd_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$environment_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$caddy_unit_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$caddy_vendor_unit_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$caddy_mask" == /etc/systemd/system/caddy.service ]]
    [[ "$caddy_vendor_unit" == /lib/systemd/system/caddy.service ]]
    [[ "$caddy_vendor_canonical" == /usr/lib/systemd/system/caddy.service ]]
    tcp_80_output_is_dualstack_lighttpd "$sample_tcp80"
    if tcp_80_output_is_dualstack_lighttpd \
        "${sample_tcp80/0.0.0.0:80/127.0.0.1:80}"; then
        printf 'Action 16ao accepted an incorrect TCP 80 address.\n' >&2
        exit 1
    fi
    printf 'action_16ao_cutover_preflight_inspector_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_16ao_remote_reached=true\n'
record_equal root_effective_uid "$EUID" 0
record_equal node_hostname "$(hostname 2>/dev/null || true)" j1-svpihole0
record_command node_ipv4_present grep -Fq '10.1.0.53/22' \
    <(ip -o -4 address show dev eth0 2>/dev/null)
record_command node_ipv6_present grep -Fq 'fd36:5aa8:6971:1::53/64' \
    <(ip -o -6 address show dev eth0 2>/dev/null)
record_equal node_architecture "$(dpkg --print-architecture 2>/dev/null || true)" arm64

for command_name in \
    bash caddy curl dpkg find grep hostname ip lighttpd openssl pgrep \
    readlink sha256sum ss stat systemctl; do
    record_command "command_${command_name}_present" command -v "$command_name"
done

record_command rollback_baseline_directory test -d "$rollback_baseline"
record_command rollback_baseline_not_symlink test ! -L "$rollback_baseline"
record_command rollback_baseline_complete grep -Fxq 'backup_complete=true' \
    "$rollback_baseline/backup-manifest.txt"
# shellcheck disable=SC2016
record_command rollback_baseline_hash_valid bash -c \
    'cd "$1" && sha256sum --check --status configuration.tar.sha256' \
    bash "$rollback_baseline"

record_equal live_lighttpd_tree \
    "$(tree_hash "$lighttpd_live" 2>/dev/null || true)" \
    "$live_lighttpd_sha256"
record_command candidate_directory test -d "$lighttpd_candidate"
record_command candidate_not_symlink test ! -L "$lighttpd_candidate"
record_equal candidate_meta \
    "$(stat -c '%U:%G:%a' "$lighttpd_candidate" 2>/dev/null || true)" \
    root:root:750
record_equal candidate_tree \
    "$(tree_hash "$lighttpd_candidate" 2>/dev/null || true)" \
    "$candidate_lighttpd_sha256"
record_equal candidate_main \
    "$(sha256sum "$lighttpd_candidate/lighttpd.conf" 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$candidate_main_sha256"
record_command candidate_native_parse lighttpd -tt \
    -f "$lighttpd_candidate/lighttpd.conf"

record_equal caddy_current_target \
    "$(readlink "$caddy_current" 2>/dev/null || true)" "$caddy_release"
record_equal caddy_current_resolved \
    "$(readlink -e "$caddy_current" 2>/dev/null || true)" "$caddy_release"
record_equal caddy_environment \
    "$(sha256sum "$caddy_environment" 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$environment_sha256"
record_command caddy_node_role grep -Fxq 'NODE_ROLE=node-a' "$caddy_environment"
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
record_command certificate_valid_now openssl x509 -checkend 0 -noout \
    -in "$caddy_release/tls/leaf.pem"
# shellcheck disable=SC2016
record_command certificate_wildcard_san bash -c \
    'openssl x509 -in "$1" -noout -ext subjectAltName |
        grep -Fq "DNS:*.local.theama.co"' \
    bash "$caddy_release/tls/leaf.pem"
record_command certificate_key_match certificate_key_matches

record_equal caddy_active "$(systemctl is-active caddy.service 2>/dev/null || true)" inactive
record_equal caddy_enabled "$(systemctl is-enabled caddy.service 2>/dev/null || true)" masked
record_equal caddy_api_active "$(systemctl is-active caddy-api.service 2>/dev/null || true)" inactive
record_equal caddy_api_enabled "$(systemctl is-enabled caddy-api.service 2>/dev/null || true)" masked
record_equal lighttpd_active "$(systemctl is-active lighttpd.service 2>/dev/null || true)" active
record_equal lighttpd_enabled "$(systemctl is-enabled lighttpd.service 2>/dev/null || true)" enabled
record_equal keepalived_active "$(systemctl is-active keepalived.service 2>/dev/null || true)" active
record_equal caddy_mask_meta \
    "$(stat -c '%F|%U:%G|%a|%s' "$caddy_mask" 2>/dev/null || true)" \
    'symbolic link|root:root|777|9'
record_equal caddy_mask_target \
    "$(readlink "$caddy_mask" 2>/dev/null || true)" /dev/null
record_equal caddy_package \
    "$(dpkg-query -W \
        -f='${Status}|${binary:Package}|${Version}|${Architecture}' \
        caddy 2>/dev/null || true)" \
    'install ok installed|caddy|2.11.4|arm64'
record_equal caddy_vendor_unit_meta \
    "$(stat -c '%F|%U:%G|%a|%s' "$caddy_vendor_unit" 2>/dev/null || true)" \
    'regular file|root:root|644|1029'
record_equal caddy_vendor_unit_canonical \
    "$(readlink -e "$caddy_vendor_unit" 2>/dev/null || true)" \
    "$caddy_vendor_canonical"
record_equal caddy_vendor_unit_hash \
    "$(sha256sum "$caddy_vendor_unit" 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$caddy_vendor_unit_sha256"
record_equal caddy_vendor_unit_owner \
    "$(dpkg-query -S "$caddy_vendor_unit" 2>/dev/null || true)" \
    'caddy: /lib/systemd/system/caddy.service'
record_equal caddy_vendor_unit_type_count \
    "$(grep -Ec '^[[:space:]]*Type[[:space:]]*=' \
        "$caddy_vendor_unit" 2>/dev/null || true)" 1
record_command caddy_vendor_unit_type grep -Fxq 'Type=notify' \
    "$caddy_vendor_unit"
record_equal caddy_stop_timeout "$(unit_state caddy.service TimeoutStopUSec)" 30s
record_equal effective_caddy_unit \
    "$(systemctl cat caddy.service 2>/dev/null | sha256sum | awk '{ print $1 }')" \
    "$caddy_unit_sha256"
record_equal effective_lighttpd_unit \
    "$(systemctl cat lighttpd.service 2>/dev/null | sha256sum | awk '{ print $1 }')" \
    "$lighttpd_unit_sha256"

record_equal tcp_80_count "$(listener_count tcp 80)" 2
record_command tcp_80_dualstack_lighttpd tcp_80_dualstack_lighttpd
record_equal tcp_443_count "$(listener_count tcp 443)" 1
record_command tcp_80_lighttpd_only tcp_owned_only_by_lighttpd 80
record_command tcp_443_lighttpd_only tcp_owned_only_by_lighttpd 443
record_equal tcp_8080_count "$(listener_count tcp 8080)" 0
record_equal tcp_2019_count "$(listener_count tcp 2019)" 0
record_equal udp_443_count "$(listener_count udp 443)" 0
record_equal caddy_process_count "$(pgrep -xc caddy 2>/dev/null || true)" 0
record_command current_http_management http_code_ok http
record_command current_https_management http_code_ok https

record_command lsyncd_configuration_absent test ! -e /etc/lsyncd/caddy.lua
record_command caddy_keepalived_fragment_absent \
    test ! -e /etc/keepalived/conf.d/caddy-ha.conf

printf 'preflight_assertion_count=%s\n' "$assertion_count"
printf 'preflight_mismatch_count=%s\n' "$mismatch_count"
printf 'first_failure=%s\n' "$first_failure"
printf 'peer_connections=false\n'
printf 'installed_helper_execution=false\n'
printf 'systemd_daemon_reload_performed=false\n'
printf 'service_mutations=false\n'
if [[ "$mismatch_count" -eq 0 ]]; then
    printf 'action_16ao_cutover_preflight_valid=true\n'
    printf 'action_16ao_inspection_complete=true\n'
    exit 0
fi
printf 'action_16ao_cutover_preflight_valid=false\n'
printf 'action_16ao_inspection_complete=true\n'
exit 1
