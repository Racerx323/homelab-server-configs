#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_30b_remote
readonly backup_directory=/var/backups/caddy-ha/action30b-systemd-boot-persistence
readonly evidence_root=/tmp/caddy-action30b
readonly obsolete_path=/etc/systemd/system/caddy-validate-reload.path
readonly obsolete_service=/etc/systemd/system/caddy-validate-reload.service
readonly obsolete_path_sha256=f7fde941ae045e5697aa9e966e4f9a40d55a1f08f413f02cf9f8775046331bb7
readonly obsolete_service_sha256=51be7495194143210bf805fdaa78072162eed028e8da3b3507f73f416cde8322
readonly cert_timer=/etc/systemd/system/caddy-cert-expiry.timer
readonly cert_timer_sha256=409a4494eff683c602ceced8d076eed1e9681e5d351665b54a3e614afb7f05f7
readonly health_timer=/etc/systemd/system/caddy-sync-health.timer
readonly health_timer_sha256=65bd3ff8f969301f17d6fdf457a8b6b1676489f5e536612cab57d61e0c6bdf8e
readonly reconcile_path=/etc/systemd/system/caddy-sync-reconcile.path
readonly reconcile_path_sha256=c8c11582580326300035c1b6e8dc97cb6b90052683b57836cc3afdcdd436f295
readonly -a persistent_units=(
    caddy.service
    caddy-lsyncd.service
    caddy-sync-reconcile.path
    caddy-cert-expiry.timer
    caddy-sync-health.timer
)
readonly -a static_units=(
    emergency.service
    caddy-cert-expiry.service
    caddy-sync-failure@.service
    caddy-sync-health.service
    caddy-sync-reconcile.service
)
readonly distribution_lsyncd_unit=lsyncd.service
readonly lsyncd_status_file=${CADDY_ACTION30B_STATUS_FILE:-/run/caddy-lsyncd/status}
readonly maximum_lsyncd_status_age=120
readonly lsyncd_status_wait_seconds=45
readonly releases_root=/etc/caddy/releases
readonly current_link=/etc/caddy/current
readonly outbound_root=/var/lib/caddy-sync/outbound
readonly quarantine_root=/var/lib/caddy-sync/quarantine
readonly historical_revision=20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4
readonly historical_parent=20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63
readonly accepted_current_revision=20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04
readonly historical_node_a_quarantine=$quarantine_root/node-b-$historical_revision
readonly protected_node_b_outbound=$quarantine_root/node-b-outbound-$historical_revision-action30b
readonly lsyncd_stability_samples=5
readonly lsyncd_stability_delay_seconds=2

