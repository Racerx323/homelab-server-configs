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
readonly replication_producer=$caddy_root/scripts/lsyncd-sync-failure-notify.sh

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

mock_logger=$fixture_root/mock-logger
mock_systemctl=$fixture_root/mock-systemctl
mock_hostname=$fixture_root/mock-hostname
mock_ip=$fixture_root/mock-ip
cat >"$mock_logger" <<'LOGGER'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CADDY_APPRISE_PRODUCER_LOG:?}"
LOGGER
cat >"$mock_systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
case "$1" in
    show) printf 'exit-code\n' ;;
    is-active) printf 'active\n' ;;
    *) exit 64 ;;
esac
SYSTEMCTL
cat >"$mock_hostname" <<'HOSTNAME'
#!/usr/bin/env bash
[[ "$1" = -s ]]
printf 'j1-svpihole00\n'
HOSTNAME
cat >"$mock_ip" <<'IP'
#!/usr/bin/env bash
printf '2: eth0    inet 10.1.0.54/22 scope global eth0\n'
printf '2: eth0    inet6 fd36:5aa8:6971:1::54/64 scope global\n'
IP
chmod 0755 "$mock_logger" "$mock_systemctl" "$mock_hostname" "$mock_ip"

export CADDY_APPRISE_TEST_MODE=1
export CADDY_APPRISE_QUEUE_ROOT=$queue_root
export CADDY_APPRISE_RUNTIME_ROOT=$runtime_root
export CADDY_APPRISE_LOG_FILE=$log_file
export CADDY_APPRISE_CURL=$mock_curl
export CADDY_APPRISE_CALL_FILE=$call_file
export CADDY_APPRISE_MOCK_STATE=$mock_state
export CADDY_APPRISE_PRODUCER_LOG=$fixture_root/producer.log
install -m 0600 /dev/null "$CADDY_APPRISE_PRODUCER_LOG"

fail() {
    printf '%s_failure=%s\n' "$prefix" "$1" >&2
    exit 1
}

enqueue_record() {
    local regression_key=$1
    "$enqueue" --source caddy-sync --severity failure \
        --event-key "$regression_key" \
        --application Replication \
        --component lsyncd \
        --check systemd-unit \
        --event failure \
        --state 'active -> failed' \
        --impact 'release replication stopped; serving traffic unaffected' \
        --failure-class systemd-unit-failed \
        --network-context 'not applicable' \
        --ha-context 'VIP movement: none; VRRP dependency: no' \
        --status 'unit=caddy-lsyncd.service result=exit-code' \
        --timing 'first observed: 2026-08-17T23:30:00Z' \
        --correlation "$regression_key" \
        --evidence 'journalctl -u caddy-lsyncd.service' \
        --first-check 'systemctl status caddy-lsyncd.service'
}

count_records() {
    local regression_directory=$1
    find "$regression_directory" -maxdepth 1 -type f -name '*.json' -printf x | wc -c
}

CADDY_APPRISE_NOW_EPOCH=300 enqueue_record schema-one
first_record=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' -print -quit)
[[ -n "$first_record" && ! -L "$first_record" ]] || fail atomic_record
[[ "$(stat -c '%a' "$first_record")" = 600 ]] || fail record_mode
jq -e '
  .schema == "caddy-apprise-queue/v1" and
  (.event_id | test("^[0-9a-f]{64}$")) and
  .source == "caddy-sync" and .severity == "failure" and
  .retry.attempt == 0 and .payload.format == "text" and
  (.payload.title | startswith("🚨 [Replication] failure on ")) and
  (.payload.body | contains("Application: Replication") and
    contains("Component: lsyncd") and
    contains("Check: systemd-unit") and
    contains("Failure class: systemd-unit-failed") and
    contains("First check: systemctl status caddy-lsyncd.service"))
' "$first_record" >/dev/null || fail schema
[[ -z "$(find "$queue_root/pending" -maxdepth 1 -type f -name '.enqueue.*' -print -quit)" ]] || fail atomic_cleanup

before_dedupe=$(count_records "$queue_root/pending")
CADDY_APPRISE_NOW_EPOCH=300 enqueue_record schema-one
[[ "$(count_records "$queue_root/pending")" -eq "$before_dedupe" ]] || fail dedupe
grep -Fq 'event=deduplicated' "$log_file" || fail dedupe_journal

