#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_33h_remote
readonly evidence_base=/tmp/caddy-action33h
readonly releases_root=/etc/caddy/releases
readonly incoming_root=/var/lib/caddy-sync/incoming
readonly outgoing_root=/var/lib/caddy-sync/outbound
readonly quarantine_root=/var/lib/caddy-sync/quarantine
readonly publisher=/usr/local/libexec/publish-release-v2.sh
readonly dns_ipv4=10.1.0.55
readonly caddy_ipv4=10.1.0.56
readonly dns_ipv6=fd36:5aa8:6971:1::55
readonly caddy_ipv6=fd36:5aa8:6971:1::56
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=32768

mode=${1:-}
role=${2:-}
run_id=${3:-}
scenario=${4:-none}
argument=${5:-}
node_token=${role//-/_}
evidence_directory=
action33h_remote_cursor=

valid_token() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
safe_stream() {
    local action33h_remote_stream=$1
    [[ "$(wc -c <"$action33h_remote_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action33h_remote_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action33h_remote_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action33h_remote_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action33h_remote_stream"
}
emit_stream() {
    local action33h_remote_label=$1
    local action33h_remote_path=$2
    printf '%s_%s_%s_bytes=%s\n' "$prefix" "$node_token" "$action33h_remote_label" "$(wc -c <"$action33h_remote_path")"
    printf '%s_%s_%s_lines=%s\n' "$prefix" "$node_token" "$action33h_remote_label" "$(line_count "$action33h_remote_path")"
    printf '%s_%s_%s_sha256=%s\n' "$prefix" "$node_token" "$action33h_remote_label" "$(file_hash "$action33h_remote_path")"
    safe_stream "$action33h_remote_path" || return 97
    printf '%s_%s_%s_classification=bounded_safe\n' "$prefix" "$node_token" "$action33h_remote_label"
    if [[ -s "$action33h_remote_path" ]]; then
        printf '%s_%s_%s_begin\n' "$prefix" "$node_token" "$action33h_remote_label"
        sed "s/^/${prefix}_${node_token}_${action33h_remote_label}_content=/" \
            "$action33h_remote_path"
        printf '%s_%s_%s_end\n' "$prefix" "$node_token" "$action33h_remote_label"
    else
        printf '%s_%s_%s_content=empty\n' "$prefix" "$node_token" "$action33h_remote_label"
    fi
}
run_captured() {
    local action33h_remote_label=$1
    local action33h_remote_status=0
    shift
    install -m 0600 /dev/null "$evidence_directory/$action33h_remote_label.stdout"
    install -m 0600 /dev/null "$evidence_directory/$action33h_remote_label.stderr"
    install -m 0600 /dev/null "$evidence_directory/$action33h_remote_label.status"
    "$@" >"$evidence_directory/$action33h_remote_label.stdout" 2>"$evidence_directory/$action33h_remote_label.stderr" || action33h_remote_status=$?
    printf '%s\n' "$action33h_remote_status" >"$evidence_directory/$action33h_remote_label.status"
    printf '%s_%s_%s_status=%s\n' "$prefix" "$node_token" "$action33h_remote_label" "$action33h_remote_status"
    emit_stream "${action33h_remote_label}_stdout" "$evidence_directory/$action33h_remote_label.stdout"
    emit_stream "${action33h_remote_label}_stderr" "$evidence_directory/$action33h_remote_label.stderr"
    [[ "$action33h_remote_status" -eq 0 ]]
}
check() {
    local action33h_remote_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action33h_remote_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "$node_token" "$action33h_remote_label" >&2
    return 1
}
inventory_tree() {
    local action33h_remote_root=$1
    if [[ -d "$action33h_remote_root" && ! -L "$action33h_remote_root" ]]; then
        find "$action33h_remote_root" -xdev -printf '%P\t%y\t%m\t%u\t%g\t%s\n' | LC_ALL=C sort
    else
        printf 'absent\n'
    fi
}
manifest_paths_safe() {
    local action33h_remote_manifest=$1

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
    ' "$action33h_remote_manifest"
}
manifest_file_set_matches() {
    local action33h_remote_release=$1
    local action33h_remote_expected
    local action33h_remote_observed
    local action33h_remote_status=0

    action33h_remote_expected=$(mktemp /tmp/caddy-action33h-manifest-expected.XXXXXX) || return 1
    action33h_remote_observed=$(mktemp /tmp/caddy-action33h-manifest-observed.XXXXXX) || {
        rm -f -- "$action33h_remote_expected"
        return 1
    }
    awk '{ print substr($0, 67) }' \
        "$action33h_remote_release/manifest.sha256" | LC_ALL=C sort -u \
        >"$action33h_remote_expected"
    (
        cd "$action33h_remote_release"
        find . -type f \
            ! -path ./manifest.sha256 \
            ! -path ./.finalize-request \
            ! -path ./.complete \
            ! -path ./.complete.pending -print | LC_ALL=C sort
    ) >"$action33h_remote_observed"
    cmp -s "$action33h_remote_expected" "$action33h_remote_observed" ||
        action33h_remote_status=$?
    rm -f -- "$action33h_remote_expected" "$action33h_remote_observed"
    [[ "$action33h_remote_status" -eq 0 ]]
}
release_manifest_valid() {
    local action33h_remote_release=$1

    [[ -d "$action33h_remote_release" && ! -L "$action33h_remote_release" ]] || return 1
    [[ -f "$action33h_remote_release/release-manifest.json" &&
        ! -L "$action33h_remote_release/release-manifest.json" ]] || return 1
    [[ -f "$action33h_remote_release/manifest.sha256" &&
        ! -L "$action33h_remote_release/manifest.sha256" ]] || return 1
    [[ -z "$(find "$action33h_remote_release" -type l -print -quit)" ]] || return 1
    [[ -z "$(find "$action33h_remote_release" ! -type d ! -type f -print -quit)" ]] || return 1
    [[ -z "$(find "$action33h_remote_release" -type f -links +1 -print -quit)" ]] || return 1
    jq -e '
        (.revision | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) and
        (.parent_revision | type == "string") and
        (.source_node == "node-a" or .source_node == "node-b") and
        (.created_at | type == "string" and length > 0)
    ' "$action33h_remote_release/release-manifest.json" >/dev/null || return 1
    manifest_paths_safe "$action33h_remote_release/manifest.sha256" || return 1
    manifest_file_set_matches "$action33h_remote_release" || return 1
    (
        cd "$action33h_remote_release"
        sha256sum --strict --check manifest.sha256 >/dev/null 2>&1
    )
}
assert_outbound_role_policy() {
    local action33h_remote_role=$1
    local action33h_remote_outbound=$2
    local action33h_remote_releases=$3
    local action33h_remote_current=$4
    local action33h_remote_candidate
    local action33h_remote_count=0
    local action33h_remote_name
    local action33h_remote_revision
    local action33h_remote_source
    local action33h_remote_target

    [[ -d "$action33h_remote_outbound" && ! -L "$action33h_remote_outbound" ]] || return 1
    [[ -d "$action33h_remote_releases" && ! -L "$action33h_remote_releases" ]] || return 1
    [[ -d "$action33h_remote_current" && ! -L "$action33h_remote_current" ]] || return 1
    while IFS= read -r -d '' action33h_remote_candidate; do
        action33h_remote_count=$((action33h_remote_count + 1))
        action33h_remote_name=${action33h_remote_candidate##*/}
        printf '%s_%s_outbound_entry_%s_name=%s\n' "$prefix" "$node_token" \
            "$action33h_remote_count" "$action33h_remote_name"
        check "outbound_entry_${action33h_remote_count}_name_safe" \
            valid_token "$action33h_remote_name" || return 1
        check "outbound_entry_${action33h_remote_count}_directory" \
            test -d "$action33h_remote_candidate" || return 1
        check "outbound_entry_${action33h_remote_count}_not_symlink" \
            test ! -L "$action33h_remote_candidate" || return 1
        release_manifest_valid "$action33h_remote_candidate" || {
            check "outbound_entry_${action33h_remote_count}_manifest_valid" false || true
            return 1
        }
        check "outbound_entry_${action33h_remote_count}_manifest_valid" true || return 1
        check "outbound_entry_${action33h_remote_count}_request_regular" \
            test -f "$action33h_remote_candidate/.finalize-request" || return 1
        check "outbound_entry_${action33h_remote_count}_request_not_symlink" \
            test ! -L "$action33h_remote_candidate/.finalize-request" || return 1
        check "outbound_entry_${action33h_remote_count}_request_empty" \
            test ! -s "$action33h_remote_candidate/.finalize-request" || return 1
        check "outbound_entry_${action33h_remote_count}_complete_absent" \
            test ! -e "$action33h_remote_candidate/.complete" || return 1
        check "outbound_entry_${action33h_remote_count}_pending_absent" \
            test ! -e "$action33h_remote_candidate/.complete.pending" || return 1
        check "outbound_entry_${action33h_remote_count}_directories_locked" \
            test -z "$(find "$action33h_remote_candidate" -type d ! -perm 0550 -print -quit)" || return 1
        check "outbound_entry_${action33h_remote_count}_files_locked" \
            test -z "$(find "$action33h_remote_candidate" -type f ! -perm 0440 -print -quit)" || return 1
        action33h_remote_revision=$(jq -er '.revision' \
            "$action33h_remote_candidate/release-manifest.json")
        action33h_remote_source=$(jq -er '.source_node' \
            "$action33h_remote_candidate/release-manifest.json")
        printf '%s_%s_outbound_entry_%s_revision=%s\n' "$prefix" "$node_token" \
            "$action33h_remote_count" "$action33h_remote_revision"
        printf '%s_%s_outbound_entry_%s_source=%s\n' "$prefix" "$node_token" \
            "$action33h_remote_count" "$action33h_remote_source"
        check "outbound_entry_${action33h_remote_count}_path_matches_revision" \
            test "$action33h_remote_name" = "$action33h_remote_revision" || return 1
        check "outbound_entry_${action33h_remote_count}_source_node_a" \
            test "$action33h_remote_source" = node-a || return 1
        action33h_remote_target=$action33h_remote_releases/$action33h_remote_revision
        check "outbound_entry_${action33h_remote_count}_installed_release" \
            test -d "$action33h_remote_target" || return 1
        check "outbound_entry_${action33h_remote_count}_installed_not_symlink" \
            test ! -L "$action33h_remote_target" || return 1
        release_manifest_valid "$action33h_remote_target" || return 1
        check "outbound_entry_${action33h_remote_count}_release_manifest_exact" \
            cmp -s "$action33h_remote_candidate/release-manifest.json" \
            "$action33h_remote_target/release-manifest.json" || return 1
        check "outbound_entry_${action33h_remote_count}_payload_manifest_exact" \
            cmp -s "$action33h_remote_candidate/manifest.sha256" \
            "$action33h_remote_target/manifest.sha256" || return 1
        if [[ "$action33h_remote_target" = "$action33h_remote_current" ]]; then
            printf '%s_%s_outbound_entry_%s_disposition=retain_exact_active_replay\n' \
                "$prefix" "$node_token" "$action33h_remote_count"
        else
            printf '%s_%s_outbound_entry_%s_disposition=retain_exact_installed_replay\n' \
                "$prefix" "$node_token" "$action33h_remote_count"
        fi
    done < <(find "$action33h_remote_outbound" -mindepth 1 -maxdepth 1 \
        -print0 | LC_ALL=C sort -z)
    printf '%s_%s_outbound_entry_count=%s\n' "$prefix" "$node_token" \
        "$action33h_remote_count"
    case "$action33h_remote_role" in
        node-a)
            # Current production may have no queued publication. Every entry
            # that does exist has already passed the complete role classifier.
            check node_a_outbound_entries_admissible test \
                "$action33h_remote_count" -ge 0
            ;;
        node-b)
            check node_b_outbound_empty test "$action33h_remote_count" -eq 0
            ;;
        *) return 1 ;;
    esac
    printf '%s_%s_outbound_role_policy=accepted\n' "$prefix" "$node_token"
}
registry_value() {
    local action33h_remote_key=$1

    awk -F '\t' -v wanted="$action33h_remote_key" \
        '$1 == wanted { print $2; found++ } END { if (found != 1) exit 1 }' \
        "/tmp/caddy-action33h-registry-$run_id.tsv"
}
assert_live_artifacts() {
    local action33h_remote_key
    local action33h_remote_path
    local action33h_remote_expected
    local action33h_remote_observed

    while IFS=$'\t' read -r action33h_remote_key action33h_remote_path; do
        action33h_remote_expected=$(registry_value "${node_token}_${action33h_remote_key}")
        action33h_remote_observed=$(file_hash "$action33h_remote_path")
        printf '%s_%s_expected_%s_sha256=%s\n' "$prefix" "$node_token" \
            "$action33h_remote_key" "$action33h_remote_expected"
        printf '%s_%s_observed_%s_sha256=%s\n' "$prefix" "$node_token" \
            "$action33h_remote_key" "$action33h_remote_observed"
        check "${action33h_remote_key}_hash" test \
            "$action33h_remote_observed" = "$action33h_remote_expected"
    done <<'ARTIFACTS'
protocol_v2_publisher	/usr/local/libexec/publish-release-v2.sh
protocol_v2_reconciler	/usr/local/libexec/reconcile-release.sh
protocol_v2_finalizer	/usr/local/libexec/finalize-incoming-release-v2.sh
lsyncd_config	/etc/lsyncd/caddy.lua
lsyncd_unit	/etc/systemd/system/caddy-lsyncd.service
reconcile_path	/etc/systemd/system/caddy-sync-reconcile.path
reconcile_service	/etc/systemd/system/caddy-sync-reconcile.service
sync_health_timer	/etc/systemd/system/caddy-sync-health.timer
sync_health_worker	/usr/local/libexec/validate-sync-health.sh
cert_expiry_helper	/usr/local/libexec/check-certificate-expiry.sh
cert_expiry_service	/etc/systemd/system/caddy-cert-expiry.service
sync_failure_unit	/etc/systemd/system/caddy-sync-failure@.service
sync_health_service	/etc/systemd/system/caddy-sync-health.service
caddy_override	/etc/systemd/system/caddy.service.d/override.conf
caddy_environment	/etc/default/caddy-ha
keepalived_main	/etc/keepalived/keepalived.conf
health_helper	/usr/local/libexec/check-caddy.sh
cert_expiry_timer	/etc/systemd/system/caddy-cert-expiry.timer
ARTIFACTS
    action33h_remote_expected=$(registry_value current_caddy_payload_manifest)
    action33h_remote_observed=$(file_hash "$(current_release)/manifest.sha256")
    printf '%s_%s_expected_current_payload_manifest_sha256=%s\n' \
        "$prefix" "$node_token" "$action33h_remote_expected"
    printf '%s_%s_observed_current_payload_manifest_sha256=%s\n' \
        "$prefix" "$node_token" "$action33h_remote_observed"
    check current_payload_manifest_hash test \
        "$action33h_remote_observed" = "$action33h_remote_expected"
}
current_release() { readlink -e /etc/caddy/current; }
vrrp_state() {
    local action33h_remote_object=$1
    busctl get-property org.keepalived.Vrrp1 "$action33h_remote_object" org.keepalived.Vrrp1.Instance State | awk -F'"' 'NF == 3 { print toupper($2) }'
}
vip_count() {
    local action33h_remote_address=$1
    ip -o addr show dev eth0 | awk -v wanted="$action33h_remote_address" '$4 == wanted || index($4, wanted "/") == 1 { count++ } END { print count + 0 }'
}
capture_baseline() {
    local action33h_remote_unit
    local action33h_remote_release_manifest_hash

    run_captured services systemctl show caddy.service caddy-lsyncd.service keepalived.service ssh.service -p Id -p ActiveState -p UnitFileState -p MainPID -p NRestarts
    run_captured timers systemctl show caddy-sync-health.timer caddy-cert-expiry.timer caddy-sync-reconcile.path -p Id -p ActiveState -p UnitFileState
    current_release >"$evidence_directory/current-release"
    printf '%s_%s_observed_current_release=%s\n' "$prefix" "$node_token" \
        "$(current_release)"
    printf '%s_%s_observed_current_revision=%s\n' "$prefix" "$node_token" \
        "$(jq -er '.revision' "$(current_release)/release-manifest.json")"
    action33h_remote_release_manifest_hash=$(file_hash \
        "$(current_release)/release-manifest.json")
    printf '%s\n' "$action33h_remote_release_manifest_hash" \
        >"$evidence_directory/release-manifest.sha256"
    printf '%s_%s_observed_release_manifest_sha256=%s\n' "$prefix" \
        "$node_token" "$action33h_remote_release_manifest_hash"
    inventory_tree "$outgoing_root" >"$evidence_directory/outgoing.inventory"
    inventory_tree "$incoming_root" >"$evidence_directory/incoming.inventory"
    inventory_tree "$quarantine_root" >"$evidence_directory/quarantine.inventory"
    run_captured boot_id cat /proc/sys/kernel/random/boot_id
    run_captured journal_cursor journalctl --show-cursor -n 0 --no-pager
    assert_live_artifacts
    check current_release_regular test -d "$(current_release)"
    check current_release_not_symlink test ! -L "$(current_release)"
    assert_outbound_role_policy "$role" "$outgoing_root" "$releases_root" \
        "$(current_release)"
    check finalized_candidate_absent test -z \
        "$(find "$incoming_root" -mindepth 2 -maxdepth 2 -type d \
            -exec test -f '{}/.complete' ';' -print -quit)"
    for action33h_remote_unit in caddy.service caddy-lsyncd.service \
        caddy-sync-reconcile.service caddy-sync-health.service \
        caddy-cert-expiry.service keepalived.service; do
        check "${action33h_remote_unit//[^A-Za-z0-9]/_}_nonfailed" \
            test "$(systemctl is-failed "$action33h_remote_unit" 2>/dev/null || true)" != failed
    done
}
assert_role_state() {
    local action33h_remote_expected=$1
    local action33h_remote_expected_vips=$2
    local action33h_remote_elapsed=0
    local action33h_remote_stable=0
    local action33h_remote_expected_count=0

    [[ "$action33h_remote_expected_vips" = four ]] && action33h_remote_expected_count=1
    while ((action33h_remote_elapsed < 90)); do
        if [[ "$(vrrp_state "$ipv4_object")" = "$action33h_remote_expected" &&
        "$(vrrp_state "$ipv6_object")" = "$action33h_remote_expected" &&
        "$(vip_count "$dns_ipv4")" -eq "$action33h_remote_expected_count" &&
        "$(vip_count "$caddy_ipv4")" -eq "$action33h_remote_expected_count" &&
        "$(vip_count "$dns_ipv6")" -eq "$action33h_remote_expected_count" &&
        "$(vip_count "$caddy_ipv6")" -eq "$action33h_remote_expected_count" ]]; then
            action33h_remote_stable=$((action33h_remote_stable + 1))
            if ((action33h_remote_stable == 5)); then
                printf '%s_%s_ownership_convergence_seconds=%s\n' "$prefix" \
                    "$node_token" "$action33h_remote_elapsed"
                printf '%s_%s_check_ownership_stable=true\n' "$prefix" "$node_token"
                return 0
            fi
        else
            action33h_remote_stable=0
        fi
        sleep 1
        action33h_remote_elapsed=$((action33h_remote_elapsed + 1))
    done
    printf '%s_%s_check_ownership_stable=false\n' "$prefix" "$node_token" >&2
    return 1
}
assert_services() {
    local action33h_remote_unit
    local action33h_remote_pid=
    local action33h_remote_restarts=
    local action33h_remote_sample
    for action33h_remote_unit in caddy.service caddy-lsyncd.service keepalived.service ssh.service caddy-sync-reconcile.path caddy-sync-health.timer caddy-cert-expiry.timer; do
        check "${action33h_remote_unit//[^A-Za-z0-9]/_}_active" systemctl is-active --quiet "$action33h_remote_unit"
    done
    for action33h_remote_unit in caddy.service caddy-lsyncd.service keepalived.service ssh.service caddy-sync-reconcile.path caddy-sync-health.timer caddy-cert-expiry.timer; do
        check "${action33h_remote_unit//[^A-Za-z0-9]/_}_enabled" systemctl is-enabled --quiet "$action33h_remote_unit"
    done
    check caddy_api_masked test "$(systemctl is-enabled caddy-api.service 2>/dev/null || true)" = masked
    for action33h_remote_unit in caddy-cert-expiry.service \
        caddy-sync-health.service caddy-sync-reconcile.service \
        caddy-sync-failure@.service; do
        check "${action33h_remote_unit//[^A-Za-z0-9]/_}_static" \
            test "$(systemctl is-enabled "$action33h_remote_unit" 2>/dev/null || true)" = static
    done
    for action33h_remote_sample in 1 2 3 4 5; do
        if [[ -z "$action33h_remote_pid" ]]; then
            action33h_remote_pid=$(systemctl show caddy-lsyncd.service -p MainPID --value)
            action33h_remote_restarts=$(systemctl show caddy-lsyncd.service -p NRestarts --value)
        fi
        check "lsyncd_pid_stable_$action33h_remote_sample" test \
            "$(systemctl show caddy-lsyncd.service -p MainPID --value)" = "$action33h_remote_pid"
        check "lsyncd_restart_count_stable_$action33h_remote_sample" test \
            "$(systemctl show caddy-lsyncd.service -p NRestarts --value)" = "$action33h_remote_restarts"
        sleep 1
    done
}
suspend_sync_health_for_lsyncd_outage() {
    local action33h_remote_label=$1
    local action33h_remote_timer_state

    run_captured "${action33h_remote_label}_health_timer_pre" systemctl show \
        caddy-sync-health.timer -p ActiveState -p UnitFileState || return
    check "${action33h_remote_label}_health_timer_enabled_before" \
        systemctl is-enabled --quiet caddy-sync-health.timer || return
    action33h_remote_timer_state=$(systemctl is-active \
        caddy-sync-health.timer 2>/dev/null || true)
    case "$action33h_remote_timer_state" in
        active)
            run_captured "${action33h_remote_label}_health_timer_stop" \
                systemctl stop caddy-sync-health.timer || return
            ;;
        inactive)
            printf '%s_%s_%s_health_timer_already_inactive=true\n' \
                "$prefix" "$node_token" "$action33h_remote_label"
            ;;
        *)
            printf '%s_%s_check_%s_health_timer_state_safe=false\n' \
                "$prefix" "$node_token" "$action33h_remote_label" >&2
            return 1
            ;;
    esac
    check "${action33h_remote_label}_health_timer_inactive" test \
        "$(systemctl is-active caddy-sync-health.timer 2>/dev/null || true)" = inactive || return
    check "${action33h_remote_label}_health_timer_still_enabled" \
        systemctl is-enabled --quiet caddy-sync-health.timer || return
    run_captured "${action33h_remote_label}_health_worker_stop" systemctl stop \
        caddy-sync-health.service || return
    check "${action33h_remote_label}_health_worker_inactive" test \
        "$(systemctl is-active caddy-sync-health.service 2>/dev/null || true)" = inactive || return
}
assert_lsyncd_stable_for_health() {
    local action33h_remote_label=$1
    local action33h_remote_pid
    local action33h_remote_restarts
    local action33h_remote_sample

    check "${action33h_remote_label}_lsyncd_active" systemctl is-active \
        --quiet caddy-lsyncd.service || return
    action33h_remote_pid=$(systemctl show caddy-lsyncd.service \
        -p MainPID --value) || return
    action33h_remote_restarts=$(systemctl show caddy-lsyncd.service \
        -p NRestarts --value) || return
    check "${action33h_remote_label}_lsyncd_pid_positive" \
        test "$action33h_remote_pid" -gt 0 || return
    for action33h_remote_sample in 1 2 3 4 5; do
        check "${action33h_remote_label}_lsyncd_pid_stable_$action33h_remote_sample" \
            test "$(systemctl show caddy-lsyncd.service -p MainPID --value)" = \
            "$action33h_remote_pid" || return
        check "${action33h_remote_label}_lsyncd_restarts_stable_$action33h_remote_sample" \
            test "$(systemctl show caddy-lsyncd.service -p NRestarts --value)" = \
            "$action33h_remote_restarts" || return
        sleep 1
    done
    run_captured "${action33h_remote_label}_lsyncd_state" systemctl show \
        caddy-lsyncd.service -p ActiveState -p SubState -p Result -p MainPID \
        -p NRestarts || return
    check "${action33h_remote_label}_lsyncd_result_success" test \
        "$(systemctl show caddy-lsyncd.service -p Result --value)" = success || return
}
restore_and_accept_sync_health() {
    local action33h_remote_label=$1
    local action33h_remote_worker_state

    check "${action33h_remote_label}_health_timer_suspended_before_lsyncd" test \
        "$(systemctl is-active caddy-sync-health.timer 2>/dev/null || true)" = inactive || return
    run_captured "${action33h_remote_label}_lsyncd_start" systemctl start \
        caddy-lsyncd.service || return
    assert_lsyncd_stable_for_health "$action33h_remote_label" || return
    action33h_remote_worker_state=$(systemctl is-failed \
        caddy-sync-health.service 2>/dev/null || true)
    printf '%s_%s_%s_health_worker_pre_reset_state=%s\n' "$prefix" \
        "$node_token" "$action33h_remote_label" "$action33h_remote_worker_state"
    if [[ "$action33h_remote_worker_state" = failed ]]; then
        run_captured "${action33h_remote_label}_health_worker_reset" \
            systemctl reset-failed caddy-sync-health.service || return
        printf '%s_%s_%s_health_worker_reset=true\n' "$prefix" \
            "$node_token" "$action33h_remote_label"
    else
        printf '%s_%s_%s_health_worker_reset=false\n' "$prefix" \
            "$node_token" "$action33h_remote_label"
    fi
    run_captured "${action33h_remote_label}_health_worker_run" systemctl start \
        caddy-sync-health.service || return
    check "${action33h_remote_label}_health_worker_result_success" test \
        "$(systemctl show caddy-sync-health.service -p Result --value)" = success || return
    check "${action33h_remote_label}_health_worker_nonfailed" test \
        "$(systemctl is-failed caddy-sync-health.service 2>/dev/null || true)" != failed || return
    run_captured "${action33h_remote_label}_health_timer_enable" systemctl enable \
        caddy-sync-health.timer || return
    run_captured "${action33h_remote_label}_health_timer_start" systemctl start \
        caddy-sync-health.timer || return
    check "${action33h_remote_label}_health_timer_active_after" \
        systemctl is-active --quiet caddy-sync-health.timer || return
    check "${action33h_remote_label}_health_timer_enabled_after" \
        systemctl is-enabled --quiet caddy-sync-health.timer || return
    run_captured "${action33h_remote_label}_health_timer_post" systemctl show \
        caddy-sync-health.timer -p ActiveState -p UnitFileState || return
}
accept_and_freeze_invalid_receiver_rejection() {
    local action33h_remote_cursor
    local action33h_remote_elapsed=0
    local action33h_remote_journal_status=0
    local action33h_remote_rejection_observed=false
    local action33h_remote_stdout=$evidence_directory/invalid_transport_receiver_journal.stdout
    local action33h_remote_stderr=$evidence_directory/invalid_transport_receiver_journal.stderr
    local action33h_remote_status_file=$evidence_directory/invalid_transport_receiver_journal.status

    check invalid_transport_health_timer_suspended_before_lsyncd test \
        "$(systemctl is-active caddy-sync-health.timer 2>/dev/null || true)" = inactive || return
    check invalid_transport_health_timer_still_enabled \
        systemctl is-enabled --quiet caddy-sync-health.timer || return
    run_captured invalid_transport_journal_cursor journalctl --show-cursor \
        -n 0 --no-pager || return
    action33h_remote_cursor=$(awk '/^-- cursor:/ { print $3 }' \
        "$evidence_directory/invalid_transport_journal_cursor.stdout" | tail -n 1)
    check invalid_transport_journal_cursor_present test \
        -n "$action33h_remote_cursor" || return
    run_captured invalid_transport_lsyncd_start systemctl start \
        caddy-lsyncd.service || return

    install -m 0600 /dev/null "$action33h_remote_stdout"
    install -m 0600 /dev/null "$action33h_remote_stderr"
    install -m 0600 /dev/null "$action33h_remote_status_file"
    while ((action33h_remote_elapsed < 30)); do
        action33h_remote_journal_status=0
        journalctl --after-cursor "$action33h_remote_cursor" --no-pager \
            -u caddy-lsyncd.service -o cat >"$action33h_remote_stdout" \
            2>"$action33h_remote_stderr" || action33h_remote_journal_status=$?
        printf '%s\n' "$action33h_remote_journal_status" \
            >"$action33h_remote_status_file"
        if [[ "$action33h_remote_journal_status" -ne 0 ]]; then
            break
        fi
        if grep -Fq \
            'caddy_sync_finalize_v2_check_manifest_file_set_exact=false' \
            "$action33h_remote_stdout"; then
            action33h_remote_rejection_observed=true
            break
        fi
        sleep 1
        action33h_remote_elapsed=$((action33h_remote_elapsed + 1))
    done
    printf '%s_%s_invalid_transport_rejection_seconds=%s\n' "$prefix" \
        "$node_token" "$action33h_remote_elapsed"
    printf '%s_%s_invalid_transport_receiver_journal_status=%s\n' \
        "$prefix" "$node_token" "$action33h_remote_journal_status"
    emit_stream invalid_transport_receiver_journal_stdout \
        "$action33h_remote_stdout" || return
    emit_stream invalid_transport_receiver_journal_stderr \
        "$action33h_remote_stderr" || return
    check invalid_transport_receiver_journal_status_zero test \
        "$action33h_remote_journal_status" -eq 0 || return
    check invalid_transport_receiver_rejection_observed test \
        "$action33h_remote_rejection_observed" = true || return
    run_captured invalid_transport_lsyncd_freeze systemctl stop \
        caddy-lsyncd.service || return
    check invalid_transport_lsyncd_frozen test \
        "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = inactive || return
    run_captured invalid_transport_lsyncd_frozen_state systemctl show \
        caddy-lsyncd.service -p ActiveState -p SubState -p Result -p MainPID \
        -p ExecMainStatus -p NRestarts || return
    check invalid_transport_health_timer_remains_suspended test \
        "$(systemctl is-active caddy-sync-health.timer 2>/dev/null || true)" = inactive || return
}
prepare_current_health_baseline() {
    local action33h_remote_status=0

    if suspend_sync_health_for_lsyncd_outage baseline_repair; then
        if restore_and_accept_sync_health baseline_repair; then
            :
        else
            action33h_remote_status=$?
        fi
    else
        action33h_remote_status=$?
    fi
    if [[ "$action33h_remote_status" -ne 0 ]]; then
        systemctl start caddy-lsyncd.service >/dev/null 2>&1 || true
        systemctl enable caddy-sync-health.timer >/dev/null 2>&1 || true
        systemctl start caddy-sync-health.timer >/dev/null 2>&1 || true
    fi
    return "$action33h_remote_status"
}
assert_recovered_without_keepalived() {
    local action33h_remote_unit

    for action33h_remote_unit in caddy.service caddy-lsyncd.service ssh.service \
        caddy-sync-reconcile.path caddy-sync-health.timer \
        caddy-cert-expiry.timer; do
        check "recovered_${action33h_remote_unit//[^A-Za-z0-9]/_}_active" \
            systemctl is-active --quiet "$action33h_remote_unit"
        check "recovered_${action33h_remote_unit//[^A-Za-z0-9]/_}_enabled" \
            systemctl is-enabled --quiet "$action33h_remote_unit"
    done
    check keepalived_still_inactive test \
        "$(systemctl is-active keepalived.service 2>/dev/null || true)" = inactive
}
assert_no_action_residue() {
    check outgoing_residue_absent test -z \
        "$(find "$outgoing_root" -mindepth 1 -maxdepth 1 \
            -name 'action33h-*' -print -quit)"
    check incoming_residue_absent test -z \
        "$(find "$incoming_root" -mindepth 2 -maxdepth 2 \
            -name 'action33h-*' -print -quit)"
    check release_residue_absent test -z \
        "$(find "$releases_root" -mindepth 1 -maxdepth 1 \
            -name 'action33h-*' -print -quit)"
}
render_controlled_recovery_script() {
    local action33h_remote_script=$1

    # The recovery unit expands its own evidence and revision variables.
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' \
        "evidence='$evidence_directory/control-recovery-pretransport'" \
        "revision='action33h-$run_id-$scenario'" \
        'if [[ ! -e "/var/lib/caddy-sync/incoming/node-a/$revision" && ! -e "/var/lib/caddy-sync/incoming/node-b/$revision" ]]; then printf "true\n" >"$evidence"; else printf "false\n" >"$evidence"; fi' \
        'chmod 0600 "$evidence"' \
        'systemctl start ssh.service caddy.service caddy-lsyncd.service caddy-sync-reconcile.path' \
        >"$action33h_remote_script"
}
write_controlled_recovery_script() {
    local action33h_remote_script=$1

    install -o root -g root -m 0700 /dev/null "$action33h_remote_script"
    render_controlled_recovery_script "$action33h_remote_script"
    chmod 0700 "$action33h_remote_script"
}
arm_controlled_recovery() {
    local action33h_remote_script=/run/caddy-action33h-recovery-$run_id-$scenario.sh
    local action33h_remote_unit=caddy-action33h-recovery-$run_id-$scenario

    write_controlled_recovery_script "$action33h_remote_script"
    run_captured recovery_arm systemd-run --unit "$action33h_remote_unit" --on-active=45s --property=Type=oneshot /bin/bash "$action33h_remote_script"
}
controlled_outage() {
    arm_controlled_recovery
    suspend_sync_health_for_lsyncd_outage controlled_outage
    run_captured controlled_outage systemctl stop keepalived.service \
        caddy-sync-reconcile.path caddy-lsyncd.service caddy.service ssh.service
}
prepare_reboot() {
    suspend_sync_health_for_lsyncd_outage reboot
    run_captured health_timer_disable_for_reboot systemctl disable \
        caddy-sync-health.timer
    run_captured keepalived_disable systemctl disable --now keepalived.service
    run_captured reboot_schedule systemd-run --unit "caddy-action33h-reboot-$run_id-$scenario" --on-active=3s /usr/bin/systemctl reboot
}
restore_services() {
    suspend_sync_health_for_lsyncd_outage restore_services
    run_captured enable_restore systemctl enable ssh.service caddy.service \
        caddy-lsyncd.service caddy-sync-reconcile.path caddy-cert-expiry.timer \
        keepalived.service
    run_captured start_restore systemctl start ssh.service caddy.service \
        caddy-lsyncd.service caddy-sync-reconcile.path caddy-cert-expiry.timer \
        keepalived.service
    restore_and_accept_sync_health restore_services
}
prepare_cleanup_services() {
    run_captured cleanup_prerequisites systemctl start ssh.service \
        caddy.service || return
    if ! systemctl is-enabled --quiet caddy-sync-health.timer; then
        run_captured cleanup_health_timer_enable systemctl enable \
            caddy-sync-health.timer || return
    fi
    check cleanup_health_timer_enabled systemctl is-enabled --quiet \
        caddy-sync-health.timer || return
}
cleanup_owned() {
    local action33h_remote_path
    local action33h_remote_original_revision
    local action33h_remote_unit
    suspend_sync_health_for_lsyncd_outage cleanup
    run_captured cleanup_transport_freeze systemctl stop \
        caddy-sync-reconcile.path caddy-lsyncd.service
    systemctl stop "caddy-action33h-recovery-$run_id-$scenario.timer" "caddy-action33h-recovery-$run_id-$scenario.service" >/dev/null 2>&1 || true
    for action33h_remote_unit in caddy-sync-reconcile.service caddy-lsyncd.service; do
        if [[ "$(systemctl is-failed "$action33h_remote_unit" 2>/dev/null || true)" = failed ]]; then
            systemctl reset-failed "$action33h_remote_unit"
        fi
    done
    for action33h_remote_path in "$outgoing_root"/action33h-"$run_id"-* "$incoming_root"/node-a/action33h-"$run_id"-* "$incoming_root"/node-b/action33h-"$run_id"-* "$releases_root"/action33h-"$run_id"-*; do
        [[ -e "$action33h_remote_path" && ! -L "$action33h_remote_path" ]] || continue
        rm -rf -- "$action33h_remote_path"
    done
    if [[ "$scenario" = interrupted-transfer ]]; then
        action33h_remote_original_revision=$(jq -er '.revision' \
            "$(cat "$evidence_base/$run_id/baseline/$role/current-release")/release-manifest.json")
        for action33h_remote_path in \
            "$outgoing_root/$action33h_remote_original_revision" \
            "$incoming_root/node-a/$action33h_remote_original_revision"; do
            [[ -e "$action33h_remote_path" && ! -L "$action33h_remote_path" ]] || continue
            rm -rf -- "$action33h_remote_path"
        done
    fi
    rm -f -- "/run/caddy-action33h-recovery-$run_id-$scenario.sh"
    for action33h_remote_path in /run/caddy-action33h-stage-"$run_id"-"$scenario"-*; do
        [[ -e "$action33h_remote_path" && ! -L "$action33h_remote_path" ]] || continue
        rm -rf -- "$action33h_remote_path"
    done
}
prepare_fixture_source() {
    local action33h_remote_revision=$1
    local action33h_remote_source=/run/caddy-action33h-stage-$run_id-$scenario-$action33h_remote_revision

    check fixture_source_absent test ! -e "$action33h_remote_source" >&2
    install -d -o root -g root -m 0700 "$action33h_remote_source"
    cp -a -- "$(current_release)/." "$action33h_remote_source/"
    printf '\n# Action 33h reliability fixture %s\n' "$action33h_remote_revision" \
        >>"$action33h_remote_source/Caddyfile"
    printf '%s\n' "$action33h_remote_source"
}
build_candidate_manifest() {
    local action33h_remote_destination=$1
    local action33h_remote_manifest_temp=$2

    # The output file must remain outside the enumerated candidate tree. Shell
    # redirection creates it before find starts, so placing it inside the tree
    # would cause the manifest to list its own temporary pathname.
    (
        cd "$action33h_remote_destination" || exit 1
        find . -type f ! -path ./manifest.sha256 \
            ! -path ./.finalize-request ! -path ./.complete \
            ! -path ./.complete.pending -print0 | LC_ALL=C sort -z |
            xargs -0 sha256sum
    ) >"$action33h_remote_manifest_temp"
}
rebuild_candidate_manifest() {
    local action33h_remote_destination=$1
    local action33h_remote_revision=$2
    local action33h_remote_manifest_temp=
    local action33h_remote_label=manifest_${action33h_remote_revision}

    action33h_remote_manifest_temp=$outgoing_root/action33h-$run_id-manifest-$action33h_remote_revision.tmp
    check "${action33h_remote_label}_temp_absent" test ! -e \
        "$action33h_remote_manifest_temp" || return
    install -m 0600 /dev/null "$action33h_remote_manifest_temp" || return
    if ! run_captured "${action33h_remote_label}_build" \
        build_candidate_manifest "$action33h_remote_destination" \
        "$action33h_remote_manifest_temp"; then
        rm -f -- "$action33h_remote_manifest_temp"
        return 1
    fi
    check "${action33h_remote_label}_temp_nonempty" test -s \
        "$action33h_remote_manifest_temp" || {
        rm -f -- "$action33h_remote_manifest_temp"
        return 1
    }
    mv -- "$action33h_remote_manifest_temp" \
        "$action33h_remote_destination/manifest.sha256" || return
    check "${action33h_remote_label}_temp_consumed" test ! -e \
        "$action33h_remote_manifest_temp" || return
    check "${action33h_remote_label}_file_set_exact" \
        manifest_file_set_matches "$action33h_remote_destination" || return
    # The positional parameter is intentionally expanded by the child shell.
    # shellcheck disable=SC2016
    check "${action33h_remote_label}_hashes_valid" \
        bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action33h_remote_destination" || return
}
adopt_publisher_output() {
    local action33h_remote_source=$1
    local action33h_remote_revision=$2
    local action33h_remote_emergency=$3
    local action33h_remote_before=$evidence_directory/publish.before
    local action33h_remote_after=$evidence_directory/publish.after
    local action33h_remote_generated
    local action33h_remote_destination=$outgoing_root/$action33h_remote_revision

    find "$outgoing_root" -mindepth 1 -maxdepth 1 -type d \
        -printf '%f\n' | LC_ALL=C sort >"$action33h_remote_before"
    if [[ "$action33h_remote_emergency" = true ]]; then
        run_captured publisher "$publisher" --source "$action33h_remote_source" \
            --node-role "$role" --emergency
    else
        run_captured publisher "$publisher" --source "$action33h_remote_source" \
            --node-role "$role"
    fi
    find "$outgoing_root" -mindepth 1 -maxdepth 1 -type d \
        -printf '%f\n' | LC_ALL=C sort >"$action33h_remote_after"
    action33h_remote_generated=$(comm -13 "$action33h_remote_before" \
        "$action33h_remote_after")
    check publisher_created_one test \
        "$(printf '%s\n' "$action33h_remote_generated" |
            awk 'NF { count++ } END { print count + 0 }')" -eq 1
    check owned_destination_absent test ! -e "$action33h_remote_destination"
    mv -- "$outgoing_root/$action33h_remote_generated" "$action33h_remote_destination"
    chmod u+w "$action33h_remote_destination/release-manifest.json"
    jq --arg revision "$action33h_remote_revision" '.revision = $revision' \
        "$action33h_remote_destination/release-manifest.json" \
        >"$action33h_remote_destination/release-manifest.json.new"
    mv -- "$action33h_remote_destination/release-manifest.json.new" \
        "$action33h_remote_destination/release-manifest.json"
    rebuild_candidate_manifest "$action33h_remote_destination" \
        "$action33h_remote_revision" || return
    chown -R caddy-sync:caddy-sync "$action33h_remote_destination"
    find "$action33h_remote_destination" -type d -exec chmod 0550 {} +
    find "$action33h_remote_destination" -type f -exec chmod 0440 {} +
    rm -rf -- "$action33h_remote_source"
}
publish_owned() {
    local action33h_remote_revision=$1
    local action33h_remote_emergency=$2
    local action33h_remote_resume=${3:-true}
    local action33h_remote_source

    suspend_sync_health_for_lsyncd_outage publish
    run_captured transport_freeze systemctl stop caddy-lsyncd.service
    action33h_remote_source=$(prepare_fixture_source "$action33h_remote_revision")
    adopt_publisher_output "$action33h_remote_source" \
        "$action33h_remote_revision" "$action33h_remote_emergency"
    if [[ "$action33h_remote_resume" = true ]]; then
        restore_and_accept_sync_health publish
    fi
}
promote_outgoing() {
    local action33h_remote_revision=$1
    local action33h_remote_source=$outgoing_root/$action33h_remote_revision
    local action33h_remote_destination=$releases_root/$action33h_remote_revision

    check outgoing_fixture_present test -d "$action33h_remote_source"
    check destination_absent test ! -e "$action33h_remote_destination"
    cp -a -- "$action33h_remote_source" "$action33h_remote_destination"
    rm -f -- "$action33h_remote_destination/.finalize-request"
    : >"$action33h_remote_destination/.complete"
    chown -R caddy:caddy "$action33h_remote_destination"
    find "$action33h_remote_destination" -type d -exec chmod 0550 {} +
    find "$action33h_remote_destination" -type f -exec chmod 0440 {} +
    ln -s "$action33h_remote_destination" /etc/caddy/current.action33h
    mv -Tf /etc/caddy/current.action33h /etc/caddy/current
    run_captured caddy_reload systemctl reload caddy.service
}
wait_current() {
    local action33h_remote_revision=$1
    local action33h_remote_elapsed=0

    while ((action33h_remote_elapsed < 60)); do
        if [[ "$(current_release)" = "$releases_root/$action33h_remote_revision" ]]; then
            printf '%s_%s_release_wait_seconds=%s\n' "$prefix" "$node_token" \
                "$action33h_remote_elapsed"
            return 0
        fi
        sleep 1
        action33h_remote_elapsed=$((action33h_remote_elapsed + 1))
    done
    return 1
}
restore_original_release() {
    local action33h_remote_original_file=$evidence_base/$run_id/baseline/$role/current-release
    local action33h_remote_original

    action33h_remote_original=$(cat "$action33h_remote_original_file")
    check original_release_safe test -d "$action33h_remote_original"
    if [[ "$(current_release)" != "$action33h_remote_original" ]]; then
        ln -s "$action33h_remote_original" /etc/caddy/current.action33h
        mv -Tf /etc/caddy/current.action33h /etc/caddy/current
        run_captured restore_caddy_reload systemctl reload caddy.service
    fi
}
stage_invalid() {
    local action33h_remote_revision=$1
    local action33h_remote_candidate=$outgoing_root/$action33h_remote_revision

    publish_owned "$action33h_remote_revision" false false
    chmod u+w "$action33h_remote_candidate/Caddyfile"
    printf '# invalidated after manifest creation\n' \
        >>"$action33h_remote_candidate/Caddyfile"
    chmod 0440 "$action33h_remote_candidate/Caddyfile"
    accept_and_freeze_invalid_receiver_rejection
}
assert_invalid_rejected() {
    local action33h_remote_revision=$1
    local action33h_remote_candidate=$incoming_root/node-a/$action33h_remote_revision
    local action33h_remote_elapsed=0

    while ((action33h_remote_elapsed < 30)) &&
        [[ ! -d "$action33h_remote_candidate" ]]; do
        sleep 1
        action33h_remote_elapsed=$((action33h_remote_elapsed + 1))
    done
    check invalid_candidate_received test -d "$action33h_remote_candidate"
    check invalid_completion_absent test ! -e "$action33h_remote_candidate/.complete"
    check invalid_destination_absent test ! -e "$releases_root/$action33h_remote_revision"
    check invalid_selection_unchanged test \
        "$(current_release)" = "$(cat "$evidence_base/$run_id/baseline/$role/current-release")"
}
assert_replay_destination_absent() {
    local action33h_remote_destination=$1

    check replay_outgoing_absent test ! -e "$action33h_remote_destination"
}
stage_active_replay() {
    local action33h_remote_revision
    local action33h_remote_destination

    action33h_remote_revision=$(jq -er '.revision' \
        "$(current_release)/release-manifest.json")
    action33h_remote_destination=$outgoing_root/$action33h_remote_revision
    assert_replay_destination_absent "$action33h_remote_destination"
    suspend_sync_health_for_lsyncd_outage replay_transport
    run_captured replay_transport_freeze systemctl stop caddy-lsyncd.service
    cp -a -- "$(current_release)" "$action33h_remote_destination"
    rm -f -- "$action33h_remote_destination/.complete" \
        "$action33h_remote_destination/.finalize-request"
    chown -R caddy-sync:caddy-sync "$action33h_remote_destination"
    find "$action33h_remote_destination" -type d -exec chmod 0550 {} +
    find "$action33h_remote_destination" -type f -exec chmod 0440 {} +
    printf '%s_%s_active_replay_revision=%s\n' "$prefix" "$node_token" \
        "$action33h_remote_revision"
    restore_and_accept_sync_health replay_transport
}
assert_replay_incomplete() {
    local action33h_remote_revision=$1
    local action33h_remote_candidate=$incoming_root/node-a/$action33h_remote_revision
    local action33h_remote_elapsed=0

    while ((action33h_remote_elapsed < 30)) &&
        [[ ! -d "$action33h_remote_candidate" ]]; do
        sleep 1
        action33h_remote_elapsed=$((action33h_remote_elapsed + 1))
    done
    check replay_received test -d "$action33h_remote_candidate"
    check replay_request_absent test ! -e "$action33h_remote_candidate/.finalize-request"
    check replay_completion_absent test ! -e "$action33h_remote_candidate/.complete"
    check replay_selection_unchanged test \
        "$(current_release)" = "$(cat "$evidence_base/$run_id/baseline/$role/current-release")"
}
request_active_replay() {
    local action33h_remote_revision=$1
    local action33h_remote_candidate=$outgoing_root/$action33h_remote_revision

    suspend_sync_health_for_lsyncd_outage replay_request
    run_captured replay_request_freeze systemctl stop caddy-lsyncd.service
    check replay_outgoing_present test -d "$action33h_remote_candidate"
    chmod 0750 "$action33h_remote_candidate"
    : >"$action33h_remote_candidate/.finalize-request"
    chown caddy-sync:caddy-sync "$action33h_remote_candidate/.finalize-request"
    chmod 0440 "$action33h_remote_candidate/.finalize-request"
    chmod 0550 "$action33h_remote_candidate"
    restore_and_accept_sync_health replay_request
}
wait_replay_consumed() {
    local action33h_remote_revision=$1
    local action33h_remote_candidate=$incoming_root/node-a/$action33h_remote_revision
    local action33h_remote_elapsed=0

    while ((action33h_remote_elapsed < 60)); do
        if [[ ! -e "$action33h_remote_candidate" &&
            "$(current_release)" = "$(cat "$evidence_base/$run_id/baseline/$role/current-release")" ]]; then
            printf '%s_%s_replay_reconcile_seconds=%s\n' "$prefix" \
                "$node_token" "$action33h_remote_elapsed"
            return 0
        fi
        sleep 1
        action33h_remote_elapsed=$((action33h_remote_elapsed + 1))
    done
    return 1
}
assert_conflict() {
    local action33h_remote_pair=$1
    local action33h_remote_first=${action33h_remote_pair%%+*}
    local action33h_remote_second=${action33h_remote_pair#*+}
    local action33h_remote_first_path=$incoming_root/node-a/$action33h_remote_first
    local action33h_remote_second_path=$incoming_root/node-a/$action33h_remote_second
    local action33h_remote_elapsed=0
    local action33h_remote_status=0
    local action33h_remote_caddy_cursor
    local action33h_remote_caddy_pid
    local action33h_remote_caddy_restarts

    # conditional-validator-explicit-failures-begin
    while ((action33h_remote_elapsed < 60)); do
        if [[ -f "$action33h_remote_first_path/.complete" &&
            -f "$action33h_remote_second_path/.complete" ]]; then break; fi
        sleep 1
        action33h_remote_elapsed=$((action33h_remote_elapsed + 1))
    done
    check conflict_first_finalized test -f \
        "$action33h_remote_first_path/.complete" || return
    check conflict_second_finalized test -f \
        "$action33h_remote_second_path/.complete" || return
    action33h_remote_caddy_pid=$(systemctl show caddy.service -p MainPID \
        --value)
    action33h_remote_caddy_restarts=$(systemctl show caddy.service -p NRestarts \
        --value)
    check conflict_caddy_pid_positive test "$action33h_remote_caddy_pid" \
        -gt 0 || return
    run_captured conflict_caddy_cursor journalctl -u caddy.service \
        --show-cursor -n 0 --no-pager || return
    action33h_remote_caddy_cursor=$(awk '/^-- cursor:/ { print $3 }' \
        "$evidence_directory/conflict_caddy_cursor.stdout" | tail -n 1)
    check conflict_caddy_cursor_present test -n \
        "$action33h_remote_caddy_cursor" || return
    systemctl start caddy-sync-reconcile.service \
        >"$evidence_directory/conflict.stdout" \
        2>"$evidence_directory/conflict.stderr" || action33h_remote_status=$?
    check conflict_worker_failed test "$action33h_remote_status" -ne 0 || return
    run_captured conflict_journal journalctl -u caddy-sync-reconcile.service \
        -n 50 --no-pager --no-hostname -o short-iso || return
    check conflict_message grep -Fq \
        'Multiple finalized candidates claim the active parent.' \
        "$evidence_directory/conflict_journal.stdout" || return
    run_captured conflict_caddy_journal journalctl -u caddy.service \
        --after-cursor "$action33h_remote_caddy_cursor" --no-pager \
        --no-hostname -o short-iso || return
    check conflict_caddy_reload_absent test \
        "$(grep -Eic 'reload' \
            "$evidence_directory/conflict_caddy_journal.stdout" || true)" \
        -eq 0 || return
    check conflict_caddy_pid_unchanged test \
        "$(systemctl show caddy.service -p MainPID --value)" = \
        "$action33h_remote_caddy_pid" || return
    check conflict_caddy_restart_count_unchanged test \
        "$(systemctl show caddy.service -p NRestarts --value)" = \
        "$action33h_remote_caddy_restarts" || return
    assert_conflict_retained "$action33h_remote_pair" || return
    # conditional-validator-explicit-failures-end
}
assert_conflict_retained() {
    local action33h_remote_pair=$1
    local action33h_remote_first=${action33h_remote_pair%%+*}
    local action33h_remote_second=${action33h_remote_pair#*+}
    local action33h_remote_first_path=$incoming_root/node-a/$action33h_remote_first
    local action33h_remote_second_path=$incoming_root/node-a/$action33h_remote_second

    # conditional-validator-explicit-failures-begin
    check conflict_first_retained test -d "$action33h_remote_first_path" || return
    check conflict_second_retained test -d "$action33h_remote_second_path" || return
    check conflict_selection_unchanged test \
        "$(current_release)" = \
        "$(cat "$evidence_base/$run_id/baseline/$role/current-release")" || return
    check conflict_first_destination_absent test ! -e \
        "$releases_root/$action33h_remote_first" || return
    check conflict_second_destination_absent test ! -e \
        "$releases_root/$action33h_remote_second" || return
    # conditional-validator-explicit-failures-end
}
start_conflict_transport() {
    local action33h_remote_pid

    check conflict_transport_health_timer_suspended test \
        "$(systemctl is-active caddy-sync-health.timer 2>/dev/null || true)" = \
        inactive
    check conflict_transport_health_timer_enabled systemctl is-enabled --quiet \
        caddy-sync-health.timer
    run_captured conflict_transport_start systemctl start \
        caddy-lsyncd.service
    check conflict_transport_active systemctl is-active --quiet \
        caddy-lsyncd.service
    action33h_remote_pid=$(systemctl show caddy-lsyncd.service -p MainPID \
        --value)
    check conflict_transport_pid_positive test "$action33h_remote_pid" -gt 0
    run_captured conflict_transport_state systemctl show caddy-lsyncd.service \
        -p ActiveState -p SubState -p Result -p MainPID -p NRestarts
}
freeze_conflict_transport() {
    check conflict_freeze_health_timer_suspended test \
        "$(systemctl is-active caddy-sync-health.timer 2>/dev/null || true)" = \
        inactive
    run_captured conflict_transport_freeze systemctl stop \
        caddy-lsyncd.service
    check conflict_transport_inactive test \
        "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = \
        inactive
    check conflict_freeze_health_timer_still_enabled systemctl is-enabled \
        --quiet caddy-sync-health.timer
}

if [[ "$mode" = --self-test ]]; then
    printf '%s_self_test_complete=true\n' "$prefix"
    exit 0
fi
[[ "$role" =~ ^node-[ab]$ ]] && valid_token "$run_id" && valid_token "$scenario" || exit 64
evidence_directory=$evidence_base/$run_id/$scenario/$role
install -d -o root -g root -m 0700 "$evidence_directory"

case "$mode" in
    --baseline)
        if [[ "$scenario" = baseline ]]; then
            prepare_current_health_baseline
        fi
        capture_baseline
        assert_services
        assert_no_action_residue
        ;;
    --assert-master) assert_role_state MASTER four ;;
    --assert-backup) assert_role_state BACKUP zero ;;
    --assert-zero)
        check dns_ipv4_absent test "$(vip_count "$dns_ipv4")" -eq 0
        check caddy_ipv4_absent test "$(vip_count "$caddy_ipv4")" -eq 0
        check dns_ipv6_absent test "$(vip_count "$dns_ipv6")" -eq 0
        check caddy_ipv6_absent test "$(vip_count "$caddy_ipv6")" -eq 0
        ;;
    --relinquish) run_captured relinquish systemctl stop keepalived.service ;;
    --restore-services) restore_services ;;
    --prepare-cleanup) prepare_cleanup_services ;;
    --freeze)
        suspend_sync_health_for_lsyncd_outage fixture_freeze
        run_captured fixture_transport_freeze systemctl stop \
            caddy-sync-reconcile.path caddy-lsyncd.service
        ;;
    --controlled-outage) controlled_outage ;;
    --prepare-reboot) prepare_reboot ;;
    --rolling-maintenance)
        suspend_sync_health_for_lsyncd_outage rolling_maintenance
        run_captured rolling_restart systemctl restart caddy.service \
            caddy-lsyncd.service caddy-sync-reconcile.path \
            caddy-cert-expiry.timer
        restore_and_accept_sync_health rolling_maintenance
        ;;
    --restore-health) restore_and_accept_sync_health recovery ;;
    --assert-recovered) assert_recovered_without_keepalived ;;
    --assert-controlled-offline)
        check controlled_offline_transport_absent grep -Fxq true \
            "$evidence_directory/control-recovery-pretransport"
        ;;
    --boot-id)
        printf '%s_%s_observed_boot_id=%s\n' "$prefix" "$node_token" \
            "$(cat /proc/sys/kernel/random/boot_id)"
        ;;
    --reject-normal)
        check ordinary_node_b_publication_context test "$role" = node-b
        install -m 0600 /dev/null "$evidence_directory/reject.stdout" \
            "$evidence_directory/reject.stderr"
        if "$publisher" --source "$(current_release)" --node-role node-b >"$evidence_directory/reject.stdout" 2>"$evidence_directory/reject.stderr"; then exit 1; fi
        check ordinary_node_b_publication_rejected grep -Fxq \
            'Node B publishing requires --emergency.' \
            "$evidence_directory/reject.stderr"
        ;;
    --publish-normal)
        valid_token "$argument"
        publish_owned "$argument" false
        ;;
    --publish-emergency)
        valid_token "$argument"
        publish_owned "$argument" true
        ;;
    --stage-invalid)
        valid_token "$argument"
        stage_invalid "$argument"
        ;;
    --assert-invalid)
        valid_token "$argument"
        assert_invalid_rejected "$argument"
        ;;
    --stage-active-replay) stage_active_replay ;;
    --assert-replay-incomplete)
        valid_token "$argument"
        assert_replay_incomplete "$argument"
        ;;
    --request-active-replay)
        valid_token "$argument"
        request_active_replay "$argument"
        ;;
    --wait-replay-consumed)
        valid_token "$argument"
        check active_replay_consumed_once wait_replay_consumed "$argument"
        ;;
    --stop-reconcile) run_captured reconcile_path_stop systemctl stop caddy-sync-reconcile.path ;;
    --start-conflict-transport) start_conflict_transport ;;
    --freeze-conflict-transport) freeze_conflict_transport ;;
    --stage-conflict)
        valid_token "$argument"
        publish_owned "$argument" false false
        ;;
    --assert-conflict)
        [[ "$argument" == *+* ]]
        valid_token "${argument%%+*}"
        valid_token "${argument#*+}"
        assert_conflict "$argument"
        ;;
    --assert-conflict-retained)
        [[ "$argument" == *+* ]]
        valid_token "${argument%%+*}"
        valid_token "${argument#*+}"
        assert_conflict_retained "$argument"
        ;;
    --promote-outgoing)
        valid_token "$argument"
        promote_outgoing "$argument"
        ;;
    --wait-current)
        valid_token "$argument"
        check expected_release_activated wait_current "$argument"
        ;;
    --assert-queued)
        valid_token "$argument"
        check outgoing_release_queued test -d "$outgoing_root/$argument"
        ;;
    --assert-incoming-absent)
        valid_token "$argument"
        check offline_destination_received_nothing_from_node_a \
            test ! -e "$incoming_root/node-a/$argument"
        check offline_destination_received_nothing_from_node_b \
            test ! -e "$incoming_root/node-b/$argument"
        ;;
    --reconcile) run_captured reconcile systemctl start caddy-sync-reconcile.service ;;
    --cleanup)
        restore_original_release
        cleanup_owned
        assert_no_action_residue
        ;;
    --final)
        if [[ -f "$evidence_base/$run_id/$scenario/$role/journal_cursor.stdout" ]]; then
            action33h_remote_cursor=$(awk '/^-- cursor:/ { print $3 }' \
                "$evidence_base/$run_id/$scenario/$role/journal_cursor.stdout" |
                tail -n 1)
        fi
        if [[ -n "$action33h_remote_cursor" ]]; then
            run_captured scenario_journal journalctl \
                --after-cursor "$action33h_remote_cursor" --no-pager \
                --no-hostname -o short-iso
        fi
        capture_baseline
        assert_services
        assert_no_action_residue
        check original_release_path_restored cmp -s \
            "$evidence_base/$run_id/baseline/$role/current-release" \
            "$evidence_directory/current-release"
        check original_release_manifest_restored test \
            "$(file_hash "$(current_release)/release-manifest.json")" = \
            "$(cat "$evidence_base/$run_id/baseline/$role/release-manifest.sha256")"
        check quarantine_inventory_unchanged cmp -s \
            "$evidence_base/$run_id/baseline/$role/quarantine.inventory" \
            "$evidence_directory/quarantine.inventory"
        check incoming_inventory_restored cmp -s \
            "$evidence_base/$run_id/baseline/$role/incoming.inventory" \
            "$evidence_directory/incoming.inventory"
        check outgoing_inventory_restored cmp -s \
            "$evidence_base/$run_id/baseline/$role/outgoing.inventory" \
            "$evidence_directory/outgoing.inventory"
        if [[ "$role" = node-a ]]; then
            assert_role_state MASTER four
        else
            assert_role_state BACKUP zero
        fi
        ;;
    --remove-registry)
        check registry_present test -f "/tmp/caddy-action33h-registry-$run_id.tsv"
        rm -f -- "/tmp/caddy-action33h-registry-$run_id.tsv"
        check registry_removed test ! -e "/tmp/caddy-action33h-registry-$run_id.tsv"
        ;;
    *) exit 64 ;;
esac
printf '%s_%s_%s_complete=true\n' "$prefix" "$node_token" "${mode#--}"
