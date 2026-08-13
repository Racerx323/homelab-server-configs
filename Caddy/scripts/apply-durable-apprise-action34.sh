#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_34_remote
readonly artifact_manifest_relative=Caddy/manifests/durable-apprise-action34.tsv
readonly runtime_baseline_relative=Caddy/manifests/caddy-runtime-lifecycle-action32g.tsv
readonly runtime_baseline_sha256=705c0e2e590e83da942048ca47c61fab545eb52c9f7b5fe866ba18524c7d1587
readonly backup_parent=/var/backups/caddy-ha
readonly queue_root=/var/lib/caddy-apprise-queue
readonly node_evidence_root=/tmp/caddy-action34
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6
readonly dns_ipv4=10.1.0.55
readonly caddy_ipv4=10.1.0.56
readonly dns_ipv6=fd36:5aa8:6971:1::55
readonly caddy_ipv6=fd36:5aa8:6971:1::56

mode=${1:-}
role=${2:-}
payload_archive=${3:-}
payload_sha256=${4:-}
run_token=${5:-}
[[ "$role" =~ ^node-[ab]$ ]] || exit 64
[[ "$run_token" =~ ^[0-9]{10,20}-[0-9]+$ ]] || exit 64
readonly mode role payload_archive payload_sha256 run_token
readonly backup_root=$backup_parent/action34-$role-$run_token
readonly evidence_root=$node_evidence_root/$run_token-$role
mutation_started=false
stage_path=

