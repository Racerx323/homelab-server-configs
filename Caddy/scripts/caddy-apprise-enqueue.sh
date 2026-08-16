#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly schema='caddy-apprise-queue/v1'
queue_root='/var/lib/caddy-apprise-queue'
if [[ "${CADDY_APPRISE_TEST_MODE:-}" = 1 ]]; then
    queue_root=${CADDY_APPRISE_QUEUE_ROOT:-$queue_root}
fi
readonly queue_root
readonly maximum_record_bytes=8192
readonly dedupe_window_seconds=300
readonly event_key_pattern='^[-A-Za-z0-9._:@/+ ]{1,256}$'
readonly stable_id_pattern='^[-A-Za-z0-9._:@+]{1,128}$'

source_name=
severity=
event_key=
title=
body=
stable_id=

queue_log() {
    if [[ "${CADDY_APPRISE_TEST_MODE:-}" = 1 && -n "${CADDY_APPRISE_LOG_FILE:-}" ]]; then
        printf '%s\n' "$*" >>"$CADDY_APPRISE_LOG_FILE"
    else
        logger -t caddy-apprise-queue -- "$*"
    fi
}

usage() {
    printf 'Usage: %s --source caddy-sync|keepalived|pihole-web --severity info|success|warning|failure --event-key KEY [--stable-id ID] --title TITLE --body BODY\n' "${0##*/}" >&2
}

while (($#)); do
    case "$1" in
        --source)
            source_name=${2:-}
            shift 2
            ;;
        --severity)
            severity=${2:-}
            shift 2
            ;;
        --event-key)
            event_key=${2:-}
            shift 2
            ;;
        --title)
            title=${2:-}
            shift 2
            ;;
        --body)
            body=${2:-}
            shift 2
            ;;
        --stable-id)
            stable_id=${2:-}
            shift 2
            ;;
        *)
            usage
            exit 64
            ;;
    esac
done

safe_text() {
    local enqueue_text=$1
    local enqueue_maximum=$2

    [[ -n "$enqueue_text" && ${#enqueue_text} -le "$enqueue_maximum" ]] || return 1
    printf '%s' "$enqueue_text" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || return 1
    jq -en --arg value "$enqueue_text" '$value | test("[[:cntrl:]]") | not' >/dev/null || return 1
    ! printf '%s' "$enqueue_text" | grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD|(^|[^[:alnum:]_])(password|passwd|token|secret|api[_-]?key)[[:space:]]*[:=]'
}

[[ "$source_name" =~ ^(caddy-sync|keepalived|pihole-web)$ ]] || exit 65
[[ "$severity" =~ ^(info|success|warning|failure)$ ]] || exit 65
[[ "$event_key" =~ $event_key_pattern ]] || exit 65
[[ -z "$stable_id" || "$stable_id" =~ $stable_id_pattern ]] || exit 65
safe_text "$title" 256 || exit 65
safe_text "$body" 2048 || exit 65

for enqueue_directory in "$queue_root" "$queue_root/pending" \
    "$queue_root/inflight" "$queue_root/dead-letter" "$queue_root/delivered"; do
    [[ -d "$enqueue_directory" && ! -L "$enqueue_directory" ]] || exit 73
    [[ "$(stat -c '%a' "$enqueue_directory")" = 700 ]] || exit 73
done

hostname_value=$(hostname -f 2>/dev/null || hostname) || exit 1
[[ "$hostname_value" =~ ^[A-Za-z0-9.-]{1,253}$ ]] || exit 65
created_epoch=$(date +%s) || exit 1
if [[ "${CADDY_APPRISE_TEST_MODE:-}" = 1 && -n "${CADDY_APPRISE_NOW_EPOCH:-}" ]]; then
    [[ "$CADDY_APPRISE_NOW_EPOCH" =~ ^[0-9]+$ ]] || exit 65
    created_epoch=$CADDY_APPRISE_NOW_EPOCH
fi
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ) || exit 1
if [[ -n "$stable_id" ]]; then
    event_identity="stable:$stable_id"
else
    dedupe_bucket=$((created_epoch / dedupe_window_seconds))
    event_identity="$event_key:$dedupe_bucket"
fi
readonly event_identity
event_id=$(printf '%s\0%s\0%s\0%s' "$schema" "$source_name" \
    "$hostname_value" "$event_identity" | sha256sum | awk '{ print $1 }') || exit 1
[[ ${#event_id} -eq 64 && "$event_id" =~ ^[0-9a-f]+$ ]] || exit 1

target=$queue_root/pending/$event_id.json
inflight=$queue_root/inflight/$event_id.json
dead_letter=$queue_root/dead-letter/$event_id.json
receipt=$queue_root/delivered/$event_id.json
if [[ -e "$target" || -e "$inflight" || -e "$dead_letter" || -e "$receipt" ]]; then
    queue_log "event=deduplicated event_id=$event_id source=$source_name"
    exit 0
fi

temporary=$(mktemp "$queue_root/pending/.enqueue.XXXXXX") || exit 1
trap 'rm -f -- "$temporary"' EXIT
chmod 0600 "$temporary" || exit 1
if [[ "${CADDY_APPRISE_TEST_MODE:-}" != 1 ]]; then
    pi_uid=$(id -u pi) || exit 77
    pi_gid=$(id -g pi) || exit 77
    case "$(id -u)" in
        0) chown "$pi_uid:$pi_gid" "$temporary" || exit 77 ;;
        "$pi_uid") : ;;
        *) exit 77 ;;
    esac
    [[ "$(stat -c '%u:%g:%a' "$temporary")" = "$pi_uid:$pi_gid:600" ]] || exit 77
fi
jq -n \
    --arg schema "$schema" \
    --arg event_id "$event_id" \
    --arg source "$source_name" \
    --arg host "$hostname_value" \
    --arg severity "$severity" \
    --arg created_at "$created_at" \
    --arg title "$title" \
    --arg body "$body" \
    --argjson created_epoch "$created_epoch" \
    '{schema: $schema, event_id: $event_id, source: $source, host: $host,
      severity: $severity, created_at: $created_at, created_epoch: $created_epoch,
      retry: {attempt: 0, next_attempt_epoch: $created_epoch},
      payload: {title: $title, body: $body, type: $severity, format: "text"}}' \
    >"$temporary" || exit 1
[[ "$(wc -c <"$temporary")" -le "$maximum_record_bytes" ]] || exit 65
jq -e --arg schema "$schema" --arg id "$event_id" \
    '.schema == $schema and .event_id == $id' "$temporary" >/dev/null || exit 65

if ln -- "$temporary" "$target" 2>/dev/null; then
    rm -f -- "$temporary"
    trap - EXIT
    queue_log "event=enqueued event_id=$event_id source=$source_name severity=$severity"
else
    [[ -e "$target" || -e "$inflight" || -e "$dead_letter" || -e "$receipt" ]] || exit 1
    queue_log "event=deduplicated event_id=$event_id source=$source_name"
fi

exit 0
