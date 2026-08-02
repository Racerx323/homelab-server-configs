#!/usr/bin/env bash
set -Eeuo pipefail

readonly live_lighttpd=/etc/lighttpd
readonly candidate_lighttpd=/etc/.lighttpd-caddy-action15-retry3
readonly original_lighttpd=/etc/.lighttpd-pre-action15-retry3
readonly failed_cutover=/etc/.lighttpd-caddy-action15-retry3.failed
readonly retry2_failed=/etc/.lighttpd-caddy-action15-retry2.failed
readonly previous_retry_failed=/etc/.lighttpd-caddy-action15-retry.failed
readonly historical_failed=/etc/.lighttpd-caddy-action15.failed
readonly accepted_stage=/var/tmp/caddy-ha-lighttpd-node-b-action15-retry
readonly caddy_config=/etc/caddy/current/Caddyfile
readonly caddy_release=/etc/caddy/releases/action15-health-follow-redirects
readonly caddy_environment=/etc/default/caddy-ha
readonly caddy_vrrp=/etc/keepalived/conf.d/caddy-ha.conf
readonly helper=/usr/local/libexec/prepare-lighttpd-config.sh
readonly desired_state=/usr/local/share/caddy-ha/lighttpd-desired-state.conf

readonly candidate_main_sha256=d5585d149bd3fbacd577b645e400a9342803cc2ed8bea8ff673601bad17aff17
readonly candidate_tree_sha256=8526150d037f0c57a81ed38653c8013900f7d5e51a3ddc2b543666c6b1144733
readonly live_tree_sha256=3f48f2374c76207c10841fc8305a1c83e803d68c3698e650f0ee38c928e68bab
readonly retry2_failed_tree_sha256=c627aa2d7915ae64ded7e0b788477d737ebe71b9fb81638c6369ddedf7c5818d
readonly previous_retry_failed_tree_sha256=c693c9d391785f45f95d62c7c77424f74e6a85ba55d61795b21310d827158b59
readonly historical_failed_tree_sha256=0bdc6ce0d71ae20eba11db969ed57852dd3f2aa5fc89b0e96ced979c40fe9ab9
readonly keepalived_tree_sha256=68d2bc846ad94da2a995f52e0f7829ff1c5706f35e399e40e1a0a552f37afd4f
readonly helper_sha256=ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f
readonly desired_state_sha256=8299970d5bb3793859071cd82f794dbae84955a6af931cf35d1509141f689027
readonly caddy_environment_sha256=f692d5b7e0a7e0f0ab142e36face6a8cc8c6680a44a2bcaf6a992247ec4c8113
readonly caddyfile_sha256=a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e
readonly caddy_override_sha256=a292487f4cbde99abce048b97ec15dbae8ef511ec845dcf5740f343e143f39df

readonly lighttpd_ready_seconds=20
readonly caddy_ready_seconds=35
readonly stability_seconds=3

original_moved=false
candidate_promoted=false
caddy_unmasked=false
success=false

