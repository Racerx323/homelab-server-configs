#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_34e_remote
readonly artifact_manifest_relative=Caddy/manifests/durable-apprise-action34e.tsv
readonly runtime_baseline_relative=Caddy/manifests/caddy-runtime-lifecycle-action32g.tsv
readonly runtime_baseline_sha256=705c0e2e590e83da942048ca47c61fab545eb52c9f7b5fe866ba18524c7d1587
readonly backup_parent=/var/backups/caddy-ha
readonly queue_root=/var/lib/caddy-apprise-queue
readonly runtime_root=/run/caddy-apprise
readonly node_evidence_root=/tmp/caddy-action34e
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6
readonly dns_ipv4=10.1.0.55
readonly caddy_ipv4=10.1.0.56
readonly dns_ipv6=fd36:5aa8:6971:1::55
readonly caddy_ipv6=fd36:5aa8:6971:1::56
readonly failed_action34_payload_sha256=15ff568ac2e0f66d6ba662d9d300470ec17ec37b6140782c8b47d2df3081dcd3

mode=${1:-}
role=${2:-}
payload_archive=${3:-}
payload_sha256=${4:-}
run_token=${5:-}
[[ "$role" =~ ^node-[ab]$ ]] || exit 64
[[ "$run_token" =~ ^[0-9]{10,20}-[0-9]+$ ]] || exit 64
readonly mode role payload_archive payload_sha256 run_token
readonly backup_root=$backup_parent/action34e-$role-$run_token
readonly evidence_root=$node_evidence_root/$run_token-$role
mutation_started=false
stage_path=

