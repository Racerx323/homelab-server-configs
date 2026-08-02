#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly live_lighttpd=/etc/lighttpd
readonly source_candidate=/var/tmp/caddy-ha-lighttpd-node-a-action16ab
readonly cutover_candidate=/etc/.lighttpd-caddy-action16ap
readonly original_lighttpd=/etc/.lighttpd-pre-action16ap
readonly failed_cutover=/etc/.lighttpd-caddy-action16ap.failed
readonly caddy_config=/etc/caddy/current/Caddyfile
readonly caddy_release=/etc/caddy/releases/bootstrap
readonly caddy_environment=/etc/default/caddy-ha
readonly caddy_mask=/etc/systemd/system/caddy.service
readonly caddy_vendor_unit=/lib/systemd/system/caddy.service
readonly caddy_vrrp=/etc/keepalived/conf.d/caddy-ha.conf

readonly live_lighttpd_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_lighttpd_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly candidate_main_sha256=c48b3f0a8c256185233b302952f0b4ee138e745fb17ede92ae3f16d7fa4a6a99
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly caddyfile_sha256=a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e
readonly caddy_vendor_unit_sha256=6c271e030644bd36a0c8956885934f16c928f88202bc126f12cde519ef9693ff
readonly caddy_override_sha256=a292487f4cbde99abce048b97ec15dbae8ef511ec845dcf5740f343e143f39df
readonly caddy_package_record='install ok installed|caddy|2.11.4|arm64'

readonly lighttpd_ready_seconds=20
readonly caddy_ready_seconds=35
readonly stability_seconds=3

stage_created=false
original_moved=false
candidate_promoted=false
caddy_unmasked=false
success=false
caddy_tree_before=
keepalived_tree_before=
services_before=
listeners_before=
transformed_candidate_sha256=