dedupe_inflight=$queue_root/inflight/${first_record##*/}
mv "$first_record" "$dedupe_inflight"
CADDY_APPRISE_NOW_EPOCH=300 enqueue_record schema-one
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

CADDY_APPRISE_NOW_EPOCH=300 "$enqueue" --source pihole-web \
    --severity failure --event-key backend-failed \
    --stable-id episode-1-failed --title 'Pi-hole backend failed' \
    --body 'Bounded backend failure'
stable_record=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' \
    -print0 | while IFS= read -r -d '' queue_candidate; do
    if jq -e '.source == "pihole-web"' "$queue_candidate" >/dev/null; then
        printf '%s\n' "$queue_candidate"
    fi
done)
[[ -n "$stable_record" ]] || fail stable_transition_record_absent
CADDY_APPRISE_NOW_EPOCH=900 "$enqueue" --source pihole-web \
    --severity failure --event-key backend-failed \
    --stable-id episode-1-failed --title 'Pi-hole backend failed' \
    --body 'Bounded backend failure'
[[ "$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' \
    -exec jq -r 'if .source == "pihole-web" then input_filename else empty end' {} + | wc -l)" -eq 1 ]] || fail stable_transition_dedupe
[[ -f "$stable_record" ]] || fail stable_transition_identity_changed
if "$enqueue" --source pihole-web --severity failure \
    --event-key backend-failed --stable-id '../unsafe' \
    --title 'bad' --body 'bad'; then
    fail unsafe_stable_id_acceptance
fi

sleep 1
enqueue_record schema-two
printf 'success\nsuccess\nsuccess\n' >"$mock_state"
"$worker"
[[ "$(count_records "$queue_root/pending")" -eq 0 ]] || fail delivery_pending
delivery_receipt_count=$(count_records "$queue_root/delivered")
[[ "$delivery_receipt_count" -eq 3 ]] || fail "delivery_receipts_$delivery_receipt_count"
[[ "$(wc -l <"$call_file")" -eq 3 ]] || fail oldest_first_call_count
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
retry_started=$(date +%s)
"$worker"
retry_finished=$(date +%s)
retry_record=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' -print -quit)
[[ "$(jq -r '.retry.attempt' "$retry_record")" -eq 1 ]] || fail retry_attempt
now=$(date +%s)
next=$(jq -r '.retry.next_attempt_epoch' "$retry_record")
((next >= retry_started + 15 && next <= retry_finished + 25)) || fail bounded_backoff
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
# shellcheck disable=SC2016
grep -Fq 'chown "$pi_uid:$pi_gid" "$temporary"' "$enqueue" || fail production_record_owner
# shellcheck disable=SC2016
grep -Fq 'stat -c '\''%u:%g:%a'\'' "$temporary"' "$enqueue" || fail production_record_metadata
if [[ -f "$keepalived_producer" ]]; then
    if grep -Eq '\bcurl\b|APPRISE_(URL|KEY|ENDPOINT)' "$keepalived_producer"; then
        fail keepalived_direct_transport
    fi
    grep -Fq '/usr/local/libexec/caddy-apprise-enqueue' "$keepalived_producer" || fail keepalived_enqueue
    # shellcheck disable=SC2016
    grep -Fq -- '--application "$application"' "$keepalived_producer" || fail keepalived_application
    # shellcheck disable=SC2016
    grep -Fq -- '--component "$component"' "$keepalived_producer" || fail keepalived_component
    # shellcheck disable=SC2016
    grep -Fq -- '--failure-class "$failure_class"' "$keepalived_producer" || fail keepalived_failure_class
else
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || fail keepalived_producer_missing
fi
if grep -Eq '\bcurl\b' "$replication_producer"; then
    fail caddy_direct_transport
fi
# shellcheck disable=SC2016
grep -Fq -- '--application "$application"' \
    "$replication_producer" || fail replication_application

keepalived_state_root=$fixture_root/keepalived-state
install -d -m 0755 "$keepalived_state_root"
CADDY_APPRISE_NOW_EPOCH=1200 \
    KEEPALIVED_NOTIFY_ENQUEUE_COMMAND=$enqueue \
    KEEPALIVED_NOTIFY_LOGGER_COMMAND=$mock_logger \
    KEEPALIVED_NOTIFY_HOSTNAME_COMMAND=$mock_hostname \
    KEEPALIVED_NOTIFY_IP_COMMAND=$mock_ip \
    KEEPALIVED_NOTIFY_STATE_ROOT=$keepalived_state_root \
    /bin/bash "$keepalived_producer" INSTANCE PIHOLE_DUALSTACK FAULT
