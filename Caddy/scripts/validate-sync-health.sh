#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly service=caddy-lsyncd.service
readonly status_file=/run/caddy-lsyncd/status
readonly maximum_status_bytes=1048576
readonly maximum_status_lines=8192

status_snapshot_valid() {
    local sync_health_snapshot=$1

    [[ -f "$sync_health_snapshot" &&
        ! -L "$sync_health_snapshot" &&
        -s "$sync_health_snapshot" ]] || return 1
    [[ "$(wc -c <"$sync_health_snapshot")" -le "$maximum_status_bytes" ]] || return 1
    [[ "$(awk 'END { print NR }' "$sync_health_snapshot")" -le "$maximum_status_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$sync_health_snapshot" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$sync_health_snapshot" >/dev/null || return 1
    grep -Eq '^Lsyncd status report at .+$' "$sync_health_snapshot" || return 1
    grep -Eq '^Sync[0-9]+ source=.+$' "$sync_health_snapshot"
}

service_property() {
    local sync_health_property=$1

    systemctl show "$service" -p "$sync_health_property" --value
}

validate_service() {
    local sync_health_main_pid
    local sync_health_restarts

    systemctl is-active --quiet "$service" || return 1
    [[ "$(service_property LoadState)" = loaded ]] || return 1
    [[ "$(service_property ActiveState)" = active ]] || return 1
    [[ "$(service_property SubState)" = running ]] || return 1
    [[ "$(service_property Result)" = success ]] || return 1
    sync_health_main_pid=$(service_property MainPID) || return 1
    sync_health_restarts=$(service_property NRestarts) || return 1
    [[ "$sync_health_main_pid" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ "$sync_health_restarts" =~ ^[0-9]+$ ]] || return 1
    printf 'caddy_sync_health_main_pid=%s\n' "$sync_health_main_pid"
    printf 'caddy_sync_health_nrestarts=%s\n' "$sync_health_restarts"
}

run_health_check() {
    if ! validate_service; then
        printf '%s is not active and stable\n' "$service" >&2
        return 1
    fi
    if ! status_snapshot_valid "$status_file"; then
        printf 'lsyncd status snapshot is missing, unsafe, or malformed: %s\n' \
            "$status_file" >&2
        return 1
    fi
    printf 'caddy_sync_health_status_snapshot_valid=true\n'
    printf 'caddy_sync_health_complete=true\n'
}

case "${1:-}" in
    '') run_health_check ;;
    --validate-status-file) [[ $# -eq 2 ]] && status_snapshot_valid "$2" ;;
    *) exit 64 ;;
esac
