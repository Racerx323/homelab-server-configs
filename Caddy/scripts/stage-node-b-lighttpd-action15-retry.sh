#!/usr/bin/env bash
set -euo pipefail

readonly stage=/var/tmp/caddy-ha-lighttpd-node-b-action15-retry
readonly candidate=/etc/.lighttpd-caddy-action15-retry
readonly failed_candidate=/etc/.lighttpd-caddy-action15.failed
readonly renderer="$stage/scripts/prepare-lighttpd-config.sh"
readonly desired_state="$stage/configs/lighttpd/desired-state.conf"
readonly renderer_sha256=ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f
readonly desired_state_sha256=8299970d5bb3793859071cd82f794dbae84955a6af931cf35d1509141f689027
readonly live_main_sha256=568507d5604cb2794106de3de29d1603c3f12c9045bf7fc1ad4342592a1395c1
readonly failed_main_sha256=998cd47e64c615e1ae9f0ea1f3c29e711608a2b3ebfebd229b44de51ac7fada8

success=false
cleanup() {
    local status=$?

    if [[ "$success" != true ]]; then
        rm -rf -- "$candidate" "$stage"
        rm -f -- /run/lighttpd-caddy-action15-retry.pid
        printf 'action_15_retry_stage_rollback_complete=true\n' >&2
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

[[ $EUID -eq 0 ]]
[[ -d "$stage" && ! -L "$stage" ]]
[[ "$(stat -c '%U:%G:%a' "$stage")" == root:root:750 ]]
[[ ! -e "$candidate" ]]
[[ -d "$failed_candidate" && ! -L "$failed_candidate" ]]
[[ "$(sha256sum "$renderer" | awk '{print $1}')" == "$renderer_sha256" ]]
[[ "$(sha256sum "$desired_state" | awk '{print $1}')" == "$desired_state_sha256" ]]
[[ "$(sha256sum /etc/lighttpd/lighttpd.conf | awk '{print $1}')" == "$live_main_sha256" ]]
[[ "$(sha256sum "$failed_candidate/lighttpd.conf" | awk '{print $1}')" == "$failed_main_sha256" ]]

for command_name in lighttpd unshare ip ss curl sha256sum; do
    command -v "$command_name" >/dev/null
done

live_tree_before=$(tree_hash /etc/lighttpd)
failed_tree_before=$(tree_hash "$failed_candidate")
keepalived_tree_before=$(tree_hash /etc/keepalived)
listeners_before=$(listener_snapshot)
services_before=$(
    for unit in lighttpd caddy caddy-api lsyncd caddy-lsyncd keepalived; do
        printf '%s=%s/%s\n' \
            "$unit" \
            "$(systemctl is-active "$unit" 2>/dev/null || true)" \
            "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    done
)

[[ "$(systemctl is-active lighttpd)" == active ]]
[[ "$(systemctl is-enabled lighttpd)" == enabled ]]
[[ "$(systemctl is-active keepalived)" == active ]]
[[ "$(systemctl is-enabled keepalived)" == enabled ]]
[[ "$(systemctl is-active caddy 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled caddy 2>/dev/null || true)" == masked ]]
[[ "$(systemctl is-active lsyncd 2>/dev/null || true)" == inactive ]]
[[ "$(systemctl is-enabled lsyncd 2>/dev/null || true)" == masked ]]

"$renderer" --source-root /etc/lighttpd --output "$candidate"

[[ "$(stat -c '%U:%G:%a' "$candidate")" == root:root:750 ]]
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
grep -R -Eq '"mod_accesslog"' \
    "$candidate/lighttpd.conf" "$candidate/conf-enabled"
if grep -R -qE \
    '/dev/(stderr|stdout)|^[[:space:]]*accesslog\.filename[[:space:]]*:?[+]?=|ssl\.engine[[:space:]]*=[[:space:]]*"enable"|:443' \
    "$candidate/lighttpd.conf" "$candidate/conf-enabled"; then
    printf 'Candidate contains a forbidden logging or HTTPS directive.\n' >&2
    exit 1
fi

runtime_config="$stage/runtime-probe.conf"
runtime_log="$stage/runtime-probe.log"
runtime_pidfile=/run/lighttpd-caddy-action15-retry.pid
cp -- "$candidate/lighttpd.conf" "$runtime_config"
pid_count=$(
    grep -Ec '^[[:space:]]*server\.pid-file[[:space:]]*=' "$runtime_config" ||
        true
)
[[ "$pid_count" -eq 1 ]]
sed -Ei \
    "s|^[[:space:]]*server\\.pid-file[[:space:]]*=.*$|server.pid-file = \"$runtime_pidfile\"|" \
    "$runtime_config"

# The variables in this script body expand only inside the network namespace.
# shellcheck disable=SC2016
runtime_probe='
set -euo pipefail
config=$1
runtime_log=$2
runtime_pidfile=$3
lighttpd_pid=
cleanup_runtime() {
    if [[ -n "$lighttpd_pid" ]] &&
        kill -0 "$lighttpd_pid" >/dev/null 2>&1; then
        kill -TERM "$lighttpd_pid"
        wait "$lighttpd_pid" || true
    fi
    rm -f -- "$runtime_pidfile"
}
trap cleanup_runtime EXIT
ip link set lo up
lighttpd -D -f "$config" >"$runtime_log" 2>&1 &
lighttpd_pid=$!
ready=false
for ((attempt = 0; attempt < 50; attempt++)); do
    if ! kill -0 "$lighttpd_pid" >/dev/null 2>&1; then
        wait "$lighttpd_pid" || true
        lighttpd_pid=
        cat "$runtime_log" >&2
        exit 1
    fi
    if ss -H -lnt "sport = :8080" | grep -Fq "127.0.0.1:8080"; then
        ready=true
        break
    fi
    sleep 0.1
done
[[ "$ready" == true ]]
curl --silent --show-error --head --max-time 3 http://127.0.0.1:8080/ \
    >/dev/null
if grep -Fq "unknown config-key" "$runtime_log"; then
    cat "$runtime_log" >&2
    exit 1
fi
'
unshare --net -- /bin/bash -c "$runtime_probe" bash \
    "$runtime_config" "$runtime_log" "$runtime_pidfile"

[[ "$(tree_hash /etc/lighttpd)" == "$live_tree_before" ]]
[[ "$(tree_hash "$failed_candidate")" == "$failed_tree_before" ]]
[[ "$(tree_hash /etc/keepalived)" == "$keepalived_tree_before" ]]
[[ "$(listener_snapshot)" == "$listeners_before" ]]
services_after=$(
    for unit in lighttpd caddy caddy-api lsyncd caddy-lsyncd keepalived; do
        printf '%s=%s/%s\n' \
            "$unit" \
            "$(systemctl is-active "$unit" 2>/dev/null || true)" \
            "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    done
)
[[ "$services_after" == "$services_before" ]]

rm -f -- "$runtime_config" "$runtime_log"
candidate_main_sha256=$(sha256sum "$candidate/lighttpd.conf" | awk '{print $1}')
candidate_tree_sha256=$(tree_hash "$candidate")
printf 'candidate_main_sha256=%s\n' "$candidate_main_sha256"
printf 'candidate_tree_sha256=%s\n' "$candidate_tree_sha256"
printf 'live_tree_sha256=%s\n' "$live_tree_before"
printf 'failed_candidate_tree_sha256=%s\n' "$failed_tree_before"
printf 'keepalived_tree_sha256=%s\n' "$keepalived_tree_before"
printf 'action_15_retry_stage_complete=true\n'
success=true