role=
node_token=
expected_hostname=
capture_directory=
mutation_started=false
transaction_complete=false
sync_journal_cursor=
semantic_fixture_root=

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_revision() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
safe_stream() {
    local action30b_stream=$1

    [[ "$(wc -c <"$action30b_stream")" -le 1048576 ]] || return 1
    [[ "$(line_count "$action30b_stream")" -le 8192 ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action30b_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action30b_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action30b_stream"
}
emit_stream() {
    local action30b_label=$1
    local action30b_stream=$2

    printf '%s_%s_%s_bytes=%s\n' "$prefix" "$node_token" "$action30b_label" "$(wc -c <"$action30b_stream")"
    printf '%s_%s_%s_lines=%s\n' "$prefix" "$node_token" "$action30b_label" "$(line_count "$action30b_stream")"
    printf '%s_%s_%s_sha256=%s\n' "$prefix" "$node_token" "$action30b_label" "$(file_hash "$action30b_stream")"
    safe_stream "$action30b_stream" || return 97
    printf '%s_%s_%s_classification=bounded_safe\n' "$prefix" "$node_token" "$action30b_label"
    if [[ -s "$action30b_stream" ]]; then
        printf '%s_%s_%s_begin\n' "$prefix" "$node_token" "$action30b_label"
        cat "$action30b_stream"
        printf '%s_%s_%s_end\n' "$prefix" "$node_token" "$action30b_label"
    else
        printf '%s_%s_%s_content=empty\n' "$prefix" "$node_token" "$action30b_label"
    fi
}
check() {
    local action30b_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action30b_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "$node_token" "$action30b_label" >&2
    return 1
}
run_captured() {
    local action30b_label=$1
    local action30b_stdout=$capture_directory/$action30b_label.stdout
    local action30b_stderr=$capture_directory/$action30b_label.stderr
    local action30b_status_file=$capture_directory/$action30b_label.status
    local action30b_status=0

    shift
    install -m 0600 /dev/null "$action30b_stdout" || return 1
    install -m 0600 /dev/null "$action30b_stderr" || return 1
    install -m 0600 /dev/null "$action30b_status_file" || return 1
    "$@" >"$action30b_stdout" 2>"$action30b_stderr" || action30b_status=$?
    printf '%s\n' "$action30b_status" >"$action30b_status_file"
    printf '%s_%s_%s_status=%s\n' "$prefix" "$node_token" "$action30b_label" "$action30b_status"
    emit_stream "${action30b_label}_stdout" "$action30b_stdout" || return $?
    emit_stream "${action30b_label}_stderr" "$action30b_stderr" || return $?
    [[ "$action30b_status" -eq 0 ]]
}
cursor_from_capture() {
    local action30b_label=$1
    local action30b_capture=$capture_directory/$action30b_label.stdout

    awk '
        /^-- cursor: / {
            cursor = substr($0, 12)
            found++
        }
        END {
            if (found != 1 || cursor !~ /^s=/) exit 1
            print cursor
        }
    ' "$action30b_capture"
}
capture_cursor() {
    local action30b_label=$1

    run_captured "$action30b_label" journalctl --show-cursor -n 0 --no-pager || return 1
    cursor_from_capture "$action30b_label" >/dev/null
}
manifest_paths_safe() {
    local action30b_manifest=$1

    awk '
        length($0) == 0 { bad = 1; next }
        {
            hash = substr($0, 1, 64)
            separator = substr($0, 65, 2)
            path = substr($0, 67)
            if (length(hash) != 64 ||
                hash !~ /^[0-9a-f]+$/ ||
                separator != "  " ||
                path !~ /^[.][/][^[:cntrl:]]+$/ ||
                path ~ /(^|[/])[.][.]([/]|$)/ ||
                path ~ /[/][/]/ ||
                path ~ /[/][.]([/]|$)/ ||
                path ~ /[/]$/) bad = 1
        }
        END { exit bad ? 1 : 0 }
    ' "$action30b_manifest"
}
manifest_file_set_matches() {
    local action30b_release=$1
    local action30b_expected
    local action30b_observed
    local action30b_status=0

    action30b_expected=$(mktemp /tmp/action30b-manifest-expected.XXXXXX) || return 1
    action30b_observed=$(mktemp /tmp/action30b-manifest-observed.XXXXXX) || {
        rm -f -- "$action30b_expected"
        return 1
    }
    awk '{ print substr($0, 67) }' "$action30b_release/manifest.sha256" |
        LC_ALL=C sort -u >"$action30b_expected"
    (
        cd "$action30b_release"
        find . -type f \
            ! -path ./manifest.sha256 \
            ! -path ./.finalize-request \
            ! -path ./.complete \
            ! -path ./.complete.pending -print |
            LC_ALL=C sort
    ) >"$action30b_observed"
    cmp -s "$action30b_expected" "$action30b_observed" || action30b_status=$?
    rm -f -- "$action30b_expected" "$action30b_observed"
    [[ "$action30b_status" -eq 0 ]]
}
manifest_valid() {
    local action30b_release=$1

    [[ -d "$action30b_release" && ! -L "$action30b_release" ]] || return 1
    [[ -f "$action30b_release/release-manifest.json" &&
        ! -L "$action30b_release/release-manifest.json" ]] || return 1
    [[ -f "$action30b_release/manifest.sha256" &&
        ! -L "$action30b_release/manifest.sha256" ]] || return 1
    [[ -z "$(find "$action30b_release" -type l -print -quit)" ]] || return 1
    [[ -z "$(find "$action30b_release" ! -type d ! -type f -print -quit)" ]] || return 1
    [[ -z "$(find "$action30b_release" -type f -links +1 -print -quit)" ]] || return 1
    jq -e '
        (.revision | type == "string" and length > 0) and
        (.parent_revision | type == "string") and
        (.source_node == "node-a" or .source_node == "node-b") and
        (.created_at | type == "string" and length > 0)
    ' "$action30b_release/release-manifest.json" >/dev/null || return 1
    manifest_paths_safe "$action30b_release/manifest.sha256" || return 1
    manifest_file_set_matches "$action30b_release" || return 1
    (cd "$action30b_release" &&
        sha256sum --strict --check manifest.sha256 >/dev/null 2>&1)
}
release_identity_exact() {
    local action30b_release=$1
    local action30b_revision=$2
    local action30b_parent=$3
    local action30b_source=$4

    manifest_valid "$action30b_release" || return 1
    [[ "$(jq -r '.revision // empty' "$action30b_release/release-manifest.json")" = "$action30b_revision" ]] || return 1
    [[ "$(jq -r '.parent_revision // empty' "$action30b_release/release-manifest.json")" = "$action30b_parent" ]] || return 1
    [[ "$(jq -r '.source_node // empty' "$action30b_release/release-manifest.json")" = "$action30b_source" ]]
}
current_release_inventory() {
    local action30b_resolved
    local action30b_revision
    local action30b_parent
    local action30b_source

    [[ -L "$current_link" ]] || return 1
    action30b_resolved=$(readlink -f -- "$current_link") || return 1
    [[ "$action30b_resolved" = "$releases_root/$accepted_current_revision" ]] || return 1
    manifest_valid "$action30b_resolved" || return 1
    action30b_revision=$(jq -r '.revision // empty' "$action30b_resolved/release-manifest.json") || return 1
    action30b_parent=$(jq -r '.parent_revision // empty' "$action30b_resolved/release-manifest.json") || return 1
    action30b_source=$(jq -r '.source_node // empty' "$action30b_resolved/release-manifest.json") || return 1
    [[ "$action30b_revision" = "$accepted_current_revision" ]] || return 1
    [[ "$action30b_source" = node-a ]] || return 1
    printf 'current_path=%s\n' "$action30b_resolved"
    printf 'current_revision=%s\n' "$action30b_revision"
    printf 'current_parent=%s\n' "$action30b_parent"
    printf 'current_source=%s\n' "$action30b_source"
    printf 'current_release_manifest_sha256=%s\n' \
        "$(file_hash "$action30b_resolved/release-manifest.json")"
    printf 'current_payload_manifest_sha256=%s\n' \
        "$(file_hash "$action30b_resolved/manifest.sha256")"
}
historical_quarantine_exact() {
    release_identity_exact "$historical_node_a_quarantine" \
        "$historical_revision" "$historical_parent" node-b || return 1
    [[ -f "$historical_node_a_quarantine/.finalize-request" &&
        ! -L "$historical_node_a_quarantine/.finalize-request" &&
        ! -s "$historical_node_a_quarantine/.finalize-request" ]] || return 1
    [[ -f "$historical_node_a_quarantine/.complete" &&
        ! -L "$historical_node_a_quarantine/.complete" &&
        ! -s "$historical_node_a_quarantine/.complete" ]] || return 1
    printf 'historical_quarantine_path=%s\n' "$historical_node_a_quarantine"
    printf 'historical_quarantine_revision=%s\n' "$historical_revision"
    printf 'historical_quarantine_parent=%s\n' "$historical_parent"
    printf 'historical_quarantine_source=node-b\n'
    printf 'historical_quarantine_release_manifest_sha256=%s\n' \
        "$(file_hash "$historical_node_a_quarantine/release-manifest.json")"
    printf 'historical_quarantine_payload_manifest_sha256=%s\n' \
        "$(file_hash "$historical_node_a_quarantine/manifest.sha256")"
}
outbound_candidate_admissible() {
    local action30b_candidate_role=$1
    local action30b_candidate_path=$2

    case "$action30b_candidate_role" in
        node-a)
            manifest_valid "$action30b_candidate_path" || return 1
            [[ "${action30b_candidate_path##*/}" = "$accepted_current_revision" ]] || return 1
            [[ "$(jq -r '.revision // empty' "$action30b_candidate_path/release-manifest.json")" = "$accepted_current_revision" ]] || return 1
            [[ "$(jq -r '.source_node // empty' "$action30b_candidate_path/release-manifest.json")" = node-a ]]
            ;;
        node-b)
            release_identity_exact "$action30b_candidate_path" \
                "$historical_revision" "$historical_parent" node-b
            ;;
        *) return 1 ;;
    esac
}
outbound_inventory() {
    local action30b_candidate
    local action30b_candidate_count=0
    local action30b_inventory
    local action30b_inventory_status=0
    local action30b_unsafe_entry

    [[ -d "$outbound_root" && ! -L "$outbound_root" ]] || return 1
    action30b_unsafe_entry=$(find "$outbound_root" -mindepth 1 -maxdepth 1 \
        \( ! -type d -o -name '.*' \) -print -quit) || return 1
    [[ -z "$action30b_unsafe_entry" ]] || return 1
    action30b_inventory=$(mktemp /tmp/action30b-outbound-inventory.XXXXXX) || return 1
    if ! find "$outbound_root" -mindepth 1 -maxdepth 1 -type d \
        ! -name '.*' -print | LC_ALL=C sort >"$action30b_inventory"; then
        rm -f -- "$action30b_inventory"
        return 1
    fi
    while IFS= read -r action30b_candidate; do
        [[ -n "$action30b_candidate" ]] || continue
        action30b_candidate_count=$((action30b_candidate_count + 1))
        manifest_valid "$action30b_candidate" || {
            action30b_inventory_status=1
            break
        }
        printf 'outbound_candidate_%s=%s\n' "$action30b_candidate_count" \
            "${action30b_candidate##*/}"
        printf 'outbound_candidate_%s_parent=%s\n' "$action30b_candidate_count" \
            "$(jq -r '.parent_revision // empty' "$action30b_candidate/release-manifest.json")"
        printf 'outbound_candidate_%s_source=%s\n' "$action30b_candidate_count" \
            "$(jq -r '.source_node // empty' "$action30b_candidate/release-manifest.json")"
        outbound_candidate_admissible "$role" "$action30b_candidate" || {
            action30b_inventory_status=1
            break
        }
    done <"$action30b_inventory"
    rm -f -- "$action30b_inventory"
    [[ "$action30b_inventory_status" -eq 0 ]] || return 1
    [[ "$action30b_candidate_count" -le 1 ]] || return 1
    printf 'outbound_candidate_count=%s\n' "$action30b_candidate_count"
    if [[ "$role" = node-b && "$action30b_candidate_count" -eq 0 ]]; then
        printf 'node_b_emergency_only_outbound=clear\n'
    elif [[ "$role" = node-b ]]; then
        printf 'node_b_emergency_only_outbound=historical_quarantine_required\n'
    else
        printf 'node_a_normal_outbound=admissible\n'
    fi
}
semantic_inventory() {
    current_release_inventory || return 1
    outbound_inventory || return 1
    if [[ "$role" = node-a ]]; then
        historical_quarantine_exact || return 1
    fi
}
protect_stale_node_b_outbound() {
    local action30b_stale=$outbound_root/$historical_revision

    [[ "$role" = node-b ]] || return 0
    if [[ -e "$protected_node_b_outbound" || -L "$protected_node_b_outbound" ]]; then
        [[ ! -e "$action30b_stale" && ! -L "$action30b_stale" ]] || return 1
        release_identity_exact "$protected_node_b_outbound" \
            "$historical_revision" "$historical_parent" node-b || return 1
        printf 'protected_outbound_state=already_quarantined\n'
        return 0
    fi
    if [[ ! -e "$action30b_stale" && ! -L "$action30b_stale" ]]; then
        printf 'protected_outbound_state=not_present\n'
        return 0
    fi
    release_identity_exact "$action30b_stale" \
        "$historical_revision" "$historical_parent" node-b || return 1
    mv -- "$action30b_stale" "$protected_node_b_outbound" || return 1
    release_identity_exact "$protected_node_b_outbound" \
        "$historical_revision" "$historical_parent" node-b || return 1
    [[ ! -e "$action30b_stale" && ! -L "$action30b_stale" ]] || return 1
    printf 'protected_outbound_state=quarantined_before_restart\n'
}
node_b_outbound_clear() {
    local action30b_observed

    [[ "$role" = node-b ]] || return 0
    action30b_observed=$(find "$outbound_root" -mindepth 1 -maxdepth 1 \
        -type d ! -name '.*' -print -quit) || return 1
    [[ -z "$action30b_observed" ]]
}
lsyncd_stable() {
    local action30b_initial_pid
    local action30b_initial_restarts
    local action30b_sample
    local action30b_observed_pid
    local action30b_observed_restarts

    action30b_initial_pid=$(systemctl show caddy-lsyncd.service -p MainPID --value) || return 1
    action30b_initial_restarts=$(systemctl show caddy-lsyncd.service -p NRestarts --value) || return 1
    [[ "$action30b_initial_pid" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ "$action30b_initial_restarts" =~ ^[0-9]+$ ]] || return 1
    printf 'lsyncd_stability_initial_pid=%s\n' "$action30b_initial_pid"
    printf 'lsyncd_stability_initial_restarts=%s\n' "$action30b_initial_restarts"
    for ((action30b_sample = 1; action30b_sample <= lsyncd_stability_samples; action30b_sample++)); do
        systemctl is-active --quiet caddy-lsyncd.service || return 1
        [[ "$(systemctl show caddy-lsyncd.service -p SubState --value)" = running ]] || return 1
        [[ "$(systemctl show caddy-lsyncd.service -p Result --value)" = success ]] || return 1
        action30b_observed_pid=$(systemctl show caddy-lsyncd.service -p MainPID --value) || return 1
        action30b_observed_restarts=$(systemctl show caddy-lsyncd.service -p NRestarts --value) || return 1
        [[ "$action30b_observed_pid" = "$action30b_initial_pid" ]] || return 1
        [[ "$action30b_observed_restarts" = "$action30b_initial_restarts" ]] || return 1
        lsyncd_status_fresh || return 1
        printf 'lsyncd_stability_sample_%s=true\n' "$action30b_sample"
        if [[ "$action30b_sample" -lt "$lsyncd_stability_samples" ]]; then
            sleep "$lsyncd_stability_delay_seconds"
        fi
    done
}
post_cursor_transport_clean() {
    local action30b_journal=$capture_directory/sync_post_cursor_journal.stdout

    [[ -f "$action30b_journal" ]] || return 1
    ! grep -Eqi \
        'Quarantined divergent release|systemd unit failed: caddy-(lsyncd|sync-reconcile)[.]service|rsync([^[:alnum:]]|$).*error|rrsync([^[:alnum:]]|$).*error|connection unexpectedly closed|Permission denied|Host key verification failed' \
        "$action30b_journal"
}
enabled_exact() {
    [[ "$(systemctl is-enabled "$1" 2>/dev/null || true)" = "$2" ]]
}
active_exact() {
    [[ "$(systemctl is-active "$1" 2>/dev/null || true)" = "$2" ]]
}
unit_not_failed() {
    [[ "$(systemctl is-failed "$1" 2>/dev/null || true)" != failed ]]
}
static_enablement_contract() {
    local action30b_unit

    for action30b_unit in "${static_units[@]}"; do
        enabled_exact "$action30b_unit" static || return 1
    done
}
lsyncd_status_age() {
    local action30b_now
    local action30b_modified

    [[ -f "$lsyncd_status_file" && ! -L "$lsyncd_status_file" && -s "$lsyncd_status_file" ]] || return 1
    action30b_now=$(date +%s) || return 1
    action30b_modified=$(stat -c %Y "$lsyncd_status_file") || return 1
    [[ "$action30b_modified" -le "$action30b_now" ]] || return 1
    printf '%s\n' "$((action30b_now - action30b_modified))"
}
lsyncd_status_fresh() {
    local action30b_age

    action30b_age=$(lsyncd_status_age) || return 1
    [[ "$action30b_age" -le "$maximum_lsyncd_status_age" ]]
}
wait_for_fresh_lsyncd_status() {
    local action30b_waited=0

    while [[ "$action30b_waited" -lt "$lsyncd_status_wait_seconds" ]]; do
        if lsyncd_status_fresh; then
            printf '%s_%s_lsyncd_status_wait_seconds=%s\n' "$prefix" "$node_token" "$action30b_waited"
            return 0
        fi
        sleep 1
        action30b_waited=$((action30b_waited + 1))
    done
    return 1
}