keepalived_record=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' \
    -exec jq -r 'if .source == "keepalived" then input_filename else empty end' {} +)
[[ -n "$keepalived_record" ]] || fail keepalived_record_absent
jq -e '
  .severity == "failure" and
  (.payload.title | startswith("🚨 [DNS] failure on ")) and
  (.payload.body | contains("Application: DNS") and
    contains("Component: Keepalived PIHOLE_DUALSTACK") and
    contains("Check: ownership-state") and
    contains("Failure class: eligibility-fault-unclassified") and
    contains("VIPs must move") and
    contains("local_vips=0") and
    contains("local_role=standby-node-b") and
    contains("peer_role=preferred-node-a") and
    contains("failover=pending-peer-convergence") and
    contains("First check: journalctl -u keepalived.service -n 50 --no-pager"))
' "$keepalived_record" >/dev/null || fail keepalived_fault_contract
if grep -Eq 'KEEPALIVED_NOTIFY_(DNS|PROXY)_STATUS_FILE|caddy-serving-health/(dns|proxy)|snapshot_(field|valid)' \
    "$keepalived_producer"; then
    fail keepalived_stale_snapshot_dependency
fi
[[ "$(<"$keepalived_state_root/PIHOLE_DUALSTACK")" = FAULT ]] ||
    fail keepalived_transition_state

CADDY_APPRISE_NOW_EPOCH=1500 \
    CADDY_SYNC_FAILURE_ENQUEUE_COMMAND=$enqueue \
    CADDY_SYNC_FAILURE_SYSTEMCTL_COMMAND=$mock_systemctl \
    CADDY_SYNC_FAILURE_LOGGER_COMMAND=$mock_logger \
    /bin/bash "$replication_producer" \
    'systemd unit failed: caddy-sync-reconcile.service'
replication_record=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' \
    -exec jq -r 'if .source == "caddy-sync" and (.payload.title | contains("[Replication]")) then input_filename else empty end' {} + | tail -1)
[[ -n "$replication_record" ]] || fail replication_record_absent
jq -e '
  .severity == "failure" and
  (.payload.body | contains("Component: reconciler") and
    contains("received releases cannot activate") and
    contains("VRRP dependency: no"))
' "$replication_record" >/dev/null || fail replication_contract
grep -Fq -- "failure) severity_icon='🚨'" "$enqueue" || fail failure_icon
grep -Fq -- "warning) severity_icon='⚠️'" "$enqueue" || fail warning_icon
grep -Fq -- "info) severity_icon='ℹ️'" "$enqueue" || fail info_icon
grep -Fq -- "success) severity_icon='✅'" "$enqueue" || fail success_icon
while IFS=$'\t' read -r production_source production_target production_mode \
    production_baseline_hash production_candidate_hash; do
    [[ -n "$production_source" && "$production_source" != \#* ]] || continue
    production_path=$repository_root/$production_source
    if [[ "$production_source" = homelab-dns/* ]]; then
        production_path=$repository_root/../$production_source
    fi
    [[ -f "$production_path" && ! -L "$production_path" ]] || fail production_source
    [[ "$production_target" = /* && "$production_mode" =~ ^0[0-7]{3}$ ]] ||
        fail production_contract
    [[ "$production_baseline_hash" = absent ||
        "$production_baseline_hash" =~ ^[0-9a-f]{64}$ ]] || fail production_baseline_hash
    [[ "$(sha256sum "$production_path" | awk '{ print $1 }')" = "$production_candidate_hash" ]] || fail production_candidate_hash
done <"$caddy_root/manifests/durable-apprise-production.tsv"
printf '%s_check_schema=true\n' "$prefix"
printf '%s_check_atomic_enqueue=true\n' "$prefix"
printf '%s_check_ordering=true\n' "$prefix"
printf '%s_check_retry_backoff=true\n' "$prefix"
printf '%s_check_deduplication=true\n' "$prefix"
printf '%s_check_stable_transition_deduplication=true\n' "$prefix"
printf '%s_check_reboot_recovery=true\n' "$prefix"
printf '%s_check_concurrency_lock=true\n' "$prefix"
printf '%s_check_controlled_record_isolation=true\n' "$prefix"
printf '%s_check_malformed_dead_letter=true\n' "$prefix"
printf '%s_check_permissions=true\n' "$prefix"
printf '%s_check_systemd_hardening=true\n' "$prefix"
printf '%s_check_production_manifest=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