gate() {
    local action34e_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "${role//-/_}" "$action34e_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "${role//-/_}" "$action34e_label" >&2
    return 1
}

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

capture_command() {
    local action34e_capture_label=$1
    shift
    local action34e_capture_stdout=$evidence_root/$action34e_capture_label.stdout
    local action34e_capture_stderr=$evidence_root/$action34e_capture_label.stderr
    local action34e_capture_status_file=$evidence_root/$action34e_capture_label.status
    local action34e_capture_status=0
    local action34e_capture_stream action34e_capture_name
    install -m 0600 /dev/null "$action34e_capture_stdout" || return 1
    install -m 0600 /dev/null "$action34e_capture_stderr" || return 1
    install -m 0600 /dev/null "$action34e_capture_status_file" || return 1
    "$@" >"$action34e_capture_stdout" 2>"$action34e_capture_stderr" || action34e_capture_status=$?
    printf '%s\n' "$action34e_capture_status" >"$action34e_capture_status_file"
    printf '%s_%s_%s_status=%s\n' "$prefix" "${role//-/_}" \
        "$action34e_capture_label" "$action34e_capture_status"
    for action34e_capture_stream in "$action34e_capture_stdout" "$action34e_capture_stderr"; do
        action34e_capture_name=${action34e_capture_stream##*.}
        [[ "$(wc -c <"$action34e_capture_stream")" -le 65536 ]] || return 97
        [[ "$(awk 'END { print NR }' "$action34e_capture_stream")" -le 256 ]] || return 97
        iconv -f UTF-8 -t UTF-8 "$action34e_capture_stream" >/dev/null 2>&1 || return 97
        ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action34e_capture_stream" >/dev/null || return 97
        ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
            "$action34e_capture_stream" || return 97
        printf '%s_%s_%s_%s_bytes=%s\n' "$prefix" "${role//-/_}" \
            "$action34e_capture_label" "$action34e_capture_name" \
            "$(wc -c <"$action34e_capture_stream")"
        printf '%s_%s_%s_%s_sha256=%s\n' "$prefix" "${role//-/_}" \
            "$action34e_capture_label" "$action34e_capture_name" \
            "$(file_hash "$action34e_capture_stream")"
        printf '%s_%s_%s_%s_classification=bounded_safe\n' "$prefix" "${role//-/_}" \
            "$action34e_capture_label" "$action34e_capture_name"
        if [[ -s "$action34e_capture_stream" ]]; then
            printf '%s_%s_%s_%s_begin\n' "$prefix" "${role//-/_}" \
                "$action34e_capture_label" "$action34e_capture_name"
            cat "$action34e_capture_stream"
            printf '%s_%s_%s_%s_end\n' "$prefix" "${role//-/_}" \
                "$action34e_capture_label" "$action34e_capture_name"
        fi
    done
    return "$action34e_capture_status"
}

artifact_label() {
    local action34e_target=$1
    local action34e_encoded
    [[ "$action34e_target" = /* && -n "$action34e_target" ]] || return 1
    action34e_encoded=$(LC_ALL=C printf '%s' "$action34e_target" | od -An -tx1 -v | tr -d ' \n') || return 1
    [[ "$action34e_encoded" =~ ^[0-9a-f]+$ ]] || return 1
    printf 'path_%s\n' "$action34e_encoded"
}

observe_artifact() {
    local action34e_target=$1
    if [[ -L "$action34e_target" ]]; then
        printf 'invalid-symlink\n'
    elif [[ -f "$action34e_target" ]]; then
        file_hash "$action34e_target"
    elif [[ -e "$action34e_target" ]]; then
        printf 'invalid-nonregular\n'
    else
        printf 'absent\n'
    fi
}

state_for() {
    local action34e_object=$1
    busctl get-property org.keepalived.Vrrp1 "$action34e_object" \
        org.keepalived.Vrrp1.Instance State | awk -F'"' 'NF == 3 { print toupper($2) }'
}

address_count() {
    local action34e_family=$1
    local action34e_address=$2
    local action34e_output
    if [[ "$action34e_family" = 4 ]]; then
        action34e_output=$(ip -o -4 addr show) || return 1
    else
        action34e_output=$(ip -o -6 addr show) || return 1
    fi
    awk -v address="$action34e_address" '$4 ~ ("^" address "/") { count++ } END { print count + 0 }' \
        <<<"$action34e_output"
}

baseline() {
    local action34e_expected_state=BACKUP
    local action34e_expected_count=0
    [[ "$role" = node-b ]] || {
        action34e_expected_state=MASTER
        action34e_expected_count=1
    }
    gate caddy_active systemctl is-active --quiet caddy.service || return 1
    gate lsyncd_active systemctl is-active --quiet caddy-lsyncd.service || return 1
    gate reconcile_path_active systemctl is-active --quiet caddy-sync-reconcile.path || return 1
    gate keepalived_active systemctl is-active --quiet keepalived.service || return 1
    gate ipv4_state test "$(state_for "$ipv4_object")" = "$action34e_expected_state" || return 1
    gate ipv6_state test "$(state_for "$ipv6_object")" = "$action34e_expected_state" || return 1
    gate dns_ipv4_ownership test "$(address_count 4 "$dns_ipv4")" -eq "$action34e_expected_count" || return 1
    gate caddy_ipv4_ownership test "$(address_count 4 "$caddy_ipv4")" -eq "$action34e_expected_count" || return 1
    gate dns_ipv6_ownership test "$(address_count 6 "$dns_ipv6")" -eq "$action34e_expected_count" || return 1
    gate caddy_ipv6_ownership test "$(address_count 6 "$caddy_ipv6")" -eq "$action34e_expected_count" || return 1
}

validate_payload() {
    local action34e_stage=$1
    local action34e_manifest=$action34e_stage/$artifact_manifest_relative
    local action34e_runtime_baseline=$action34e_stage/$runtime_baseline_relative
    local action34e_source action34e_target action34e_mode action34e_baseline action34e_candidate

    [[ "$payload_archive" = /tmp/caddy-action34e-payload-* && -f "$payload_archive" && ! -L "$payload_archive" ]] || return 1
    [[ "$(file_hash "$payload_archive")" = "$payload_sha256" ]] || return 1
    tar -xf "$payload_archive" -C "$action34e_stage" || return 1
    [[ -f "$action34e_manifest" && ! -L "$action34e_manifest" ]] || return 1
    [[ -f "$action34e_runtime_baseline" && ! -L "$action34e_runtime_baseline" ]] || return 1
    [[ "$(file_hash "$action34e_runtime_baseline")" = "$runtime_baseline_sha256" ]] || return 1
    while IFS=$'\t' read -r action34e_source action34e_target action34e_mode \
        action34e_baseline action34e_candidate; do
        [[ -n "$action34e_source" && "$action34e_source" != \#* ]] || continue
        : "$action34e_target" "$action34e_mode" "$action34e_baseline"
        [[ "$action34e_source" != /* && "$action34e_source" != *..* ]] || return 1
        [[ -f "$action34e_stage/$action34e_source" && ! -L "$action34e_stage/$action34e_source" ]] || return 1
        [[ "$(file_hash "$action34e_stage/$action34e_source")" = "$action34e_candidate" ]] || return 1
    done <"$action34e_manifest"
}

verify_runtime_baseline() {
    local action34e_runtime_manifest=$1
    local action34e_allowed_mutations=${2:-}
    local action34e_source action34e_target action34e_mode action34e_accepted action34e_candidate

    while IFS=$'\t' read -r action34e_source action34e_target action34e_mode \
        action34e_accepted action34e_candidate; do
        [[ -n "$action34e_source" && "$action34e_source" != \#* ]] || continue
        : "$action34e_source" "$action34e_mode" "$action34e_accepted"
        if [[ -n "$action34e_allowed_mutations" ]] &&
            awk -F '\t' -v target="$action34e_target" \
                '!/^[[:space:]]*(#|$)/ && $2 == target { found++ } END { exit(found ? 0 : 1) }' \
                "$action34e_allowed_mutations"; then
            continue
        fi
        [[ -f "$action34e_target" && ! -L "$action34e_target" ]] || return 1
        [[ "$(file_hash "$action34e_target")" = "$action34e_candidate" ]] || return 1
    done <"$action34e_runtime_manifest"
}

verify_resume_baseline() {
    local action34e_manifest=$1
    local action34e_source action34e_target action34e_mode action34e_baseline action34e_candidate
    local action34e_label action34e_observed

    while IFS=$'\t' read -r action34e_source action34e_target action34e_mode \
        action34e_baseline action34e_candidate; do
        [[ -n "$action34e_source" && "$action34e_source" != \#* ]] || continue
        : "$action34e_source" "$action34e_mode"
        action34e_label=$(artifact_label "$action34e_target") || return 1
        action34e_observed=$(observe_artifact "$action34e_target") || return 1
        printf '%s_%s_baseline_%s_expected=legacy:%s|candidate:%s\n' \
            "$prefix" "${role//-/_}" "$action34e_label" "$action34e_baseline" "$action34e_candidate"
        printf '%s_%s_baseline_%s_observed=%s\n' \
            "$prefix" "${role//-/_}" "$action34e_label" "$action34e_observed"
        if [[ "$action34e_observed" = "$action34e_baseline" ||
            "$action34e_observed" = "$action34e_candidate" ]]; then
            printf '%s_%s_check_baseline_%s_identity=true\n' \
                "$prefix" "${role//-/_}" "$action34e_label"
        else
            printf '%s_%s_check_baseline_%s_identity=false\n' \
                "$prefix" "${role//-/_}" "$action34e_label" >&2
            return 1
        fi
    done <"$action34e_manifest"
}

verify_candidate_artifacts() {
    local action34e_manifest=$1
    local action34e_source action34e_target action34e_mode action34e_baseline action34e_candidate
    local action34e_label action34e_observed

    while IFS=$'\t' read -r action34e_source action34e_target action34e_mode \
        action34e_baseline action34e_candidate; do
        [[ -n "$action34e_source" && "$action34e_source" != \#* ]] || continue
        : "$action34e_source" "$action34e_mode" "$action34e_baseline"
        action34e_label=$(artifact_label "$action34e_target") || return 1
        action34e_observed=$(observe_artifact "$action34e_target") || return 1
        printf '%s_%s_candidate_%s_expected=%s\n' \
            "$prefix" "${role//-/_}" "$action34e_label" "$action34e_candidate"
        printf '%s_%s_candidate_%s_observed=%s\n' \
            "$prefix" "${role//-/_}" "$action34e_label" "$action34e_observed"
        if [[ "$action34e_observed" = "$action34e_candidate" ]]; then
            printf '%s_%s_check_candidate_%s_identity=true\n' \
                "$prefix" "${role//-/_}" "$action34e_label"
        else
            printf '%s_%s_check_candidate_%s_identity=false\n' \
                "$prefix" "${role//-/_}" "$action34e_label" >&2
            return 1
        fi
    done <"$action34e_manifest"
}

cleanup_failed_action34_payload_at() {
    local action34e_scan_root=$1
    local action34e_expected_sha256=$2
    local action34e_entry action34e_name action34e_hash
    local action34e_match_count=0
    local action34e_inventory_count=0
    local action34e_match_path=
    [[ "$action34e_scan_root" = /tmp ||
        "$action34e_scan_root" =~ ^/tmp/caddy-action34e-regression\.[a-zA-Z0-9]+/cleanup$ ]] || return 1
    shopt -s nullglob
    for action34e_entry in "$action34e_scan_root"/caddy-action34-payload-node-*.tar; do
        action34e_inventory_count=$((action34e_inventory_count + 1))
        action34e_name=${action34e_entry##*/}
        [[ "$action34e_name" =~ ^caddy-action34-payload-node-[ab]-[0-9]{10,20}-[0-9]+\.tar$ ]] || return 1
        [[ -f "$action34e_entry" && ! -L "$action34e_entry" ]] || return 1
        action34e_hash=$(file_hash "$action34e_entry") || return 1
        printf '%s_%s_failed_action34_payload_%s_sha256=%s\n' \
            "$prefix" "${role//-/_}" "$action34e_inventory_count" "$action34e_hash"
        if [[ "$action34e_hash" = "$action34e_expected_sha256" ]]; then
            action34e_match_count=$((action34e_match_count + 1))
            action34e_match_path=$action34e_entry
        fi
    done
    shopt -u nullglob
    printf '%s_%s_failed_action34_payload_inventory_count=%s\n' \
        "$prefix" "${role//-/_}" "$action34e_inventory_count"
    printf '%s_%s_failed_action34_payload_match_count=%s\n' \
        "$prefix" "${role//-/_}" "$action34e_match_count"
    gate failed_action34_payload_match_bounded test "$action34e_match_count" -le 1 || return 1
    if [[ "$action34e_match_count" -eq 1 ]]; then
        action34e_name=${action34e_match_path##*/}
        rm -f -- "$action34e_match_path" || return 1
        [[ ! -e "$action34e_match_path" && ! -L "$action34e_match_path" ]] || return 1
        printf '%s_%s_failed_action34_payload_removed=%s\n' \
            "$prefix" "${role//-/_}" "$action34e_name"
    fi
}

cleanup_failed_action34_payload() {
    cleanup_failed_action34_payload_at /tmp "$failed_action34_payload_sha256"
}

backup_artifacts() {
    local action34e_stage=$1
    local action34e_manifest=$action34e_stage/$artifact_manifest_relative
    local action34e_source action34e_target action34e_mode action34e_baseline action34e_candidate
    install -d -o root -g root -m 0700 "$backup_root/files" || return 1
    install -m 0600 "$action34e_manifest" "$backup_root/artifacts.tsv" || return 1
    : >"$backup_root/baseline.tsv"
    chmod 0600 "$backup_root/baseline.tsv"
    while IFS=$'\t' read -r action34e_source action34e_target action34e_mode \
        action34e_baseline action34e_candidate; do
        [[ -n "$action34e_source" && "$action34e_source" != \#* ]] || continue
        : "$action34e_candidate"
        if [[ -e "$action34e_target" || -L "$action34e_target" ]]; then
            install -d -m 0700 "$backup_root/files${action34e_target%/*}" || return 1
            cp -a -- "$action34e_target" "$backup_root/files$action34e_target" || return 1
            printf 'present\t%s\n' "$action34e_target" >>"$backup_root/baseline.tsv"
        else
            printf 'absent\t%s\n' "$action34e_target" >>"$backup_root/baseline.tsv"
        fi
    done <"$action34e_manifest"
    install -m 0600 "$action34e_stage/$runtime_baseline_relative" \
        "$backup_root/runtime-baseline.tsv" || return 1
    install -m 0600 /dev/null "$backup_root/backup-complete" || return 1
}

install_artifacts() {
    local action34e_stage=$1
    local action34e_manifest=$action34e_stage/$artifact_manifest_relative
    local action34e_source action34e_target action34e_mode action34e_baseline action34e_candidate
    install -m 0600 /dev/null "$backup_root/mutation-started" || return 1
    mutation_started=true
    while IFS=$'\t' read -r action34e_source action34e_target action34e_mode \
        action34e_baseline action34e_candidate; do
        [[ -n "$action34e_source" && "$action34e_source" != \#* ]] || continue
        : "$action34e_baseline" "$action34e_candidate"
        install -d -o root -g root -m 0755 "${action34e_target%/*}" || return 1
        install -o root -g root -m "$action34e_mode" \
            "$action34e_stage/$action34e_source" "$action34e_target" || return 1
    done <"$action34e_manifest"
}

dispose_stale_worker_lock_at() {
    local action34e_lock_runtime_root=$1
    local action34e_lock_path=$action34e_lock_runtime_root/worker.lock
    local action34e_lock_metadata

    # conditional-validator-explicit-failures-begin
    gate worker_inactive_before_lock_disposition test \
        "$(systemctl show -p ActiveState --value caddy-apprise-worker.service)" = inactive || return 1
    gate lock_runtime_metadata test \
        "$(stat -c '%U:%G:%a' "$action34e_lock_runtime_root")" = pi:pi:700 || return 1
    if [[ ! -e "$action34e_lock_path" && ! -L "$action34e_lock_path" ]]; then
        printf '%s_%s_stale_worker_lock_disposition=absent\n' "$prefix" "${role//-/_}"
        return 0
    fi
    [[ -f "$action34e_lock_path" && ! -L "$action34e_lock_path" ]] || return 1
    action34e_lock_metadata=$(stat -c '%U:%G:%a' "$action34e_lock_path") || return 1
    printf '%s_%s_stale_worker_lock_metadata=%s\n' \
        "$prefix" "${role//-/_}" "$action34e_lock_metadata"
    [[ "$action34e_lock_metadata" = root:root:600 ]] || return 1
    rm -f -- "$action34e_lock_path" || return 1
    gate stale_worker_lock_removed test \
        ! -e "$action34e_lock_path" || return 1
    printf '%s_%s_stale_worker_lock_disposition=removed_exact_legacy\n' \
        "$prefix" "${role//-/_}"
    # conditional-validator-explicit-failures-end
}

exercise_queue() {
    local action34e_before action34e_after action34e_record action34e_temporary action34e_now
    local action34e_mock=$evidence_root/mock-curl
    local action34e_controlled=$evidence_root/controlled-records
    local action34e_service_mock=$runtime_root/action34e-mock-$run_token
    local action34e_service_controlled=$runtime_root/action34e-controlled-$run_token
    local action34e_pi_identity

    systemctl stop caddy-apprise-worker.path caddy-apprise-worker.timer \
        caddy-apprise-worker.service || return 1
    dispose_stale_worker_lock_at "$runtime_root" || return 1
    action34e_before=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' | wc -l) || return 1
    /usr/local/libexec/lsyncd-sync-failure-notify.sh 'Action 34e controlled enqueue test' || return 1
    /usr/local/bin/keepalived-notify.sh GROUP PIHOLE_DUALSTACK TEST || return 1
    : >"$action34e_controlled"
    chmod 0600 "$action34e_controlled"
    for action34e_record in "$queue_root/pending/"*.json; do
        if jq -e '
            (.source == "caddy-sync" and (.payload.body | contains("Action 34e controlled enqueue test"))) or
            (.source == "keepalived" and (.payload.body | contains("state change to: TEST")))
        ' "$action34e_record" >/dev/null; then
            printf '%s\n' "${action34e_record##*/}" >>"$action34e_controlled"
        fi
    done
    gate controlled_record_count test "$(wc -l <"$action34e_controlled")" -eq 2 || return 1
    action34e_after=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' | wc -l) || return 1
    gate producer_enqueue_count test "$((action34e_after - action34e_before))" -eq 2 || return 1
    grep -Fq 'curl' /usr/local/libexec/lsyncd-sync-failure-notify.sh && return 1
    grep -Eq '\bcurl\b|APPRISE_(URL|KEY|ENDPOINT)' /usr/local/bin/keepalived-notify.sh && return 1
    gate runtime_metadata test "$(stat -c '%U:%G:%a' "$runtime_root")" = pi:pi:700 || return 1
    action34e_pi_identity=$(id -u pi):$(id -g pi)
    while IFS= read -r action34e_controlled_name; do
        [[ "$action34e_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 1
        gate "record_owner_${action34e_controlled_name%.json}" test \
            "$(stat -c '%u:%g:%a' "$queue_root/pending/$action34e_controlled_name")" = \
            "$action34e_pi_identity:600" || return 1
    done <"$action34e_controlled"
    install -o pi -g pi -m 0600 "$action34e_controlled" "$action34e_service_controlled" || return 1

    cat >"$action34e_mock" <<'MOCK'
#!/usr/bin/env bash
exit 28
MOCK
    chmod 0700 "$action34e_mock"
    install -o pi -g pi -m 0700 "$action34e_mock" "$action34e_service_mock" || return 1
    runuser --user pi -- env CADDY_APPRISE_TEST_MODE=1 \
        CADDY_APPRISE_CURL="$action34e_service_mock" \
        CADDY_APPRISE_EVENT_ALLOWLIST="$action34e_service_controlled" \
        /usr/local/libexec/caddy-apprise-delivery-worker || return 1
    while IFS= read -r action34e_controlled_name; do
        [[ "$action34e_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 1
        action34e_record=$queue_root/pending/$action34e_controlled_name
        [[ -f "$action34e_record" && ! -L "$action34e_record" ]] || return 1
        gate "retry_attempt_${action34e_controlled_name%.json}" test \
            "$(jq -r '.retry.attempt' "$action34e_record")" -eq 1 || return 1
    done <"$action34e_controlled"
    action34e_now=$(date +%s)
    while IFS= read -r action34e_controlled_name; do
        [[ "$action34e_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 1
        action34e_record=$queue_root/pending/$action34e_controlled_name
        [[ -f "$action34e_record" && ! -L "$action34e_record" ]] || return 1
        action34e_temporary=$(mktemp "$queue_root/pending/.action34e.XXXXXX") || return 1
        chmod 0600 "$action34e_temporary" || return 1
        jq --argjson now "$action34e_now" '.retry.next_attempt_epoch = $now' \
            "$action34e_record" >"$action34e_temporary" || return 1
        mv -f -- "$action34e_temporary" "$action34e_record" || return 1
    done <"$action34e_controlled"
    cat >"$action34e_mock" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
    chmod 0700 "$action34e_mock"
    install -o pi -g pi -m 0700 "$action34e_mock" "$action34e_service_mock" || return 1
    runuser --user pi -- env CADDY_APPRISE_TEST_MODE=1 \
        CADDY_APPRISE_CURL="$action34e_service_mock" \
        CADDY_APPRISE_EVENT_ALLOWLIST="$action34e_service_controlled" \
        /usr/local/libexec/caddy-apprise-delivery-worker || return 1
    gate controlled_queue_empty test "$(find "$queue_root/pending" "$queue_root/inflight" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 0 || return 1
    gate controlled_dead_letter_empty test "$(find "$queue_root/dead-letter" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 0 || return 1
    while IFS= read -r action34e_controlled_name; do
        [[ "$action34e_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 1
        rm -f -- "$queue_root/delivered/$action34e_controlled_name" || return 1
    done <"$action34e_controlled"
    rm -f -- "$action34e_service_mock" "$action34e_service_controlled" || return 1
    gate worker_lock_metadata test "$(stat -c '%U:%G:%a' "$runtime_root/worker.lock")" = pi:pi:600 || return 1
    if systemctl is-failed --quiet caddy-apprise-worker.service; then
        capture_command worker_reset_failed systemctl reset-failed \
            caddy-apprise-worker.service || return 1
    fi
    gate worker_not_failed_before_enable test \
        "$(systemctl is-failed caddy-apprise-worker.service 2>&1 || true)" != failed || return 1
    capture_command systemctl_enable systemctl enable --now \
        caddy-apprise-worker.path caddy-apprise-worker.timer || return 1
    capture_command worker_service_start systemctl start \
        caddy-apprise-worker.service || return 1
    gate worker_result_success test \
        "$(systemctl show -p Result --value caddy-apprise-worker.service)" = success || return 1
    gate worker_inactive_after_oneshot test \
        "$(systemctl show -p ActiveState --value caddy-apprise-worker.service)" = inactive || return 1
}

apply_action() {
    local action34e_stage
    local action34e_manifest
    local action34e_cursor

    [[ "$PWD" = / ]] || return 1
    install -d -o root -g root -m 0700 "$evidence_root" || return 1
    journalctl --show-cursor -n 0 -o cat >"$evidence_root/journal.cursor" || return 1
    action34e_cursor=$(sed -n 's/^-- cursor: //p' "$evidence_root/journal.cursor")
    [[ -n "$action34e_cursor" ]] || return 1
    baseline || return 1
    gate queue_baseline_absent test ! -e "$queue_root" || return 1
    [[ ! -e "$backup_root" ]] || return 1
    action34e_stage=$(mktemp -d /run/caddy-action34e-stage.XXXXXX) || return 1
    stage_path=$action34e_stage
    chmod 0700 "$action34e_stage" || return 1
    validate_payload "$action34e_stage" || return 1
    action34e_manifest=$action34e_stage/$artifact_manifest_relative
    gate action32g_runtime_baseline verify_runtime_baseline \
        "$action34e_stage/$runtime_baseline_relative" || return 1
    cleanup_failed_action34_payload || return 1
    verify_resume_baseline "$action34e_manifest" || return 1
    backup_artifacts "$action34e_stage" || return 1
    install_artifacts "$action34e_stage" || return 1
    systemctl daemon-reload || return 1
    systemd-tmpfiles --create /etc/tmpfiles.d/caddy-ha.conf || return 1
    verify_candidate_artifacts "$action34e_manifest" || return 1
    gate queue_metadata test "$(stat -c '%U:%G:%a' "$queue_root")" = pi:pi:700 || return 1
    exercise_queue || return 1
    gate path_enabled systemctl is-enabled --quiet caddy-apprise-worker.path || return 1
    gate path_active systemctl is-active --quiet caddy-apprise-worker.path || return 1
    gate timer_enabled systemctl is-enabled --quiet caddy-apprise-worker.timer || return 1
    gate timer_active systemctl is-active --quiet caddy-apprise-worker.timer || return 1
    gate worker_static test "$(systemctl is-enabled caddy-apprise-worker.service 2>&1 || true)" = static || return 1
    baseline || return 1
    journalctl --after-cursor "$action34e_cursor" -o short-iso --no-pager \
        >"$evidence_root/journal.log" || return 1
    chmod 0600 "$evidence_root/journal.log" || return 1
    grep -Eq 'event=(enqueued|attempt|retry-scheduled|delivered)' "$evidence_root/journal.log" || return 1
    cleanup_current_payload || return 1
    mutation_started=false
    printf '%s_%s_backup_root=%s\n' "$prefix" "${role//-/_}" "$backup_root"
    printf '%s_%s_evidence_root=%s\n' "$prefix" "${role//-/_}" "$evidence_root"
    printf '%s_%s_apply_complete=true\n' "$prefix" "${role//-/_}"
}

rollback_action() {
    local action34e_state action34e_target
    [[ -f "$backup_root/mutation-started" && ! -L "$backup_root/mutation-started" ]] || return 125
    [[ -f "$backup_root/backup-complete" && ! -L "$backup_root/backup-complete" ]] || return 125
    [[ -f "$backup_root/baseline.tsv" && ! -L "$backup_root/baseline.tsv" ]] || return 125
    systemctl disable --now caddy-apprise-worker.path caddy-apprise-worker.timer >/dev/null 2>&1 || true
    while IFS=$'\t' read -r action34e_state action34e_target; do
        case "$action34e_state" in
            present)
                [[ -e "$backup_root/files$action34e_target" || -L "$backup_root/files$action34e_target" ]] || return 125
                cp -a --remove-destination "$backup_root/files$action34e_target" "$action34e_target" || return 125
                ;;
            absent) rm -f -- "$action34e_target" || return 125 ;;
            *) return 125 ;;
        esac
    done <"$backup_root/baseline.tsv"
    if [[ -f "$evidence_root/controlled-records" && ! -L "$evidence_root/controlled-records" ]]; then
        while IFS= read -r action34e_controlled_name; do
            [[ "$action34e_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 125
            rm -f -- "$queue_root"/{pending,inflight,dead-letter,delivered}/"$action34e_controlled_name" || return 125
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
    systemctl reset-failed caddy-apprise-worker.service >/dev/null 2>&1 || true
    [[ "$(systemctl is-failed caddy-apprise-worker.service 2>&1 || true)" != failed ]] || return 125
    baseline || return 125
    printf '%s_%s_rollback_complete=true\n' "$prefix" "${role//-/_}"
}

cleanup_current_payload() {
    [[ "$payload_archive" = /tmp/caddy-action34e-payload-* ]] || return 0
    if [[ -e "$payload_archive" || -L "$payload_archive" ]]; then
        [[ -f "$payload_archive" && ! -L "$payload_archive" ]] || return 1
        [[ "$(file_hash "$payload_archive")" = "$payload_sha256" ]] || return 1
        rm -f -- "$payload_archive" || return 1
    fi
    [[ ! -e "$payload_archive" && ! -L "$payload_archive" ]]
}

cleanup_unmutated_backup() {
    [[ "$backup_root" =~ ^/var/backups/caddy-ha/action34e-node-[ab]-[0-9]{10,20}-[0-9]+$ ]] || return 1
    [[ ! -e "$backup_root/mutation-started" && ! -L "$backup_root/mutation-started" ]] || return 1
    if [[ -e "$backup_root" || -L "$backup_root" ]]; then
        [[ -d "$backup_root" && ! -L "$backup_root" ]] || return 1
        rm -rf -- "$backup_root" || return 1
    fi
    [[ ! -e "$backup_root" && ! -L "$backup_root" ]]
}

recover_action() {
    if [[ -f "$backup_root/mutation-started" && ! -L "$backup_root/mutation-started" ]]; then
        rollback_action || return 125
        printf '%s_%s_recovery_mutation_rollback=true\n' "$prefix" "${role//-/_}"
        return 0
    fi
    cleanup_current_payload || return 1
    cleanup_unmutated_backup || return 1
    baseline || return 1
    gate recovery_queue_absent test ! -e "$queue_root" || return 1
    printf '%s_%s_recovery_pre_mutation_cleanup=true\n' "$prefix" "${role//-/_}"
}

verify_current() {
    local action34e_manifest=$backup_root/artifacts.tsv
    baseline || return 1
    verify_candidate_artifacts "$action34e_manifest" || return 1
    gate action32g_runtime_baseline verify_runtime_baseline \
        "$backup_root/runtime-baseline.tsv" "$action34e_manifest" || return 1
    gate pending_empty test "$(find "$queue_root/pending" "$queue_root/inflight" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 0 || return 1
    gate dead_letter_empty test "$(find "$queue_root/dead-letter" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 0 || return 1
    gate path_enabled systemctl is-enabled --quiet caddy-apprise-worker.path || return 1
    gate timer_enabled systemctl is-enabled --quiet caddy-apprise-worker.timer || return 1
    printf '%s_%s_verify_complete=true\n' "$prefix" "${role//-/_}"
}

# shellcheck disable=SC2317
cleanup_on_exit() {
    local action34e_status=$?
    trap - EXIT
    [[ -z "$stage_path" ]] || rm -rf -- "$stage_path"
    if [[ "$action34e_status" -ne 0 && "$mutation_started" = true ]]; then
        if rollback_action; then
            printf '%s_%s_automatic_rollback=true\n' "$prefix" "${role//-/_}" >&2
        else
            printf '%s_%s_manual_intervention_required=true\n' "$prefix" "${role//-/_}" >&2
            exit 125
        fi
    elif [[ "$action34e_status" -ne 0 ]]; then
        if cleanup_current_payload && cleanup_unmutated_backup; then
            printf '%s_%s_pre_mutation_cleanup_complete=true\n' \
                "$prefix" "${role//-/_}" >&2
        else
            printf '%s_%s_pre_mutation_cleanup_incomplete=true\n' \
                "$prefix" "${role//-/_}" >&2
        fi
    fi
    exit "$action34e_status"
}

if [[ "$mode" = --library-test ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi

trap cleanup_on_exit EXIT

case "$mode" in
    --apply) apply_action ;;
    --rollback) rollback_action ;;
    --recover) recover_action ;;
    --verify-current) verify_current ;;
    *) exit 64 ;;
esac
