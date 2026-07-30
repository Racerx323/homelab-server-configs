#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly source_root=/etc/caddy/current
readonly correction_relative=conf.d/91-exact-listener-default-deny.caddy

work_dir=$(mktemp -d /tmp/caddy-action16ar-reload.XXXXXX)
readonly work_dir
readonly baseline="$work_dir/bootstrap"
readonly candidate="$work_dir/candidate"
readonly current="$work_dir/current"
readonly temporary_link="$work_dir/current.new"
readonly caddy_log="$work_dir/caddy.log"
caddy_pid=

cleanup() {
    local status=$?

    trap - EXIT
    if [[ -n "$caddy_pid" ]] &&
        kill -0 "$caddy_pid" >/dev/null 2>&1; then
        kill -TERM "$caddy_pid"
        wait "$caddy_pid" || true
    fi
    rm -rf -- "$work_dir"
    exit "$status"
}
trap cleanup EXIT

probe_code() {
    local fqdn=$1
    local address=$2

    curl --noproxy '*' --insecure --silent --show-error \
        --connect-timeout 1 --max-time 2 \
        --resolve "$fqdn:443:$address" \
        --output /dev/null --write-out '%{http_code}' \
        "https://$fqdn/" 2>/dev/null
}

listener_snapshot_raw() {
    ss -H -lntup 2>/dev/null |
        awk '$5 ~ /:(80|443|8080|2019)$/ { print }' |
        sort
}

listener_snapshot_semantic() {
    ss -H -lntup 2>/dev/null |
        awk '$5 ~ /:(80|443|8080|2019)$/ {
            process = "none"
            if (match($0, /users:\(\("[^"]+"/)) {
                process = substr($0, RSTART + 9, RLENGTH - 10)
            }
            print $1 "|" $2 "|" $5 "|" process
        }' |
        sort
}

wait_for_code() {
    local fqdn=$1
    local address=$2
    local expected=$3
    local attempt

    for ((attempt = 0; attempt < 100; attempt++)); do
        if [[ "$(probe_code "$fqdn" "$address" || true)" == "$expected" ]]; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

select_release() {
    local release=$1

    ln -s "$release" "$temporary_link"
    mv -Tf -- "$temporary_link" "$current"
}

[[ -L "$source_root" ]]
[[ -f "$source_root/$correction_relative" ]]
cp -a --dereference -- "$source_root" "$baseline"
cp -a --dereference -- "$source_root" "$candidate"
rm -f -- "$baseline/$correction_relative"
ln -s "$baseline" "$current"

export CADDY_CONFIG_ROOT="$current"
export NODE_FQDN=pihole0.local.theama.co
export NODE_IPV4=10.1.0.53
export NODE_IPV6=fd36:5aa8:6971:1::53

caddy validate --config "$current/Caddyfile" --adapter caddyfile >/dev/null
caddy run --config "$current/Caddyfile" --adapter caddyfile \
    >"$caddy_log" 2>&1 &
caddy_pid=$!
wait_for_code localhost 127.0.0.1 204
wait_for_code unexpected.local.theama.co 10.1.0.53 200
readonly pid_before=$caddy_pid
raw_before=$(listener_snapshot_raw)
semantic_before=$(listener_snapshot_semantic)

select_release "$candidate"
caddy reload --config "$current/Caddyfile" --adapter caddyfile --force
wait_for_code localhost 127.0.0.1 204
wait_for_code unexpected.local.theama.co 10.1.0.53 421
[[ "$caddy_pid" == "$pid_before" ]]
raw_candidate=$(listener_snapshot_raw)
semantic_candidate=$(listener_snapshot_semantic)

select_release "$baseline"
caddy reload --config "$current/Caddyfile" --adapter caddyfile --force
wait_for_code localhost 127.0.0.1 204
wait_for_code unexpected.local.theama.co 10.1.0.53 200
[[ "$caddy_pid" == "$pid_before" ]]
raw_restored=$(listener_snapshot_raw)
semantic_restored=$(listener_snapshot_semantic)

printf 'baseline_unknown_code=200\n'
printf 'candidate_unknown_code=421\n'
printf 'restored_unknown_code=200\n'
printf 'caddy_pid_preserved=true\n'
printf 'raw_listener_candidate_equal=%s\n' \
    "$([[ "$raw_candidate" == "$raw_before" ]] && printf true || printf false)"
printf 'raw_listener_restored_equal=%s\n' \
    "$([[ "$raw_restored" == "$raw_before" ]] && printf true || printf false)"
printf 'semantic_listener_candidate_equal=%s\n' \
    "$([[ "$semantic_candidate" == "$semantic_before" ]] && printf true || printf false)"
printf 'semantic_listener_restored_equal=%s\n' \
    "$([[ "$semantic_restored" == "$semantic_before" ]] && printf true || printf false)"
[[ "$semantic_candidate" == "$semantic_before" ]]
[[ "$semantic_restored" == "$semantic_before" ]]
printf 'action_16ar_reload_regression_complete=true\n'