gate() {
    local action34_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "${role//-/_}" "$action34_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "${role//-/_}" "$action34_label" >&2
    return 1
}

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

state_for() {
    local action34_object=$1
    busctl get-property org.keepalived.Vrrp1 "$action34_object" \
        org.keepalived.Vrrp1.Instance State | awk -F'"' 'NF == 3 { print toupper($2) }'
}

address_count() {
    local action34_family=$1
    local action34_address=$2
    local action34_output
    if [[ "$action34_family" = 4 ]]; then
        action34_output=$(ip -o -4 addr show) || return 1
    else
        action34_output=$(ip -o -6 addr show) || return 1
    fi
    awk -v address="$action34_address" '$4 ~ ("^" address "/") { count++ } END { print count + 0 }' \
        <<<"$action34_output"
}

baseline() {
    local action34_expected_state=BACKUP
    local action34_expected_count=0
    [[ "$role" = node-b ]] || {
        action34_expected_state=MASTER
        action34_expected_count=1
    }
    gate caddy_active systemctl is-active --quiet caddy.service || return 1
    gate lsyncd_active systemctl is-active --quiet caddy-lsyncd.service || return 1
    gate reconcile_path_active systemctl is-active --quiet caddy-sync-reconcile.path || return 1
    gate keepalived_active systemctl is-active --quiet keepalived.service || return 1
    gate ipv4_state test "$(state_for "$ipv4_object")" = "$action34_expected_state" || return 1
    gate ipv6_state test "$(state_for "$ipv6_object")" = "$action34_expected_state" || return 1
    gate dns_ipv4_ownership test "$(address_count 4 "$dns_ipv4")" -eq "$action34_expected_count" || return 1
    gate caddy_ipv4_ownership test "$(address_count 4 "$caddy_ipv4")" -eq "$action34_expected_count" || return 1
    gate dns_ipv6_ownership test "$(address_count 6 "$dns_ipv6")" -eq "$action34_expected_count" || return 1
    gate caddy_ipv6_ownership test "$(address_count 6 "$caddy_ipv6")" -eq "$action34_expected_count" || return 1
}

validate_payload() {
    local action34_stage=$1
    local action34_manifest=$action34_stage/$artifact_manifest_relative
    local action34_runtime_baseline=$action34_stage/$runtime_baseline_relative
    local action34_source action34_target action34_mode action34_baseline action34_candidate

    [[ "$payload_archive" = /tmp/caddy-action34-payload-* && -f "$payload_archive" && ! -L "$payload_archive" ]] || return 1
    [[ "$(file_hash "$payload_archive")" = "$payload_sha256" ]] || return 1
    tar -xf "$payload_archive" -C "$action34_stage" || return 1
    [[ -f "$action34_manifest" && ! -L "$action34_manifest" ]] || return 1
    [[ -f "$action34_runtime_baseline" && ! -L "$action34_runtime_baseline" ]] || return 1
    [[ "$(file_hash "$action34_runtime_baseline")" = "$runtime_baseline_sha256" ]] || return 1
    while IFS=$'\t' read -r action34_source action34_target action34_mode \
        action34_baseline action34_candidate; do
        [[ -n "$action34_source" && "$action34_source" != \#* ]] || continue
        : "$action34_target" "$action34_mode" "$action34_baseline"
        [[ "$action34_source" != /* && "$action34_source" != *..* ]] || return 1
        [[ -f "$action34_stage/$action34_source" && ! -L "$action34_stage/$action34_source" ]] || return 1
        [[ "$(file_hash "$action34_stage/$action34_source")" = "$action34_candidate" ]] || return 1
    done <"$action34_manifest"
}

verify_runtime_baseline() {
    local action34_runtime_manifest=$1
    local action34_allowed_mutations=${2:-}
    local action34_source action34_target action34_mode action34_accepted action34_candidate

    while IFS=$'\t' read -r action34_source action34_target action34_mode \
        action34_accepted action34_candidate; do
        [[ -n "$action34_source" && "$action34_source" != \#* ]] || continue
        : "$action34_source" "$action34_mode" "$action34_accepted"
        if [[ -n "$action34_allowed_mutations" ]] &&
            awk -F '\t' -v target="$action34_target" \
                '!/^[[:space:]]*(#|$)/ && $2 == target { found++ } END { exit(found ? 0 : 1) }' \
                "$action34_allowed_mutations"; then
            continue
        fi
        [[ -f "$action34_target" && ! -L "$action34_target" ]] || return 1
        [[ "$(file_hash "$action34_target")" = "$action34_candidate" ]] || return 1
    done <"$action34_runtime_manifest"
}

verify_artifacts() {
    local action34_manifest=$1
    local action34_expected_column=$2
    local action34_source action34_target action34_mode action34_baseline action34_candidate
    local action34_expected

    while IFS=$'\t' read -r action34_source action34_target action34_mode \
        action34_baseline action34_candidate; do
        [[ -n "$action34_source" && "$action34_source" != \#* ]] || continue
        : "$action34_source" "$action34_mode"
        if [[ "$action34_expected_column" = baseline ]]; then
            action34_expected=$action34_baseline
        else
            action34_expected=$action34_candidate
        fi
        if [[ "$action34_expected" = absent ]]; then
            [[ ! -e "$action34_target" && ! -L "$action34_target" ]] || return 1
        else
            [[ -f "$action34_target" && ! -L "$action34_target" ]] || return 1
            [[ "$(file_hash "$action34_target")" = "$action34_expected" ]] || return 1
        fi
    done <"$action34_manifest"
}

backup_and_install() {
    local action34_stage=$1
    local action34_manifest=$action34_stage/$artifact_manifest_relative
    local action34_source action34_target action34_mode action34_baseline action34_candidate
    install -d -o root -g root -m 0700 "$backup_root/files" || return 1
    install -m 0600 "$action34_manifest" "$backup_root/artifacts.tsv" || return 1
    : >"$backup_root/baseline.tsv"
    chmod 0600 "$backup_root/baseline.tsv"
    while IFS=$'\t' read -r action34_source action34_target action34_mode \
        action34_baseline action34_candidate; do
        [[ -n "$action34_source" && "$action34_source" != \#* ]] || continue
        : "$action34_candidate"
        if [[ -e "$action34_target" || -L "$action34_target" ]]; then
            install -d -m 0700 "$backup_root/files${action34_target%/*}" || return 1
            cp -a -- "$action34_target" "$backup_root/files$action34_target" || return 1
            printf 'present\t%s\n' "$action34_target" >>"$backup_root/baseline.tsv"
        else
            printf 'absent\t%s\n' "$action34_target" >>"$backup_root/baseline.tsv"
        fi
        install -d -o root -g root -m 0755 "${action34_target%/*}" || return 1
        install -o root -g root -m "$action34_mode" \
            "$action34_stage/$action34_source" "$action34_target" || return 1
    done <"$action34_manifest"
}

exercise_queue() {
    local action34_before action34_after action34_record action34_temporary action34_now
    local action34_mock=$evidence_root/mock-curl
    local action34_controlled=$evidence_root/controlled-records

    systemctl stop caddy-apprise-worker.path caddy-apprise-worker.timer || return 1
    action34_before=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' | wc -l) || return 1
    /usr/local/libexec/lsyncd-sync-failure-notify.sh 'Action 34 controlled enqueue test' || return 1
    /usr/local/bin/keepalived-notify.sh GROUP PIHOLE_DUALSTACK TEST || return 1
    : >"$action34_controlled"
    chmod 0600 "$action34_controlled"
    for action34_record in "$queue_root/pending/"*.json; do
        if jq -e '
            (.source == "caddy-sync" and (.payload.body | contains("Action 34 controlled enqueue test"))) or
            (.source == "keepalived" and (.payload.body | contains("state change to: TEST")))
        ' "$action34_record" >/dev/null; then
            printf '%s\n' "${action34_record##*/}" >>"$action34_controlled"
        fi
    done
    gate controlled_record_count test "$(wc -l <"$action34_controlled")" -eq 2 || return 1
    action34_after=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' | wc -l) || return 1
    gate producer_enqueue_count test "$((action34_after - action34_before))" -eq 2 || return 1
    grep -Fq 'curl' /usr/local/libexec/lsyncd-sync-failure-notify.sh && return 1
    grep -Eq '\bcurl\b|APPRISE_(URL|KEY|ENDPOINT)' /usr/local/bin/keepalived-notify.sh && return 1

    cat >"$action34_mock" <<'MOCK'
#!/usr/bin/env bash
exit 28
MOCK
    chmod 0700 "$action34_mock"
    CADDY_APPRISE_TEST_MODE=1 CADDY_APPRISE_CURL=$action34_mock \
        CADDY_APPRISE_EVENT_ALLOWLIST=$action34_controlled \
        /usr/local/libexec/caddy-apprise-delivery-worker || return 1
    while IFS= read -r action34_controlled_name; do
        [[ "$action34_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 1
        action34_record=$queue_root/pending/$action34_controlled_name
        [[ -f "$action34_record" && ! -L "$action34_record" ]] || return 1
        gate "retry_attempt_${action34_controlled_name%.json}" test \
            "$(jq -r '.retry.attempt' "$action34_record")" -eq 1 || return 1
    done <"$action34_controlled"
    action34_now=$(date +%s)
    while IFS= read -r action34_controlled_name; do
        [[ "$action34_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 1
        action34_record=$queue_root/pending/$action34_controlled_name
        [[ -f "$action34_record" && ! -L "$action34_record" ]] || return 1
        action34_temporary=$(mktemp "$queue_root/pending/.action34.XXXXXX") || return 1
        chmod 0600 "$action34_temporary" || return 1
        jq --argjson now "$action34_now" '.retry.next_attempt_epoch = $now' \
            "$action34_record" >"$action34_temporary" || return 1
        mv -f -- "$action34_temporary" "$action34_record" || return 1
    done <"$action34_controlled"
    cat >"$action34_mock" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
    chmod 0700 "$action34_mock"
    CADDY_APPRISE_TEST_MODE=1 CADDY_APPRISE_CURL=$action34_mock \
        CADDY_APPRISE_EVENT_ALLOWLIST=$action34_controlled \
        /usr/local/libexec/caddy-apprise-delivery-worker || return 1
    gate controlled_queue_empty test "$(find "$queue_root/pending" "$queue_root/inflight" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 0 || return 1
    gate controlled_dead_letter_empty test "$(find "$queue_root/dead-letter" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 0 || return 1
    while IFS= read -r action34_controlled_name; do
        [[ "$action34_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 1
        rm -f -- "$queue_root/delivered/$action34_controlled_name" || return 1
    done <"$action34_controlled"
    systemctl enable --now caddy-apprise-worker.path caddy-apprise-worker.timer || return 1
}

apply_action() {
    local action34_stage
    local action34_manifest
    local action34_cursor

    [[ "$PWD" = / ]] || return 1
    install -d -o root -g root -m 0700 "$evidence_root" || return 1
    journalctl --show-cursor -n 0 -o cat >"$evidence_root/journal.cursor" || return 1
    action34_cursor=$(sed -n 's/^-- cursor: //p' "$evidence_root/journal.cursor")
    [[ -n "$action34_cursor" ]] || return 1
    baseline || return 1
    gate queue_baseline_absent test ! -e "$queue_root" || return 1
    [[ ! -e "$backup_root" ]] || return 1
    action34_stage=$(mktemp -d /run/caddy-action34-stage.XXXXXX) || return 1
    stage_path=$action34_stage
    chmod 0700 "$action34_stage" || return 1
    validate_payload "$action34_stage" || return 1
    action34_manifest=$action34_stage/$artifact_manifest_relative
    gate action32g_runtime_baseline verify_runtime_baseline \
        "$action34_stage/$runtime_baseline_relative" || return 1
    gate accepted_baseline verify_artifacts "$action34_manifest" baseline || return 1
    mutation_started=true
    backup_and_install "$action34_stage" || return 1
    install -m 0600 "$action34_stage/$runtime_baseline_relative" \
        "$backup_root/runtime-baseline.tsv" || return 1
    systemctl daemon-reload || return 1
    systemd-tmpfiles --create /etc/tmpfiles.d/caddy-ha.conf || return 1
    gate candidate_artifacts verify_artifacts "$action34_manifest" candidate || return 1
    gate queue_metadata test "$(stat -c '%U:%G:%a' "$queue_root")" = pi:pi:700 || return 1
    exercise_queue || return 1
    gate path_enabled systemctl is-enabled --quiet caddy-apprise-worker.path || return 1
    gate path_active systemctl is-active --quiet caddy-apprise-worker.path || return 1
    gate timer_enabled systemctl is-enabled --quiet caddy-apprise-worker.timer || return 1
    gate timer_active systemctl is-active --quiet caddy-apprise-worker.timer || return 1
    gate worker_static test "$(systemctl is-enabled caddy-apprise-worker.service 2>&1 || true)" = static || return 1
    baseline || return 1
    journalctl --after-cursor "$action34_cursor" -o short-iso --no-pager \
        >"$evidence_root/journal.log" || return 1
    chmod 0600 "$evidence_root/journal.log" || return 1
    grep -Eq 'event=(enqueued|attempt|retry-scheduled|delivered)' "$evidence_root/journal.log" || return 1
    rm -f -- "$payload_archive"
    mutation_started=false
    printf '%s_%s_backup_root=%s\n' "$prefix" "${role//-/_}" "$backup_root"
    printf '%s_%s_evidence_root=%s\n' "$prefix" "${role//-/_}" "$evidence_root"
    printf '%s_%s_apply_complete=true\n' "$prefix" "${role//-/_}"
}

rollback_action() {
    local action34_state action34_target
    [[ -f "$backup_root/baseline.tsv" && ! -L "$backup_root/baseline.tsv" ]] || return 125
    systemctl disable --now caddy-apprise-worker.path caddy-apprise-worker.timer >/dev/null 2>&1 || true
    while IFS=$'\t' read -r action34_state action34_target; do
        case "$action34_state" in
            present)
                [[ -e "$backup_root/files$action34_target" || -L "$backup_root/files$action34_target" ]] || return 125
                cp -a --remove-destination "$backup_root/files$action34_target" "$action34_target" || return 125
                ;;
            absent) rm -f -- "$action34_target" || return 125 ;;
            *) return 125 ;;
        esac
    done <"$backup_root/baseline.tsv"
    if [[ -f "$evidence_root/controlled-records" && ! -L "$evidence_root/controlled-records" ]]; then
        while IFS= read -r action34_controlled_name; do
            [[ "$action34_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 125
            rm -f -- "$queue_root"/{pending,inflight,dead-letter,delivered}/"$action34_controlled_name" || return 125
        done <"$evidence_root/controlled-records"
    fi
    if [[ -d "$queue_root" ]] &&
        [[ -z "$(find "$queue_root" -mindepth 2 -maxdepth 2 -print -quit)" ]]; then
        rm -rf -- "$queue_root" || return 125
    elif [[ -d "$queue_root" ]]; then
        printf '%s_%s_unexpected_queue_preserved=true\n' "$prefix" "${role//-/_}" >&2
    fi
    rm -rf -- /run/caddy-apprise || return 125
    systemctl daemon-reload || return 125
    baseline || return 125
    printf '%s_%s_rollback_complete=true\n' "$prefix" "${role//-/_}"
}

verify_current() {
    local action34_manifest=$backup_root/artifacts.tsv
    baseline || return 1
    gate current_artifacts verify_artifacts "$action34_manifest" candidate || return 1
    gate action32g_runtime_baseline verify_runtime_baseline \
        "$backup_root/runtime-baseline.tsv" "$action34_manifest" || return 1
    gate pending_empty test "$(find "$queue_root/pending" "$queue_root/inflight" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 0 || return 1
    gate dead_letter_empty test "$(find "$queue_root/dead-letter" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 0 || return 1
    gate path_enabled systemctl is-enabled --quiet caddy-apprise-worker.path || return 1
    gate timer_enabled systemctl is-enabled --quiet caddy-apprise-worker.timer || return 1
    printf '%s_%s_verify_complete=true\n' "$prefix" "${role//-/_}"
}

# shellcheck disable=SC2317
cleanup_on_exit() {
    local action34_status=$?
    trap - EXIT
    [[ -z "$stage_path" ]] || rm -rf -- "$stage_path"
    if [[ "$action34_status" -ne 0 && "$mutation_started" = true ]]; then
        if rollback_action; then
            printf '%s_%s_automatic_rollback=true\n' "$prefix" "${role//-/_}" >&2
        else
            printf '%s_%s_manual_intervention_required=true\n' "$prefix" "${role//-/_}" >&2
            exit 125
        fi
    fi
    exit "$action34_status"
}

trap cleanup_on_exit EXIT

case "$mode" in
    --apply) apply_action ;;
    --rollback) rollback_action ;;
    --verify-current) verify_current ;;
    *) exit 64 ;;
esac
