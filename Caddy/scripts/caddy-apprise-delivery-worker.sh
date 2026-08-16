#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly schema='caddy-apprise-queue/v1'
readonly endpoint='http://10.1.3.83:8000/notify/apprise'
queue_root='/var/lib/caddy-apprise-queue'
runtime_root='/run/caddy-apprise'
if [[ "${CADDY_APPRISE_TEST_MODE:-}" = 1 ]]; then
    queue_root=${CADDY_APPRISE_QUEUE_ROOT:-$queue_root}
    runtime_root=${CADDY_APPRISE_RUNTIME_ROOT:-$runtime_root}
fi
readonly queue_root runtime_root
readonly maximum_record_bytes=8192
readonly maximum_attempts=8
readonly maximum_backoff_seconds=3600

curl_binary=/usr/bin/curl
event_allowlist=
if [[ "${CADDY_APPRISE_TEST_MODE:-}" = 1 ]]; then
    curl_binary=${CADDY_APPRISE_CURL:-$curl_binary}
    event_allowlist=${CADDY_APPRISE_EVENT_ALLOWLIST:-}
fi
readonly event_allowlist
[[ "$curl_binary" = /* && -f "$curl_binary" && ! -L "$curl_binary" && -x "$curl_binary" ]] || exit 70
if [[ -n "$event_allowlist" ]]; then
    [[ "$event_allowlist" = /* && -f "$event_allowlist" && ! -L "$event_allowlist" ]] || exit 70
    [[ "$(stat -c '%a' "$event_allowlist")" = 600 ]] || exit 70
    awk 'NF != 1 || length($1) != 69 || $1 !~ /^[0-9a-f]+[.]json$/ { invalid=1 } END { exit(invalid || NR == 0 ? 1 : 0) }' \
        "$event_allowlist" || exit 70
fi

log_transition() {
    if [[ "${CADDY_APPRISE_TEST_MODE:-}" = 1 && -n "${CADDY_APPRISE_LOG_FILE:-}" ]]; then
        printf '%s\n' "$*" >>"$CADDY_APPRISE_LOG_FILE"
    else
        logger -t caddy-apprise-worker -- "$*"
    fi
}

valid_record() {
    local worker_record=$1
    local worker_basename=${worker_record##*/}
    local worker_mode

    [[ "$worker_basename" =~ ^[0-9a-f]{64}\.json$ ]] || return 1
    [[ -f "$worker_record" && ! -L "$worker_record" ]] || return 1
    worker_mode=$(stat -c '%a' "$worker_record") || return 1
    [[ "$worker_mode" = 600 ]] || return 1
    [[ "$(wc -c <"$worker_record")" -le "$maximum_record_bytes" ]] || return 1
    jq -e --arg schema "$schema" --arg id "${worker_basename%.json}" '
      type == "object" and keys == ["created_at","created_epoch","event_id","host","payload","retry","schema","severity","source"] and
      .schema == $schema and .event_id == $id and
      (.source | test("^(caddy-sync|keepalived|pihole-web)$")) and
      (.host | type == "string" and test("^[A-Za-z0-9.-]{1,253}$")) and
      (.severity | test("^(info|success|warning|failure)$")) and
      (.created_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
      (.created_epoch | type == "number" and floor == . and . >= 0) and
      (.retry | keys == ["attempt","next_attempt_epoch"]) and
      (.retry.attempt | type == "number" and floor == . and . >= 0) and
      (.retry.next_attempt_epoch | type == "number" and floor == . and . >= 0) and
      (.payload | keys == ["body","format","title","type"]) and
      (.payload.title | type == "string" and length > 0 and length <= 256) and
      (.payload.body | type == "string" and length > 0 and length <= 2048) and
      .payload.type == .severity and .payload.format == "text" and
      ([.payload.title,.payload.body] | all(test("[[:cntrl:]]") | not)) and
      ([.payload.title,.payload.body] | all(test("BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD|(^|[^[:alnum:]_])(password|passwd|token|secret|api[_-]?key)[[:space:]]*[:=]"; "i") | not))
    ' "$worker_record" >/dev/null
}

atomic_rewrite_retry() {
    local worker_record=$1
    local worker_attempt=$2
    local worker_next=$3
    local worker_temporary

    worker_temporary=$(mktemp "$queue_root/inflight/.retry.XXXXXX") || return 1
    chmod 0600 "$worker_temporary" || {
        rm -f -- "$worker_temporary"
        return 1
    }
    jq --argjson attempt "$worker_attempt" --argjson next "$worker_next" \
        '.retry.attempt = $attempt | .retry.next_attempt_epoch = $next' \
        "$worker_record" >"$worker_temporary" || {
        rm -f -- "$worker_temporary"
        return 1
    }
    mv -f -- "$worker_temporary" "$worker_record"
}

for worker_directory in "$queue_root/pending" "$queue_root/inflight" \
    "$queue_root/dead-letter" "$queue_root/delivered" "$runtime_root"; do
    [[ -d "$worker_directory" && ! -L "$worker_directory" ]] || exit 73
done

exec 9>"$runtime_root/worker.lock"
flock -n 9 || exit 0

# Any inflight record predates this lock holder. Requeue it. A crash after the
# HTTP peer accepted a request but before the receipt was committed can cause
# one retry; the stable event ID is also sent as Idempotency-Key.
shopt -s nullglob
for inflight_record in "$queue_root/inflight/"*.json; do
    inflight_name=${inflight_record##*/}
    inflight_name_sha256=$(printf '%s' "$inflight_name" | sha256sum | awk '{ print $1 }')
    if [[ -f "$queue_root/delivered/$inflight_name" ]]; then
        rm -f -- "$inflight_record"
        log_transition "event=receipt-reconciled event_id=${inflight_name%.json}"
    elif valid_record "$inflight_record"; then
        mv -f -- "$inflight_record" "$queue_root/pending/$inflight_name"
        log_transition "event=crash-requeued event_id=${inflight_name%.json}"
    else
        rm -f -- "$inflight_record"
        log_transition "event=unsafe-inflight-discarded record_name_sha256=$inflight_name_sha256"
    fi
done

now=$(date +%s)
inventory=$runtime_root/eligible.$$
trap 'rm -f -- "$inventory" "$runtime_root/response.$$"' EXIT
: >"$inventory"
chmod 0600 "$inventory"
for pending_record in "$queue_root/pending/"*.json; do
    pending_name=${pending_record##*/}
    pending_name_sha256=$(printf '%s' "$pending_name" | sha256sum | awk '{ print $1 }')
    if [[ -n "$event_allowlist" ]] && ! grep -Fxq -- "$pending_name" "$event_allowlist"; then
        continue
    fi
    if [[ -e "$queue_root/delivered/$pending_name" || -L "$queue_root/delivered/$pending_name" ]]; then
        [[ -f "$queue_root/delivered/$pending_name" && ! -L "$queue_root/delivered/$pending_name" ]] || exit 75
        rm -f -- "$pending_record"
        log_transition "event=receipt-reconciled event_id=${pending_name%.json}"
        continue
    fi
    if ! valid_record "$pending_record"; then
        if [[ -f "$pending_record" && ! -L "$pending_record" ]]; then
            mv -f -- "$pending_record" "$queue_root/dead-letter/$pending_name"
            log_transition "event=dead-lettered reason=malformed record_name_sha256=$pending_name_sha256"
        else
            rm -f -- "$pending_record"
            log_transition "event=unsafe-record-discarded record_name_sha256=$pending_name_sha256"
        fi
        continue
    fi
    next_attempt=$(jq -r '.retry.next_attempt_epoch' "$pending_record")
    created_epoch=$(jq -r '.created_epoch' "$pending_record")
    if ((next_attempt <= now)); then
        printf '%020d\t%s\n' "$created_epoch" "$pending_record" >>"$inventory"
    fi
done

sort -n -k1,1 "$inventory" -o "$inventory"
while IFS=$'\t' read -r _ pending_record; do
    [[ -n "$pending_record" ]] || continue
    pending_name=${pending_record##*/}
    event_id=${pending_name%.json}
    inflight_record=$queue_root/inflight/$pending_name
    [[ ! -e "$inflight_record" ]] || exit 74
    mv -- "$pending_record" "$inflight_record"
    payload=$(jq -c '.payload' "$inflight_record") || exit 1
    attempt=$(jq -r '.retry.attempt' "$inflight_record") || exit 1
    response_path=$runtime_root/response.$$
    : >"$response_path"
    chmod 0600 "$response_path"
    log_transition "event=attempt event_id=$event_id attempt=$((attempt + 1))"
    curl_status=0
    "$curl_binary" --silent --show-error --fail-with-body \
        --connect-timeout 2 --max-time 5 --max-filesize "$maximum_record_bytes" --request POST \
        --header 'Content-Type: application/json' \
        --header "Idempotency-Key: $event_id" \
        --data "$payload" "$endpoint" \
        >"$response_path" 2>&1 || curl_status=$?
    response_bytes=$(wc -c <"$response_path")
    if [[ "$curl_status" -eq 0 ]]; then
        receipt_temporary=$(mktemp "$queue_root/delivered/.receipt.XXXXXX") || exit 1
        chmod 0600 "$receipt_temporary" || exit 1
        jq -n --arg event_id "$event_id" --arg delivered_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{event_id: $event_id, delivered_at: $delivered_at}' >"$receipt_temporary" || exit 1
        mv -f -- "$receipt_temporary" "$queue_root/delivered/$pending_name"
        rm -f -- "$inflight_record"
        log_transition "event=delivered event_id=$event_id attempt=$((attempt + 1)) response_class=accepted response_bytes=$response_bytes"
        continue
    fi

    attempt=$((attempt + 1))
    if ((attempt >= maximum_attempts)); then
        atomic_rewrite_retry "$inflight_record" "$attempt" "$now" || exit 1
        mv -f -- "$inflight_record" "$queue_root/dead-letter/$pending_name"
        log_transition "event=dead-lettered event_id=$event_id reason=max-attempts attempts=$attempt response_class=transport-failure response_bytes=$response_bytes"
        continue
    fi
    backoff=$((15 * (1 << (attempt - 1))))
    ((backoff > maximum_backoff_seconds)) && backoff=$maximum_backoff_seconds
    jitter=$((16#${event_id:0:2} % 11))
    next_attempt=$((now + backoff + jitter))
    atomic_rewrite_retry "$inflight_record" "$attempt" "$next_attempt" || exit 1
    mv -f -- "$inflight_record" "$queue_root/pending/$pending_name"
    log_transition "event=retry-scheduled event_id=$event_id attempt=$attempt next_attempt_epoch=$next_attempt response_class=transport-failure response_bytes=$response_bytes"
done <"$inventory"

exit 0
