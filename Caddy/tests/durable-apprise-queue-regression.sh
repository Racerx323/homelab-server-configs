#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=durable_apprise_queue_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly enqueue=$caddy_root/scripts/caddy-apprise-enqueue.sh
readonly worker=$caddy_root/scripts/caddy-apprise-delivery-worker.sh
readonly keepalived_producer=$repository_root/../homelab-dns/Keepalived/scripts/keepalived-notify.sh
readonly transaction=$caddy_root/scripts/apply-durable-apprise-action34.sh
readonly outer=$caddy_root/scripts/run-dual-node-durable-apprise-action34-outer.sh

fixture_root=$(mktemp -d /tmp/caddy-apprise-regression.XXXXXX)
readonly fixture_root
trap 'rm -rf -- "$fixture_root"' EXIT
readonly queue_root=$fixture_root/queue
readonly runtime_root=$fixture_root/run
readonly log_file=$fixture_root/journal.log
readonly call_file=$fixture_root/calls.log
readonly mock_state=$fixture_root/mock.state
mkdir -p "$queue_root"/{pending,inflight,dead-letter,delivered} "$runtime_root"
chmod 0700 "$queue_root" "$queue_root"/{pending,inflight,dead-letter,delivered} "$runtime_root"
install -m 0600 /dev/null "$log_file"
install -m 0600 /dev/null "$call_file"
printf 'success\n' >"$mock_state"
chmod 0600 "$mock_state"

mock_curl=$fixture_root/mock-curl
cat >"$mock_curl" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$CADDY_APPRISE_CALL_FILE"
state=$(sed -n '1p' "$CADDY_APPRISE_MOCK_STATE")
sed '1d' "$CADDY_APPRISE_MOCK_STATE" >"$CADDY_APPRISE_MOCK_STATE.next"
mv "$CADDY_APPRISE_MOCK_STATE.next" "$CADDY_APPRISE_MOCK_STATE"
if [ "$state" = fail ]; then
    printf 'bounded failure\n' >&2
    exit 28
fi
printf 'accepted\n'
MOCK
chmod 0755 "$mock_curl"

export CADDY_APPRISE_TEST_MODE=1
export CADDY_APPRISE_QUEUE_ROOT=$queue_root
export CADDY_APPRISE_RUNTIME_ROOT=$runtime_root
export CADDY_APPRISE_LOG_FILE=$log_file
export CADDY_APPRISE_CURL=$mock_curl
export CADDY_APPRISE_CALL_FILE=$call_file
export CADDY_APPRISE_MOCK_STATE=$mock_state

fail() {
    printf '%s_failure=%s\n' "$prefix" "$1" >&2
    exit 1
}

enqueue_record() {
    local regression_key=$1
    "$enqueue" --source caddy-sync --severity failure \
        --event-key "$regression_key" --title "Test $regression_key" \
        --body "Bounded regression body $regression_key"
}

count_records() {
    local regression_directory=$1
    find "$regression_directory" -maxdepth 1 -type f -name '*.json' -printf x | wc -c
}

enqueue_record schema-one
first_record=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' -print -quit)
[[ -n "$first_record" && ! -L "$first_record" ]] || fail atomic_record
[[ "$(stat -c '%a' "$first_record")" = 600 ]] || fail record_mode
jq -e '
  .schema == "caddy-apprise-queue/v1" and
  (.event_id | test("^[0-9a-f]{64}$")) and
  .source == "caddy-sync" and .severity == "failure" and
  .retry.attempt == 0 and .payload.format == "text"
' "$first_record" >/dev/null || fail schema
[[ -z "$(find "$queue_root/pending" -maxdepth 1 -type f -name '.enqueue.*' -print -quit)" ]] || fail atomic_cleanup

before_dedupe=$(count_records "$queue_root/pending")
enqueue_record schema-one
[[ "$(count_records "$queue_root/pending")" -eq "$before_dedupe" ]] || fail dedupe
grep -Fq 'event=deduplicated' "$log_file" || fail dedupe_journal

