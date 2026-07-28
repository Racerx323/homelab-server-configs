#!/usr/bin/env bash
set -euo pipefail

readonly live=/etc/lighttpd
readonly candidate=/etc/.lighttpd-caddy-action15-retry2
readonly failed_retry=/etc/.lighttpd-caddy-action15-retry.failed
readonly historical_failed=/etc/.lighttpd-caddy-action15.failed
readonly helper=/usr/local/libexec/prepare-lighttpd-config.sh
readonly desired_state=/usr/local/share/caddy-ha/lighttpd-desired-state.conf
readonly caddy_vrrp=/etc/keepalived/conf.d/caddy-ha.conf

readonly live_tree_sha256=3f48f2374c76207c10841fc8305a1c83e803d68c3698e650f0ee38c928e68bab
readonly failed_retry_main_sha256=b712ee21f71a9102ef90d53d07d0a783a1fd848c1fa307d20166029dc14dd248
readonly failed_retry_tree_sha256=c693c9d391785f45f95d62c7c77424f74e6a85ba55d61795b21310d827158b59
readonly historical_failed_tree_sha256=0bdc6ce0d71ae20eba11db969ed57852dd3f2aa5fc89b0e96ced979c40fe9ab9
readonly keepalived_tree_sha256=68d2bc846ad94da2a995f52e0f7829ff1c5706f35e399e40e1a0a552f37afd4f
readonly helper_sha256=ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f
readonly desired_state_sha256=8299970d5bb3793859071cd82f794dbae84955a6af931cf35d1509141f689027

success=false
cleanup() {
    local status=$?

    if [[ "$success" != true ]]; then
        rm -rf -- "$candidate"
        printf 'action_15_retry2_stage_rollback_complete=true\n' >&2
    fi
    exit "$status"
}
trap cleanup EXIT

tree_hash() {
    local root=$1

    (
        cd "$root"
        find . -type f -print0 |
            sort -z |
            xargs -0 sha256sum
    ) | sha256sum | awk '{print $1}'
}

listener_snapshot() {
    ss -H -lntup |
        awk '$5 ~ /:(80|443|8080|2019)$/ {print}' |
        sort
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

[[ $EUID -eq 0 ]]
for command_name in diff grep lighttpd sed sha256sum ss systemctl; do
    command -v "$command_name" >/dev/null
done

[[ -d "$live" && ! -L "$live" ]]
[[ -d "$failed_retry" && ! -L "$failed_retry" ]]
[[ -d "$historical_failed" && ! -L "$historical_failed" ]]
[[ ! -e "$candidate" ]]
[[ ! -e /etc/.lighttpd-pre-action15-retry2 ]]
[[ ! -e /etc/.lighttpd-caddy-action15-retry2.failed ]]
[[ ! -e "$caddy_vrrp" ]]

[[ "$(tree_hash "$live")" == "$live_tree_sha256" ]]
[[ "$(sha256sum "$failed_retry/lighttpd.conf" | awk '{print $1}')" == "$failed_retry_main_sha256" ]]
[[ "$(tree_hash "$failed_retry")" == "$failed_retry_tree_sha256" ]]
[[ "$(tree_hash "$historical_failed")" == "$historical_failed_tree_sha256" ]]
[[ "$(tree_hash /etc/keepalived)" == "$keepalived_tree_sha256" ]]
[[ "$(sha256sum "$helper" | awk '{print $1}')" == "$helper_sha256" ]]
[[ "$(sha256sum "$desired_state" | awk '{print $1}')" == "$desired_state_sha256" ]]

services_before=$(service_snapshot)
listeners_before=$(listener_snapshot)

[[ "$(systemctl is-active lighttpd)" == active ]]
[[ "$(systemctl is-enabled lighttpd)" == enabled ]]
[[ "$(systemctl is-active caddy 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lsyncd 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active keepalived)" == active ]]
[[ "$(systemctl is-enabled keepalived)" == enabled ]]

"$helper" --source-root "$live" --output "$candidate"

[[ "$(stat -c '%U:%G:%a' "$candidate")" == root:root:750 ]]
grep -Fqx \
    'include "/etc/.lighttpd-caddy-action15-retry2/conf-enabled/*.conf"' \
    "$candidate/lighttpd.conf"
grep -Eq \
    '^[[:space:]]*server\.bind[[:space:]]*=[[:space:]]*"127\.0\.0\.1"' \
    "$candidate/lighttpd.conf"
grep -Eq \
    '^[[:space:]]*server\.port[[:space:]]*=[[:space:]]*8080' \
    "$candidate/lighttpd.conf"
grep -Eq \
    '^[[:space:]]*server\.errorlog-use-syslog[[:space:]]*=[[:space:]]*"enable"' \
    "$candidate/lighttpd.conf"
accesslog_syslog_count=$(
    grep -R -Eh \
        '^[[:space:]]*accesslog\.use-syslog[[:space:]]*=[[:space:]]*"enable"' \
        "$candidate/lighttpd.conf" "$candidate/conf-enabled" |
        wc -l
)
[[ "$accesslog_syslog_count" -ge 1 ]]
if grep -R -qE \
    '/dev/(stderr|stdout)|^[[:space:]]*accesslog\.filename[[:space:]]*:?[+]?=|ssl\.engine[[:space:]]*=[[:space:]]*"enable"|:443' \
    "$candidate/lighttpd.conf" "$candidate/conf-enabled"; then
    printf 'Candidate contains a forbidden logging or HTTPS directive.\n' >&2
    exit 1
fi

diff -qr --exclude=lighttpd.conf "$failed_retry" "$candidate"
normalized_main_sha256=$(
    sed \
        's|/etc/[.]lighttpd-caddy-action15-retry2/|/etc/.lighttpd-caddy-action15-retry/|g' \
        "$candidate/lighttpd.conf" |
        sha256sum |
        awk '{print $1}'
)
[[ "$normalized_main_sha256" == "$failed_retry_main_sha256" ]]
lighttpd -tt -f "$candidate/lighttpd.conf"

[[ "$(tree_hash "$live")" == "$live_tree_sha256" ]]
[[ "$(tree_hash "$failed_retry")" == "$failed_retry_tree_sha256" ]]
[[ "$(tree_hash "$historical_failed")" == "$historical_failed_tree_sha256" ]]
[[ "$(tree_hash /etc/keepalived)" == "$keepalived_tree_sha256" ]]
[[ "$(service_snapshot)" == "$services_before" ]]
[[ "$(listener_snapshot)" == "$listeners_before" ]]

printf 'candidate_main_sha256=%s\n' \
    "$(sha256sum "$candidate/lighttpd.conf" | awk '{print $1}')"
printf 'candidate_tree_sha256=%s\n' "$(tree_hash "$candidate")"
printf 'normalized_candidate_main_sha256=%s\n' "$normalized_main_sha256"
printf 'action_15_retry2_stage_complete=true\n'
success=true