tree_hash() {
    local root=$1

    (
        cd "$root"
        find . -type f -print0 |
            sort -z |
            xargs -0 sha256sum
    ) | sha256sum | awk '{print $1}'
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

tcp_listener_owned_by() {
    local port=$1
    local process=$2

    ss -H -lntp "sport = :$port" | grep -Fq "\"$process\""
}

udp_listener_owned_by() {
    local port=$1
    local process=$2

    ss -H -lnup "sport = :$port" | grep -Fq "\"$process\""
}

loopback_lighttpd_listener() {
    ss -H -lntp 'sport = :8080' |
        grep -F '127.0.0.1:8080' |
        grep -Fq '"lighttpd"'
}

http_code_is_success_or_redirect() {
    local code=$1

    [[ "$code" =~ ^[23][0-9][0-9]$ ]]
}

lighttpd_backend_ready_once() {
    local code

    systemctl is-active --quiet lighttpd ||
        return 1
    loopback_lighttpd_listener ||
        return 1
    if tcp_listener_owned_by 80 lighttpd ||
        tcp_listener_owned_by 443 lighttpd; then
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
    tcp_listener_owned_by 80 lighttpd ||
        return 1
    tcp_listener_owned_by 443 lighttpd ||
        return 1
    code=$(
        curl --insecure --silent --show-error \
            --connect-timeout 1 --max-time 2 \
            --resolve pihole00.local.theama.co:443:10.1.0.54 \
            --output /dev/null --write-out '%{http_code}' \
            https://pihole00.local.theama.co/admin/ 2>/dev/null ||
            true
    )
    http_code_is_success_or_redirect "$code"
}

caddy_ready_once() {
    local code

    systemctl is-active --quiet caddy ||
        return 1
    tcp_listener_owned_by 80 caddy ||
        return 1
    tcp_listener_owned_by 443 caddy ||
        return 1
    udp_listener_owned_by 443 caddy ||
        return 1
    if tcp_listener_owned_by 80 lighttpd ||
        tcp_listener_owned_by 443 lighttpd; then
        return 1
    fi
    curl --insecure --fail --silent --show-error --head \
        --connect-timeout 1 --max-time 3 \
        https://localhost/ >/dev/null ||
        return 1
    code=$(
        curl --silent --show-error \
            --connect-timeout 1 --max-time 3 \
            --resolve pihole00.local.theama.co:443:10.1.0.54 \
            --output /dev/null --write-out '%{http_code}' \
            https://pihole00.local.theama.co/admin/ 2>/dev/null ||
            true
    )
    http_code_is_success_or_redirect "$code"
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
    printf 'action_15_retry_failure_status=%s\n' "$triggering_status" >&2

    if [[ "$caddy_unmasked" == true ]]; then
        systemctl stop caddy.service || rollback_ok=false
        systemctl mask caddy.service || rollback_ok=false
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

    if [[ -d "$live_lighttpd" && ! -L "$live_lighttpd" ]]; then
        lighttpd -tt -f "$live_lighttpd/lighttpd.conf" ||
            rollback_ok=false
        systemctl restart lighttpd.service || true
        wait_until_stable original_lighttpd "$lighttpd_ready_seconds" \
            original_lighttpd_ready_once ||
            rollback_ok=false
    else
        rollback_ok=false
    fi

    [[ "$(tree_hash "$live_lighttpd" 2>/dev/null || true)" == "$live_tree_sha256" ]] ||
        rollback_ok=false
    [[ "$(tree_hash "$previous_retry_failed" 2>/dev/null || true)" == "$previous_retry_failed_tree_sha256" ]] ||
        rollback_ok=false
    [[ "$(tree_hash "$retry2_failed" 2>/dev/null || true)" == "$retry2_failed_tree_sha256" ]] ||
        rollback_ok=false
    [[ "$(tree_hash "$historical_failed" 2>/dev/null || true)" == "$historical_failed_tree_sha256" ]] ||
        rollback_ok=false
    [[ "$(tree_hash /etc/keepalived 2>/dev/null || true)" == "$keepalived_tree_sha256" ]] ||
        rollback_ok=false
    [[ "$(systemctl is-active caddy 2>/dev/null || true)" == inactive ]] ||
        rollback_ok=false
    [[ "$(systemctl is-enabled caddy 2>/dev/null || true)" == masked ]] ||
        rollback_ok=false
    [[ "$(systemctl is-active lsyncd 2>/dev/null || true)" == inactive ]] ||
        rollback_ok=false
    [[ "$(systemctl is-enabled lsyncd 2>/dev/null || true)" == masked ]] ||
        rollback_ok=false
    [[ ! -e "$caddy_vrrp" ]] ||
        rollback_ok=false

    if [[ "$rollback_ok" == true ]]; then
        printf 'action_15_retry_rollback_complete=true\n' >&2
        exit "$triggering_status"
    fi

    printf 'action_15_retry_rollback_incomplete=true\n' >&2
    printf 'manual_intervention_required=true\n' >&2
    exit 125
}

on_exit() {
    local status=$?

    if [[ "$success" != true ]]; then
        if [[ "$original_moved" != true &&
            "$candidate_promoted" != true &&
            "$caddy_unmasked" != true ]]; then
            printf 'action_15_retry_rollback_not_required=true\n' >&2
            return
        fi
        rollback "$status"
    fi
}
trap on_exit EXIT

[[ $EUID -eq 0 ]]
for command_name in caddy curl grep lighttpd readlink runuser sha256sum ss systemctl; do
    command -v "$command_name" >/dev/null
done

[[ -d "$live_lighttpd" && ! -L "$live_lighttpd" ]]
[[ -d "$candidate_lighttpd" && ! -L "$candidate_lighttpd" ]]
[[ -d "$accepted_stage" && ! -L "$accepted_stage" ]]
[[ -d "$retry2_failed" && ! -L "$retry2_failed" ]]
[[ -d "$previous_retry_failed" && ! -L "$previous_retry_failed" ]]
[[ -d "$historical_failed" && ! -L "$historical_failed" ]]
[[ ! -e "$original_lighttpd" ]]
[[ ! -e "$failed_cutover" ]]
[[ -f "$caddy_config" && ! -L "$caddy_config" ]]
[[ "$(readlink -e /etc/caddy/current)" == "$caddy_release" ]]
[[ -f "$caddy_environment" && ! -L "$caddy_environment" ]]
[[ ! -e "$caddy_vrrp" ]]

[[ "$(stat -c '%U:%G:%a' "$candidate_lighttpd")" == root:root:750 ]]
[[ "$(sha256sum "$candidate_lighttpd/lighttpd.conf" | awk '{print $1}')" == "$candidate_main_sha256" ]]
[[ "$(tree_hash "$candidate_lighttpd")" == "$candidate_tree_sha256" ]]
[[ "$(tree_hash "$live_lighttpd")" == "$live_tree_sha256" ]]
[[ "$(tree_hash "$retry2_failed")" == "$retry2_failed_tree_sha256" ]]
[[ "$(tree_hash "$previous_retry_failed")" == "$previous_retry_failed_tree_sha256" ]]
[[ "$(tree_hash "$historical_failed")" == "$historical_failed_tree_sha256" ]]
[[ "$(tree_hash /etc/keepalived)" == "$keepalived_tree_sha256" ]]
[[ "$(sha256sum "$helper" | awk '{print $1}')" == "$helper_sha256" ]]
[[ "$(sha256sum "$desired_state" | awk '{print $1}')" == "$desired_state_sha256" ]]
[[ "$(stat -c '%U:%G:%a' "$caddy_environment")" == root:caddy-tls:640 ]]
[[ "$(sha256sum "$caddy_environment" | awk '{print $1}')" == "$caddy_environment_sha256" ]]
[[ "$(sha256sum "$caddy_config" | awk '{print $1}')" == "$caddyfile_sha256" ]]
[[ "$(sha256sum /etc/systemd/system/caddy.service.d/override.conf | awk '{print $1}')" == "$caddy_override_sha256" ]]

set -a
# shellcheck disable=SC1090
source "$caddy_environment"
set +a
[[ "$NODE_ROLE" == node-b ]]
[[ "$NODE_FQDN" == pihole00.local.theama.co ]]
[[ "$NODE_IPV4" == 10.1.0.54 ]]
[[ "$NODE_IPV6" == fd36:5aa8:6971:1::54 ]]

[[ "$(systemctl is-active lighttpd)" == active ]]
[[ "$(systemctl is-enabled lighttpd)" == enabled ]]
[[ "$(systemctl is-active keepalived)" == active ]]
[[ "$(systemctl is-enabled keepalived)" == enabled ]]
[[ "$(systemctl is-active caddy 2>/dev/null || true)" == failed ]]
[[ "$(systemctl is-enabled caddy 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lsyncd 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd 2>/dev/null || true)" == masked ]]
tcp_listener_owned_by 80 lighttpd
tcp_listener_owned_by 443 lighttpd
if ss -H -lntup | awk '$5 ~ /:(8080|2019)$/ {found = 1} END {exit found ? 0 : 1}'; then
    printf 'TCP 8080 or 2019 is already occupied.\n' >&2
    exit 1
fi
if ss -H -lnup 'sport = :443' | grep -q .; then
    printf 'UDP 443 is already occupied.\n' >&2
    exit 1
fi

lighttpd -tt -f "$candidate_lighttpd/lighttpd.conf"
runuser -u caddy -- \
    caddy validate --config "$caddy_config" --adapter caddyfile

services_before=$(service_snapshot)
caddy_tree_before=$(tree_hash /etc/caddy)

mv -- "$live_lighttpd" "$original_lighttpd"
original_moved=true
mv -- "$candidate_lighttpd" "$live_lighttpd"
candidate_promoted=true

include_old='/etc/.lighttpd-caddy-action15-retry3/conf-enabled/*.conf'
include_new='/etc/lighttpd/conf-enabled/*.conf'
[[ "$(grep -Fxc "include \"$include_old\"" "$live_lighttpd/lighttpd.conf")" -eq 1 ]]
sed -i \
    's|^include "/etc/[.]lighttpd-caddy-action15-retry3/conf-enabled/[*][.]conf"$|include "/etc/lighttpd/conf-enabled/*.conf"|' \
    "$live_lighttpd/lighttpd.conf"
[[ "$(grep -Fxc "include \"$include_new\"" "$live_lighttpd/lighttpd.conf")" -eq 1 ]]
if grep -Fq "$include_old" "$live_lighttpd/lighttpd.conf"; then
    printf 'Promoted lighttpd configuration retains its inactive include root.\n' >&2
    exit 1
fi

lighttpd -tt -f "$live_lighttpd/lighttpd.conf"
systemctl restart lighttpd.service || true
wait_until_stable lighttpd_backend "$lighttpd_ready_seconds" \
    lighttpd_backend_ready_once

systemctl unmask caddy.service
caddy_unmasked=true
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
[[ "$(systemctl is-active lsyncd 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active caddy-lsyncd 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy-lsyncd 2>/dev/null || true)" == disabled ]]
[[ "$(tree_hash /etc/caddy)" == "$caddy_tree_before" ]]
[[ "$(tree_hash /etc/keepalived)" == "$keepalived_tree_sha256" ]]
[[ "$(tree_hash "$retry2_failed")" == "$retry2_failed_tree_sha256" ]]
[[ "$(tree_hash "$previous_retry_failed")" == "$previous_retry_failed_tree_sha256" ]]
[[ "$(tree_hash "$historical_failed")" == "$historical_failed_tree_sha256" ]]
[[ -d "$original_lighttpd" && ! -L "$original_lighttpd" ]]
[[ "$(tree_hash "$original_lighttpd")" == "$live_tree_sha256" ]]
[[ ! -e "$candidate_lighttpd" ]]
[[ ! -e "$failed_cutover" ]]
[[ ! -e "$caddy_vrrp" ]]

printf 'services_before=%q\n' "$services_before"
printf 'promoted_lighttpd_main_sha256=%s\n' \
    "$(sha256sum "$live_lighttpd/lighttpd.conf" | awk '{print $1}')"
printf 'promoted_lighttpd_tree_sha256=%s\n' \
    "$(tree_hash "$live_lighttpd")"
printf 'original_lighttpd_tree_sha256=%s\n' \
    "$(tree_hash "$original_lighttpd")"
printf 'caddy_tree_sha256=%s\n' "$caddy_tree_before"
printf 'keepalived_tree_sha256=%s\n' "$keepalived_tree_sha256"
printf 'caddy_timeout_stop=%s\n' \
    "$(systemctl show caddy.service --property=TimeoutStopUSec --value)"
printf 'action_15_retry3_cutover_complete=true\n'
success=true