dedupe_inflight=$queue_root/inflight/${first_record##*/}
mv "$first_record" "$dedupe_inflight"
enqueue_record schema-one
[[ ! -e "$first_record" ]] || fail inflight_dedupe
mv "$dedupe_inflight" "$first_record"

if "$enqueue" --source keepalived --severity warning --event-key bad-control \
    --title 'bad' --body $'bad\ncontrol'; then
    fail control_character_acceptance
fi
if "$enqueue" --source keepalived --severity warning --event-key bad-secret \
    --title 'bad' --body 'token=do-not-store'; then
    fail secret_acceptance
fi

sleep 1
enqueue_record schema-two
printf 'success\nsuccess\n' >"$mock_state"
"$worker"
[[ "$(count_records "$queue_root/pending")" -eq 0 ]] || fail delivery_pending
[[ "$(count_records "$queue_root/delivered")" -eq 2 ]] || fail delivery_receipts
[[ "$(wc -l <"$call_file")" -eq 2 ]] || fail oldest_first_call_count
first_id=${first_record##*/}
grep -Fq "Idempotency-Key: ${first_id%.json}" "$call_file" || fail idempotency_header

receipt_duplicate=$queue_root/pending/$first_id
cp "$queue_root/delivered/$first_id" "$receipt_duplicate"
chmod 0600 "$receipt_duplicate"
calls_before_receipt=$(wc -l <"$call_file")
"$worker"
[[ ! -e "$receipt_duplicate" ]] || fail receipt_reconciliation
[[ "$(wc -l <"$call_file")" -eq "$calls_before_receipt" ]] || fail receipt_duplicate_delivery

enqueue_record retry-case
printf 'fail\n' >"$mock_state"
"$worker"
retry_record=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' -print -quit)
[[ "$(jq -r '.retry.attempt' "$retry_record")" -eq 1 ]] || fail retry_attempt
now=$(date +%s)
next=$(jq -r '.retry.next_attempt_epoch' "$retry_record")
((next >= now + 15 && next <= now + 25)) || fail bounded_backoff
retry_tmp=$queue_root/pending/.test-retry
jq --argjson now "$now" '.retry.next_attempt_epoch = $now' "$retry_record" >"$retry_tmp"
chmod 0600 "$retry_tmp"
mv -f "$retry_tmp" "$retry_record"
printf 'success\n' >"$mock_state"
"$worker"
[[ "$(count_records "$queue_root/pending")" -eq 0 ]] || fail retry_delivery

enqueue_record allowlisted-case
allowlisted_record=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' -print -quit)
enqueue_record preserved-case
allowlist=$fixture_root/controlled-records
printf '%s\n' "${allowlisted_record##*/}" >"$allowlist"
chmod 0600 "$allowlist"
printf 'success\n' >"$mock_state"
CADDY_APPRISE_EVENT_ALLOWLIST=$allowlist "$worker"
[[ ! -e "$allowlisted_record" ]] || fail allowlisted_delivery
[[ "$(count_records "$queue_root/pending")" -eq 1 ]] || fail unrelated_record_preservation
printf '../unsafe.json\n' >"$allowlist"
if CADDY_APPRISE_EVENT_ALLOWLIST=$allowlist "$worker"; then
    fail malformed_allowlist_acceptance
fi
printf 'success\n' >"$mock_state"
"$worker"

enqueue_record reboot-case
reboot_record=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' -print -quit)
mv "$reboot_record" "$queue_root/inflight/${reboot_record##*/}"
printf 'success\n' >"$mock_state"
"$worker"
grep -Fq 'event=crash-requeued' "$log_file" || fail reboot_requeue

malformed=$queue_root/pending/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.json
printf '{}\n' >"$malformed"
chmod 0600 "$malformed"
printf 'success\n' >"$mock_state"
"$worker"
[[ -f "$queue_root/dead-letter/${malformed##*/}" ]] || fail malformed_dead_letter

enqueue_record maximum-attempts
maximum_record=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' -print -quit)
maximum_tmp=$queue_root/pending/.test-maximum
jq --argjson now "$(date +%s)" '.retry.attempt = 7 | .retry.next_attempt_epoch = $now' \
    "$maximum_record" >"$maximum_tmp"
chmod 0600 "$maximum_tmp"
mv -f "$maximum_tmp" "$maximum_record"
printf 'fail\n' >"$mock_state"
"$worker"
[[ -f "$queue_root/dead-letter/${maximum_record##*/}" ]] || fail maximum_dead_letter
maximum_dead_name=${maximum_record##*/}
maximum_dead_key=maximum-attempts
records_before_dead_dedupe=$(count_records "$queue_root/pending")
enqueue_record "$maximum_dead_key"
[[ "$(count_records "$queue_root/pending")" -eq "$records_before_dead_dedupe" ]] || fail dead_letter_dedupe
[[ -f "$queue_root/dead-letter/$maximum_dead_name" ]] || fail dead_letter_preservation

enqueue_record locked-case
calls_before_lock=$(wc -l <"$call_file")
exec 8>"$runtime_root/worker.lock"
flock -n 8 || fail test_lock
printf 'success\n' >"$mock_state"
"$worker"
[[ "$(wc -l <"$call_file")" -eq "$calls_before_lock" ]] || fail concurrent_delivery
flock -u 8
exec 8>&-
"$worker"

grep -Fq "readonly endpoint='http://10.1.3.83:8000/notify/apprise'" "$worker" || fail endpoint_ip
grep -Fq 'flock -n 9' "$worker" || fail worker_lock
grep -Fq 'Idempotency-Key:' "$worker" || fail idempotency_contract
grep -Fq 'CADDY_APPRISE_EVENT_ALLOWLIST' "$worker" || fail controlled_allowlist_contract
grep -Fq 'Persistent=true' "$caddy_root/systemd/caddy-apprise-worker.timer" || fail persistent_timer
grep -Fq 'PathChanged=/var/lib/caddy-apprise-queue/pending' \
    "$caddy_root/systemd/caddy-apprise-worker.path" || fail path_activation
grep -Fq 'ProtectSystem=strict' "$caddy_root/systemd/caddy-apprise-worker.service" || fail hardening
if [[ -f "$keepalived_producer" ]]; then
    if grep -Eq '\bcurl\b|APPRISE_(URL|KEY|ENDPOINT)' "$keepalived_producer"; then
        fail keepalived_direct_transport
    fi
    grep -Fq '/usr/local/libexec/caddy-apprise-enqueue' "$keepalived_producer" || fail keepalived_enqueue
else
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || fail keepalived_producer_missing
fi
if grep -Eq '\bcurl\b' "$caddy_root/scripts/lsyncd-sync-failure-notify.sh"; then
    fail caddy_direct_transport
fi
grep -Fq 'journalctl --after-cursor' "$transaction" || fail cursor_journal
grep -Fq 'systemctl stop caddy-apprise-worker.path caddy-apprise-worker.timer' \
    "$transaction" || fail bounded_producer_capture
grep -Fq 'CADDY_APPRISE_EVENT_ALLOWLIST=' "$transaction" || fail controlled_retry
grep -Fq 'manual_intervention_required=true' "$transaction" || fail status_125_boundary
grep -Fq 'verify_runtime_baseline' "$transaction" || fail action32g_baseline
grep -Fq 'node_a_started=true' "$outer" || fail node_a_attempted_rollback
grep -Fq 'node_b_started=true' "$outer" || fail node_b_attempted_rollback
grep -Fq "return \"\$action34_outer_status\"" "$outer" || fail remote_status_preservation
printf -v streamed_remote_boundary '%s%s' 'cd / && sudo -n /bin/bash ' '-s --'
readonly streamed_remote_boundary
grep -Fq "$streamed_remote_boundary" "$outer" || fail remote_cwd
grep -Fq 'ssh-local-evidence-contract-v1' "$outer" || fail workstation_evidence

printf '%s_check_schema=true\n' "$prefix"
printf '%s_check_atomic_enqueue=true\n' "$prefix"
printf '%s_check_ordering=true\n' "$prefix"
printf '%s_check_retry_backoff=true\n' "$prefix"
printf '%s_check_deduplication=true\n' "$prefix"
printf '%s_check_reboot_recovery=true\n' "$prefix"
printf '%s_check_concurrency_lock=true\n' "$prefix"
printf '%s_check_controlled_record_isolation=true\n' "$prefix"
printf '%s_check_malformed_dead_letter=true\n' "$prefix"
printf '%s_check_permissions=true\n' "$prefix"
printf '%s_check_systemd_hardening=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