wait_for_lsyncd_status_advance() {
    local action30b_initial_mtime
    local action30b_current_mtime
    local action30b_waited=0

    action30b_initial_mtime=$(stat -c %Y "$lsyncd_status_file") || return 1
    printf '%s_%s_lsyncd_status_mtime_initial=%s\n' "$prefix" "$node_token" "$action30b_initial_mtime"
    while [[ "$action30b_waited" -lt "$lsyncd_status_wait_seconds" ]]; do
        sleep 1
        action30b_waited=$((action30b_waited + 1))
        action30b_current_mtime=$(stat -c %Y "$lsyncd_status_file" 2>/dev/null || true)
        if [[ "$action30b_current_mtime" =~ ^[0-9]+$ &&
            "$action30b_current_mtime" -gt "$action30b_initial_mtime" ]]; then
            printf '%s_%s_lsyncd_status_mtime_advanced=%s\n' "$prefix" "$node_token" "$action30b_current_mtime"
            printf '%s_%s_lsyncd_status_advance_wait_seconds=%s\n' "$prefix" "$node_token" "$action30b_waited"
            return 0
        fi
    done
    return 1
}
emit_unit_properties() {
    local action30b_label=$1
    local action30b_unit=$2

    run_captured "$action30b_label" systemctl show "$action30b_unit" \
        -p LoadState -p UnitFileState -p ActiveState -p SubState -p Result -p ExecMainStatus
}
successful_static_worker() {
    local action30b_unit=$1

    enabled_exact "$action30b_unit" static || return 1
    unit_not_failed "$action30b_unit" || return 1
    [[ "$(systemctl show "$action30b_unit" -p Result --value 2>/dev/null || true)" = success ]] || return 1
    [[ "$(systemctl show "$action30b_unit" -p ExecMainStatus --value 2>/dev/null || true)" = 0 ]]
}
continuity() {
    check uid_root test "$(id -u)" -eq 0 || return 1
    check working_directory_root test "$PWD" = / || return 1
    check hostname_exact test "$(hostname)" = "$expected_hostname" || return 1
    check caddy_active active_exact caddy.service active || return 1
    check lsyncd_active active_exact caddy-lsyncd.service active || return 1
    check reconcile_path_active active_exact caddy-sync-reconcile.path active || return 1
    check keepalived_active active_exact keepalived.service active || return 1
    check lighttpd_active active_exact lighttpd.service active || return 1
}
target_contract() {
    local action30b_unit

    continuity || return 1
    for action30b_unit in "${persistent_units[@]}"; do
        check "${action30b_unit//[^a-zA-Z0-9]/_}_enabled" enabled_exact "$action30b_unit" enabled || return 1
        check "${action30b_unit//[^a-zA-Z0-9]/_}_active" active_exact "$action30b_unit" active || return 1
    done
    check caddy_api_masked enabled_exact caddy-api.service masked || return 1
    check caddy_api_inactive active_exact caddy-api.service inactive || return 1
    check distribution_lsyncd_masked enabled_exact "$distribution_lsyncd_unit" masked || return 1
    check distribution_lsyncd_inactive active_exact "$distribution_lsyncd_unit" inactive || return 1
    check emergency_service_static enabled_exact emergency.service static || return 1
    check emergency_service_nonfailed unit_not_failed emergency.service || return 1
    check cert_worker_static enabled_exact caddy-cert-expiry.service static || return 1
    check cert_worker_success successful_static_worker caddy-cert-expiry.service || return 1
    check health_worker_static enabled_exact caddy-sync-health.service static || return 1
    check health_worker_success successful_static_worker caddy-sync-health.service || return 1
    check failure_worker_static enabled_exact caddy-sync-failure@.service static || return 1
    check failure_worker_nonfailed unit_not_failed caddy-sync-failure@.service || return 1
    check reconcile_worker_static enabled_exact caddy-sync-reconcile.service static || return 1
    check reconcile_worker_nonfailed unit_not_failed caddy-sync-reconcile.service || return 1
    check lsyncd_status_fresh lsyncd_status_fresh || return 1
    run_captured target_semantic_inventory semantic_inventory || return 1
    check node_b_outbound_clear node_b_outbound_clear || return 1
    check cert_timer_hash test "$(file_hash "$cert_timer")" = "$cert_timer_sha256" || return 1
    check health_timer_hash test "$(file_hash "$health_timer")" = "$health_timer_sha256" || return 1
    check reconcile_path_hash test "$(file_hash "$reconcile_path")" = "$reconcile_path_sha256" || return 1
    check obsolete_path_absent test ! -e "$obsolete_path" || return 1
    check obsolete_service_absent test ! -e "$obsolete_service" || return 1
    check validate_path_not_loaded test "$(systemctl show caddy-validate-reload.path -p LoadState --value 2>/dev/null || true)" = not-found || return 1
    check validate_service_not_loaded test "$(systemctl show caddy-validate-reload.service -p LoadState --value 2>/dev/null || true)" = not-found || return 1
}
manifest_value() {
    local action30b_key=$1

    awk -F= -v key="$action30b_key" '$1 == key { print $2; found++ } END { if (found != 1) exit 1 }' \
        "$backup_directory/manifest"
}
record_backup() {
    local action30b_unit
    local action30b_backup_staging=${backup_directory}.staging.$$

    if ! install -d -o root -g root -m 0700 "$action30b_backup_staging"; then
        return 1
    fi
    if ! install -o root -g root -m 0600 "$obsolete_path" \
        "$action30b_backup_staging/caddy-validate-reload.path" ||
        ! install -o root -g root -m 0600 "$obsolete_service" \
            "$action30b_backup_staging/caddy-validate-reload.service"; then
        rm -rf -- "$action30b_backup_staging"
        return 1
    fi
    {
        printf 'action=30a\nrole=%s\n' "$role"
        for action30b_unit in "${persistent_units[@]}" caddy-api.service "$distribution_lsyncd_unit" caddy-validate-reload.path; do
            printf 'enabled_%s=%s\n' "${action30b_unit//[^a-zA-Z0-9]/_}" \
                "$(systemctl is-enabled "$action30b_unit" 2>/dev/null || true)"
            printf 'active_%s=%s\n' "${action30b_unit//[^a-zA-Z0-9]/_}" \
                "$(systemctl is-active "$action30b_unit" 2>/dev/null || true)"
        done
    } >"$action30b_backup_staging/manifest" || {
        rm -rf -- "$action30b_backup_staging"
        return 1
    }
    if ! chmod 0600 "$action30b_backup_staging/manifest" ||
        ! mv -- "$action30b_backup_staging" "$backup_directory"; then
        rm -rf -- "$action30b_backup_staging"
        return 1
    fi
}
restore_enablement() {
    local action30b_unit=$1
    local action30b_token=${action30b_unit//[^a-zA-Z0-9]/_}
    local action30b_state
    local action30b_active

    action30b_state=$(manifest_value "enabled_$action30b_token") || return 1
    action30b_active=$(manifest_value "active_$action30b_token") || return 1
    case "$action30b_state" in
        enabled) systemctl enable "$action30b_unit" >/dev/null 2>&1 || return 1 ;;
        disabled) systemctl disable "$action30b_unit" >/dev/null 2>&1 || return 1 ;;
        masked) systemctl mask "$action30b_unit" >/dev/null 2>&1 || return 1 ;;
        static | indirect | generated | transient | '') ;;
        *) return 1 ;;
    esac
    case "$action30b_active" in
        active) systemctl start "$action30b_unit" >/dev/null 2>&1 || return 1 ;;
        inactive) systemctl stop "$action30b_unit" >/dev/null 2>&1 || return 1 ;;
        failed) return 1 ;;
        *) ;;
    esac
}
rollback() {
    local action30b_unit

    check backup_manifest_regular test -f "$backup_directory/manifest" || return 1
    install -o root -g root -m 0644 "$backup_directory/caddy-validate-reload.path" "$obsolete_path" || return 1
    install -o root -g root -m 0644 "$backup_directory/caddy-validate-reload.service" "$obsolete_service" || return 1
    systemctl daemon-reload || return 1
    for action30b_unit in "${persistent_units[@]}" caddy-api.service "$distribution_lsyncd_unit" caddy-validate-reload.path; do
        restore_enablement "$action30b_unit" || return 1
    done
    continuity || return 1
    printf '%s_%s_rollback_complete=true\n' "$prefix" "$node_token"
}
apply() {
    local action30b_cert_journal_cursor
    local action30b_health_journal_cursor
    local action30b_status_age

    continuity || return 1
    run_captured semantic_inventory_before semantic_inventory || return 1
    capture_cursor sync_journal_cursor || return 1
    sync_journal_cursor=$(cursor_from_capture sync_journal_cursor) || return 1
    check backup_absent test ! -e "$backup_directory" || return 1
    check obsolete_path_regular test -f "$obsolete_path" || return 1
    check obsolete_path_not_symlink test ! -L "$obsolete_path" || return 1
    check obsolete_path_hash test "$(file_hash "$obsolete_path")" = "$obsolete_path_sha256" || return 1
    check obsolete_service_regular test -f "$obsolete_service" || return 1
    check obsolete_service_not_symlink test ! -L "$obsolete_service" || return 1
    check obsolete_service_hash test "$(file_hash "$obsolete_service")" = "$obsolete_service_sha256" || return 1
    check obsolete_path_inactive active_exact caddy-validate-reload.path inactive || return 1
    check caddy_api_masked_before enabled_exact caddy-api.service masked || return 1
    check caddy_api_inactive_before active_exact caddy-api.service inactive || return 1
    check distribution_lsyncd_masked_before enabled_exact "$distribution_lsyncd_unit" masked || return 1
    check distribution_lsyncd_inactive_before active_exact "$distribution_lsyncd_unit" inactive || return 1
    check static_enablement_before static_enablement_contract || return 1
    record_backup || return 1
    mutation_started=true
    if [[ "$role" = node-b &&
        (-e "$outbound_root/$historical_revision" ||
        -L "$outbound_root/$historical_revision") ]]; then
        run_captured stop_lsyncd_for_outbound_quarantine \
            systemctl stop caddy-lsyncd.service || return 1
    fi
    run_captured protect_stale_outbound protect_stale_node_b_outbound || return 1
    check node_b_outbound_clear_before_restart node_b_outbound_clear || return 1
    if action30b_status_age=$(lsyncd_status_age 2>/dev/null); then
        printf '%s_%s_lsyncd_status_age_before=%s\n' "$prefix" "$node_token" "$action30b_status_age"
    else
        printf '%s_%s_lsyncd_status_age_before=unavailable\n' "$prefix" "$node_token"
    fi
    if ! systemctl is-active --quiet caddy-lsyncd.service ||
        ! lsyncd_status_fresh; then
        run_captured restart_managed_lsyncd systemctl restart caddy-lsyncd.service || return 1
    else
        printf '%s_%s_restart_managed_lsyncd=not_required\n' "$prefix" "$node_token"
    fi
    check lsyncd_status_fresh_after_wait wait_for_fresh_lsyncd_status || return 1
    printf '%s_%s_lsyncd_status_age_after=%s\n' "$prefix" "$node_token" "$(lsyncd_status_age)"
    check lsyncd_status_writer_advances wait_for_lsyncd_status_advance || return 1
    check lsyncd_status_fresh_after_advance lsyncd_status_fresh || return 1
    if systemctl is-failed --quiet caddy-sync-health.service; then
        run_captured reset_failed_health_worker systemctl reset-failed caddy-sync-health.service || return 1
    else
        printf '%s_%s_reset_failed_health_worker=not_required\n' "$prefix" "$node_token"
    fi
    check health_worker_nonfailed_after_reset unit_not_failed caddy-sync-health.service || return 1
    run_captured disable_obsolete_path systemctl disable --now caddy-validate-reload.path || return 1
    mv -- "$obsolete_path" "$backup_directory/caddy-validate-reload.path.live" || return 1
    mv -- "$obsolete_service" "$backup_directory/caddy-validate-reload.service.live" || return 1
    run_captured daemon_reload systemctl daemon-reload || return 1
    run_captured enable_caddy systemctl enable caddy.service || return 1
    run_captured enable_cert_timer systemctl enable caddy-cert-expiry.timer || return 1
    capture_cursor cert_worker_journal_cursor || return 1
    action30b_cert_journal_cursor=$(cursor_from_capture cert_worker_journal_cursor) || return 1
    run_captured invoke_cert_worker systemctl start caddy-cert-expiry.service || return 1
    emit_unit_properties cert_worker_properties caddy-cert-expiry.service || return 1
    run_captured cert_worker_journal journalctl -u caddy-cert-expiry.service \
        --after-cursor "$action30b_cert_journal_cursor" \
        --no-pager --no-hostname -o short-iso || return 1
    check cert_worker_acceptance successful_static_worker caddy-cert-expiry.service || return 1
    run_captured start_cert_timer systemctl start caddy-cert-expiry.timer || return 1
    check cert_timer_active active_exact caddy-cert-expiry.timer active || return 1
    run_captured enable_health_timer systemctl enable caddy-sync-health.timer || return 1
    capture_cursor health_worker_journal_cursor || return 1
    action30b_health_journal_cursor=$(cursor_from_capture health_worker_journal_cursor) || return 1
    run_captured invoke_health_worker systemctl start caddy-sync-health.service || return 1
    emit_unit_properties health_worker_properties caddy-sync-health.service || return 1
    run_captured health_worker_journal journalctl -u caddy-sync-health.service \
        --after-cursor "$action30b_health_journal_cursor" \
        --no-pager --no-hostname -o short-iso || return 1
    check health_worker_acceptance successful_static_worker caddy-sync-health.service || return 1
    run_captured start_health_timer systemctl start caddy-sync-health.timer || return 1
    check health_timer_active active_exact caddy-sync-health.timer active || return 1
    run_captured enable_lsyncd systemctl enable caddy-lsyncd.service || return 1
    run_captured enable_reconcile_path systemctl enable caddy-sync-reconcile.path || return 1
    run_captured mask_caddy_api systemctl mask caddy-api.service || return 1
    run_captured mask_distribution_lsyncd systemctl mask "$distribution_lsyncd_unit" || return 1
    run_captured lsyncd_stability lsyncd_stable || return 1
    check lsyncd_status_writer_still_advances wait_for_lsyncd_status_advance || return 1
    run_captured sync_post_cursor_journal journalctl \
        -u caddy-lsyncd.service -u caddy-sync-reconcile.service \
        --after-cursor "$sync_journal_cursor" \
        --no-pager --no-hostname -o short-iso || return 1
    check no_new_transport_failure_or_quarantine post_cursor_transport_clean || return 1
    target_contract || return 1
    printf '%s\n' committed >"$backup_directory/transaction.complete"
    chmod 0600 "$backup_directory/transaction.complete" || return 1
    transaction_complete=true
    printf '%s_%s_complete=true\n' "$prefix" "$node_token"
}
rollback_on_error() {
    local action30b_status=$?

    trap - EXIT INT TERM
    if [[ "$transaction_complete" = true || "$mutation_started" = false ]]; then
        exit "$action30b_status"
    fi
    printf '%s_%s_rollback_started=true\n' "$prefix" "$node_token" >&2
    if [[ "$role" = node-b &&
        (-e "$protected_node_b_outbound" ||
        -L "$protected_node_b_outbound") ]]; then
        printf '%s_%s_protected_stale_outbound_retained=true\n' \
            "$prefix" "$node_token" >&2
    fi
    if rollback; then
        exit "$action30b_status"
    fi
    printf '%s_%s_manual_intervention_required=true\n' "$prefix" "$node_token" >&2
    exit 125
}
configure_role() {
    role=$1
    node_token=${role//-/_}
    case "$role" in
        node-a) expected_hostname=j1-svpihole0 ;;
        node-b) expected_hostname=j1-svpihole00 ;;
        *) return 64 ;;
    esac
    capture_directory=$evidence_root/$node_token
}
create_semantic_fixture_release() {
    local action30b_fixture_release=$1
    local action30b_fixture_revision=$2
    local action30b_fixture_parent=$3
    local action30b_fixture_source=$4

    mkdir -p "$action30b_fixture_release"
    printf 'fixture\n' >"$action30b_fixture_release/Caddyfile"
    jq -cn --arg revision "$action30b_fixture_revision" \
        --arg parent "$action30b_fixture_parent" \
        --arg source "$action30b_fixture_source" \
        '{revision:$revision,parent_revision:$parent,source_node:$source,created_at:"2026-08-11T00:00:00Z"}' \
        >"$action30b_fixture_release/release-manifest.json"
    (
        cd "$action30b_fixture_release"
        sha256sum ./Caddyfile ./release-manifest.json >manifest.sha256
    )
}
semantic_self_test() {
    local action30b_fixture_node_a
    local action30b_fixture_node_b
    local action30b_fixture_drift

    semantic_fixture_root=$(mktemp -d /tmp/action30b-semantic.XXXXXX) || return 1
    trap 'rm -rf -- "${semantic_fixture_root:-}"' EXIT INT TERM
    capture_directory=$semantic_fixture_root/captures
    mkdir -p "$capture_directory"
    action30b_fixture_node_a=$semantic_fixture_root/$accepted_current_revision
    action30b_fixture_node_b=$semantic_fixture_root/$historical_revision
    action30b_fixture_drift=$semantic_fixture_root/drift
    create_semantic_fixture_release "$action30b_fixture_node_a" \
        "$accepted_current_revision" "$historical_revision" node-a
    create_semantic_fixture_release "$action30b_fixture_node_b" \
        "$historical_revision" "$historical_parent" node-b
    create_semantic_fixture_release "$action30b_fixture_drift" \
        "$historical_revision" wrong-parent node-b
    outbound_candidate_admissible node-a "$action30b_fixture_node_a" || return 1
    outbound_candidate_admissible node-b "$action30b_fixture_node_b" || return 1
    if outbound_candidate_admissible node-b "$action30b_fixture_drift"; then
        return 1
    fi
    printf '%s_semantic_admissible_candidates_accepted=true\n' "$prefix"
    printf '%s_semantic_divergent_candidate_rejected=true\n' "$prefix"
    printf '%s\n' '-- cursor: s=fixture;i=1;b=fixture;m=1;t=1;x=1' \
        >"$capture_directory/cursor.stdout"
    [[ "$(cursor_from_capture cursor)" = 's=fixture;i=1;b=fixture;m=1;t=1;x=1' ]] || return 1
    printf '%s\n' '-- cursor: s=duplicate;i=2' \
        >>"$capture_directory/cursor.stdout"
    if cursor_from_capture cursor >/dev/null 2>&1; then
        return 1
    fi
    : >"$capture_directory/cursor.stdout"
    if cursor_from_capture cursor >/dev/null 2>&1; then
        return 1
    fi
    printf '%s_cursor_exact_accepted=true\n' "$prefix"
    printf '%s_cursor_missing_or_duplicate_rejected=true\n' "$prefix"
    printf 'Started Caddy synchronization daemon.\n' \
        >"$capture_directory/sync_post_cursor_journal.stdout"
    post_cursor_transport_clean || return 1
    printf 'Quarantined divergent release fixture\n' \
        >"$capture_directory/sync_post_cursor_journal.stdout"
    if post_cursor_transport_clean; then
        return 1
    fi
    printf '%s_post_cursor_clean_journal_accepted=true\n' "$prefix"
    printf '%s_post_cursor_new_quarantine_rejected=true\n' "$prefix"
    printf '%s_semantic_self_test_complete=true\n' "$prefix"
}
self_test() {
    configure_role "$1" || return 1
    printf '%s_%s_node_contact=false\n' "$prefix" "$node_token"
    printf '%s_%s_self_test_complete=true\n' "$prefix" "$node_token"
}
main() {
    local action30b_mode=${1:-}
    local action30b_role=${2:-}

    configure_role "$action30b_role" || return $?
    install -d -o root -g root -m 0700 "$capture_directory" || return 1
    case "$action30b_mode" in
        --apply)
            trap rollback_on_error EXIT INT TERM
            apply
            trap - EXIT INT TERM
            ;;
        --verify)
            target_contract
            printf '%s_%s_verify_complete=true\n' "$prefix" "$node_token"
            ;;
        --verify-continuity)
            continuity
            printf '%s_%s_verify_continuity_complete=true\n' "$prefix" "$node_token"
            ;;
        --rollback) rollback ;;
        *) return 64 ;;
    esac
}

case "${1:-}" in
    --self-test) [[ $# -eq 2 ]] && self_test "$2" ;;
    --semantic-self-test) [[ $# -eq 1 ]] && semantic_self_test ;;
    --apply | --verify | --verify-continuity | --rollback) [[ $# -eq 2 ]] && main "$@" ;;
    *) exit 64 ;;
esac
