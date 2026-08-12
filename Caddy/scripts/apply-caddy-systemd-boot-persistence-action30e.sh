#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_30e_remote
readonly backup_directory=/var/backups/caddy-ha/action30e-systemd-boot-persistence
readonly evidence_root=/tmp/caddy-action30e
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
readonly lsyncd_status_file=${CADDY_ACTION30E_STATUS_FILE:-/run/caddy-lsyncd/status}
readonly lsyncd_status_wait_seconds=45
readonly health_worker=/usr/local/libexec/validate-sync-health.sh
readonly accepted_health_worker_sha256=77c5ab2ada350d24bf890eb055db58e6e46086cda6e023b533c7c793c181f56b
readonly corrected_health_worker_sha256=91df406d38b3fbceec28a1adb188da0d996b3916521934318948b4e289fb85d4
readonly lsyncd_unit=/etc/systemd/system/caddy-lsyncd.service
readonly accepted_lsyncd_unit_sha256=93cbc36cea03b8b7e1605c44667463592cf64e0293ded9f816d1e34760a69ac8
readonly corrected_lsyncd_unit_sha256=e9139d40f7891485ea423d4a064b9cb162ff1b6234bf27e83d2bb9fbce4c02d2
readonly releases_root=/etc/caddy/releases
readonly current_link=/etc/caddy/current
readonly outbound_root=/var/lib/caddy-sync/outbound
readonly quarantine_root=/var/lib/caddy-sync/quarantine
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6
readonly historical_revision=20260811T180716Z-d45a4dc3-64b6-47c5-bebc-02dade4d9ec4
readonly older_historical_revision=20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29
readonly historical_parent=20260809T193432Z-6a2fab64-69e6-4cfb-a026-0a38fcae5b63
readonly accepted_current_revision=20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04
readonly historical_node_a_quarantine=$quarantine_root/node-b-$historical_revision
readonly protected_node_b_older_quarantine=$quarantine_root/node_b-outbound-${older_historical_revision}-action30c
readonly protected_node_b_newer_quarantine=$quarantine_root/node_b-outbound-${historical_revision}-action30c
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
outbound_inventory_snapshot=
outbound_quarantine_plan=
quarantined_outbound_count=0
health_worker_stage=
health_worker_candidate=
lsyncd_unit_candidate=

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_revision() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
safe_stream() {
    local action30e_stream=$1

    [[ "$(wc -c <"$action30e_stream")" -le 1048576 ]] || return 1
    [[ "$(line_count "$action30e_stream")" -le 8192 ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action30e_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action30e_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action30e_stream"
}
emit_stream() {
    local action30e_label=$1
    local action30e_stream=$2

    printf '%s_%s_%s_bytes=%s\n' "$prefix" "$node_token" "$action30e_label" "$(wc -c <"$action30e_stream")"
    printf '%s_%s_%s_lines=%s\n' "$prefix" "$node_token" "$action30e_label" "$(line_count "$action30e_stream")"
    printf '%s_%s_%s_sha256=%s\n' "$prefix" "$node_token" "$action30e_label" "$(file_hash "$action30e_stream")"
    safe_stream "$action30e_stream" || return 97
    printf '%s_%s_%s_classification=bounded_safe\n' "$prefix" "$node_token" "$action30e_label"
    if [[ -s "$action30e_stream" ]]; then
        printf '%s_%s_%s_begin\n' "$prefix" "$node_token" "$action30e_label"
        cat "$action30e_stream"
        printf '%s_%s_%s_end\n' "$prefix" "$node_token" "$action30e_label"
    else
        printf '%s_%s_%s_content=empty\n' "$prefix" "$node_token" "$action30e_label"
    fi
}
check() {
    local action30e_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action30e_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "$node_token" "$action30e_label" >&2
    return 1
}
run_captured() {
    local action30e_label=$1
    local action30e_stdout=$capture_directory/$action30e_label.stdout
    local action30e_stderr=$capture_directory/$action30e_label.stderr
    local action30e_status_file=$capture_directory/$action30e_label.status
    local action30e_status=0

    shift
    install -m 0600 /dev/null "$action30e_stdout" || return 1
    install -m 0600 /dev/null "$action30e_stderr" || return 1
    install -m 0600 /dev/null "$action30e_status_file" || return 1
    "$@" >"$action30e_stdout" 2>"$action30e_stderr" || action30e_status=$?
    printf '%s\n' "$action30e_status" >"$action30e_status_file"
    printf '%s_%s_%s_status=%s\n' "$prefix" "$node_token" "$action30e_label" "$action30e_status"
    emit_stream "${action30e_label}_stdout" "$action30e_stdout" || return $?
    emit_stream "${action30e_label}_stderr" "$action30e_stderr" || return $?
    [[ "$action30e_status" -eq 0 ]]
}
cursor_from_capture() {
    local action30e_label=$1
    local action30e_capture=$capture_directory/$action30e_label.stdout

    awk '
        /^-- cursor: / {
            cursor = substr($0, 12)
            found++
        }
        END {
            if (found != 1 || cursor !~ /^s=/) exit 1
            print cursor
        }
    ' "$action30e_capture"
}
capture_cursor() {
    local action30e_label=$1

    run_captured "$action30e_label" journalctl --show-cursor -n 0 --no-pager || return 1
    cursor_from_capture "$action30e_label" >/dev/null
}
manifest_paths_safe() {
    local action30e_manifest=$1

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
    ' "$action30e_manifest"
}
manifest_file_set_matches() {
    local action30e_release=$1
    local action30e_expected
    local action30e_observed
    local action30e_status=0

    action30e_expected=$(mktemp /tmp/action30e-manifest-expected.XXXXXX) || return 1
    action30e_observed=$(mktemp /tmp/action30e-manifest-observed.XXXXXX) || {
        rm -f -- "$action30e_expected"
        return 1
    }
    awk '{ print substr($0, 67) }' "$action30e_release/manifest.sha256" |
        LC_ALL=C sort -u >"$action30e_expected"
    (
        cd "$action30e_release"
        find . -type f \
            ! -path ./manifest.sha256 \
            ! -path ./.finalize-request \
            ! -path ./.complete \
            ! -path ./.complete.pending -print |
            LC_ALL=C sort
    ) >"$action30e_observed"
    cmp -s "$action30e_expected" "$action30e_observed" || action30e_status=$?
    rm -f -- "$action30e_expected" "$action30e_observed"
    [[ "$action30e_status" -eq 0 ]]
}
manifest_valid() {
    local action30e_release=$1

    [[ -d "$action30e_release" && ! -L "$action30e_release" ]] || return 1
    [[ -f "$action30e_release/release-manifest.json" &&
        ! -L "$action30e_release/release-manifest.json" ]] || return 1
    [[ -f "$action30e_release/manifest.sha256" &&
        ! -L "$action30e_release/manifest.sha256" ]] || return 1
    [[ -z "$(find "$action30e_release" -type l -print -quit)" ]] || return 1
    [[ -z "$(find "$action30e_release" ! -type d ! -type f -print -quit)" ]] || return 1
    [[ -z "$(find "$action30e_release" -type f -links +1 -print -quit)" ]] || return 1
    jq -e '
        (.revision | type == "string" and length > 0) and
        (.parent_revision | type == "string") and
        (.source_node == "node-a" or .source_node == "node-b") and
        (.created_at | type == "string" and length > 0)
    ' "$action30e_release/release-manifest.json" >/dev/null || return 1
    manifest_paths_safe "$action30e_release/manifest.sha256" || return 1
    manifest_file_set_matches "$action30e_release" || return 1
    (cd "$action30e_release" &&
        sha256sum --strict --check manifest.sha256 >/dev/null 2>&1)
}
release_identity_exact() {
    local action30e_release=$1
    local action30e_revision=$2
    local action30e_parent=$3
    local action30e_source=$4

    manifest_valid "$action30e_release" || return 1
    [[ "$(jq -r '.revision // empty' "$action30e_release/release-manifest.json")" = "$action30e_revision" ]] || return 1
    [[ "$(jq -r '.parent_revision // empty' "$action30e_release/release-manifest.json")" = "$action30e_parent" ]] || return 1
    [[ "$(jq -r '.source_node // empty' "$action30e_release/release-manifest.json")" = "$action30e_source" ]]
}
current_release_inventory() {
    local action30e_resolved
    local action30e_revision
    local action30e_parent
    local action30e_source

    [[ -L "$current_link" ]] || return 1
    action30e_resolved=$(readlink -f -- "$current_link") || return 1
    [[ "$action30e_resolved" = "$releases_root/$accepted_current_revision" ]] || return 1
    manifest_valid "$action30e_resolved" || return 1
    action30e_revision=$(jq -r '.revision // empty' "$action30e_resolved/release-manifest.json") || return 1
    action30e_parent=$(jq -r '.parent_revision // empty' "$action30e_resolved/release-manifest.json") || return 1
    action30e_source=$(jq -r '.source_node // empty' "$action30e_resolved/release-manifest.json") || return 1
    [[ "$action30e_revision" = "$accepted_current_revision" ]] || return 1
    [[ "$action30e_source" = node-a ]] || return 1
    printf 'current_path=%s\n' "$action30e_resolved"
    printf 'current_revision=%s\n' "$action30e_revision"
    printf 'current_parent=%s\n' "$action30e_parent"
    printf 'current_source=%s\n' "$action30e_source"
    printf 'current_release_manifest_sha256=%s\n' \
        "$(file_hash "$action30e_resolved/release-manifest.json")"
    printf 'current_payload_manifest_sha256=%s\n' \
        "$(file_hash "$action30e_resolved/manifest.sha256")"
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
protected_node_b_quarantines_exact() {
    [[ "$role" = node-b ]] || return 0
    release_identity_exact "$protected_node_b_older_quarantine" \
        "$older_historical_revision" "$historical_parent" node-b || return 1
    release_identity_exact "$protected_node_b_newer_quarantine" \
        "$historical_revision" "$historical_parent" node-b || return 1
    printf 'protected_action30c_quarantine_1=%s\n' "$protected_node_b_older_quarantine"
    printf 'protected_action30c_quarantine_2=%s\n' "$protected_node_b_newer_quarantine"
    printf 'protected_action30c_quarantine_count=2\n'
}
outbound_entry_type() {
    local action30e_entry=$1

    if [[ -L "$action30e_entry" ]]; then
        printf 'symlink\n'
    elif [[ -d "$action30e_entry" ]]; then
        printf 'directory\n'
    elif [[ -f "$action30e_entry" ]]; then
        printf 'regular\n'
    elif [[ -b "$action30e_entry" ]]; then
        printf 'block\n'
    elif [[ -c "$action30e_entry" ]]; then
        printf 'character\n'
    elif [[ -p "$action30e_entry" ]]; then
        printf 'fifo\n'
    elif [[ -S "$action30e_entry" ]]; then
        printf 'socket\n'
    else
        printf 'other\n'
    fi
}
write_outbound_snapshot() {
    local action30e_snapshot=$1
    local action30e_snapshot_root=${2:-$outbound_root}

    install -m 0600 /dev/null "$action30e_snapshot" || return 1
    find "$action30e_snapshot_root" -mindepth 1 -maxdepth 1 -print0 >"$action30e_snapshot" || return 1
    sort -z -o "$action30e_snapshot" "$action30e_snapshot" || return 1
}
candidate_disposition() {
    local action30e_candidate=$1
    local action30e_revision=$2
    local action30e_source=$3
    local action30e_current_candidate=${4:-$releases_root/$accepted_current_revision}

    [[ "${action30e_candidate##*/}" = "$action30e_revision" ]] || return 1
    case "$role" in
        node-a)
            [[ "$action30e_source" = node-a ]] || return 1
            if [[ "$action30e_revision" = "$accepted_current_revision" ]]; then
                manifest_valid "$action30e_current_candidate" || return 1
                [[ "$(file_hash "$action30e_candidate/release-manifest.json")" = "$(file_hash "$action30e_current_candidate/release-manifest.json")" ]] || return 1
                [[ "$(file_hash "$action30e_candidate/manifest.sha256")" = "$(file_hash "$action30e_current_candidate/manifest.sha256")" ]] || return 1
                printf 'retain\n'
            else
                printf 'quarantine\n'
            fi
            ;;
        node-b)
            [[ "$action30e_source" = node-b ]] || return 1
            printf 'quarantine\n'
            ;;
        *) return 1 ;;
    esac
}
outbound_inventory() {
    local action30e_inventory_root=${1:-$outbound_root}
    local action30e_candidate
    local action30e_candidate_count=0
    local action30e_disposition
    local action30e_entry_count=0
    local action30e_entry_name
    local action30e_entry_type
    local action30e_invalid_entry=false
    local action30e_parent
    local action30e_quarantine_count=0
    local action30e_retain_count=0
    local action30e_revision
    local action30e_source

    [[ -d "$action30e_inventory_root" && ! -L "$action30e_inventory_root" ]] || return 1
    outbound_inventory_snapshot=$capture_directory/outbound-inventory.snapshot
    outbound_quarantine_plan=$capture_directory/outbound-quarantine.plan
    write_outbound_snapshot "$outbound_inventory_snapshot" "$action30e_inventory_root" || return 1
    install -m 0600 /dev/null "$outbound_quarantine_plan" || return 1
    while IFS= read -r -d '' action30e_candidate; do
        action30e_entry_count=$((action30e_entry_count + 1))
        action30e_entry_name=${action30e_candidate##*/}
        action30e_entry_type=$(outbound_entry_type "$action30e_candidate") || return 1
        printf 'outbound_entry_%s_name_q=%q\n' "$action30e_entry_count" "$action30e_entry_name"
        printf 'outbound_entry_%s_type=%s\n' "$action30e_entry_count" "$action30e_entry_type"
        if [[ "$action30e_entry_type" != directory ||
            "$action30e_entry_name" = .* ]] ||
            ! valid_revision "$action30e_entry_name"; then
            action30e_invalid_entry=true
        fi
    done <"$outbound_inventory_snapshot"
    printf 'outbound_entry_count=%s\n' "$action30e_entry_count"
    [[ "$action30e_invalid_entry" = false ]] || return 1
    while IFS= read -r -d '' action30e_candidate; do
        [[ -n "$action30e_candidate" ]] || continue
        action30e_candidate_count=$((action30e_candidate_count + 1))
        manifest_valid "$action30e_candidate" || return 1
        action30e_revision=$(jq -r '.revision // empty' "$action30e_candidate/release-manifest.json") || return 1
        action30e_parent=$(jq -r '.parent_revision // empty' "$action30e_candidate/release-manifest.json") || return 1
        action30e_source=$(jq -r '.source_node // empty' "$action30e_candidate/release-manifest.json") || return 1
        valid_revision "$action30e_revision" || return 1
        action30e_disposition=$(candidate_disposition "$action30e_candidate" \
            "$action30e_revision" "$action30e_source") || return 1
        printf 'outbound_candidate_%s=%s\n' "$action30e_candidate_count" \
            "${action30e_candidate##*/}"
        printf 'outbound_candidate_%s_parent=%s\n' "$action30e_candidate_count" \
            "$action30e_parent"
        printf 'outbound_candidate_%s_source=%s\n' "$action30e_candidate_count" \
            "$action30e_source"
        printf 'outbound_candidate_%s_disposition=%s\n' "$action30e_candidate_count" \
            "$action30e_disposition"
        if [[ "$action30e_disposition" = quarantine ]]; then
            printf '%s\0' "$action30e_candidate" >>"$outbound_quarantine_plan" || return 1
            action30e_quarantine_count=$((action30e_quarantine_count + 1))
        else
            action30e_retain_count=$((action30e_retain_count + 1))
        fi
    done <"$outbound_inventory_snapshot"
    [[ "$action30e_retain_count" -le 1 ]] || return 1
    printf 'outbound_candidate_count=%s\n' "$action30e_candidate_count"
    printf 'outbound_retain_count=%s\n' "$action30e_retain_count"
    printf 'outbound_quarantine_count=%s\n' "$action30e_quarantine_count"
    [[ "$role" != node-b || "$action30e_retain_count" -eq 0 ]] || return 1
    printf '%s_outbound_role_policy=accepted\n' "${role//-/_}"
}
semantic_inventory() {
    current_release_inventory || return 1
    outbound_inventory || return 1
    if [[ "$role" = node-a ]]; then
        historical_quarantine_exact || return 1
    else
        protected_node_b_quarantines_exact || return 1
    fi
}
outbound_snapshot_unchanged() {
    local action30e_observed=$capture_directory/outbound-inventory.after-stop

    write_outbound_snapshot "$action30e_observed" || return 1
    cmp -s "$outbound_inventory_snapshot" "$action30e_observed"
}
protect_ineligible_outbound() {
    local action30e_candidate
    local action30e_destination
    local action30e_parent
    local action30e_revision
    local action30e_source

    [[ -f "$outbound_quarantine_plan" && ! -L "$outbound_quarantine_plan" ]] || return 1
    [[ -d "$quarantine_root" && ! -L "$quarantine_root" ]] || return 1
    while IFS= read -r -d '' action30e_candidate; do
        manifest_valid "$action30e_candidate" || return 1
        action30e_revision=$(jq -r '.revision // empty' "$action30e_candidate/release-manifest.json") || return 1
        action30e_parent=$(jq -r '.parent_revision // empty' "$action30e_candidate/release-manifest.json") || return 1
        action30e_source=$(jq -r '.source_node // empty' "$action30e_candidate/release-manifest.json") || return 1
        [[ "$(candidate_disposition "$action30e_candidate" "$action30e_revision" "$action30e_source")" = quarantine ]] || return 1
        action30e_destination=$quarantine_root/${node_token}-outbound-${action30e_revision}-action30e
        [[ ! -e "$action30e_destination" && ! -L "$action30e_destination" ]] || return 1
        mv -- "$action30e_candidate" "$action30e_destination" || return 1
        release_identity_exact "$action30e_destination" \
            "$action30e_revision" "$action30e_parent" "$action30e_source" || return 1
        [[ ! -e "$action30e_candidate" && ! -L "$action30e_candidate" ]] || return 1
        quarantined_outbound_count=$((quarantined_outbound_count + 1))
        printf 'protected_outbound_%s_revision=%s\n' "$quarantined_outbound_count" "$action30e_revision"
        printf 'protected_outbound_%s_source=%s\n' "$quarantined_outbound_count" "$action30e_source"
        printf 'protected_outbound_%s_path=%s\n' "$quarantined_outbound_count" "$action30e_destination"
    done <"$outbound_quarantine_plan"
    printf 'protected_outbound_count=%s\n' "$quarantined_outbound_count"
}
node_b_outbound_clear() {
    local action30e_observed

    [[ "$role" = node-b ]] || return 0
    action30e_observed=$(find "$outbound_root" -mindepth 1 -maxdepth 1 \
        -type d ! -name '.*' -print -quit) || return 1
    [[ -z "$action30e_observed" ]]
}
role_state_exact() {
    local action30e_expected

    case "$role" in
        node-a) action30e_expected='(us) 2 "Master"' ;;
        node-b) action30e_expected='(us) 1 "Backup"' ;;
        *) return 1 ;;
    esac
    [[ "$(timeout 3 busctl get-property org.keepalived.Vrrp1 \
        "$ipv4_object" org.keepalived.Vrrp1.Instance State)" = "$action30e_expected" ]] || return 1
    [[ "$(timeout 3 busctl get-property org.keepalived.Vrrp1 \
        "$ipv6_object" org.keepalived.Vrrp1.Instance State)" = "$action30e_expected" ]]
}
lsyncd_stable() {
    local action30e_initial_pid
    local action30e_initial_restarts
    local action30e_sample
    local action30e_observed_pid
    local action30e_observed_restarts

    action30e_initial_pid=$(systemctl show caddy-lsyncd.service -p MainPID --value) || return 1
    action30e_initial_restarts=$(systemctl show caddy-lsyncd.service -p NRestarts --value) || return 1
    [[ "$action30e_initial_pid" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ "$action30e_initial_restarts" =~ ^[0-9]+$ ]] || return 1
    printf 'lsyncd_stability_initial_pid=%s\n' "$action30e_initial_pid"
    printf 'lsyncd_stability_initial_restarts=%s\n' "$action30e_initial_restarts"
    for ((action30e_sample = 1; action30e_sample <= lsyncd_stability_samples; action30e_sample++)); do
        systemctl is-active --quiet caddy-lsyncd.service || return 1
        [[ "$(systemctl show caddy-lsyncd.service -p SubState --value)" = running ]] || return 1
        [[ "$(systemctl show caddy-lsyncd.service -p Result --value)" = success ]] || return 1
        action30e_observed_pid=$(systemctl show caddy-lsyncd.service -p MainPID --value) || return 1
        action30e_observed_restarts=$(systemctl show caddy-lsyncd.service -p NRestarts --value) || return 1
        [[ "$action30e_observed_pid" = "$action30e_initial_pid" ]] || return 1
        [[ "$action30e_observed_restarts" = "$action30e_initial_restarts" ]] || return 1
        lsyncd_status_snapshot_valid || return 1
        printf 'lsyncd_stability_sample_%s=true\n' "$action30e_sample"
        if [[ "$action30e_sample" -lt "$lsyncd_stability_samples" ]]; then
            sleep "$lsyncd_stability_delay_seconds"
        fi
    done
}
post_cursor_transport_clean() {
    local action30e_journal=$capture_directory/sync_post_cursor_journal.stdout

    [[ -f "$action30e_journal" ]] || return 1
    ! grep -Eqi \
        'Quarantined divergent release|systemd unit failed: caddy-(lsyncd|sync-reconcile)[.]service|rsync([^[:alnum:]]|$).*error|rrsync([^[:alnum:]]|$).*error|connection unexpectedly closed|Permission denied|Host key verification failed' \
        "$action30e_journal"
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
    local action30e_unit

    for action30e_unit in "${static_units[@]}"; do
        enabled_exact "$action30e_unit" static || return 1
    done
}
lsyncd_status_snapshot_valid() {
    local action30e_validator=${health_worker_candidate:-$health_worker}

    [[ -f "$action30e_validator" && ! -L "$action30e_validator" ]] || return 1
    /bin/bash "$action30e_validator" --validate-status-file "$lsyncd_status_file"
}
wait_for_lsyncd_status_snapshot() {
    local action30e_waited=0

    while [[ "$action30e_waited" -lt "$lsyncd_status_wait_seconds" ]]; do
        if lsyncd_status_snapshot_valid; then
            printf '%s_%s_lsyncd_status_snapshot_wait_seconds=%s\n' "$prefix" "$node_token" "$action30e_waited"
            return 0
        fi
        sleep 1
        action30e_waited=$((action30e_waited + 1))
    done
    return 1
}
create_health_worker_candidate() {
    health_worker_stage=$(mktemp -d /run/caddy-action30e-health.XXXXXX) || return 1
    chown root:root "$health_worker_stage" || return 1
    chmod 0700 "$health_worker_stage" || return 1
    [[ "$(stat -c '%U:%G:%a' "$health_worker_stage")" = root:root:700 ]] || return 1
    health_worker_candidate=$health_worker_stage/validate-sync-health.sh
    install -o root -g root -m 0755 /dev/null "$health_worker_candidate" || return 1
    cat >"$health_worker_candidate" <<'ACTION30E_HEALTH_WORKER'
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

notify_failure() {
    /usr/local/libexec/lsyncd-sync-failure-notify.sh "$1"
}

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
        notify_failure "$service is not active and stable"
        return 1
    fi
    if ! status_snapshot_valid "$status_file"; then
        notify_failure "lsyncd status snapshot is missing, unsafe, or malformed: $status_file"
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
ACTION30E_HEALTH_WORKER
    chmod 0755 "$health_worker_candidate" || return 1
    [[ "$(stat -c '%U:%G:%a' "$health_worker_candidate")" = root:root:755 ]] || return 1
    [[ "$(file_hash "$health_worker_candidate")" = "$corrected_health_worker_sha256" ]] || return 1
    /bin/bash -n "$health_worker_candidate" || return 1
    lsyncd_unit_candidate=$health_worker_stage/caddy-lsyncd.service
    install -o root -g root -m 0644 /dev/null "$lsyncd_unit_candidate" || return 1
    cat >"$lsyncd_unit_candidate" <<'ACTION30E_LSYNCD_UNIT'
[Unit]
Description=Caddy HA release synchronization
Wants=network-online.target
After=network-online.target
OnFailure=caddy-sync-failure@%n.service

[Service]
Type=simple
User=caddy-sync
Group=caddy-sync
RuntimeDirectory=caddy-lsyncd
RuntimeDirectoryMode=0750
ExecStart=/usr/bin/lsyncd -nodaemon /etc/lsyncd/caddy.lua
SuccessExitStatus=143
Restart=on-failure
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/caddy-sync /run/caddy-lsyncd

[Install]
WantedBy=multi-user.target
ACTION30E_LSYNCD_UNIT
    chmod 0644 "$lsyncd_unit_candidate" || return 1
    [[ "$(stat -c '%U:%G:%a' "$lsyncd_unit_candidate")" = root:root:644 ]] || return 1
    [[ "$(file_hash "$lsyncd_unit_candidate")" = "$corrected_lsyncd_unit_sha256" ]]
}
cleanup_health_worker_stage() {
    if [[ -n "$health_worker_stage" && -d "$health_worker_stage" ]]; then
        rm -rf -- "$health_worker_stage"
    fi
    health_worker_stage=
    health_worker_candidate=
    lsyncd_unit_candidate=
}
emit_unit_properties() {
    local action30e_label=$1
    local action30e_unit=$2

    run_captured "$action30e_label" systemctl show "$action30e_unit" \
        -p LoadState -p UnitFileState -p ActiveState -p SubState -p Result -p ExecMainStatus
}
successful_static_worker() {
    local action30e_unit=$1

    enabled_exact "$action30e_unit" static || return 1
    unit_not_failed "$action30e_unit" || return 1
    [[ "$(systemctl show "$action30e_unit" -p Result --value 2>/dev/null || true)" = success ]] || return 1
    [[ "$(systemctl show "$action30e_unit" -p ExecMainStatus --value 2>/dev/null || true)" = 0 ]]
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
    check coupled_role_state role_state_exact || return 1
}
target_contract() {
    local action30e_unit

    continuity || return 1
    for action30e_unit in "${persistent_units[@]}"; do
        check "${action30e_unit//[^a-zA-Z0-9]/_}_enabled" enabled_exact "$action30e_unit" enabled || return 1
        check "${action30e_unit//[^a-zA-Z0-9]/_}_active" active_exact "$action30e_unit" active || return 1
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
    check lsyncd_unit_hash test "$(file_hash "$lsyncd_unit")" = "$corrected_lsyncd_unit_sha256" || return 1
    check lsyncd_success_exit_status test "$(systemctl show caddy-lsyncd.service -p SuccessExitStatus --value)" = 143 || return 1
    check health_worker_hash test "$(file_hash "$health_worker")" = "$corrected_health_worker_sha256" || return 1
    check lsyncd_status_snapshot_valid lsyncd_status_snapshot_valid || return 1
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
    local action30e_key=$1

    awk -F= -v key="$action30e_key" '$1 == key { print $2; found++ } END { if (found != 1) exit 1 }' \
        "$backup_directory/manifest"
}
record_backup() {
    local action30e_unit
    local action30e_backup_staging=${backup_directory}.staging.$$

    if ! install -d -o root -g root -m 0700 "$action30e_backup_staging"; then
        return 1
    fi
    if ! install -o root -g root -m 0600 "$obsolete_path" \
        "$action30e_backup_staging/caddy-validate-reload.path" ||
        ! install -o root -g root -m 0600 "$obsolete_service" \
            "$action30e_backup_staging/caddy-validate-reload.service" ||
        ! install -o root -g root -m 0700 "$health_worker" \
            "$action30e_backup_staging/validate-sync-health.sh" ||
        ! install -o root -g root -m 0600 "$lsyncd_unit" \
            "$action30e_backup_staging/caddy-lsyncd.service"; then
        rm -rf -- "$action30e_backup_staging"
        return 1
    fi
    {
        printf 'action=30e\nrole=%s\n' "$role"
        for action30e_unit in "${persistent_units[@]}" caddy-api.service "$distribution_lsyncd_unit" caddy-validate-reload.path; do
            printf 'enabled_%s=%s\n' "${action30e_unit//[^a-zA-Z0-9]/_}" \
                "$(systemctl is-enabled "$action30e_unit" 2>/dev/null || true)"
            printf 'active_%s=%s\n' "${action30e_unit//[^a-zA-Z0-9]/_}" \
                "$(systemctl is-active "$action30e_unit" 2>/dev/null || true)"
        done
    } >"$action30e_backup_staging/manifest" || {
        rm -rf -- "$action30e_backup_staging"
        return 1
    }
    if ! chmod 0600 "$action30e_backup_staging/manifest" ||
        ! mv -- "$action30e_backup_staging" "$backup_directory"; then
        rm -rf -- "$action30e_backup_staging"
        return 1
    fi
}
restore_enablement() {
    local action30e_unit=$1
    local action30e_token=${action30e_unit//[^a-zA-Z0-9]/_}
    local action30e_state
    local action30e_active

    action30e_state=$(manifest_value "enabled_$action30e_token") || return 1
    action30e_active=$(manifest_value "active_$action30e_token") || return 1
    case "$action30e_state" in
        enabled) systemctl enable "$action30e_unit" >/dev/null 2>&1 || return 1 ;;
        disabled) systemctl disable "$action30e_unit" >/dev/null 2>&1 || return 1 ;;
        masked) systemctl mask "$action30e_unit" >/dev/null 2>&1 || return 1 ;;
        static | indirect | generated | transient | '') ;;
        *) return 1 ;;
    esac
    case "$action30e_active" in
        active) systemctl start "$action30e_unit" >/dev/null 2>&1 || return 1 ;;
        inactive) systemctl stop "$action30e_unit" >/dev/null 2>&1 || return 1 ;;
        failed) return 1 ;;
        *) ;;
    esac
}
rollback() {
    local action30e_unit

    check backup_manifest_regular test -f "$backup_directory/manifest" || return 1
    install -o root -g root -m 0755 "$backup_directory/validate-sync-health.sh" "$health_worker" || return 1
    install -o root -g root -m 0644 "$backup_directory/caddy-lsyncd.service" "$lsyncd_unit" || return 1
    install -o root -g root -m 0644 "$backup_directory/caddy-validate-reload.path" "$obsolete_path" || return 1
    install -o root -g root -m 0644 "$backup_directory/caddy-validate-reload.service" "$obsolete_service" || return 1
    systemctl daemon-reload || return 1
    for action30e_unit in "${persistent_units[@]}" caddy-api.service "$distribution_lsyncd_unit" caddy-validate-reload.path; do
        restore_enablement "$action30e_unit" || return 1
    done
    cleanup_health_worker_stage || return 1
    continuity || return 1
    printf '%s_%s_rollback_complete=true\n' "$prefix" "$node_token"
}
apply() {
    local action30e_cert_journal_cursor
    local action30e_health_journal_cursor

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
    check health_worker_regular test -f "$health_worker" || return 1
    check health_worker_not_symlink test ! -L "$health_worker" || return 1
    check health_worker_owner_mode test "$(stat -c '%U:%G:%a' "$health_worker")" = root:root:755 || return 1
    check accepted_health_worker_hash test "$(file_hash "$health_worker")" = "$accepted_health_worker_sha256" || return 1
    check lsyncd_unit_regular test -f "$lsyncd_unit" || return 1
    check lsyncd_unit_not_symlink test ! -L "$lsyncd_unit" || return 1
    check lsyncd_unit_owner_mode test "$(stat -c '%U:%G:%a' "$lsyncd_unit")" = root:root:644 || return 1
    check accepted_lsyncd_unit_hash test "$(file_hash "$lsyncd_unit")" = "$accepted_lsyncd_unit_sha256" || return 1
    check obsolete_path_inactive active_exact caddy-validate-reload.path inactive || return 1
    check caddy_api_masked_before enabled_exact caddy-api.service masked || return 1
    check caddy_api_inactive_before active_exact caddy-api.service inactive || return 1
    check distribution_lsyncd_masked_before enabled_exact "$distribution_lsyncd_unit" masked || return 1
    check distribution_lsyncd_inactive_before active_exact "$distribution_lsyncd_unit" inactive || return 1
    check static_enablement_before static_enablement_contract || return 1
    record_backup || return 1
    mutation_started=true
    create_health_worker_candidate || return 1
    run_captured install_corrected_lsyncd_unit install -o root -g root -m 0644 \
        "$lsyncd_unit_candidate" "$lsyncd_unit" || return 1
    check corrected_lsyncd_unit_hash test \
        "$(file_hash "$lsyncd_unit")" = "$corrected_lsyncd_unit_sha256" || return 1
    run_captured reload_corrected_lsyncd_unit systemctl daemon-reload || return 1
    if [[ -s "$outbound_quarantine_plan" ]]; then
        run_captured stop_lsyncd_for_outbound_quarantine \
            systemctl stop caddy-lsyncd.service || return 1
    fi
    check outbound_snapshot_unchanged_after_stop outbound_snapshot_unchanged || return 1
    run_captured protect_ineligible_outbound protect_ineligible_outbound || return 1
    check node_b_outbound_clear_before_restart node_b_outbound_clear || return 1
    if ! systemctl is-active --quiet caddy-lsyncd.service ||
        ! lsyncd_status_snapshot_valid; then
        run_captured restart_managed_lsyncd systemctl restart caddy-lsyncd.service || return 1
    else
        printf '%s_%s_restart_managed_lsyncd=not_required\n' "$prefix" "$node_token"
    fi
    check lsyncd_status_snapshot_after_wait wait_for_lsyncd_status_snapshot || return 1
    run_captured install_corrected_health_worker install -o root -g root -m 0755 \
        "$health_worker_candidate" "$health_worker" || return 1
    check corrected_health_worker_hash test \
        "$(file_hash "$health_worker")" = "$corrected_health_worker_sha256" || return 1
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
    action30e_cert_journal_cursor=$(cursor_from_capture cert_worker_journal_cursor) || return 1
    run_captured invoke_cert_worker systemctl start caddy-cert-expiry.service || return 1
    emit_unit_properties cert_worker_properties caddy-cert-expiry.service || return 1
    run_captured cert_worker_journal journalctl -u caddy-cert-expiry.service \
        --after-cursor "$action30e_cert_journal_cursor" \
        --no-pager --no-hostname -o short-iso || return 1
    check cert_worker_acceptance successful_static_worker caddy-cert-expiry.service || return 1
    run_captured start_cert_timer systemctl start caddy-cert-expiry.timer || return 1
    check cert_timer_active active_exact caddy-cert-expiry.timer active || return 1
    run_captured enable_health_timer systemctl enable caddy-sync-health.timer || return 1
    capture_cursor health_worker_journal_cursor || return 1
    action30e_health_journal_cursor=$(cursor_from_capture health_worker_journal_cursor) || return 1
    run_captured invoke_health_worker systemctl start caddy-sync-health.service || return 1
    emit_unit_properties health_worker_properties caddy-sync-health.service || return 1
    run_captured health_worker_journal journalctl -u caddy-sync-health.service \
        --after-cursor "$action30e_health_journal_cursor" \
        --no-pager --no-hostname -o short-iso || return 1
    check health_worker_acceptance successful_static_worker caddy-sync-health.service || return 1
    run_captured start_health_timer systemctl start caddy-sync-health.timer || return 1
    check health_timer_active active_exact caddy-sync-health.timer active || return 1
    run_captured enable_lsyncd systemctl enable caddy-lsyncd.service || return 1
    run_captured enable_reconcile_path systemctl enable caddy-sync-reconcile.path || return 1
    run_captured mask_caddy_api systemctl mask caddy-api.service || return 1
    run_captured mask_distribution_lsyncd systemctl mask "$distribution_lsyncd_unit" || return 1
    run_captured lsyncd_stability lsyncd_stable || return 1
    run_captured sync_post_cursor_journal journalctl \
        -u caddy-lsyncd.service -u caddy-sync-reconcile.service \
        --after-cursor "$sync_journal_cursor" \
        --no-pager --no-hostname -o short-iso || return 1
    check no_new_transport_failure_or_quarantine post_cursor_transport_clean || return 1
    if systemctl is-failed --quiet caddy-sync-reconcile.service; then
        run_captured reset_failed_reconcile_worker \
            systemctl reset-failed caddy-sync-reconcile.service || return 1
    else
        printf '%s_%s_reset_failed_reconcile_worker=not_required\n' "$prefix" "$node_token"
    fi
    check reconcile_worker_nonfailed_after_safe_reset \
        unit_not_failed caddy-sync-reconcile.service || return 1
    target_contract || return 1
    cleanup_health_worker_stage || return 1
    printf '%s\n' committed >"$backup_directory/transaction.complete"
    chmod 0600 "$backup_directory/transaction.complete" || return 1
    transaction_complete=true
    printf '%s_%s_complete=true\n' "$prefix" "$node_token"
}
rollback_on_error() {
    local action30e_status=$?

    trap - EXIT INT TERM
    if [[ "$transaction_complete" = true || "$mutation_started" = false ]]; then
        cleanup_health_worker_stage
        exit "$action30e_status"
    fi
    printf '%s_%s_rollback_started=true\n' "$prefix" "$node_token" >&2
    if [[ "$quarantined_outbound_count" -gt 0 ]]; then
        printf '%s_%s_protected_outbound_retained_count=%s\n' \
            "$prefix" "$node_token" "$quarantined_outbound_count" >&2
    fi
    if rollback; then
        exit "$action30e_status"
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
    local action30e_fixture_release=$1
    local action30e_fixture_revision=$2
    local action30e_fixture_parent=$3
    local action30e_fixture_source=$4

    mkdir -p "$action30e_fixture_release"
    printf 'fixture\n' >"$action30e_fixture_release/Caddyfile"
    jq -cn --arg revision "$action30e_fixture_revision" \
        --arg parent "$action30e_fixture_parent" \
        --arg source "$action30e_fixture_source" \
        '{revision:$revision,parent_revision:$parent,source_node:$source,created_at:"2026-08-11T00:00:00Z"}' \
        >"$action30e_fixture_release/release-manifest.json"
    (
        cd "$action30e_fixture_release"
        sha256sum ./Caddyfile ./release-manifest.json >manifest.sha256
    )
}
semantic_self_test() {
    local action30e_fixture_node_a
    local action30e_fixture_node_b
    local action30e_fixture_node_b_older
    local action30e_fixture_wrong_source
    local action30e_observed

    semantic_fixture_root=$(mktemp -d /tmp/action30e-semantic.XXXXXX) || return 1
    trap 'rm -rf -- "${semantic_fixture_root:-}"' EXIT INT TERM
    capture_directory=$semantic_fixture_root/captures
    mkdir -p "$capture_directory"
    action30e_fixture_node_a=$semantic_fixture_root/$accepted_current_revision
    action30e_fixture_node_b=$semantic_fixture_root/$historical_revision
    action30e_fixture_node_b_older=$semantic_fixture_root/20260811T174240Z-31d43261-5cd7-44ce-83e5-947927184d29
    action30e_fixture_wrong_source=$semantic_fixture_root/wrong-source
    create_semantic_fixture_release "$action30e_fixture_node_a" \
        "$accepted_current_revision" "$historical_revision" node-a
    create_semantic_fixture_release "$action30e_fixture_node_b" \
        "$historical_revision" "$historical_parent" node-b
    create_semantic_fixture_release "$action30e_fixture_node_b_older" \
        "${action30e_fixture_node_b_older##*/}" "$historical_parent" node-b
    create_semantic_fixture_release "$action30e_fixture_wrong_source" \
        wrong-source "$historical_parent" node-a
    configure_role node-a || return 1
    [[ "$(candidate_disposition "$action30e_fixture_node_a" \
        "$accepted_current_revision" node-a "$action30e_fixture_node_a")" = retain ]] || return 1
    configure_role node-b || return 1
    [[ "$(candidate_disposition "$action30e_fixture_node_b" \
        "$historical_revision" node-b)" = quarantine ]] || return 1
    [[ "$(candidate_disposition "$action30e_fixture_node_b_older" \
        "${action30e_fixture_node_b_older##*/}" node-b)" = quarantine ]] || return 1
    if candidate_disposition "$action30e_fixture_wrong_source" wrong-source node-a >/dev/null; then
        return 1
    fi
    printf '%s_role_based_current_node_a_retained=true\n' "$prefix"
    printf '%s_role_based_multiple_node_b_revisions_quarantined=true\n' "$prefix"
    printf '%s_role_based_wrong_source_rejected=true\n' "$prefix"
    mkdir -p "$semantic_fixture_root/outbound"
    mv "$action30e_fixture_node_b" "$semantic_fixture_root/outbound/"
    mv "$action30e_fixture_node_b_older" "$semantic_fixture_root/outbound/"
    capture_directory=$semantic_fixture_root/inventory-captures
    mkdir -p "$capture_directory"
    outbound_inventory "$semantic_fixture_root/outbound" \
        >"$semantic_fixture_root/inventory.stdout" || return 1
    [[ "$(awk -F= '$1 == "outbound_entry_count" { print $2 }' \
        "$semantic_fixture_root/inventory.stdout")" = 2 ]] || return 1
    [[ "$(awk -F= '$1 == "outbound_quarantine_count" { print $2 }' \
        "$semantic_fixture_root/inventory.stdout")" = 2 ]] || return 1
    action30e_observed=$(grep -c '^outbound_entry_[0-9][0-9]*_name_q=' \
        "$semantic_fixture_root/inventory.stdout") || return 1
    [[ "$action30e_observed" -eq 2 ]] || return 1
    printf '%s_complete_inventory_precedes_policy=true\n' "$prefix"
    printf '%s_multiple_historical_candidates_accepted_for_quarantine=true\n' "$prefix"
    mkdir -p "$semantic_fixture_root/invalid-outbound/.hidden"
    ln -s "$semantic_fixture_root/invalid-outbound/.hidden" \
        "$semantic_fixture_root/invalid-outbound/symlink-entry"
    mkfifo "$semantic_fixture_root/invalid-outbound/fifo-entry"
    capture_directory=$semantic_fixture_root/invalid-captures
    mkdir -p "$capture_directory"
    if outbound_inventory "$semantic_fixture_root/invalid-outbound" \
        >"$semantic_fixture_root/invalid-inventory.stdout"; then
        return 1
    fi
    [[ "$(awk -F= '$1 == "outbound_entry_count" { print $2 }' \
        "$semantic_fixture_root/invalid-inventory.stdout")" = 3 ]] || return 1
    action30e_observed=$(grep -c '^outbound_entry_[0-9][0-9]*_name_q=' \
        "$semantic_fixture_root/invalid-inventory.stdout") || return 1
    [[ "$action30e_observed" -eq 3 ]] || return 1
    grep -Fq 'outbound_entry_1_type=directory' \
        "$semantic_fixture_root/invalid-inventory.stdout" || return 1
    grep -Fq 'type=fifo' "$semantic_fixture_root/invalid-inventory.stdout" || return 1
    grep -Fq 'type=symlink' "$semantic_fixture_root/invalid-inventory.stdout" || return 1
    printf '%s_hidden_symlink_special_complete_inventory_emitted=true\n' "$prefix"
    printf '%s_hidden_symlink_special_entries_rejected=true\n' "$prefix"
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
    local action30e_mode=${1:-}
    local action30e_role=${2:-}

    configure_role "$action30e_role" || return $?
    install -d -o root -g root -m 0700 "$capture_directory" || return 1
    case "$action30e_mode" in
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
