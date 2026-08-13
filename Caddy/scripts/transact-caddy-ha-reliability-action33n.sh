#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_33n_remote
readonly evidence_base=/tmp/caddy-action33n
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
readonly accepted_release_revision=20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04
readonly accepted_release_path=$releases_root/$accepted_release_revision
readonly accepted_release_manifest_sha256=beb54698e8722d6450f1125fd843808a376cf1be31dcbdef8fafe3cc5ba56109
readonly failed_action33k_run_id=20260813T000701Z-2499021
readonly failed_action33k_emergency_revision=action33k-$failed_action33k_run_id-node-a-reboot
readonly failed_action33k_normalized_revision=$failed_action33k_emergency_revision-normalized
readonly failed_action33k_normalized_release_path=$releases_root/$failed_action33k_normalized_revision
readonly failed_action33k_normalized_manifest_sha256=bf711fa44181d89654ea08530d5fd44a9dade7dc1a4cd5ea42858b1309d8f807
readonly -a baseline_files=(
    current-release
    release-manifest.sha256
    outgoing.inventory
    incoming.inventory
    quarantine.inventory
)

mode=${1:-}
role=${2:-}
run_id=${3:-}
scenario=${4:-none}
argument=${5:-}
node_token=${role//-/_}
evidence_directory=
action33n_remote_cursor=

valid_token() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
safe_stream() {
    local action33n_remote_stream=$1
    [[ "$(wc -c <"$action33n_remote_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action33n_remote_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action33n_remote_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action33n_remote_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action33n_remote_stream"
}
emit_stream() {
    local action33n_remote_label=$1
    local action33n_remote_path=$2
    printf '%s_%s_%s_bytes=%s\n' "$prefix" "$node_token" "$action33n_remote_label" "$(wc -c <"$action33n_remote_path")"
    printf '%s_%s_%s_lines=%s\n' "$prefix" "$node_token" "$action33n_remote_label" "$(line_count "$action33n_remote_path")"
    printf '%s_%s_%s_sha256=%s\n' "$prefix" "$node_token" "$action33n_remote_label" "$(file_hash "$action33n_remote_path")"
    safe_stream "$action33n_remote_path" || return 97
    printf '%s_%s_%s_classification=bounded_safe\n' "$prefix" "$node_token" "$action33n_remote_label"
    if [[ -s "$action33n_remote_path" ]]; then
        printf '%s_%s_%s_begin\n' "$prefix" "$node_token" "$action33n_remote_label"
        sed "s/^/${prefix}_${node_token}_${action33n_remote_label}_content=/" \
            "$action33n_remote_path"
        printf '%s_%s_%s_end\n' "$prefix" "$node_token" "$action33n_remote_label"
    else
        printf '%s_%s_%s_content=empty\n' "$prefix" "$node_token" "$action33n_remote_label"
    fi
}
run_captured() {
    local action33n_remote_label=$1
    local action33n_remote_status=0
    shift
    install -m 0600 /dev/null "$evidence_directory/$action33n_remote_label.stdout"
    install -m 0600 /dev/null "$evidence_directory/$action33n_remote_label.stderr"
    install -m 0600 /dev/null "$evidence_directory/$action33n_remote_label.status"
    "$@" >"$evidence_directory/$action33n_remote_label.stdout" 2>"$evidence_directory/$action33n_remote_label.stderr" || action33n_remote_status=$?
    printf '%s\n' "$action33n_remote_status" >"$evidence_directory/$action33n_remote_label.status"
    printf '%s_%s_%s_status=%s\n' "$prefix" "$node_token" "$action33n_remote_label" "$action33n_remote_status"
    emit_stream "${action33n_remote_label}_stdout" "$evidence_directory/$action33n_remote_label.stdout"
    emit_stream "${action33n_remote_label}_stderr" "$evidence_directory/$action33n_remote_label.stderr"
    [[ "$action33n_remote_status" -eq 0 ]]
}
prepare_reject_capture_files() {
    install -m 0600 /dev/null "$evidence_directory/reject.stdout"
    install -m 0600 /dev/null "$evidence_directory/reject.stderr"
    install -m 0600 /dev/null "$evidence_directory/reject.status"
}
check() {
    local action33n_remote_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action33n_remote_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "$node_token" "$action33n_remote_label" >&2
    return 1
}
inventory_tree() {
    local action33n_remote_root=$1
    if [[ -d "$action33n_remote_root" && ! -L "$action33n_remote_root" ]]; then
        find "$action33n_remote_root" -xdev -printf '%P\t%y\t%m\t%u\t%g\t%s\n' | LC_ALL=C sort
    else
        printf 'absent\n'
    fi
}
manifest_paths_safe() {
    local action33n_remote_manifest=$1

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
    ' "$action33n_remote_manifest"
}
manifest_file_set_matches() {
    local action33n_remote_release=$1
    local action33n_remote_expected
    local action33n_remote_observed
    local action33n_remote_status=0

    action33n_remote_expected=$(mktemp /tmp/caddy-action33n-manifest-expected.XXXXXX) || return 1
    action33n_remote_observed=$(mktemp /tmp/caddy-action33n-manifest-observed.XXXXXX) || {
        rm -f -- "$action33n_remote_expected"
        return 1
    }
    awk '{ print substr($0, 67) }' \
        "$action33n_remote_release/manifest.sha256" | LC_ALL=C sort -u \
        >"$action33n_remote_expected"
    (
        cd "$action33n_remote_release"
        find . -type f \
            ! -path ./manifest.sha256 \
            ! -path ./.finalize-request \
            ! -path ./.complete \
            ! -path ./.complete.pending -print | LC_ALL=C sort
    ) >"$action33n_remote_observed"
    cmp -s "$action33n_remote_expected" "$action33n_remote_observed" ||
        action33n_remote_status=$?
    rm -f -- "$action33n_remote_expected" "$action33n_remote_observed"
    [[ "$action33n_remote_status" -eq 0 ]]
}
release_manifest_valid() {
    local action33n_remote_release=$1

    [[ -d "$action33n_remote_release" && ! -L "$action33n_remote_release" ]] || return 1
    [[ -f "$action33n_remote_release/release-manifest.json" &&
        ! -L "$action33n_remote_release/release-manifest.json" ]] || return 1
    [[ -f "$action33n_remote_release/manifest.sha256" &&
        ! -L "$action33n_remote_release/manifest.sha256" ]] || return 1
    [[ -z "$(find "$action33n_remote_release" -type l -print -quit)" ]] || return 1
    [[ -z "$(find "$action33n_remote_release" ! -type d ! -type f -print -quit)" ]] || return 1
    [[ -z "$(find "$action33n_remote_release" -type f -links +1 -print -quit)" ]] || return 1
    jq -e '
        (.revision | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) and
        (.parent_revision | type == "string") and
        (.source_node == "node-a" or .source_node == "node-b") and
        (.created_at | type == "string" and length > 0)
    ' "$action33n_remote_release/release-manifest.json" >/dev/null || return 1
    manifest_paths_safe "$action33n_remote_release/manifest.sha256" || return 1
    manifest_file_set_matches "$action33n_remote_release" || return 1
    (
        cd "$action33n_remote_release"
        sha256sum --strict --check manifest.sha256 >/dev/null 2>&1
    )
}
assert_outbound_role_policy() {
    local action33n_remote_role=$1
    local action33n_remote_outbound=$2
    local action33n_remote_releases=$3
    local action33n_remote_current=$4
    local action33n_remote_candidate
    local action33n_remote_count=0
    local action33n_remote_name
    local action33n_remote_revision
    local action33n_remote_source
    local action33n_remote_target

    [[ -d "$action33n_remote_outbound" && ! -L "$action33n_remote_outbound" ]] || return 1
    [[ -d "$action33n_remote_releases" && ! -L "$action33n_remote_releases" ]] || return 1
    [[ -d "$action33n_remote_current" && ! -L "$action33n_remote_current" ]] || return 1
    while IFS= read -r -d '' action33n_remote_candidate; do
        action33n_remote_count=$((action33n_remote_count + 1))
        action33n_remote_name=${action33n_remote_candidate##*/}
        printf '%s_%s_outbound_entry_%s_name=%s\n' "$prefix" "$node_token" \
            "$action33n_remote_count" "$action33n_remote_name"
        check "outbound_entry_${action33n_remote_count}_name_safe" \
            valid_token "$action33n_remote_name" || return 1
        check "outbound_entry_${action33n_remote_count}_directory" \
            test -d "$action33n_remote_candidate" || return 1
        check "outbound_entry_${action33n_remote_count}_not_symlink" \
            test ! -L "$action33n_remote_candidate" || return 1
        release_manifest_valid "$action33n_remote_candidate" || {
            check "outbound_entry_${action33n_remote_count}_manifest_valid" false || true
            return 1
        }
        check "outbound_entry_${action33n_remote_count}_manifest_valid" true || return 1
        check "outbound_entry_${action33n_remote_count}_request_regular" \
            test -f "$action33n_remote_candidate/.finalize-request" || return 1
        check "outbound_entry_${action33n_remote_count}_request_not_symlink" \
            test ! -L "$action33n_remote_candidate/.finalize-request" || return 1
        check "outbound_entry_${action33n_remote_count}_request_empty" \
            test ! -s "$action33n_remote_candidate/.finalize-request" || return 1
        check "outbound_entry_${action33n_remote_count}_complete_absent" \
            test ! -e "$action33n_remote_candidate/.complete" || return 1
        check "outbound_entry_${action33n_remote_count}_pending_absent" \
            test ! -e "$action33n_remote_candidate/.complete.pending" || return 1
        check "outbound_entry_${action33n_remote_count}_directories_locked" \
            test -z "$(find "$action33n_remote_candidate" -type d ! -perm 0550 -print -quit)" || return 1
        check "outbound_entry_${action33n_remote_count}_files_locked" \
            test -z "$(find "$action33n_remote_candidate" -type f ! -perm 0440 -print -quit)" || return 1
        action33n_remote_revision=$(jq -er '.revision' \
            "$action33n_remote_candidate/release-manifest.json")
        action33n_remote_source=$(jq -er '.source_node' \
            "$action33n_remote_candidate/release-manifest.json")
        printf '%s_%s_outbound_entry_%s_revision=%s\n' "$prefix" "$node_token" \
            "$action33n_remote_count" "$action33n_remote_revision"
        printf '%s_%s_outbound_entry_%s_source=%s\n' "$prefix" "$node_token" \
            "$action33n_remote_count" "$action33n_remote_source"
        check "outbound_entry_${action33n_remote_count}_path_matches_revision" \
            test "$action33n_remote_name" = "$action33n_remote_revision" || return 1
        check "outbound_entry_${action33n_remote_count}_source_node_a" \
            test "$action33n_remote_source" = node-a || return 1
        action33n_remote_target=$action33n_remote_releases/$action33n_remote_revision
        check "outbound_entry_${action33n_remote_count}_installed_release" \
            test -d "$action33n_remote_target" || return 1
        check "outbound_entry_${action33n_remote_count}_installed_not_symlink" \
            test ! -L "$action33n_remote_target" || return 1
        release_manifest_valid "$action33n_remote_target" || return 1
        check "outbound_entry_${action33n_remote_count}_release_manifest_exact" \
            cmp -s "$action33n_remote_candidate/release-manifest.json" \
            "$action33n_remote_target/release-manifest.json" || return 1
        check "outbound_entry_${action33n_remote_count}_payload_manifest_exact" \
            cmp -s "$action33n_remote_candidate/manifest.sha256" \
            "$action33n_remote_target/manifest.sha256" || return 1
        if [[ "$action33n_remote_target" = "$action33n_remote_current" ]]; then
            printf '%s_%s_outbound_entry_%s_disposition=retain_exact_active_replay\n' \
                "$prefix" "$node_token" "$action33n_remote_count"
        else
            printf '%s_%s_outbound_entry_%s_disposition=retain_exact_installed_replay\n' \
                "$prefix" "$node_token" "$action33n_remote_count"
        fi
    done < <(find "$action33n_remote_outbound" -mindepth 1 -maxdepth 1 \
        -print0 | LC_ALL=C sort -z)
    printf '%s_%s_outbound_entry_count=%s\n' "$prefix" "$node_token" \
        "$action33n_remote_count"
    case "$action33n_remote_role" in
        node-a)
            # Current production may have no queued publication. Every entry
            # that does exist has already passed the complete role classifier.
            check node_a_outbound_entries_admissible test \
                "$action33n_remote_count" -ge 0
            ;;
        node-b)
            check node_b_outbound_empty test "$action33n_remote_count" -eq 0
            ;;
        *) return 1 ;;
    esac
    printf '%s_%s_outbound_role_policy=accepted\n' "$prefix" "$node_token"
}
registry_value() {
    local action33n_remote_key=$1

    awk -F '\t' -v wanted="$action33n_remote_key" \
        '$1 == wanted { print $2; found++ } END { if (found != 1) exit 1 }' \
        "/tmp/caddy-action33n-registry-$run_id.tsv"
}
assert_live_artifacts() {
    local action33n_remote_key
    local action33n_remote_path
    local action33n_remote_expected
    local action33n_remote_observed

    while IFS=$'\t' read -r action33n_remote_key action33n_remote_path; do
        action33n_remote_expected=$(registry_value "${node_token}_${action33n_remote_key}")
        action33n_remote_observed=$(file_hash "$action33n_remote_path")
        printf '%s_%s_expected_%s_sha256=%s\n' "$prefix" "$node_token" \
            "$action33n_remote_key" "$action33n_remote_expected"
        printf '%s_%s_observed_%s_sha256=%s\n' "$prefix" "$node_token" \
            "$action33n_remote_key" "$action33n_remote_observed"
        check "${action33n_remote_key}_hash" test \
            "$action33n_remote_observed" = "$action33n_remote_expected"
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
    action33n_remote_expected=$(registry_value current_caddy_payload_manifest)
    action33n_remote_observed=$(file_hash "$(current_release)/manifest.sha256")
    printf '%s_%s_expected_current_payload_manifest_sha256=%s\n' \
        "$prefix" "$node_token" "$action33n_remote_expected"
    printf '%s_%s_observed_current_payload_manifest_sha256=%s\n' \
        "$prefix" "$node_token" "$action33n_remote_observed"
    check current_payload_manifest_hash test \
        "$action33n_remote_observed" = "$action33n_remote_expected"
}
current_release() { readlink -e /etc/caddy/current; }
release_manifest_hash() { file_hash "$1/release-manifest.json"; }
action33k_revision_for_path() {
    local action33n_remote_candidate=$1

    case "$action33n_remote_candidate" in
        "$releases_root/$failed_action33k_emergency_revision" | \
            "$incoming_root/node-b/$failed_action33k_emergency_revision" | \
            "$outgoing_root/$failed_action33k_emergency_revision" | \
            "$quarantine_root/$failed_action33k_emergency_revision")
            printf '%s\n' "$failed_action33k_emergency_revision"
            ;;
        "$failed_action33k_normalized_release_path" | \
            "$incoming_root/node-a/$failed_action33k_normalized_revision" | \
            "$outgoing_root/$failed_action33k_normalized_revision" | \
            "$quarantine_root/$failed_action33k_normalized_revision")
            printf '%s\n' "$failed_action33k_normalized_revision"
            ;;
        *) return 1 ;;
    esac
}
exact_failed_action33k_path() {
    action33k_revision_for_path "$1" >/dev/null
}
payload_manifest_matches() {
    local action33n_remote_candidate=$1
    local action33n_remote_reference=$2

    # conditional-validator-explicit-failures-begin
    diff -u \
        <(awk '$0 !~ /  [.][/](release-manifest[.]json)$/ { print }' \
            "$action33n_remote_candidate/manifest.sha256") \
        <(awk '$0 !~ /  [.][/](release-manifest[.]json)$/ { print }' \
            "$action33n_remote_reference/manifest.sha256") \
        >/dev/null || return
    # conditional-validator-explicit-failures-end
}
validate_action33k_release_family() {
    local action33n_remote_candidate=$1
    local action33n_remote_expected_revision=$2
    local action33n_remote_reference=${3:-$accepted_release_path}
    local action33n_remote_normalized_hash=${4:-$failed_action33k_normalized_manifest_sha256}
    local action33n_remote_source
    local action33n_remote_parent

    # conditional-validator-explicit-failures-begin
    test -d "$action33n_remote_candidate" || return
    test ! -L "$action33n_remote_candidate" || return
    release_manifest_valid "$action33n_remote_candidate" || return
    test "$(jq -er '.revision' \
        "$action33n_remote_candidate/release-manifest.json")" = \
        "$action33n_remote_expected_revision" || return
    action33n_remote_source=$(jq -er '.source_node' \
        "$action33n_remote_candidate/release-manifest.json") || return
    action33n_remote_parent=$(jq -er '.parent_revision' \
        "$action33n_remote_candidate/release-manifest.json") || return
    payload_manifest_matches "$action33n_remote_candidate" \
        "$action33n_remote_reference" || return
    case "$action33n_remote_expected_revision" in
        "$failed_action33k_emergency_revision")
            test "$action33n_remote_source" = node-b || return
            test "$action33n_remote_parent" = \
                "$accepted_release_revision" || return
            ;;
        "$failed_action33k_normalized_revision")
            test "$action33n_remote_source" = node-a || return
            test "$action33n_remote_parent" = \
                "$failed_action33k_emergency_revision" || return
            test "$(release_manifest_hash "$action33n_remote_candidate")" = \
                "$action33n_remote_normalized_hash" || return
            ;;
        *) return 1 ;;
    esac
    # conditional-validator-explicit-failures-end
}
validate_failed_action33k_candidate() {
    local action33n_remote_candidate=$1
    local action33n_remote_expected_revision

    # conditional-validator-explicit-failures-begin
    action33n_remote_expected_revision=$(action33k_revision_for_path \
        "$action33n_remote_candidate") || return
    validate_action33k_release_family "$action33n_remote_candidate" \
        "$action33n_remote_expected_revision" || return
    # conditional-validator-explicit-failures-end
}
inventory_failed_action33k_paths() {
    find "$releases_root" "$incoming_root" "$outgoing_root" \
        "$quarantine_root" -mindepth 1 -maxdepth 3 \
        -name "action33k-$failed_action33k_run_id-*" -print |
        LC_ALL=C sort
}
assert_failed_action33k_state() {
    local action33n_remote_candidate
    local action33n_remote_count=0
    local action33n_remote_emergency_count=0
    local action33n_remote_normalized_count=0
    local action33n_remote_revision
    local action33n_remote_manifest_sha256

    check accepted_release_present test -d "$accepted_release_path"
    check accepted_release_not_symlink test ! -L "$accepted_release_path"
    check accepted_release_manifest_identity test \
        "$(release_manifest_hash "$accepted_release_path")" = \
        "$accepted_release_manifest_sha256"
    while IFS= read -r action33n_remote_candidate; do
        [[ -n "$action33n_remote_candidate" ]] || continue
        check failed_action33k_path_exact exact_failed_action33k_path \
            "$action33n_remote_candidate"
        check failed_action33k_candidate_valid \
            validate_failed_action33k_candidate "$action33n_remote_candidate"
        action33n_remote_revision=$(jq -er '.revision' \
            "$action33n_remote_candidate/release-manifest.json")
        action33n_remote_manifest_sha256=$(release_manifest_hash \
            "$action33n_remote_candidate")
        printf '%s_%s_failed_action33k_residue_%s_path=%s\n' "$prefix" \
            "$node_token" "$action33n_remote_count" \
            "$action33n_remote_candidate"
        printf '%s_%s_failed_action33k_residue_%s_revision=%s\n' "$prefix" \
            "$node_token" "$action33n_remote_count" \
            "$action33n_remote_revision"
        printf '%s_%s_failed_action33k_residue_%s_manifest_sha256=%s\n' \
            "$prefix" "$node_token" "$action33n_remote_count" \
            "$action33n_remote_manifest_sha256"
        case "$action33n_remote_revision" in
            "$failed_action33k_emergency_revision")
                action33n_remote_emergency_count=$((action33n_remote_emergency_count + 1))
                ;;
            "$failed_action33k_normalized_revision")
                action33n_remote_normalized_count=$((action33n_remote_normalized_count + 1))
                ;;
        esac
        action33n_remote_count=$((action33n_remote_count + 1))
    done < <(inventory_failed_action33k_paths)
    printf '%s_%s_failed_action33k_residue_count=%s\n' "$prefix" \
        "$node_token" "$action33n_remote_count"
    printf '%s_%s_failed_action33k_emergency_family_count=%s\n' "$prefix" \
        "$node_token" "$action33n_remote_emergency_count"
    printf '%s_%s_failed_action33k_normalized_family_count=%s\n' "$prefix" \
        "$node_token" "$action33n_remote_normalized_count"
    if [[ "$role" = node-a ]]; then
        if [[ "$(current_release)" = "$accepted_release_path" ]]; then
            printf '%s_%s_failed_action33k_node_a_current_already_restored=true\n' \
                "$prefix" "$node_token"
        else
            check failed_action33k_node_a_current_is_known_failed_release test \
                "$(current_release)" = \
                "$failed_action33k_normalized_release_path"
        fi
    else
        check failed_action33k_node_b_current_exact test \
            "$(current_release)" = "$accepted_release_path"
    fi
}
freeze_failed_action33k_transport() {
    suspend_sync_health_for_lsyncd_outage action33k_recovery
    run_captured action33k_transport_freeze systemctl stop \
        caddy-sync-reconcile.path caddy-lsyncd.service
    assert_failed_action33k_state
}
remove_failed_action33k_residue() {
    local action33n_remote_candidate

    assert_failed_action33k_state
    if [[ "$role" = node-a && "$(current_release)" != "$accepted_release_path" ]]; then
        ln -s "$accepted_release_path" /etc/caddy/current.action33n-recovery
        mv -Tf /etc/caddy/current.action33n-recovery /etc/caddy/current
        run_captured action33k_restore_caddy_reload systemctl reload caddy.service
    fi
    check action33k_accepted_release_selected test \
        "$(current_release)" = "$accepted_release_path"
    while IFS= read -r action33n_remote_candidate; do
        [[ -n "$action33n_remote_candidate" ]] || continue
        validate_failed_action33k_candidate "$action33n_remote_candidate"
        rm -rf -- "$action33n_remote_candidate"
        check action33k_exact_residue_removed test \
            ! -e "$action33n_remote_candidate"
    done < <(inventory_failed_action33k_paths)
    check action33k_residue_absent test -z \
        "$(inventory_failed_action33k_paths)"
    if [[ "$role" = node-b &&
        "$(systemctl is-failed caddy-sync-reconcile.service \
            2>/dev/null || true)" = failed ]]; then
        run_captured action33k_reconcile_worker_reset systemctl reset-failed \
            caddy-sync-reconcile.service
    else
        printf '%s_%s_action33k_reconcile_worker_reset=false\n' "$prefix" \
            "$node_token"
    fi
}
restore_after_failed_action33k() {
    run_captured action33k_restore_units systemctl start caddy.service \
        caddy-lsyncd.service caddy-sync-reconcile.path
    restore_and_accept_sync_health action33k_recovery
    assert_failed_action33k_state
    check action33k_residue_absent_after_restore test -z \
        "$(inventory_failed_action33k_paths)"
}
create_baseline_archive() {
    local action33n_remote_source=$1
    local action33n_remote_archive=$2
    local action33n_remote_name

    # conditional-validator-explicit-failures-begin
    test -d "$action33n_remote_source" || return
    for action33n_remote_name in "${baseline_files[@]}"; do
        test -f "$action33n_remote_source/$action33n_remote_name" || return
        test ! -L "$action33n_remote_source/$action33n_remote_name" || return
    done
    tar -C "$action33n_remote_source" -cf "$action33n_remote_archive" \
        "${baseline_files[@]}" || return
    test -s "$action33n_remote_archive" || return
    # conditional-validator-explicit-failures-end
}
import_baseline_archive() {
    local action33n_remote_archive=$1
    local action33n_remote_expected_sha=$2
    local action33n_remote_destination=$3
    local action33n_remote_owner=${4:-root}
    local action33n_remote_group=${5:-root}
    local action33n_remote_extract
    local action33n_remote_name

    # conditional-validator-explicit-failures-begin
    test -f "$action33n_remote_archive" || return
    test ! -L "$action33n_remote_archive" || return
    test "$(file_hash "$action33n_remote_archive")" = \
        "$action33n_remote_expected_sha" || return
    diff -u <(printf '%s\n' "${baseline_files[@]}") \
        <(tar -tf "$action33n_remote_archive") >/dev/null || return
    action33n_remote_extract=$(mktemp -d /tmp/action33n-baseline-import.XXXXXX) || return
    tar -C "$action33n_remote_extract" -xf "$action33n_remote_archive" || {
        rm -rf -- "$action33n_remote_extract"
        return 1
    }
    install -d -o "$action33n_remote_owner" -g "$action33n_remote_group" \
        -m 0700 "$action33n_remote_destination" || {
        rm -rf -- "$action33n_remote_extract"
        return 1
    }
    for action33n_remote_name in "${baseline_files[@]}"; do
        install -o "$action33n_remote_owner" -g "$action33n_remote_group" \
            -m 0600 \
            "$action33n_remote_extract/$action33n_remote_name" \
            "$action33n_remote_destination/$action33n_remote_name" || {
            rm -rf -- "$action33n_remote_extract"
            return 1
        }
    done
    rm -rf -- "$action33n_remote_extract" || return
    # conditional-validator-explicit-failures-end
}
stage_baseline_bundle() {
    local action33n_remote_source=$evidence_base/$run_id/$scenario/$role
    local action33n_remote_stage=/run/caddy-action33n-baseline-$run_id-$scenario-$role
    local action33n_remote_archive=$action33n_remote_stage/baseline.tar

    check baseline_stage_absent test ! -e "$action33n_remote_stage"
    install -d -o pi -g pi -m 0700 "$action33n_remote_stage"
    create_baseline_archive "$action33n_remote_source" \
        "$action33n_remote_archive"
    chown pi:pi "$action33n_remote_archive"
    chmod 0600 "$action33n_remote_archive"
    check baseline_stage_owner_group_mode test \
        "$(stat -c '%U:%G:%a' "$action33n_remote_stage")" = pi:pi:700
    check baseline_archive_regular test -f "$action33n_remote_archive"
    check baseline_archive_not_symlink test ! -L "$action33n_remote_archive"
    check baseline_archive_owner_group_mode test \
        "$(stat -c '%U:%G:%a' "$action33n_remote_archive")" = pi:pi:600
    check baseline_stage_exact_inventory test \
        "$(find "$action33n_remote_stage" -mindepth 1 -maxdepth 1 \
            -printf '%f\n')" = baseline.tar
    printf '%s_%s_baseline_bundle_sha256=%s\n' "$prefix" "$node_token" \
        "$(file_hash "$action33n_remote_archive")"
}
import_workstation_baseline() {
    local action33n_remote_archive=/tmp/caddy-action33n-baseline-$run_id-$scenario-$role.tar

    check baseline_import_upload_regular test -f \
        "$action33n_remote_archive"
    check baseline_import_upload_not_symlink test ! -L \
        "$action33n_remote_archive"
    check baseline_import_upload_owner test \
        "$(stat -c '%U' "$action33n_remote_archive")" = pi
    check baseline_import_upload_mode test \
        "$(stat -c '%a' "$action33n_remote_archive")" = 600
    check baseline_import_sha_valid test \
        "$(file_hash "$action33n_remote_archive")" = "$argument"
    import_baseline_archive "$action33n_remote_archive" "$argument" \
        "$evidence_base/$run_id/$scenario/$role"
    rm -f -- "$action33n_remote_archive"
    check baseline_import_upload_removed test ! -e \
        "$action33n_remote_archive"
}
remove_baseline_stage() {
    local action33n_remote_stage=/run/caddy-action33n-baseline-$run_id-$scenario-$role

    check baseline_stage_present test -d "$action33n_remote_stage"
    rm -rf -- "$action33n_remote_stage"
    check baseline_stage_removed test ! -e "$action33n_remote_stage"
}
vrrp_state() {
    local action33n_remote_object=$1
    busctl get-property org.keepalived.Vrrp1 "$action33n_remote_object" org.keepalived.Vrrp1.Instance State | awk -F'"' 'NF == 3 { print toupper($2) }'
}
vip_count() {
    local action33n_remote_address=$1
    ip -o addr show dev eth0 | awk -v wanted="$action33n_remote_address" '$4 == wanted || index($4, wanted "/") == 1 { count++ } END { print count + 0 }'
}
capture_baseline() {
    local action33n_remote_unit
    local action33n_remote_release_manifest_hash

    run_captured services systemctl show caddy.service caddy-lsyncd.service keepalived.service ssh.service -p Id -p ActiveState -p UnitFileState -p MainPID -p NRestarts
    run_captured timers systemctl show caddy-sync-health.timer caddy-cert-expiry.timer caddy-sync-reconcile.path -p Id -p ActiveState -p UnitFileState
    current_release >"$evidence_directory/current-release"
    printf '%s_%s_observed_current_release=%s\n' "$prefix" "$node_token" \
        "$(current_release)"
    printf '%s_%s_observed_current_revision=%s\n' "$prefix" "$node_token" \
        "$(jq -er '.revision' "$(current_release)/release-manifest.json")"
    action33n_remote_release_manifest_hash=$(file_hash \
        "$(current_release)/release-manifest.json")
    printf '%s\n' "$action33n_remote_release_manifest_hash" \
        >"$evidence_directory/release-manifest.sha256"
    printf '%s_%s_observed_release_manifest_sha256=%s\n' "$prefix" \
        "$node_token" "$action33n_remote_release_manifest_hash"
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
    for action33n_remote_unit in caddy.service caddy-lsyncd.service \
        caddy-sync-reconcile.service caddy-sync-health.service \
        caddy-cert-expiry.service keepalived.service; do
        check "${action33n_remote_unit//[^A-Za-z0-9]/_}_nonfailed" \
            test "$(systemctl is-failed "$action33n_remote_unit" 2>/dev/null || true)" != failed
    done
}
assert_role_state() {
    local action33n_remote_expected=$1
    local action33n_remote_expected_vips=$2
    local action33n_remote_elapsed=0
    local action33n_remote_stable=0
    local action33n_remote_expected_count=0

    [[ "$action33n_remote_expected_vips" = four ]] && action33n_remote_expected_count=1
    while ((action33n_remote_elapsed < 90)); do
        if [[ "$(vrrp_state "$ipv4_object")" = "$action33n_remote_expected" &&
        "$(vrrp_state "$ipv6_object")" = "$action33n_remote_expected" &&
        "$(vip_count "$dns_ipv4")" -eq "$action33n_remote_expected_count" &&
        "$(vip_count "$caddy_ipv4")" -eq "$action33n_remote_expected_count" &&
        "$(vip_count "$dns_ipv6")" -eq "$action33n_remote_expected_count" &&
        "$(vip_count "$caddy_ipv6")" -eq "$action33n_remote_expected_count" ]]; then
            action33n_remote_stable=$((action33n_remote_stable + 1))
            if ((action33n_remote_stable == 5)); then
                printf '%s_%s_ownership_convergence_seconds=%s\n' "$prefix" \
                    "$node_token" "$action33n_remote_elapsed"
                printf '%s_%s_check_ownership_stable=true\n' "$prefix" "$node_token"
                return 0
            fi
        else
            action33n_remote_stable=0
        fi
        sleep 1
        action33n_remote_elapsed=$((action33n_remote_elapsed + 1))
    done
    printf '%s_%s_check_ownership_stable=false\n' "$prefix" "$node_token" >&2
    return 1
}
assert_services() {
    local action33n_remote_unit
    local action33n_remote_pid=
    local action33n_remote_restarts=
    local action33n_remote_sample
    for action33n_remote_unit in caddy.service caddy-lsyncd.service keepalived.service ssh.service caddy-sync-reconcile.path caddy-sync-health.timer caddy-cert-expiry.timer; do
        check "${action33n_remote_unit//[^A-Za-z0-9]/_}_active" systemctl is-active --quiet "$action33n_remote_unit"
    done
    for action33n_remote_unit in caddy.service caddy-lsyncd.service keepalived.service ssh.service caddy-sync-reconcile.path caddy-sync-health.timer caddy-cert-expiry.timer; do
        check "${action33n_remote_unit//[^A-Za-z0-9]/_}_enabled" systemctl is-enabled --quiet "$action33n_remote_unit"
    done
    check caddy_api_masked test "$(systemctl is-enabled caddy-api.service 2>/dev/null || true)" = masked
    for action33n_remote_unit in caddy-cert-expiry.service \
        caddy-sync-health.service caddy-sync-reconcile.service \
        caddy-sync-failure@.service; do
        check "${action33n_remote_unit//[^A-Za-z0-9]/_}_static" \
            test "$(systemctl is-enabled "$action33n_remote_unit" 2>/dev/null || true)" = static
    done
    for action33n_remote_sample in 1 2 3 4 5; do
        if [[ -z "$action33n_remote_pid" ]]; then
            action33n_remote_pid=$(systemctl show caddy-lsyncd.service -p MainPID --value)
            action33n_remote_restarts=$(systemctl show caddy-lsyncd.service -p NRestarts --value)
        fi
        check "lsyncd_pid_stable_$action33n_remote_sample" test \
            "$(systemctl show caddy-lsyncd.service -p MainPID --value)" = "$action33n_remote_pid"
        check "lsyncd_restart_count_stable_$action33n_remote_sample" test \
            "$(systemctl show caddy-lsyncd.service -p NRestarts --value)" = "$action33n_remote_restarts"
        sleep 1
    done
}
suspend_sync_health_for_lsyncd_outage() {
    local action33n_remote_label=$1
    local action33n_remote_timer_state

    run_captured "${action33n_remote_label}_health_timer_pre" systemctl show \
        caddy-sync-health.timer -p ActiveState -p UnitFileState || return
    check "${action33n_remote_label}_health_timer_enabled_before" \
        systemctl is-enabled --quiet caddy-sync-health.timer || return
    action33n_remote_timer_state=$(systemctl is-active \
        caddy-sync-health.timer 2>/dev/null || true)
    case "$action33n_remote_timer_state" in
        active)
            run_captured "${action33n_remote_label}_health_timer_stop" \
                systemctl stop caddy-sync-health.timer || return
            ;;
        inactive)
            printf '%s_%s_%s_health_timer_already_inactive=true\n' \
                "$prefix" "$node_token" "$action33n_remote_label"
            ;;
        *)
            printf '%s_%s_check_%s_health_timer_state_safe=false\n' \
                "$prefix" "$node_token" "$action33n_remote_label" >&2
            return 1
            ;;
    esac
    check "${action33n_remote_label}_health_timer_inactive" test \
        "$(systemctl is-active caddy-sync-health.timer 2>/dev/null || true)" = inactive || return
    check "${action33n_remote_label}_health_timer_still_enabled" \
        systemctl is-enabled --quiet caddy-sync-health.timer || return
    run_captured "${action33n_remote_label}_health_worker_stop" systemctl stop \
        caddy-sync-health.service || return
    check "${action33n_remote_label}_health_worker_inactive" test \
        "$(systemctl is-active caddy-sync-health.service 2>/dev/null || true)" = inactive || return
}
assert_lsyncd_stable_for_health() {
    local action33n_remote_label=$1
    local action33n_remote_pid
    local action33n_remote_restarts
    local action33n_remote_sample

    check "${action33n_remote_label}_lsyncd_active" systemctl is-active \
        --quiet caddy-lsyncd.service || return
    action33n_remote_pid=$(systemctl show caddy-lsyncd.service \
        -p MainPID --value) || return
    action33n_remote_restarts=$(systemctl show caddy-lsyncd.service \
        -p NRestarts --value) || return
    check "${action33n_remote_label}_lsyncd_pid_positive" \
        test "$action33n_remote_pid" -gt 0 || return
    for action33n_remote_sample in 1 2 3 4 5; do
        check "${action33n_remote_label}_lsyncd_pid_stable_$action33n_remote_sample" \
            test "$(systemctl show caddy-lsyncd.service -p MainPID --value)" = \
            "$action33n_remote_pid" || return
        check "${action33n_remote_label}_lsyncd_restarts_stable_$action33n_remote_sample" \
            test "$(systemctl show caddy-lsyncd.service -p NRestarts --value)" = \
            "$action33n_remote_restarts" || return
        sleep 1
    done
    run_captured "${action33n_remote_label}_lsyncd_state" systemctl show \
        caddy-lsyncd.service -p ActiveState -p SubState -p Result -p MainPID \
        -p NRestarts || return
    check "${action33n_remote_label}_lsyncd_result_success" test \
        "$(systemctl show caddy-lsyncd.service -p Result --value)" = success || return
}
restore_and_accept_sync_health() {
    local action33n_remote_label=$1
    local action33n_remote_worker_state

    check "${action33n_remote_label}_health_timer_suspended_before_lsyncd" test \
        "$(systemctl is-active caddy-sync-health.timer 2>/dev/null || true)" = inactive || return
    run_captured "${action33n_remote_label}_lsyncd_start" systemctl start \
        caddy-lsyncd.service || return
    assert_lsyncd_stable_for_health "$action33n_remote_label" || return
    action33n_remote_worker_state=$(systemctl is-failed \
        caddy-sync-health.service 2>/dev/null || true)
    printf '%s_%s_%s_health_worker_pre_reset_state=%s\n' "$prefix" \
        "$node_token" "$action33n_remote_label" "$action33n_remote_worker_state"
    if [[ "$action33n_remote_worker_state" = failed ]]; then
        run_captured "${action33n_remote_label}_health_worker_reset" \
            systemctl reset-failed caddy-sync-health.service || return
        printf '%s_%s_%s_health_worker_reset=true\n' "$prefix" \
            "$node_token" "$action33n_remote_label"
    else
        printf '%s_%s_%s_health_worker_reset=false\n' "$prefix" \
            "$node_token" "$action33n_remote_label"
    fi
    run_captured "${action33n_remote_label}_health_worker_run" systemctl start \
        caddy-sync-health.service || return
    check "${action33n_remote_label}_health_worker_result_success" test \
        "$(systemctl show caddy-sync-health.service -p Result --value)" = success || return
    check "${action33n_remote_label}_health_worker_nonfailed" test \
        "$(systemctl is-failed caddy-sync-health.service 2>/dev/null || true)" != failed || return
    run_captured "${action33n_remote_label}_health_timer_enable" systemctl enable \
        caddy-sync-health.timer || return
    run_captured "${action33n_remote_label}_health_timer_start" systemctl start \
        caddy-sync-health.timer || return
    check "${action33n_remote_label}_health_timer_active_after" \
        systemctl is-active --quiet caddy-sync-health.timer || return
    check "${action33n_remote_label}_health_timer_enabled_after" \
        systemctl is-enabled --quiet caddy-sync-health.timer || return
    run_captured "${action33n_remote_label}_health_timer_post" systemctl show \
        caddy-sync-health.timer -p ActiveState -p UnitFileState || return
}
accept_and_freeze_invalid_receiver_rejection() {
    local action33n_remote_cursor
    local action33n_remote_elapsed=0
    local action33n_remote_journal_status=0
    local action33n_remote_rejection_observed=false
    local action33n_remote_stdout=$evidence_directory/invalid_transport_receiver_journal.stdout
    local action33n_remote_stderr=$evidence_directory/invalid_transport_receiver_journal.stderr
    local action33n_remote_status_file=$evidence_directory/invalid_transport_receiver_journal.status

    check invalid_transport_health_timer_suspended_before_lsyncd test \
        "$(systemctl is-active caddy-sync-health.timer 2>/dev/null || true)" = inactive || return
    check invalid_transport_health_timer_still_enabled \
        systemctl is-enabled --quiet caddy-sync-health.timer || return
    run_captured invalid_transport_journal_cursor journalctl --show-cursor \
        -n 0 --no-pager || return
    action33n_remote_cursor=$(awk '/^-- cursor:/ { print $3 }' \
        "$evidence_directory/invalid_transport_journal_cursor.stdout" | tail -n 1)
    check invalid_transport_journal_cursor_present test \
        -n "$action33n_remote_cursor" || return
    run_captured invalid_transport_lsyncd_start systemctl start \
        caddy-lsyncd.service || return

    install -m 0600 /dev/null "$action33n_remote_stdout"
    install -m 0600 /dev/null "$action33n_remote_stderr"
    install -m 0600 /dev/null "$action33n_remote_status_file"
    while ((action33n_remote_elapsed < 30)); do
        action33n_remote_journal_status=0
        journalctl --after-cursor "$action33n_remote_cursor" --no-pager \
            -u caddy-lsyncd.service -o cat >"$action33n_remote_stdout" \
            2>"$action33n_remote_stderr" || action33n_remote_journal_status=$?
        printf '%s\n' "$action33n_remote_journal_status" \
            >"$action33n_remote_status_file"
        if [[ "$action33n_remote_journal_status" -ne 0 ]]; then
            break
        fi
        if grep -Fq \
            'caddy_sync_finalize_v2_check_manifest_file_set_exact=false' \
            "$action33n_remote_stdout"; then
            action33n_remote_rejection_observed=true
            break
        fi
        sleep 1
        action33n_remote_elapsed=$((action33n_remote_elapsed + 1))
    done
    printf '%s_%s_invalid_transport_rejection_seconds=%s\n' "$prefix" \
        "$node_token" "$action33n_remote_elapsed"
    printf '%s_%s_invalid_transport_receiver_journal_status=%s\n' \
        "$prefix" "$node_token" "$action33n_remote_journal_status"
    emit_stream invalid_transport_receiver_journal_stdout \
        "$action33n_remote_stdout" || return
    emit_stream invalid_transport_receiver_journal_stderr \
        "$action33n_remote_stderr" || return
    check invalid_transport_receiver_journal_status_zero test \
        "$action33n_remote_journal_status" -eq 0 || return
    check invalid_transport_receiver_rejection_observed test \
        "$action33n_remote_rejection_observed" = true || return
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
    local action33n_remote_status=0

    if suspend_sync_health_for_lsyncd_outage baseline_repair; then
        if restore_and_accept_sync_health baseline_repair; then
            :
        else
            action33n_remote_status=$?
        fi
    else
        action33n_remote_status=$?
    fi
    if [[ "$action33n_remote_status" -ne 0 ]]; then
        systemctl start caddy-lsyncd.service >/dev/null 2>&1 || true
        systemctl enable caddy-sync-health.timer >/dev/null 2>&1 || true
        systemctl start caddy-sync-health.timer >/dev/null 2>&1 || true
    fi
    return "$action33n_remote_status"
}
assert_recovered_without_keepalived() {
    local action33n_remote_unit

    for action33n_remote_unit in caddy.service caddy-lsyncd.service ssh.service \
        caddy-sync-reconcile.path caddy-sync-health.timer \
        caddy-cert-expiry.timer; do
        check "recovered_${action33n_remote_unit//[^A-Za-z0-9]/_}_active" \
            systemctl is-active --quiet "$action33n_remote_unit"
        check "recovered_${action33n_remote_unit//[^A-Za-z0-9]/_}_enabled" \
            systemctl is-enabled --quiet "$action33n_remote_unit"
    done
    check keepalived_still_inactive test \
        "$(systemctl is-active keepalived.service 2>/dev/null || true)" = inactive
}
assert_no_action_residue() {
    check outgoing_residue_absent test -z \
        "$(find "$outgoing_root" -mindepth 1 -maxdepth 1 \
            -name 'action33n-*' -print -quit)"
    check incoming_residue_absent test -z \
        "$(find "$incoming_root" -mindepth 2 -maxdepth 2 \
            -name 'action33n-*' -print -quit)"
    check release_residue_absent test -z \
        "$(find "$releases_root" -mindepth 1 -maxdepth 1 \
            -name 'action33n-*' -print -quit)"
}
render_controlled_recovery_script() {
    local action33n_remote_script=$1

    # The recovery unit expands its own evidence and revision variables.
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' \
        "evidence='$evidence_directory/control-recovery-pretransport'" \
        "revision='action33n-$run_id-$scenario'" \
        'if [[ ! -e "/var/lib/caddy-sync/incoming/node-a/$revision" && ! -e "/var/lib/caddy-sync/incoming/node-b/$revision" ]]; then printf "true\n" >"$evidence"; else printf "false\n" >"$evidence"; fi' \
        'chmod 0600 "$evidence"' \
        'systemctl start ssh.service caddy.service caddy-lsyncd.service caddy-sync-reconcile.path' \
        >"$action33n_remote_script"
}
write_controlled_recovery_script() {
    local action33n_remote_script=$1

    install -o root -g root -m 0700 /dev/null "$action33n_remote_script"
    render_controlled_recovery_script "$action33n_remote_script"
    chmod 0700 "$action33n_remote_script"
}
arm_controlled_recovery() {
    local action33n_remote_script=/run/caddy-action33n-recovery-$run_id-$scenario.sh
    local action33n_remote_unit=caddy-action33n-recovery-$run_id-$scenario

    write_controlled_recovery_script "$action33n_remote_script"
    run_captured recovery_arm systemd-run --unit "$action33n_remote_unit" --on-active=45s --property=Type=oneshot /bin/bash "$action33n_remote_script"
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
    run_captured reboot_schedule systemd-run --unit "caddy-action33n-reboot-$run_id-$scenario" --on-active=3s /usr/bin/systemctl reboot
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
    local action33n_remote_path
    local action33n_remote_original_revision
    local action33n_remote_unit
    suspend_sync_health_for_lsyncd_outage cleanup
    run_captured cleanup_transport_freeze systemctl stop \
        caddy-sync-reconcile.path caddy-lsyncd.service
    systemctl stop "caddy-action33n-recovery-$run_id-$scenario.timer" "caddy-action33n-recovery-$run_id-$scenario.service" >/dev/null 2>&1 || true
    for action33n_remote_unit in caddy-sync-reconcile.service caddy-lsyncd.service; do
        if [[ "$(systemctl is-failed "$action33n_remote_unit" 2>/dev/null || true)" = failed ]]; then
            systemctl reset-failed "$action33n_remote_unit"
        fi
    done
    for action33n_remote_path in "$outgoing_root"/action33n-"$run_id"-* "$incoming_root"/node-a/action33n-"$run_id"-* "$incoming_root"/node-b/action33n-"$run_id"-* "$releases_root"/action33n-"$run_id"-*; do
        [[ -e "$action33n_remote_path" && ! -L "$action33n_remote_path" ]] || continue
        rm -rf -- "$action33n_remote_path"
    done
    if [[ "$scenario" = interrupted-transfer ]]; then
        action33n_remote_original_revision=$(jq -er '.revision' \
            "$(cat "$evidence_base/$run_id/baseline/$role/current-release")/release-manifest.json")
        for action33n_remote_path in \
            "$outgoing_root/$action33n_remote_original_revision" \
            "$incoming_root/node-a/$action33n_remote_original_revision"; do
            [[ -e "$action33n_remote_path" && ! -L "$action33n_remote_path" ]] || continue
            rm -rf -- "$action33n_remote_path"
        done
    fi
    rm -f -- "/run/caddy-action33n-recovery-$run_id-$scenario.sh"
    for action33n_remote_path in /run/caddy-action33n-stage-"$run_id"-"$scenario"-*; do
        [[ -e "$action33n_remote_path" && ! -L "$action33n_remote_path" ]] || continue
        rm -rf -- "$action33n_remote_path"
    done
}
prepare_fixture_source() {
    local action33n_remote_revision=$1
    local action33n_remote_source=/run/caddy-action33n-stage-$run_id-$scenario-$action33n_remote_revision

    check fixture_source_absent test ! -e "$action33n_remote_source" >&2
    install -d -o root -g root -m 0700 "$action33n_remote_source"
    cp -a -- "$(current_release)/." "$action33n_remote_source/"
    printf '\n# Action 33n reliability fixture %s\n' "$action33n_remote_revision" \
        >>"$action33n_remote_source/Caddyfile"
    printf '%s\n' "$action33n_remote_source"
}
build_candidate_manifest() {
    local action33n_remote_destination=$1
    local action33n_remote_manifest_temp=$2

    # The output file must remain outside the enumerated candidate tree. Shell
    # redirection creates it before find starts, so placing it inside the tree
    # would cause the manifest to list its own temporary pathname.
    (
        cd "$action33n_remote_destination" || exit 1
        find . -type f ! -path ./manifest.sha256 \
            ! -path ./.finalize-request ! -path ./.complete \
            ! -path ./.complete.pending -print0 | LC_ALL=C sort -z |
            xargs -0 sha256sum
    ) >"$action33n_remote_manifest_temp"
}
rebuild_candidate_manifest() {
    local action33n_remote_destination=$1
    local action33n_remote_revision=$2
    local action33n_remote_manifest_temp=
    local action33n_remote_label=manifest_${action33n_remote_revision}

    action33n_remote_manifest_temp=$outgoing_root/action33n-$run_id-manifest-$action33n_remote_revision.tmp
    check "${action33n_remote_label}_temp_absent" test ! -e \
        "$action33n_remote_manifest_temp" || return
    install -m 0600 /dev/null "$action33n_remote_manifest_temp" || return
    if ! run_captured "${action33n_remote_label}_build" \
        build_candidate_manifest "$action33n_remote_destination" \
        "$action33n_remote_manifest_temp"; then
        rm -f -- "$action33n_remote_manifest_temp"
        return 1
    fi
    check "${action33n_remote_label}_temp_nonempty" test -s \
        "$action33n_remote_manifest_temp" || {
        rm -f -- "$action33n_remote_manifest_temp"
        return 1
    }
    mv -- "$action33n_remote_manifest_temp" \
        "$action33n_remote_destination/manifest.sha256" || return
    check "${action33n_remote_label}_temp_consumed" test ! -e \
        "$action33n_remote_manifest_temp" || return
    check "${action33n_remote_label}_file_set_exact" \
        manifest_file_set_matches "$action33n_remote_destination" || return
    # The positional parameter is intentionally expanded by the child shell.
    # shellcheck disable=SC2016
    check "${action33n_remote_label}_hashes_valid" \
        bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' \
        _ "$action33n_remote_destination" || return
}
adopt_publisher_output() {
    local action33n_remote_source=$1
    local action33n_remote_revision=$2
    local action33n_remote_emergency=$3
    local action33n_remote_before=$evidence_directory/publish.before
    local action33n_remote_after=$evidence_directory/publish.after
    local action33n_remote_generated
    local action33n_remote_destination=$outgoing_root/$action33n_remote_revision

    find "$outgoing_root" -mindepth 1 -maxdepth 1 -type d \
        -printf '%f\n' | LC_ALL=C sort >"$action33n_remote_before"
    if [[ "$action33n_remote_emergency" = true ]]; then
        run_captured publisher "$publisher" --source "$action33n_remote_source" \
            --node-role "$role" --emergency
    else
        run_captured publisher "$publisher" --source "$action33n_remote_source" \
            --node-role "$role"
    fi
    find "$outgoing_root" -mindepth 1 -maxdepth 1 -type d \
        -printf '%f\n' | LC_ALL=C sort >"$action33n_remote_after"
    action33n_remote_generated=$(comm -13 "$action33n_remote_before" \
        "$action33n_remote_after")
    check publisher_created_one test \
        "$(printf '%s\n' "$action33n_remote_generated" |
            awk 'NF { count++ } END { print count + 0 }')" -eq 1
    check owned_destination_absent test ! -e "$action33n_remote_destination"
    mv -- "$outgoing_root/$action33n_remote_generated" "$action33n_remote_destination"
    chmod u+w "$action33n_remote_destination/release-manifest.json"
    jq --arg revision "$action33n_remote_revision" '.revision = $revision' \
        "$action33n_remote_destination/release-manifest.json" \
        >"$action33n_remote_destination/release-manifest.json.new"
    mv -- "$action33n_remote_destination/release-manifest.json.new" \
        "$action33n_remote_destination/release-manifest.json"
    rebuild_candidate_manifest "$action33n_remote_destination" \
        "$action33n_remote_revision" || return
    chown -R caddy-sync:caddy-sync "$action33n_remote_destination"
    find "$action33n_remote_destination" -type d -exec chmod 0550 {} +
    find "$action33n_remote_destination" -type f -exec chmod 0440 {} +
    rm -rf -- "$action33n_remote_source"
}
publish_owned() {
    local action33n_remote_revision=$1
    local action33n_remote_emergency=$2
    local action33n_remote_resume=${3:-true}
    local action33n_remote_source

    suspend_sync_health_for_lsyncd_outage publish
    run_captured transport_freeze systemctl stop caddy-lsyncd.service
    action33n_remote_source=$(prepare_fixture_source "$action33n_remote_revision")
    adopt_publisher_output "$action33n_remote_source" \
        "$action33n_remote_revision" "$action33n_remote_emergency"
    if [[ "$action33n_remote_resume" = true ]]; then
        restore_and_accept_sync_health publish
    fi
}
promote_outgoing() {
    local action33n_remote_revision=$1
    local action33n_remote_source=$outgoing_root/$action33n_remote_revision
    local action33n_remote_destination=$releases_root/$action33n_remote_revision

    check outgoing_fixture_present test -d "$action33n_remote_source"
    check destination_absent test ! -e "$action33n_remote_destination"
    cp -a -- "$action33n_remote_source" "$action33n_remote_destination"
    rm -f -- "$action33n_remote_destination/.finalize-request"
    : >"$action33n_remote_destination/.complete"
    chown -R caddy:caddy "$action33n_remote_destination"
    find "$action33n_remote_destination" -type d -exec chmod 0550 {} +
    find "$action33n_remote_destination" -type f -exec chmod 0440 {} +
    ln -s "$action33n_remote_destination" /etc/caddy/current.action33n
    mv -Tf /etc/caddy/current.action33n /etc/caddy/current
    run_captured caddy_reload systemctl reload caddy.service
}
wait_current() {
    local action33n_remote_revision=$1
    local action33n_remote_elapsed=0

    while ((action33n_remote_elapsed < 60)); do
        if [[ "$(current_release)" = "$releases_root/$action33n_remote_revision" ]]; then
            printf '%s_%s_release_wait_seconds=%s\n' "$prefix" "$node_token" \
                "$action33n_remote_elapsed"
            return 0
        fi
        sleep 1
        action33n_remote_elapsed=$((action33n_remote_elapsed + 1))
    done
    return 1
}
restore_original_release() {
    local action33n_remote_original_file=$evidence_base/$run_id/baseline/$role/current-release
    local action33n_remote_original

    action33n_remote_original=$(cat "$action33n_remote_original_file")
    check original_release_safe test -d "$action33n_remote_original"
    if [[ "$(current_release)" != "$action33n_remote_original" ]]; then
        ln -s "$action33n_remote_original" /etc/caddy/current.action33n
        mv -Tf /etc/caddy/current.action33n /etc/caddy/current
        run_captured restore_caddy_reload systemctl reload caddy.service
    fi
}
stage_invalid() {
    local action33n_remote_revision=$1
    local action33n_remote_candidate=$outgoing_root/$action33n_remote_revision

    publish_owned "$action33n_remote_revision" false false
    chmod u+w "$action33n_remote_candidate/Caddyfile"
    printf '# invalidated after manifest creation\n' \
        >>"$action33n_remote_candidate/Caddyfile"
    chmod 0440 "$action33n_remote_candidate/Caddyfile"
    accept_and_freeze_invalid_receiver_rejection
}
assert_invalid_rejected() {
    local action33n_remote_revision=$1
    local action33n_remote_candidate=$incoming_root/node-a/$action33n_remote_revision
    local action33n_remote_elapsed=0

    while ((action33n_remote_elapsed < 30)) &&
        [[ ! -d "$action33n_remote_candidate" ]]; do
        sleep 1
        action33n_remote_elapsed=$((action33n_remote_elapsed + 1))
    done
    check invalid_candidate_received test -d "$action33n_remote_candidate"
    check invalid_completion_absent test ! -e "$action33n_remote_candidate/.complete"
    check invalid_destination_absent test ! -e "$releases_root/$action33n_remote_revision"
    check invalid_selection_unchanged test \
        "$(current_release)" = "$(cat "$evidence_base/$run_id/baseline/$role/current-release")"
}
assert_replay_destination_absent() {
    local action33n_remote_destination=$1

    check replay_outgoing_absent test ! -e "$action33n_remote_destination"
}
stage_active_replay() {
    local action33n_remote_revision
    local action33n_remote_destination

    action33n_remote_revision=$(jq -er '.revision' \
        "$(current_release)/release-manifest.json")
    action33n_remote_destination=$outgoing_root/$action33n_remote_revision
    assert_replay_destination_absent "$action33n_remote_destination"
    suspend_sync_health_for_lsyncd_outage replay_transport
    run_captured replay_transport_freeze systemctl stop caddy-lsyncd.service
    cp -a -- "$(current_release)" "$action33n_remote_destination"
    rm -f -- "$action33n_remote_destination/.complete" \
        "$action33n_remote_destination/.finalize-request"
    chown -R caddy-sync:caddy-sync "$action33n_remote_destination"
    find "$action33n_remote_destination" -type d -exec chmod 0550 {} +
    find "$action33n_remote_destination" -type f -exec chmod 0440 {} +
    printf '%s_%s_active_replay_revision=%s\n' "$prefix" "$node_token" \
        "$action33n_remote_revision"
    restore_and_accept_sync_health replay_transport
}
assert_replay_incomplete() {
    local action33n_remote_revision=$1
    local action33n_remote_candidate=$incoming_root/node-a/$action33n_remote_revision
    local action33n_remote_elapsed=0

    while ((action33n_remote_elapsed < 30)) &&
        [[ ! -d "$action33n_remote_candidate" ]]; do
        sleep 1
        action33n_remote_elapsed=$((action33n_remote_elapsed + 1))
    done
    check replay_received test -d "$action33n_remote_candidate"
    check replay_request_absent test ! -e "$action33n_remote_candidate/.finalize-request"
    check replay_completion_absent test ! -e "$action33n_remote_candidate/.complete"
    check replay_selection_unchanged test \
        "$(current_release)" = "$(cat "$evidence_base/$run_id/baseline/$role/current-release")"
}
request_active_replay() {
    local action33n_remote_revision=$1
    local action33n_remote_candidate=$outgoing_root/$action33n_remote_revision

    suspend_sync_health_for_lsyncd_outage replay_request
    run_captured replay_request_freeze systemctl stop caddy-lsyncd.service
    check replay_outgoing_present test -d "$action33n_remote_candidate"
    chmod 0750 "$action33n_remote_candidate"
    : >"$action33n_remote_candidate/.finalize-request"
    chown caddy-sync:caddy-sync "$action33n_remote_candidate/.finalize-request"
    chmod 0440 "$action33n_remote_candidate/.finalize-request"
    chmod 0550 "$action33n_remote_candidate"
    restore_and_accept_sync_health replay_request
}
wait_replay_consumed() {
    local action33n_remote_revision=$1
    local action33n_remote_candidate=$incoming_root/node-a/$action33n_remote_revision
    local action33n_remote_elapsed=0

    while ((action33n_remote_elapsed < 60)); do
        if [[ ! -e "$action33n_remote_candidate" &&
            "$(current_release)" = "$(cat "$evidence_base/$run_id/baseline/$role/current-release")" ]]; then
            printf '%s_%s_replay_reconcile_seconds=%s\n' "$prefix" \
                "$node_token" "$action33n_remote_elapsed"
            return 0
        fi
        sleep 1
        action33n_remote_elapsed=$((action33n_remote_elapsed + 1))
    done
    return 1
}
assert_conflict() {
    local action33n_remote_pair=$1
    local action33n_remote_first=${action33n_remote_pair%%+*}
    local action33n_remote_second=${action33n_remote_pair#*+}
    local action33n_remote_first_path=$incoming_root/node-a/$action33n_remote_first
    local action33n_remote_second_path=$incoming_root/node-a/$action33n_remote_second
    local action33n_remote_elapsed=0
    local action33n_remote_status=0
    local action33n_remote_caddy_cursor
    local action33n_remote_caddy_pid
    local action33n_remote_caddy_restarts

    # conditional-validator-explicit-failures-begin
    while ((action33n_remote_elapsed < 60)); do
        if [[ -f "$action33n_remote_first_path/.complete" &&
            -f "$action33n_remote_second_path/.complete" ]]; then break; fi
        sleep 1
        action33n_remote_elapsed=$((action33n_remote_elapsed + 1))
    done
    check conflict_first_finalized test -f \
        "$action33n_remote_first_path/.complete" || return
    check conflict_second_finalized test -f \
        "$action33n_remote_second_path/.complete" || return
    action33n_remote_caddy_pid=$(systemctl show caddy.service -p MainPID \
        --value)
    action33n_remote_caddy_restarts=$(systemctl show caddy.service -p NRestarts \
        --value)
    check conflict_caddy_pid_positive test "$action33n_remote_caddy_pid" \
        -gt 0 || return
    run_captured conflict_caddy_cursor journalctl -u caddy.service \
        --show-cursor -n 0 --no-pager || return
    action33n_remote_caddy_cursor=$(awk '/^-- cursor:/ { print $3 }' \
        "$evidence_directory/conflict_caddy_cursor.stdout" | tail -n 1)
    check conflict_caddy_cursor_present test -n \
        "$action33n_remote_caddy_cursor" || return
    systemctl start caddy-sync-reconcile.service \
        >"$evidence_directory/conflict.stdout" \
        2>"$evidence_directory/conflict.stderr" || action33n_remote_status=$?
    check conflict_worker_failed test "$action33n_remote_status" -ne 0 || return
    run_captured conflict_journal journalctl -u caddy-sync-reconcile.service \
        -n 50 --no-pager --no-hostname -o short-iso || return
    check conflict_message grep -Fq \
        'Multiple finalized candidates claim the active parent.' \
        "$evidence_directory/conflict_journal.stdout" || return
    run_captured conflict_caddy_journal journalctl -u caddy.service \
        --after-cursor "$action33n_remote_caddy_cursor" --no-pager \
        --no-hostname -o short-iso || return
    check conflict_caddy_reload_absent test \
        "$(grep -Eic 'reload' \
            "$evidence_directory/conflict_caddy_journal.stdout" || true)" \
        -eq 0 || return
    check conflict_caddy_pid_unchanged test \
        "$(systemctl show caddy.service -p MainPID --value)" = \
        "$action33n_remote_caddy_pid" || return
    check conflict_caddy_restart_count_unchanged test \
        "$(systemctl show caddy.service -p NRestarts --value)" = \
        "$action33n_remote_caddy_restarts" || return
    assert_conflict_retained "$action33n_remote_pair" || return
    # conditional-validator-explicit-failures-end
}
assert_conflict_retained() {
    local action33n_remote_pair=$1
    local action33n_remote_first=${action33n_remote_pair%%+*}
    local action33n_remote_second=${action33n_remote_pair#*+}
    local action33n_remote_first_path=$incoming_root/node-a/$action33n_remote_first
    local action33n_remote_second_path=$incoming_root/node-a/$action33n_remote_second

    # conditional-validator-explicit-failures-begin
    check conflict_first_retained test -d "$action33n_remote_first_path" || return
    check conflict_second_retained test -d "$action33n_remote_second_path" || return
    check conflict_selection_unchanged test \
        "$(current_release)" = \
        "$(cat "$evidence_base/$run_id/baseline/$role/current-release")" || return
    check conflict_first_destination_absent test ! -e \
        "$releases_root/$action33n_remote_first" || return
    check conflict_second_destination_absent test ! -e \
        "$releases_root/$action33n_remote_second" || return
    # conditional-validator-explicit-failures-end
}
start_conflict_transport() {
    local action33n_remote_pid

    check conflict_transport_health_timer_suspended test \
        "$(systemctl is-active caddy-sync-health.timer 2>/dev/null || true)" = \
        inactive
    check conflict_transport_health_timer_enabled systemctl is-enabled --quiet \
        caddy-sync-health.timer
    run_captured conflict_transport_start systemctl start \
        caddy-lsyncd.service
    check conflict_transport_active systemctl is-active --quiet \
        caddy-lsyncd.service
    action33n_remote_pid=$(systemctl show caddy-lsyncd.service -p MainPID \
        --value)
    check conflict_transport_pid_positive test "$action33n_remote_pid" -gt 0
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

write_action33k_family_fixture() {
    local action33n_remote_fixture=$1
    local action33n_remote_revision=$2
    local action33n_remote_parent=$3
    local action33n_remote_source=$4

    install -d -m 0700 "$action33n_remote_fixture"
    printf 'fixture payload\n' >"$action33n_remote_fixture/Caddyfile"
    jq -n --arg revision "$action33n_remote_revision" \
        --arg parent "$action33n_remote_parent" \
        --arg source "$action33n_remote_source" \
        '{revision: $revision, parent_revision: $parent, source_node: $source,
          created_at: "2026-08-13T00:07:01Z"}' \
        >"$action33n_remote_fixture/release-manifest.json"
    (
        cd "$action33n_remote_fixture"
        sha256sum Caddyfile release-manifest.json |
            sed 's#  #  ./#' >manifest.sha256
    )
}

if [[ "$mode" = --self-test ]]; then
    printf '%s_self_test_complete=true\n' "$prefix"
    exit 0
fi
if [[ "$mode" = --reject-capture-self-test ]]; then
    action33n_remote_self_test_root=$(mktemp -d /tmp/action33n-reject-capture.XXXXXX)
    trap 'rm -rf -- "$action33n_remote_self_test_root"' EXIT INT TERM
    chmod 0700 "$action33n_remote_self_test_root"
    evidence_directory=$action33n_remote_self_test_root
    prepare_reject_capture_files
    check reject_capture_stdout_regular test -f \
        "$evidence_directory/reject.stdout"
    check reject_capture_stderr_regular test -f \
        "$evidence_directory/reject.stderr"
    check reject_capture_status_regular test -f \
        "$evidence_directory/reject.status"
    check reject_capture_stdout_mode test \
        "$(stat -c %a "$evidence_directory/reject.stdout")" = 600
    check reject_capture_stderr_mode test \
        "$(stat -c %a "$evidence_directory/reject.stderr")" = 600
    check reject_capture_status_mode test \
        "$(stat -c %a "$evidence_directory/reject.status")" = 600
    printf '%s_reject_capture_self_test_complete=true\n' "$prefix"
    exit 0
fi
if [[ "$mode" = --baseline-bundle-self-test ]]; then
    action33n_remote_self_test_root=$(mktemp -d /tmp/action33n-baseline-bundle.XXXXXX)
    trap 'rm -rf -- "$action33n_remote_self_test_root"' EXIT INT TERM
    install -d -m 0700 "$action33n_remote_self_test_root/source" \
        "$action33n_remote_self_test_root/imported"
    for action33n_remote_self_test_name in "${baseline_files[@]}"; do
        printf '%s\n' "$action33n_remote_self_test_name" \
            >"$action33n_remote_self_test_root/source/$action33n_remote_self_test_name"
    done
    create_baseline_archive "$action33n_remote_self_test_root/source" \
        "$action33n_remote_self_test_root/baseline.tar"
    action33n_remote_self_test_sha=$(file_hash \
        "$action33n_remote_self_test_root/baseline.tar")
    import_baseline_archive "$action33n_remote_self_test_root/baseline.tar" \
        "$action33n_remote_self_test_sha" \
        "$action33n_remote_self_test_root/imported" "$(id -un)" "$(id -gn)"
    for action33n_remote_self_test_name in "${baseline_files[@]}"; do
        check "baseline_bundle_${action33n_remote_self_test_name//[^A-Za-z0-9]/_}_round_trip" \
            cmp -s \
            "$action33n_remote_self_test_root/source/$action33n_remote_self_test_name" \
            "$action33n_remote_self_test_root/imported/$action33n_remote_self_test_name"
    done
    if import_baseline_archive \
        "$action33n_remote_self_test_root/baseline.tar" \
        0000000000000000000000000000000000000000000000000000000000000000 \
        "$action33n_remote_self_test_root/rejected"; then
        printf '%s_baseline_bundle_bad_hash_rejected=false\n' "$prefix" >&2
        exit 1
    fi
    printf '%s_baseline_bundle_bad_hash_rejected=true\n' "$prefix"
    printf '%s_baseline_bundle_self_test_complete=true\n' "$prefix"
    exit 0
fi
if [[ "$mode" = --action33k-family-self-test ]]; then
    action33n_remote_self_test_root=$(mktemp -d /tmp/action33n-family.XXXXXX)
    trap 'rm -rf -- "$action33n_remote_self_test_root"' EXIT INT TERM
    chmod 0700 "$action33n_remote_self_test_root"
    write_action33k_family_fixture "$action33n_remote_self_test_root/accepted" \
        "$accepted_release_revision" original node-a
    write_action33k_family_fixture "$action33n_remote_self_test_root/emergency" \
        "$failed_action33k_emergency_revision" \
        "$accepted_release_revision" node-b
    write_action33k_family_fixture "$action33n_remote_self_test_root/normalized" \
        "$failed_action33k_normalized_revision" \
        "$failed_action33k_emergency_revision" node-a
    action33n_remote_self_test_sha=$(release_manifest_hash \
        "$action33n_remote_self_test_root/normalized")
    check action33k_emergency_family_accepted \
        validate_action33k_release_family \
        "$action33n_remote_self_test_root/emergency" \
        "$failed_action33k_emergency_revision" \
        "$action33n_remote_self_test_root/accepted"
    check action33k_normalized_family_accepted \
        validate_action33k_release_family \
        "$action33n_remote_self_test_root/normalized" \
        "$failed_action33k_normalized_revision" \
        "$action33n_remote_self_test_root/accepted" \
        "$action33n_remote_self_test_sha"
    cp -a "$action33n_remote_self_test_root/emergency" \
        "$action33n_remote_self_test_root/wrong-source"
    jq '.source_node = "node-a"' \
        "$action33n_remote_self_test_root/wrong-source/release-manifest.json" \
        >"$action33n_remote_self_test_root/wrong-source/release-manifest.json.new"
    mv -- "$action33n_remote_self_test_root/wrong-source/release-manifest.json.new" \
        "$action33n_remote_self_test_root/wrong-source/release-manifest.json"
    (
        cd "$action33n_remote_self_test_root/wrong-source"
        sha256sum Caddyfile release-manifest.json | sed 's#  #  ./#' \
            >manifest.sha256
    )
    if validate_action33k_release_family \
        "$action33n_remote_self_test_root/wrong-source" \
        "$failed_action33k_emergency_revision" \
        "$action33n_remote_self_test_root/accepted"; then
        printf '%s_action33k_wrong_source_rejected=false\n' "$prefix" >&2
        exit 1
    fi
    printf '%s_action33k_wrong_source_rejected=true\n' "$prefix"
    cp -a "$action33n_remote_self_test_root/emergency" \
        "$action33n_remote_self_test_root/wrong-payload"
    printf 'drift\n' >>"$action33n_remote_self_test_root/wrong-payload/Caddyfile"
    (
        cd "$action33n_remote_self_test_root/wrong-payload"
        sha256sum Caddyfile release-manifest.json | sed 's#  #  ./#' \
            >manifest.sha256
    )
    if validate_action33k_release_family \
        "$action33n_remote_self_test_root/wrong-payload" \
        "$failed_action33k_emergency_revision" \
        "$action33n_remote_self_test_root/accepted"; then
        printf '%s_action33k_wrong_payload_rejected=false\n' "$prefix" >&2
        exit 1
    fi
    printf '%s_action33k_wrong_payload_rejected=true\n' "$prefix"
    cp -a "$action33n_remote_self_test_root/emergency" \
        "$action33n_remote_self_test_root/wrong-parent"
    jq '.parent_revision = "wrong"' \
        "$action33n_remote_self_test_root/wrong-parent/release-manifest.json" \
        >"$action33n_remote_self_test_root/wrong-parent/release-manifest.json.new"
    mv -- "$action33n_remote_self_test_root/wrong-parent/release-manifest.json.new" \
        "$action33n_remote_self_test_root/wrong-parent/release-manifest.json"
    (
        cd "$action33n_remote_self_test_root/wrong-parent"
        sha256sum Caddyfile release-manifest.json | sed 's#  #  ./#' \
            >manifest.sha256
    )
    if validate_action33k_release_family \
        "$action33n_remote_self_test_root/wrong-parent" \
        "$failed_action33k_emergency_revision" \
        "$action33n_remote_self_test_root/accepted"; then
        printf '%s_action33k_wrong_parent_rejected=false\n' "$prefix" >&2
        exit 1
    fi
    printf '%s_action33k_wrong_parent_rejected=true\n' "$prefix"
    if validate_action33k_release_family \
        "$action33n_remote_self_test_root/normalized" \
        "$failed_action33k_normalized_revision" \
        "$action33n_remote_self_test_root/accepted" \
        0000000000000000000000000000000000000000000000000000000000000000; then
        printf '%s_action33k_wrong_normalized_hash_rejected=false\n' "$prefix" >&2
        exit 1
    fi
    printf '%s_action33k_wrong_normalized_hash_rejected=true\n' "$prefix"
    printf '%s_action33k_family_self_test_complete=true\n' "$prefix"
    exit 0
fi
[[ "$role" =~ ^node-[ab]$ ]] && valid_token "$run_id" && valid_token "$scenario" || exit 64
evidence_directory=$evidence_base/$run_id/$scenario/$role
install -d -o root -g root -m 0700 "$evidence_directory"

case "$mode" in
    --recover-action33k-preflight) assert_failed_action33k_state ;;
    --recover-action33k-freeze) freeze_failed_action33k_transport ;;
    --recover-action33k-apply) remove_failed_action33k_residue ;;
    --recover-action33k-restore) restore_after_failed_action33k ;;
    --stage-baseline-bundle) stage_baseline_bundle ;;
    --remove-baseline-stage) remove_baseline_stage ;;
    --import-baseline) import_workstation_baseline ;;
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
        action33n_remote_reject_status=0
        check ordinary_node_b_publication_context test "$role" = node-b
        prepare_reject_capture_files
        "$publisher" --source "$(current_release)" --node-role node-b \
            >"$evidence_directory/reject.stdout" \
            2>"$evidence_directory/reject.stderr" ||
            action33n_remote_reject_status=$?
        printf '%s\n' "$action33n_remote_reject_status" \
            >"$evidence_directory/reject.status"
        printf '%s_%s_reject_status=%s\n' "$prefix" "$node_token" \
            "$action33n_remote_reject_status"
        emit_stream reject_stdout "$evidence_directory/reject.stdout"
        emit_stream reject_stderr "$evidence_directory/reject.stderr"
        check ordinary_node_b_publication_status_nonzero test \
            "$action33n_remote_reject_status" -ne 0
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
            action33n_remote_cursor=$(awk '/^-- cursor:/ { print $3 }' \
                "$evidence_base/$run_id/$scenario/$role/journal_cursor.stdout" |
                tail -n 1)
        fi
        if [[ -n "$action33n_remote_cursor" ]]; then
            run_captured scenario_journal journalctl \
                --after-cursor "$action33n_remote_cursor" --no-pager \
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
        check registry_present test -f "/tmp/caddy-action33n-registry-$run_id.tsv"
        rm -f -- "/tmp/caddy-action33n-registry-$run_id.tsv"
        check registry_removed test ! -e "/tmp/caddy-action33n-registry-$run_id.tsv"
        ;;
    *) exit 64 ;;
esac
printf '%s_%s_%s_complete=true\n' "$prefix" "$node_token" "${mode#--}"