tree_hash() {
    local root=$1

    (
        cd "$root"
        find . -type f -print0 |
            sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

service_snapshot() {
    local unit

    for unit in lighttpd caddy caddy-api lsyncd caddy-lsyncd keepalived; do
        printf '%s=%s/%s\n' \
            "$unit" \
            "$(systemctl is-active "$unit" 2>/dev/null || true)" \
            "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    done
}

listener_snapshot() {
    ss -H -lntup 2>/dev/null |
        awk '$5 ~ /:(80|443|8080|2019)$/ { print }' |
        sort
}

tcp_listener_count() {
    local port=$1

    ss -H -lntp "sport = :$port" 2>/dev/null |
        awk 'END { print NR + 0 }'
}

tcp_listener_owned_only_by() {
    local port=$1
    local process=$2
    local output

    output=$(ss -H -lntp "sport = :$port" 2>/dev/null)
    [[ -n "$output" ]] &&
        grep -Fq "users:((\"$process\"" <<<"$output" &&
        ! grep -Fv "users:((\"$process\"" <<<"$output" >/dev/null
}

udp_listener_owned_by() {
    local port=$1
    local process=$2

    ss -H -lnup "sport = :$port" 2>/dev/null |
        grep -Fq "\"$process\""
}

loopback_lighttpd_listener() {
    local output

    output=$(ss -H -lntp 'sport = :8080' 2>/dev/null)
    [[ "$(wc -l <<<"$output")" -eq 1 ]] &&
        grep -Fq '127.0.0.1:8080' <<<"$output" &&
        grep -Fq 'users:(("lighttpd"' <<<"$output"
}

caddy_admin_listener() {
    local output

    output=$(ss -H -lntp 'sport = :2019' 2>/dev/null)
    [[ "$(wc -l <<<"$output")" -eq 1 ]] &&
        grep -Fq '127.0.0.1:2019' <<<"$output" &&
        grep -Fq 'users:(("caddy"' <<<"$output"
}

http_code_is_success_or_redirect() {
    [[ "$1" =~ ^[23][0-9][0-9]$ ]]
}

lighttpd_backend_ready_once() {
    local code

    systemctl is-active --quiet lighttpd ||
        return 1
    loopback_lighttpd_listener ||
        return 1
    if ss -H -lntp 'sport = :80 or sport = :443' 2>/dev/null |
        grep -Fq 'users:(("lighttpd"'; then
        return 1
    fi
    code=$(
        curl --silent --show-error \
            --connect-timeout 1 --max-time 2 \
            --output /dev/null --write-out '%{http_code}' \
            http://127.0.0.1:8080/admin/ 2>/dev/null ||
            true
    )
    http_code_is_success_or_redirect "$code"
}

original_lighttpd_ready_once() {
    local code

    systemctl is-active --quiet lighttpd ||
        return 1
    tcp_listener_owned_only_by 80 lighttpd ||
        return 1
    tcp_listener_owned_only_by 443 lighttpd ||
        return 1
    code=$(
        curl --insecure --silent --show-error \
            --connect-timeout 1 --max-time 2 \
            --resolve pihole0.local.theama.co:443:10.1.0.53 \
            --output /dev/null --write-out '%{http_code}' \
            https://pihole0.local.theama.co/admin/ 2>/dev/null ||
            true
    )
    http_code_is_success_or_redirect "$code"
}

caddy_ready_once() {
    local code resolved_address

    systemctl is-active --quiet caddy ||
        return 1
    tcp_listener_owned_only_by 80 caddy ||
        return 1
    tcp_listener_owned_only_by 443 caddy ||
        return 1
    udp_listener_owned_by 443 caddy ||
        return 1
    caddy_admin_listener ||
        return 1
    if ss -H -lntp 'sport = :80 or sport = :443' 2>/dev/null |
        grep -Fq 'users:(("lighttpd"'; then
        return 1
    fi
    curl --insecure --fail --silent --show-error --head \
        --connect-timeout 1 --max-time 3 \
        https://localhost/ >/dev/null ||
        return 1
    for resolved_address in 10.1.0.53 '[fd36:5aa8:6971:1::53]'; do
        code=$(
            curl --silent --show-error \
                --connect-timeout 1 --max-time 3 \
                --resolve "pihole0.local.theama.co:443:$resolved_address" \
                --output /dev/null --write-out '%{http_code}' \
                https://pihole0.local.theama.co/admin/ 2>/dev/null ||
                true
        )
        http_code_is_success_or_redirect "$code" ||
            return 1
    done
    return 0
}

wait_until_stable() {
    local description=$1
    local timeout_seconds=$2
    local probe=$3
    local deadline=$((SECONDS + timeout_seconds))

    while ((SECONDS < deadline)); do
        if "$probe"; then
            sleep "$stability_seconds"
            if "$probe"; then
                printf '%s_ready=true\n' "$description"
                return 0
            fi
        fi
        sleep 0.2
    done
    printf '%s_ready=false\n' "$description" >&2
    return 1
}

rollback() {
    local triggering_status=$1
    local rollback_ok=true

    trap - EXIT
    printf 'action_16ap_failure_status=%s\n' "$triggering_status" >&2

    if [[ "$caddy_unmasked" == true ]]; then
        systemctl stop caddy.service || rollback_ok=false
        systemctl mask caddy.service || rollback_ok=false
        systemctl daemon-reload || rollback_ok=false
        systemctl reset-failed caddy.service || rollback_ok=false
    fi

    if [[ "$candidate_promoted" == true ]]; then
        systemctl stop lighttpd.service || rollback_ok=false
        if [[ -d "$live_lighttpd" && ! -L "$live_lighttpd" &&
            ! -e "$failed_cutover" ]]; then
            mv -- "$live_lighttpd" "$failed_cutover" || rollback_ok=false
        else
            rollback_ok=false
        fi
    fi

    if [[ "$original_moved" == true ]]; then
        if [[ ! -e "$live_lighttpd" &&
            -d "$original_lighttpd" && ! -L "$original_lighttpd" ]]; then
            mv -- "$original_lighttpd" "$live_lighttpd" || rollback_ok=false
        else
            rollback_ok=false
        fi
    fi

    if [[ "$original_moved" == true || "$candidate_promoted" == true ]]; then
        [[ -d "$live_lighttpd" && ! -L "$live_lighttpd" ]] ||
            rollback_ok=false
        lighttpd -tt -f "$live_lighttpd/lighttpd.conf" ||
            rollback_ok=false
        systemctl restart lighttpd.service || true
        wait_until_stable original_lighttpd "$lighttpd_ready_seconds" \
            original_lighttpd_ready_once ||
            rollback_ok=false
    fi

    if [[ -d "$cutover_candidate" && ! -L "$cutover_candidate" ]]; then
        rm -rf -- "$cutover_candidate" || rollback_ok=false
    elif [[ -e "$cutover_candidate" || -L "$cutover_candidate" ]]; then
        rollback_ok=false
    fi
    if [[ -d "$failed_cutover" && ! -L "$failed_cutover" ]]; then
        rm -rf -- "$failed_cutover" || rollback_ok=false
    elif [[ -e "$failed_cutover" || -L "$failed_cutover" ]]; then
        rollback_ok=false
    fi

    [[ "$(tree_hash "$live_lighttpd" 2>/dev/null || true)" == "$live_lighttpd_sha256" ]] ||
        rollback_ok=false
    [[ "$(tree_hash "$source_candidate" 2>/dev/null || true)" == "$candidate_lighttpd_sha256" ]] ||
        rollback_ok=false
    [[ "$(tree_hash /etc/caddy 2>/dev/null || true)" == "$caddy_tree_before" ]] ||
        rollback_ok=false
    [[ "$(tree_hash /etc/keepalived 2>/dev/null || true)" == "$keepalived_tree_before" ]] ||
        rollback_ok=false
    [[ "$(service_snapshot)" == "$services_before" ]] ||
        rollback_ok=false
    [[ "$(tcp_listener_count 80)" -eq 2 ]] ||
        rollback_ok=false
    tcp_listener_owned_only_by 80 lighttpd ||
        rollback_ok=false
    [[ "$(tcp_listener_count 443)" -eq 1 ]] ||
        rollback_ok=false
    tcp_listener_owned_only_by 443 lighttpd ||
        rollback_ok=false
    [[ "$(tcp_listener_count 8080)" -eq 0 ]] ||
        rollback_ok=false
    [[ "$(tcp_listener_count 2019)" -eq 0 ]] ||
        rollback_ok=false
    if ss -H -lnup 'sport = :443' 2>/dev/null | grep -q .; then
        rollback_ok=false
    fi
    [[ ! -e "$original_lighttpd" && ! -L "$original_lighttpd" ]] ||
        rollback_ok=false
    [[ ! -e "$cutover_candidate" && ! -L "$cutover_candidate" ]] ||
        rollback_ok=false
    [[ ! -e "$failed_cutover" && ! -L "$failed_cutover" ]] ||
        rollback_ok=false
    [[ ! -e "$caddy_vrrp" ]] ||
        rollback_ok=false

    if [[ "$rollback_ok" == true ]]; then
        printf 'action_16ap_rollback_complete=true\n' >&2
        exit "$triggering_status"
    fi
    printf 'action_16ap_rollback_incomplete=true\n' >&2
    printf 'manual_intervention_required=true\n' >&2
    exit 125
}

on_exit() {
    local status=$?

    if [[ "$success" == true ]]; then
        return
    fi
    if [[ "$stage_created" != true &&
        "$original_moved" != true &&
        "$candidate_promoted" != true &&
        "$caddy_unmasked" != true ]]; then
        printf 'action_16ap_rollback_not_required=true\n' >&2
        return
    fi
    rollback "$status"
}
trap on_exit EXIT

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$candidate_lighttpd_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$caddy_vendor_unit_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$lighttpd_ready_seconds" -eq 20 ]]
    [[ "$caddy_ready_seconds" -eq 35 ]]
    [[ "$stability_seconds" -eq 3 ]]
    [[ "$source_candidate" == /var/tmp/caddy-ha-lighttpd-node-a-action16ab ]]
    [[ "$cutover_candidate" == /etc/.lighttpd-caddy-action16ap ]]
    printf 'action_16ap_cutover_self_test_complete=true\n'
    success=true
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

printf 'action_16ap_remote_reached=true\n'
[[ $EUID -eq 0 ]]
for command_name in \
    awk caddy cp curl dpkg-query find grep lighttpd mv readlink rm runuser sed \
    sha256sum sleep sort ss stat systemctl wc xargs; do
    command -v "$command_name" >/dev/null
done

[[ -d "$live_lighttpd" && ! -L "$live_lighttpd" ]]
[[ -d "$source_candidate" && ! -L "$source_candidate" ]]
[[ ! -e "$cutover_candidate" && ! -L "$cutover_candidate" ]]
[[ ! -e "$original_lighttpd" && ! -L "$original_lighttpd" ]]
[[ ! -e "$failed_cutover" && ! -L "$failed_cutover" ]]
[[ ! -e "$caddy_vrrp" ]]
[[ "$(stat -c '%U:%G:%a' "$source_candidate")" == root:root:750 ]]
[[ "$(sha256sum "$source_candidate/lighttpd.conf" |
    awk '{ print $1 }')" == "$candidate_main_sha256" ]]
[[ "$(tree_hash "$source_candidate")" == "$candidate_lighttpd_sha256" ]]
[[ "$(tree_hash "$live_lighttpd")" == "$live_lighttpd_sha256" ]]
lighttpd -tt -f "$source_candidate/lighttpd.conf"

[[ "$(readlink -e /etc/caddy/current)" == "$caddy_release" ]]
[[ "$(sha256sum "$caddy_config" |
    awk '{ print $1 }')" == "$caddyfile_sha256" ]]
[[ "$(sha256sum "$caddy_environment" |
    awk '{ print $1 }')" == "$environment_sha256" ]]
[[ "$(readlink "$caddy_mask")" == /dev/null ]]
[[ "$(sha256sum "$caddy_vendor_unit" |
    awk '{ print $1 }')" == "$caddy_vendor_unit_sha256" ]]
[[ "$(dpkg-query -W \
    -f='${Status}|${binary:Package}|${Version}|${Architecture}' caddy)" == "$caddy_package_record" ]]
[[ "$(grep -Ec '^[[:space:]]*Type[[:space:]]*=' \
    "$caddy_vendor_unit")" -eq 1 ]]
grep -Fxq 'Type=notify' "$caddy_vendor_unit"
[[ "$(sha256sum /etc/systemd/system/caddy.service.d/override.conf |
    awk '{ print $1 }')" == "$caddy_override_sha256" ]]

set -a
# shellcheck disable=SC1090
source "$caddy_environment"
set +a
[[ "$NODE_ROLE" == node-a ]]
[[ "$NODE_FQDN" == pihole0.local.theama.co ]]
[[ "$NODE_IPV4" == 10.1.0.53 ]]
[[ "$NODE_IPV6" == fd36:5aa8:6971:1::53 ]]

[[ "$(systemctl is-active lighttpd)" == active ]]
[[ "$(systemctl is-enabled lighttpd)" == enabled ]]
[[ "$(systemctl is-active keepalived)" == active ]]
[[ "$(systemctl is-enabled keepalived)" == enabled ]]
[[ "$(systemctl is-active caddy 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active caddy-api 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy-api 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lsyncd 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active caddy-lsyncd 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy-lsyncd 2>/dev/null || true)" == disabled ]]
[[ "$(tcp_listener_count 80)" -eq 2 ]]
tcp_listener_owned_only_by 80 lighttpd
[[ "$(tcp_listener_count 443)" -eq 1 ]]
tcp_listener_owned_only_by 443 lighttpd
[[ "$(tcp_listener_count 8080)" -eq 0 ]]
[[ "$(tcp_listener_count 2019)" -eq 0 ]]
if ss -H -lnup 'sport = :443' 2>/dev/null | grep -q .; then
    printf 'UDP 443 is already occupied.\n' >&2
    exit 1
fi

runuser -u caddy -- \
    caddy validate --config "$caddy_config" --adapter caddyfile

services_before=$(service_snapshot)
listeners_before=$(listener_snapshot)
caddy_tree_before=$(tree_hash /etc/caddy)
keepalived_tree_before=$(tree_hash /etc/keepalived)
printf 'action_16ap_preflight_complete=true\n'
printf 'action_16ap_mutation_started=true\n'

stage_created=true
cp -a -- "$source_candidate" "$cutover_candidate"
[[ "$(stat -c '%U:%G:%a' "$cutover_candidate")" == root:root:750 ]]
[[ "$(tree_hash "$cutover_candidate")" == "$candidate_lighttpd_sha256" ]]

source_include="$source_candidate/conf-enabled/*.conf"
stage_include="$cutover_candidate/conf-enabled/*.conf"
live_include="$live_lighttpd/conf-enabled/*.conf"
[[ "$(grep -Fxc "include \"$source_include\"" \
    "$cutover_candidate/lighttpd.conf")" -eq 1 ]]
sed -i \
    's|^include "/var/tmp/caddy-ha-lighttpd-node-a-action16ab/conf-enabled/[*][.]conf"$|include "/etc/.lighttpd-caddy-action16ap/conf-enabled/*.conf"|' \
    "$cutover_candidate/lighttpd.conf"
[[ "$(grep -Fxc "include \"$stage_include\"" \
    "$cutover_candidate/lighttpd.conf")" -eq 1 ]]
lighttpd -tt -f "$cutover_candidate/lighttpd.conf"
transformed_candidate_sha256=$(tree_hash "$cutover_candidate")

mv -- "$live_lighttpd" "$original_lighttpd"
original_moved=true
mv -- "$cutover_candidate" "$live_lighttpd"
candidate_promoted=true
stage_created=false

[[ "$(grep -Fxc "include \"$stage_include\"" \
    "$live_lighttpd/lighttpd.conf")" -eq 1 ]]
sed -i \
    's|^include "/etc/[.]lighttpd-caddy-action16ap/conf-enabled/[*][.]conf"$|include "/etc/lighttpd/conf-enabled/*.conf"|' \
    "$live_lighttpd/lighttpd.conf"
[[ "$(grep -Fxc "include \"$live_include\"" \
    "$live_lighttpd/lighttpd.conf")" -eq 1 ]]
lighttpd -tt -f "$live_lighttpd/lighttpd.conf"
systemctl restart lighttpd.service || true
wait_until_stable lighttpd_backend "$lighttpd_ready_seconds" \
    lighttpd_backend_ready_once

caddy_unmasked=true
systemctl unmask caddy.service
systemctl daemon-reload
[[ "$(systemctl is-enabled caddy 2>/dev/null || true)" == disabled ]]
[[ "$(systemctl show caddy.service --property=Type --value)" == notify ]]
[[ "$(systemctl show caddy.service --property=TimeoutStopUSec --value)" == 30s ]]
systemctl reset-failed caddy.service
systemctl start caddy.service || true
wait_until_stable caddy "$caddy_ready_seconds" caddy_ready_once

runuser -u caddy -- \
    caddy validate --config "$caddy_config" --adapter caddyfile
curl --insecure --fail --silent --show-error --head \
    --connect-timeout 1 --max-time 3 https://localhost/ >/dev/null

[[ "$(systemctl is-active lighttpd)" == active ]]
[[ "$(systemctl is-enabled lighttpd)" == enabled ]]
[[ "$(systemctl is-active caddy)" == active ]]
[[ "$(systemctl is-enabled caddy)" == disabled ]]
[[ "$(systemctl is-active keepalived)" == active ]]
[[ "$(systemctl is-enabled keepalived)" == enabled ]]
[[ "$(systemctl is-active caddy-api 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy-api 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lsyncd 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active caddy-lsyncd 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy-lsyncd 2>/dev/null || true)" == disabled ]]
[[ "$(tree_hash /etc/caddy)" == "$caddy_tree_before" ]]
[[ "$(tree_hash /etc/keepalived)" == "$keepalived_tree_before" ]]
[[ "$(tree_hash "$source_candidate")" == "$candidate_lighttpd_sha256" ]]
[[ -d "$original_lighttpd" && ! -L "$original_lighttpd" ]]
[[ "$(tree_hash "$original_lighttpd")" == "$live_lighttpd_sha256" ]]
[[ ! -e "$cutover_candidate" && ! -L "$cutover_candidate" ]]
[[ ! -e "$failed_cutover" && ! -L "$failed_cutover" ]]
[[ ! -e "$caddy_vrrp" ]]
lighttpd_backend_ready_once
caddy_ready_once

printf 'services_before=%q\n' "$services_before"
printf 'listeners_before_sha256=%s\n' \
    "$(printf '%s' "$listeners_before" | sha256sum | awk '{ print $1 }')"
printf 'source_candidate_tree_sha256=%s\n' \
    "$(tree_hash "$source_candidate")"
printf 'transformed_candidate_tree_sha256=%s\n' \
    "$transformed_candidate_sha256"
printf 'promoted_lighttpd_tree_sha256=%s\n' \
    "$(tree_hash "$live_lighttpd")"
printf 'original_lighttpd_tree_sha256=%s\n' \
    "$(tree_hash "$original_lighttpd")"
printf 'caddy_tree_sha256=%s\n' "$caddy_tree_before"
printf 'keepalived_tree_sha256=%s\n' "$keepalived_tree_before"
printf 'caddy_timeout_stop=%s\n' \
    "$(systemctl show caddy.service --property=TimeoutStopUSec --value)"
printf 'peer_connections=false\n'
printf 'lsyncd_configuration_changes=false\n'
printf 'keepalived_configuration_changes=false\n'
printf 'action_16ap_cutover_complete=true\n'
success=true
