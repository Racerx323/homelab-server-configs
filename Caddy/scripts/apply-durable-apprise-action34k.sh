#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH
transaction_path=$(readlink -f -- "${BASH_SOURCE[0]}")
readonly transaction_path

readonly prefix=action_34k_remote
readonly artifact_manifest_relative=Caddy/manifests/durable-apprise-action34k.tsv
readonly runtime_baseline_relative=Caddy/manifests/caddy-runtime-lifecycle-action32g.tsv
readonly runtime_baseline_sha256=705c0e2e590e83da942048ca47c61fab545eb52c9f7b5fe866ba18524c7d1587
readonly backup_parent=/var/backups/caddy-ha
mode=${1:-}
production_path_test_mode=false
production_path_test_root=
if [[ "$mode" = --production-path-case ]]; then
    production_path_test_mode=true
    production_path_test_root=${3:-}
    role=${4:-}
    payload_archive=none
    payload_sha256=none
    run_token=1700000000-1
elif [[ "$mode" = --production-path-test ]]; then
    role=node-b
    payload_archive=none
    payload_sha256=none
    run_token=1700000000-1
else
    role=${2:-}
    payload_archive=${3:-}
    payload_sha256=${4:-}
    run_token=${5:-}
fi

if [[ "$production_path_test_mode" = true ]]; then
    [[ "$production_path_test_root" = /tmp/caddy-action34k-production-path.* ]] || exit 64
    queue_root=$production_path_test_root/queue
    runtime_root=$production_path_test_root/run
    node_evidence_root=$production_path_test_root/evidence
else
    queue_root=/var/lib/caddy-apprise-queue
    runtime_root=/run/caddy-apprise
    node_evidence_root=/tmp/caddy-action34k
fi
readonly queue_root runtime_root node_evidence_root
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6
readonly dns_ipv4=10.1.0.55
readonly caddy_ipv4=10.1.0.56
readonly dns_ipv6=fd36:5aa8:6971:1::55
readonly caddy_ipv6=fd36:5aa8:6971:1::56
readonly failed_action34_payload_sha256=15ff568ac2e0f66d6ba662d9d300470ec17ec37b6140782c8b47d2df3081dcd3
readonly action34g_retained_record_one=30e1e40455a0f893f47dc6b8731b83f3e81018d139dd85fa254163b916ffda5f.json
readonly action34g_retained_record_two=73c17e8e70d538a2dbbf564cb47878690e351e0d141289636a8752c6968c8184.json
readonly retry_transport=/usr/bin/false
readonly delivery_transport=/usr/bin/true

[[ "$role" =~ ^node-[ab]$ ]] || exit 64
[[ "$run_token" =~ ^[0-9]{10,20}-[0-9]+$ ]] || exit 64
readonly mode role payload_archive payload_sha256 run_token production_path_test_mode
readonly production_path_test_root
if [[ "$production_path_test_mode" = true ]]; then
    backup_root=$production_path_test_root/backup
else
    backup_root=$backup_parent/action34k-$role-$run_token
fi
readonly backup_root
readonly evidence_root=$node_evidence_root/$run_token-$role
mutation_started=false
stage_path=

gate() {
    local action34h_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "${role//-/_}" "$action34h_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "${role//-/_}" "$action34h_label" >&2
    return 1
}

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

capture_command() {
    local action34h_capture_label=$1
    shift
    local action34h_capture_stdout=$evidence_root/$action34h_capture_label.stdout
    local action34h_capture_stderr=$evidence_root/$action34h_capture_label.stderr
    local action34h_capture_status_file=$evidence_root/$action34h_capture_label.status
    local action34h_capture_status=0
    local action34h_capture_stream action34h_capture_name
    install -m 0600 /dev/null "$action34h_capture_stdout" || return 1
    install -m 0600 /dev/null "$action34h_capture_stderr" || return 1
    install -m 0600 /dev/null "$action34h_capture_status_file" || return 1
    "$@" >"$action34h_capture_stdout" 2>"$action34h_capture_stderr" || action34h_capture_status=$?
    printf '%s\n' "$action34h_capture_status" >"$action34h_capture_status_file"
    printf '%s_%s_%s_status=%s\n' "$prefix" "${role//-/_}" \
        "$action34h_capture_label" "$action34h_capture_status"
    for action34h_capture_stream in "$action34h_capture_stdout" "$action34h_capture_stderr"; do
        action34h_capture_name=${action34h_capture_stream##*.}
        [[ "$(wc -c <"$action34h_capture_stream")" -le 65536 ]] || return 97
        [[ "$(awk 'END { print NR }' "$action34h_capture_stream")" -le 256 ]] || return 97
        iconv -f UTF-8 -t UTF-8 "$action34h_capture_stream" >/dev/null 2>&1 || return 97
        ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action34h_capture_stream" >/dev/null || return 97
        ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
            "$action34h_capture_stream" || return 97
        printf '%s_%s_%s_%s_bytes=%s\n' "$prefix" "${role//-/_}" \
            "$action34h_capture_label" "$action34h_capture_name" \
            "$(wc -c <"$action34h_capture_stream")"
        printf '%s_%s_%s_%s_sha256=%s\n' "$prefix" "${role//-/_}" \
            "$action34h_capture_label" "$action34h_capture_name" \
            "$(file_hash "$action34h_capture_stream")"
        printf '%s_%s_%s_%s_classification=bounded_safe\n' "$prefix" "${role//-/_}" \
            "$action34h_capture_label" "$action34h_capture_name"
        if [[ -s "$action34h_capture_stream" ]]; then
            printf '%s_%s_%s_%s_begin\n' "$prefix" "${role//-/_}" \
                "$action34h_capture_label" "$action34h_capture_name"
            cat "$action34h_capture_stream"
            printf '%s_%s_%s_%s_end\n' "$prefix" "${role//-/_}" \
                "$action34h_capture_label" "$action34h_capture_name"
        fi
    done
    return "$action34h_capture_status"
}

artifact_label() {
    local action34h_target=$1
    local action34h_encoded
    [[ "$action34h_target" = /* && -n "$action34h_target" ]] || return 1
    action34h_encoded=$(LC_ALL=C printf '%s' "$action34h_target" | od -An -tx1 -v | tr -d ' \n') || return 1
    [[ "$action34h_encoded" =~ ^[0-9a-f]+$ ]] || return 1
    printf 'path_%s\n' "$action34h_encoded"
}

observe_artifact() {
    local action34h_target=$1
    if [[ -L "$action34h_target" ]]; then
        printf 'invalid-symlink\n'
    elif [[ -f "$action34h_target" ]]; then
        file_hash "$action34h_target"
    elif [[ -e "$action34h_target" ]]; then
        printf 'invalid-nonregular\n'
    else
        printf 'absent\n'
    fi
}

state_for() {
    local action34h_object=$1
    busctl get-property org.keepalived.Vrrp1 "$action34h_object" \
        org.keepalived.Vrrp1.Instance State | awk -F'"' 'NF == 3 { print toupper($2) }'
}

address_count() {
    local action34h_family=$1
    local action34h_address=$2
    local action34h_output
    if [[ "$action34h_family" = 4 ]]; then
        action34h_output=$(ip -o -4 addr show) || return 1
    else
        action34h_output=$(ip -o -6 addr show) || return 1
    fi
    awk -v address="$action34h_address" '$4 ~ ("^" address "/") { count++ } END { print count + 0 }' \
        <<<"$action34h_output"
}

baseline() {
    local action34h_expected_state=BACKUP
    local action34h_expected_count=0
    if [[ "$production_path_test_mode" = true ]]; then
        printf '%s_%s_production_baseline=accepted_action34j_recovery\n' \
            "$prefix" "${role//-/_}"
        return 0
    fi
    [[ "$role" = node-b ]] || {
        action34h_expected_state=MASTER
        action34h_expected_count=1
    }
    gate caddy_active systemctl is-active --quiet caddy.service || return 1
    gate lsyncd_active systemctl is-active --quiet caddy-lsyncd.service || return 1
    gate reconcile_path_active systemctl is-active --quiet caddy-sync-reconcile.path || return 1
    gate keepalived_active systemctl is-active --quiet keepalived.service || return 1
    gate ipv4_state test "$(state_for "$ipv4_object")" = "$action34h_expected_state" || return 1
    gate ipv6_state test "$(state_for "$ipv6_object")" = "$action34h_expected_state" || return 1
    gate dns_ipv4_ownership test "$(address_count 4 "$dns_ipv4")" -eq "$action34h_expected_count" || return 1
    gate caddy_ipv4_ownership test "$(address_count 4 "$caddy_ipv4")" -eq "$action34h_expected_count" || return 1
    gate dns_ipv6_ownership test "$(address_count 6 "$dns_ipv6")" -eq "$action34h_expected_count" || return 1
    gate caddy_ipv6_ownership test "$(address_count 6 "$caddy_ipv6")" -eq "$action34h_expected_count" || return 1
}

validate_payload() {
    local action34h_stage=$1
    local action34h_manifest=$action34h_stage/$artifact_manifest_relative
    local action34h_runtime_baseline=$action34h_stage/$runtime_baseline_relative
    local action34h_source action34h_target action34h_mode action34h_baseline action34h_candidate

    if [[ "$production_path_test_mode" = true ]]; then
        printf '%s_%s_production_payload_validation=reached\n' \
            "$prefix" "${role//-/_}"
        return 0
    fi

    [[ "$payload_archive" = /tmp/caddy-action34k-payload-* && -f "$payload_archive" && ! -L "$payload_archive" ]] || return 1
    [[ "$(file_hash "$payload_archive")" = "$payload_sha256" ]] || return 1
    tar -xf "$payload_archive" -C "$action34h_stage" || return 1
    [[ -f "$action34h_manifest" && ! -L "$action34h_manifest" ]] || return 1
    [[ -f "$action34h_runtime_baseline" && ! -L "$action34h_runtime_baseline" ]] || return 1
    [[ "$(file_hash "$action34h_runtime_baseline")" = "$runtime_baseline_sha256" ]] || return 1
    while IFS=$'\t' read -r action34h_source action34h_target action34h_mode \
        action34h_baseline action34h_candidate; do
        [[ -n "$action34h_source" && "$action34h_source" != \#* ]] || continue
        : "$action34h_target" "$action34h_mode" "$action34h_baseline"
        [[ "$action34h_source" != /* && "$action34h_source" != *..* ]] || return 1
        [[ -f "$action34h_stage/$action34h_source" && ! -L "$action34h_stage/$action34h_source" ]] || return 1
        [[ "$(file_hash "$action34h_stage/$action34h_source")" = "$action34h_candidate" ]] || return 1
    done <"$action34h_manifest"
}

verify_runtime_baseline() {
    local action34h_runtime_manifest=$1
    local action34h_allowed_mutations=${2:-}
    local action34h_source action34h_target action34h_mode action34h_accepted action34h_candidate

    while IFS=$'\t' read -r action34h_source action34h_target action34h_mode \
        action34h_accepted action34h_candidate; do
        [[ -n "$action34h_source" && "$action34h_source" != \#* ]] || continue
        : "$action34h_source" "$action34h_mode" "$action34h_accepted"
        if [[ -n "$action34h_allowed_mutations" ]] &&
            awk -F '\t' -v target="$action34h_target" \
                '!/^[[:space:]]*(#|$)/ && $2 == target { found++ } END { exit(found ? 0 : 1) }' \
                "$action34h_allowed_mutations"; then
            continue
        fi
        [[ -f "$action34h_target" && ! -L "$action34h_target" ]] || return 1
        [[ "$(file_hash "$action34h_target")" = "$action34h_candidate" ]] || return 1
    done <"$action34h_runtime_manifest"
}

verify_resume_baseline() {
    local action34h_manifest=$1
    local action34h_source action34h_target action34h_mode action34h_baseline action34h_candidate
    local action34h_label action34h_observed

    while IFS=$'\t' read -r action34h_source action34h_target action34h_mode \
        action34h_baseline action34h_candidate; do
        [[ -n "$action34h_source" && "$action34h_source" != \#* ]] || continue
        : "$action34h_source" "$action34h_mode"
        action34h_label=$(artifact_label "$action34h_target") || return 1
        action34h_observed=$(observe_artifact "$action34h_target") || return 1
        printf '%s_%s_baseline_%s_expected=legacy:%s|candidate:%s\n' \
            "$prefix" "${role//-/_}" "$action34h_label" "$action34h_baseline" "$action34h_candidate"
        printf '%s_%s_baseline_%s_observed=%s\n' \
            "$prefix" "${role//-/_}" "$action34h_label" "$action34h_observed"
        if [[ "$action34h_observed" = "$action34h_baseline" ||
            "$action34h_observed" = "$action34h_candidate" ]]; then
            printf '%s_%s_check_baseline_%s_identity=true\n' \
                "$prefix" "${role//-/_}" "$action34h_label"
        else
            printf '%s_%s_check_baseline_%s_identity=false\n' \
                "$prefix" "${role//-/_}" "$action34h_label" >&2
            return 1
        fi
    done <"$action34h_manifest"
}

verify_candidate_artifacts() {
    local action34h_manifest=$1
    local action34h_source action34h_target action34h_mode action34h_baseline action34h_candidate
    local action34h_label action34h_observed

    while IFS=$'\t' read -r action34h_source action34h_target action34h_mode \
        action34h_baseline action34h_candidate; do
        [[ -n "$action34h_source" && "$action34h_source" != \#* ]] || continue
        : "$action34h_source" "$action34h_mode" "$action34h_baseline"
        action34h_label=$(artifact_label "$action34h_target") || return 1
        action34h_observed=$(observe_artifact "$action34h_target") || return 1
        printf '%s_%s_candidate_%s_expected=%s\n' \
            "$prefix" "${role//-/_}" "$action34h_label" "$action34h_candidate"
        printf '%s_%s_candidate_%s_observed=%s\n' \
            "$prefix" "${role//-/_}" "$action34h_label" "$action34h_observed"
        if [[ "$action34h_observed" = "$action34h_candidate" ]]; then
            printf '%s_%s_check_candidate_%s_identity=true\n' \
                "$prefix" "${role//-/_}" "$action34h_label"
        else
            printf '%s_%s_check_candidate_%s_identity=false\n' \
                "$prefix" "${role//-/_}" "$action34h_label" >&2
            return 1
        fi
    done <"$action34h_manifest"
}

cleanup_failed_action34_payload_at() {
    local action34h_scan_root=$1
    local action34h_expected_sha256=$2
    local action34h_entry action34h_name action34h_hash
    local action34h_match_count=0
    local action34h_inventory_count=0
    local action34h_match_path=
    [[ "$action34h_scan_root" = /tmp ||
        "$action34h_scan_root" =~ ^/tmp/caddy-action34h-regression\.[a-zA-Z0-9]+/cleanup$ ]] || return 1
    shopt -s nullglob
    for action34h_entry in "$action34h_scan_root"/caddy-action34-payload-node-*.tar; do
        action34h_inventory_count=$((action34h_inventory_count + 1))
        action34h_name=${action34h_entry##*/}
        [[ "$action34h_name" =~ ^caddy-action34-payload-node-[ab]-[0-9]{10,20}-[0-9]+\.tar$ ]] || return 1
        [[ -f "$action34h_entry" && ! -L "$action34h_entry" ]] || return 1
        action34h_hash=$(file_hash "$action34h_entry") || return 1
        printf '%s_%s_failed_action34_payload_%s_sha256=%s\n' \
            "$prefix" "${role//-/_}" "$action34h_inventory_count" "$action34h_hash"
        if [[ "$action34h_hash" = "$action34h_expected_sha256" ]]; then
            action34h_match_count=$((action34h_match_count + 1))
            action34h_match_path=$action34h_entry
        fi
    done
    shopt -u nullglob
    printf '%s_%s_failed_action34_payload_inventory_count=%s\n' \
        "$prefix" "${role//-/_}" "$action34h_inventory_count"
    printf '%s_%s_failed_action34_payload_match_count=%s\n' \
        "$prefix" "${role//-/_}" "$action34h_match_count"
    gate failed_action34_payload_match_bounded test "$action34h_match_count" -le 1 || return 1
    if [[ "$action34h_match_count" -eq 1 ]]; then
        action34h_name=${action34h_match_path##*/}
        rm -f -- "$action34h_match_path" || return 1
        [[ ! -e "$action34h_match_path" && ! -L "$action34h_match_path" ]] || return 1
        printf '%s_%s_failed_action34_payload_removed=%s\n' \
            "$prefix" "${role//-/_}" "$action34h_name"
    fi
}

cleanup_failed_action34_payload() {
    cleanup_failed_action34_payload_at /tmp "$failed_action34_payload_sha256"
}

backup_artifacts() {
    local action34h_stage=$1
    local action34h_manifest=$action34h_stage/$artifact_manifest_relative
    local action34h_source action34h_target action34h_mode action34h_baseline action34h_candidate
    install -d -o root -g root -m 0700 "$backup_root/files" || return 1
    install -m 0600 "$action34h_manifest" "$backup_root/artifacts.tsv" || return 1
    : >"$backup_root/baseline.tsv"
    chmod 0600 "$backup_root/baseline.tsv"
    while IFS=$'\t' read -r action34h_source action34h_target action34h_mode \
        action34h_baseline action34h_candidate; do
        [[ -n "$action34h_source" && "$action34h_source" != \#* ]] || continue
        : "$action34h_candidate"
        if [[ -e "$action34h_target" || -L "$action34h_target" ]]; then
            install -d -m 0700 "$backup_root/files${action34h_target%/*}" || return 1
            cp -a -- "$action34h_target" "$backup_root/files$action34h_target" || return 1
            printf 'present\t%s\n' "$action34h_target" >>"$backup_root/baseline.tsv"
        else
            printf 'absent\t%s\n' "$action34h_target" >>"$backup_root/baseline.tsv"
        fi
    done <"$action34h_manifest"
    install -m 0600 "$action34h_stage/$runtime_baseline_relative" \
        "$backup_root/runtime-baseline.tsv" || return 1
    install -m 0600 /dev/null "$backup_root/backup-complete" || return 1
}

install_artifacts() {
    local action34h_stage=$1
    local action34h_manifest=$action34h_stage/$artifact_manifest_relative
    local action34h_source action34h_target action34h_mode action34h_baseline action34h_candidate
    install -m 0600 /dev/null "$backup_root/mutation-started" || return 1
    mutation_started=true
    while IFS=$'\t' read -r action34h_source action34h_target action34h_mode \
        action34h_baseline action34h_candidate; do
        [[ -n "$action34h_source" && "$action34h_source" != \#* ]] || continue
        : "$action34h_baseline" "$action34h_candidate"
        install -d -o root -g root -m 0755 "${action34h_target%/*}" || return 1
        install -o root -g root -m "$action34h_mode" \
            "$action34h_stage/$action34h_source" "$action34h_target" || return 1
    done <"$action34h_manifest"
}

dispose_stale_worker_lock_at() {
    local action34h_lock_runtime_root=$1
    local action34h_lock_path=$action34h_lock_runtime_root/worker.lock
    local action34h_lock_metadata

    # conditional-validator-explicit-failures-begin
    gate worker_inactive_before_lock_disposition test \
        "$(systemctl show -p ActiveState --value caddy-apprise-worker.service)" = inactive || return 1
    gate lock_runtime_metadata test \
        "$(stat -c '%U:%G:%a' "$action34h_lock_runtime_root")" = pi:pi:700 || return 1
    if [[ ! -e "$action34h_lock_path" && ! -L "$action34h_lock_path" ]]; then
        printf '%s_%s_stale_worker_lock_disposition=absent\n' "$prefix" "${role//-/_}"
        return 0
    fi
    [[ -f "$action34h_lock_path" && ! -L "$action34h_lock_path" ]] || return 1
    action34h_lock_metadata=$(stat -c '%U:%G:%a' "$action34h_lock_path") || return 1
    printf '%s_%s_stale_worker_lock_metadata=%s\n' \
        "$prefix" "${role//-/_}" "$action34h_lock_metadata"
    [[ "$action34h_lock_metadata" = root:root:600 ]] || return 1
    rm -f -- "$action34h_lock_path" || return 1
    gate stale_worker_lock_removed test \
        ! -e "$action34h_lock_path" || return 1
    printf '%s_%s_stale_worker_lock_disposition=removed_exact_legacy\n' \
        "$prefix" "${role//-/_}"
    # conditional-validator-explicit-failures-end
}

validate_controlled_worker_prerequisites_at() {
    local action34h_prerequisite_phase=$1
    local action34h_prerequisite_transport=$2
    local action34h_prerequisite_allowlist=$3
    local action34h_prerequisite_expected_count=$4
    local action34h_prerequisite_label

    action34h_prerequisite_label=${action34h_prerequisite_phase}_transport_path_absolute
    gate "$action34h_prerequisite_label" test "${action34h_prerequisite_transport#/}" != "$action34h_prerequisite_transport" || return 1
    action34h_prerequisite_label=${action34h_prerequisite_phase}_transport_parent_searchable_by_pi
    gate "$action34h_prerequisite_label" runuser --user pi -- test -x "${action34h_prerequisite_transport%/*}" || return 1
    action34h_prerequisite_label=${action34h_prerequisite_phase}_transport_regular_by_pi
    gate "$action34h_prerequisite_label" runuser --user pi -- test -f "$action34h_prerequisite_transport" || return 1
    action34h_prerequisite_label=${action34h_prerequisite_phase}_transport_nonsymlink_by_pi
    gate "$action34h_prerequisite_label" runuser --user pi -- test ! -L "$action34h_prerequisite_transport" || return 1
    action34h_prerequisite_label=${action34h_prerequisite_phase}_transport_readable_by_pi
    gate "$action34h_prerequisite_label" runuser --user pi -- test -r "$action34h_prerequisite_transport" || return 1
    action34h_prerequisite_label=${action34h_prerequisite_phase}_transport_executable_by_pi
    gate "$action34h_prerequisite_label" runuser --user pi -- test -x "$action34h_prerequisite_transport" || return 1
    action34h_prerequisite_label=${action34h_prerequisite_phase}_transport_metadata
    gate "$action34h_prerequisite_label" test "$(stat -c '%U:%G:%a' "$action34h_prerequisite_transport")" = root:root:755 || return 1

    action34h_prerequisite_label=${action34h_prerequisite_phase}_allowlist_path_absolute
    gate "$action34h_prerequisite_label" test "${action34h_prerequisite_allowlist#/}" != "$action34h_prerequisite_allowlist" || return 1
    action34h_prerequisite_label=${action34h_prerequisite_phase}_allowlist_parent_searchable_by_pi
    gate "$action34h_prerequisite_label" runuser --user pi -- test -x "${action34h_prerequisite_allowlist%/*}" || return 1
    action34h_prerequisite_label=${action34h_prerequisite_phase}_allowlist_regular_by_pi
    gate "$action34h_prerequisite_label" runuser --user pi -- test -f "$action34h_prerequisite_allowlist" || return 1
    action34h_prerequisite_label=${action34h_prerequisite_phase}_allowlist_nonsymlink_by_pi
    gate "$action34h_prerequisite_label" runuser --user pi -- test ! -L "$action34h_prerequisite_allowlist" || return 1
    action34h_prerequisite_label=${action34h_prerequisite_phase}_allowlist_readable_by_pi
    gate "$action34h_prerequisite_label" runuser --user pi -- test -r "$action34h_prerequisite_allowlist" || return 1
    action34h_prerequisite_label=${action34h_prerequisite_phase}_allowlist_metadata
    gate "$action34h_prerequisite_label" test "$(stat -c '%U:%G:%a' "$action34h_prerequisite_allowlist")" = pi:pi:600 || return 1
    action34h_prerequisite_label=${action34h_prerequisite_phase}_allowlist_entry_count
    gate "$action34h_prerequisite_label" runuser --user pi -- test "$(runuser --user pi -- awk 'END { print NR }' "$action34h_prerequisite_allowlist")" -eq "$action34h_prerequisite_expected_count" ||
        return 1
    action34h_prerequisite_label=${action34h_prerequisite_phase}_allowlist_exact_grammar
    # shellcheck disable=SC2016
    gate "$action34h_prerequisite_label" runuser --user pi -- awk '
        NF != 1 || length($1) != 69 || $1 !~ /^[0-9a-f]+[.]json$/ { invalid=1 }
        END { exit(invalid || NR == 0 ? 1 : 0) }
    ' "$action34h_prerequisite_allowlist" || return 1
}

dispose_action34g_residue_at() {
    local action34h_residue_queue=$1
    local action34h_residue_evidence=$2
    local action34h_residue_role=$3
    local action34h_residue_uid=$4
    local action34h_residue_gid=$5
    local action34h_residue_path action34h_residue_name action34h_residue_hash
    local action34h_residue_source_count=0
    local action34h_residue_keepalived_count=0
    local action34h_residue_inventory_count=0

    # conditional-validator-explicit-failures-begin
    if [[ "$action34h_residue_role" = node-a ]]; then
        gate action34j_recovery_node_a_queue_absent test \
            ! -e "$action34h_residue_queue" || return 1
        printf '%s_%s_action34j_recovery_queue_disposition=already_absent\n' \
            "$prefix" "${action34h_residue_role//-/_}"
        return 0
    fi
    [[ "$action34h_residue_role" = node-b ]] || return 1
    if [[ ! -e "$action34h_residue_queue" && ! -L "$action34h_residue_queue" ]]; then
        gate action34j_recovery_node_b_queue_absent test \
            ! -e "$action34h_residue_queue" || return 1
        printf '%s_%s_action34j_recovery_queue_disposition=already_absent\n' \
            "$prefix" "${action34h_residue_role//-/_}"
        return 0
    fi
    [[ -d "$action34h_residue_queue" && ! -L "$action34h_residue_queue" ]] || return 1
    gate action34g_residue_queue_metadata test "$(stat -c '%u:%g:%a' "$action34h_residue_queue")" = "$action34h_residue_uid:$action34h_residue_gid:700" || return 1
    for action34h_residue_name in pending inflight dead-letter delivered; do
        action34h_residue_path=$action34h_residue_queue/$action34h_residue_name
        [[ -d "$action34h_residue_path" && ! -L "$action34h_residue_path" ]] || return 1
        gate "action34g_residue_directory_${action34h_residue_name//-/_}_metadata" test "$(stat -c '%u:%g:%a' "$action34h_residue_path")" = "$action34h_residue_uid:$action34h_residue_gid:700" || return 1
    done
    while IFS= read -r action34h_residue_path; do
        action34h_residue_inventory_count=$((action34h_residue_inventory_count + 1))
        action34h_residue_name=${action34h_residue_path##*/}
        case "$action34h_residue_path" in
            "$action34h_residue_queue/pending/$action34g_retained_record_one" | "$action34h_residue_queue/pending/$action34g_retained_record_two") ;;
            *) return 1 ;;
        esac
        [[ -f "$action34h_residue_path" && ! -L "$action34h_residue_path" ]] || return 1
        [[ "$(stat -c '%u:%g:%a' "$action34h_residue_path")" = "$action34h_residue_uid:$action34h_residue_gid:600" ]] || return 1
        [[ "$(wc -c <"$action34h_residue_path")" -le 8192 ]] || return 1
        action34h_residue_hash=$(file_hash "$action34h_residue_path") || return 1
        printf '%s_%s_action34g_residue_%s_sha256=%s\n' "$prefix" "${role//-/_}" "${action34h_residue_name%.json}" "$action34h_residue_hash"
        jq -e --arg id "${action34h_residue_name%.json}" '
            .schema == "caddy-apprise-queue/v1" and
            .event_id == $id and
            (.source == "caddy-sync" or .source == "keepalived") and
            (.host | type == "string" and length > 0 and length <= 253) and
            (.severity | IN("info", "success", "warning", "failure")) and
            (.created_at | type == "string") and
            (.created_epoch | type == "number") and
            .retry.attempt == 0 and
            (.retry.next_attempt_epoch | type == "number") and
            .payload.format == "text" and
            (.payload.title | type == "string") and
            (.payload.body | type == "string")
        ' "$action34h_residue_path" >/dev/null || return 1
        if jq -e '
            .source == "caddy-sync" and
            (.payload.body | contains("Action 34g controlled enqueue test"))
        ' "$action34h_residue_path" >/dev/null; then
            action34h_residue_source_count=$((action34h_residue_source_count + 1))
        elif jq -e '
            .source == "keepalived" and
            (.payload.body | contains("state change to: TEST"))
        ' "$action34h_residue_path" >/dev/null; then
            action34h_residue_keepalived_count=$((action34h_residue_keepalived_count + 1))
        else
            return 1
        fi
    done < <(find "$action34h_residue_queue" -mindepth 2 -maxdepth 2 -type f -name '*.json' -print | LC_ALL=C sort)
    gate action34g_residue_exact_record_count test "$action34h_residue_inventory_count" -eq 2 || return 1
    gate action34g_residue_caddy_sync_count test "$action34h_residue_source_count" -eq 1 || return 1
    gate action34g_residue_keepalived_count test "$action34h_residue_keepalived_count" -eq 1 || return 1
    gate action34g_residue_complete_inventory test "$(find "$action34h_residue_queue" -mindepth 1 -print | wc -l)" -eq 6 || return 1
    if [[ "$production_path_test_mode" = true ]]; then
        install -m 0600 /dev/null \
            "$action34h_residue_evidence/action34g-retained-records" || return 1
    else
        install -o root -g root -m 0600 /dev/null \
            "$action34h_residue_evidence/action34g-retained-records" || return 1
    fi
    printf '%s\n%s\n' "$action34g_retained_record_one" "$action34g_retained_record_two" >"$action34h_residue_evidence/action34g-retained-records" || return 1
    if [[ "$production_path_test_mode" = true ]]; then
        gate action34g_residue_evidence_metadata test \
            "$(stat -c '%u:%g:%a' "$action34h_residue_evidence/action34g-retained-records")" = \
            "$action34h_residue_uid:$action34h_residue_gid:600" || return 1
    else
        gate action34g_residue_evidence_metadata test \
            "$(stat -c '%U:%G:%a' "$action34h_residue_evidence/action34g-retained-records")" = \
            root:root:600 || return 1
    fi
    rm -f -- "$action34h_residue_queue/pending/$action34g_retained_record_one" "$action34h_residue_queue/pending/$action34g_retained_record_two" || return 1
    rmdir -- "$action34h_residue_queue/pending" "$action34h_residue_queue/inflight" "$action34h_residue_queue/dead-letter" "$action34h_residue_queue/delivered" || return 1
    rmdir -- "$action34h_residue_queue" || return 1
    gate action34g_residue_removed test ! -e "$action34h_residue_queue" || return 1
    printf '%s_%s_action34j_recovery_queue_disposition=removed_exact_two\n' \
        "$prefix" "${action34h_residue_role//-/_}"
    # conditional-validator-explicit-failures-end
}

force_record_eligible_at() {
    local action34j_record=$1
    local action34j_now=$2
    local action34j_uid=$3
    local action34j_gid=$4
    local action34j_temporary

    # conditional-validator-explicit-failures-begin
    [[ -f "$action34j_record" && ! -L "$action34j_record" ]] || return 1
    [[ "$action34j_uid" =~ ^[0-9]+$ && "$action34j_gid" =~ ^[0-9]+$ ]] || return 1
    [[ "$(stat -c '%u:%g:%a' -- "$action34j_record")" = "$action34j_uid:$action34j_gid:600" ]] || return 1
    action34j_temporary=$(mktemp "${action34j_record%/*}/.action34j.XXXXXX") || return 1
    jq --argjson now "$action34j_now" '.retry.next_attempt_epoch = $now' \
        "$action34j_record" >"$action34j_temporary" || {
        rm -f -- "$action34j_temporary"
        return 1
    }
    chown "$action34j_uid:$action34j_gid" "$action34j_temporary" || {
        rm -f -- "$action34j_temporary"
        return 1
    }
    chmod 0600 "$action34j_temporary" || {
        rm -f -- "$action34j_temporary"
        return 1
    }
    mv -f -- "$action34j_temporary" "$action34j_record" || return 1
    [[ -f "$action34j_record" && ! -L "$action34j_record" ]] || return 1
    [[ "$(stat -c '%u:%g:%a' -- "$action34j_record")" = "$action34j_uid:$action34j_gid:600" ]] || return 1
    [[ "$(jq -r '.retry.next_attempt_epoch' "$action34j_record")" -eq "$action34j_now" ]] || return 1
    # conditional-validator-explicit-failures-end
}

production_path_verify_ownership_rewrite() {
    local action34k_rewrite_record=$production_path_test_root/ownership-rewrite.json
    local action34k_rewrite_uid action34k_rewrite_gid
    action34k_rewrite_uid=$(id -u) || return 1
    action34k_rewrite_gid=$(id -g) || return 1
    jq -n '{retry:{attempt:1,next_attempt_epoch:1}}' >"$action34k_rewrite_record" || return 1
    chmod 0600 "$action34k_rewrite_record" || return 1
    force_record_eligible_at "$action34k_rewrite_record" 1700000100 \
        "$action34k_rewrite_uid" "$action34k_rewrite_gid" || return 1
    [[ "$(stat -c '%u:%g:%a' "$action34k_rewrite_record")" = "$action34k_rewrite_uid:$action34k_rewrite_gid:600" ]] || return 1
    [[ "$(jq -r '.retry.next_attempt_epoch' "$action34k_rewrite_record")" -eq 1700000100 ]] || return 1
    printf '%s_%s_production_ownership_rewrite=preserved\n' \
        "$prefix" "${role//-/_}"
}

production_path_write_record() {
    local action34k_record_path=$1
    local action34k_record_id=${action34k_record_path##*/}
    local action34k_record_source=$2
    local action34k_record_body=$3
    action34k_record_id=${action34k_record_id%.json}
    jq -n --arg id "$action34k_record_id" --arg source "$action34k_record_source" \
        --arg body "$action34k_record_body" '{
            schema:"caddy-apprise-queue/v1",
            event_id:$id,
            source:$source,
            host:"production-path.local",
            severity:"warning",
            created_at:"2026-08-15T00:00:00Z",
            created_epoch:1700000000,
            retry:{attempt:0,next_attempt_epoch:1700000000},
            payload:{format:"text",title:"production path",body:$body}
        }' >"$action34k_record_path" || return 1
    chmod 0600 "$action34k_record_path"
}

production_path_prepare_queue() {
    local action34k_case_root=$1
    local action34k_case=$2
    local action34k_case_queue=$action34k_case_root/queue
    local action34k_extra_name=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.json
    [[ "$action34k_case" != node-b-queue-absent &&
        "$action34k_case" != node-a-queue-absent ]] || return 0
    install -d -m 0700 "$action34k_case_queue" || return 1
    install -d -m 0700 "$action34k_case_queue/pending" \
        "$action34k_case_queue/inflight" "$action34k_case_queue/dead-letter" \
        "$action34k_case_queue/delivered" || return 1
    case "$action34k_case" in
        node-b-exact-two-records | node-b-extra-record | node-b-unsafe-metadata | \
            node-b-symlink | node-b-malformed-record)
            production_path_write_record \
                "$action34k_case_queue/pending/$action34g_retained_record_two" \
                keepalived 'state change to: TEST' || return 1
            ;;
    esac
    case "$action34k_case" in
        node-b-exact-two-records | node-b-one-record | node-b-extra-record | \
            node-b-unsafe-metadata)
            production_path_write_record \
                "$action34k_case_queue/pending/$action34g_retained_record_one" \
                caddy-sync 'Action 34g controlled enqueue test' || return 1
            ;;
        node-b-symlink)
            ln -s /dev/null \
                "$action34k_case_queue/pending/$action34g_retained_record_one" || return 1
            ;;
        node-b-malformed-record)
            printf 'not-json\n' \
                >"$action34k_case_queue/pending/$action34g_retained_record_one" || return 1
            chmod 0600 "$action34k_case_queue/pending/$action34g_retained_record_one" || return 1
            ;;
    esac
    if [[ "$action34k_case" = node-b-extra-record ]]; then
        production_path_write_record "$action34k_case_queue/pending/$action34k_extra_name" \
            caddy-sync 'unexpected extra record' || return 1
    elif [[ "$action34k_case" = node-b-unsafe-metadata ]]; then
        chmod 0755 "$action34k_case_queue" || return 1
    fi
}

production_path_run_case() {
    local action34k_case=$1
    local action34k_case_role=$2
    local action34k_expected_status=$3
    local action34k_case_root=$4/$action34k_case
    local action34k_case_stdout=$action34k_case_root.stdout
    local action34k_case_stderr=$action34k_case_root.stderr
    local action34k_case_status=0
    install -d -m 0700 "$action34k_case_root" || return 1
    production_path_prepare_queue "$action34k_case_root" "$action34k_case" || return 1
    (
        cd /
        /bin/bash "$transaction_path" --production-path-case \
            "$action34k_case" "$action34k_case_root" "$action34k_case_role"
    ) >"$action34k_case_stdout" 2>"$action34k_case_stderr" || action34k_case_status=$?
    [[ "$action34k_case_status" -eq "$action34k_expected_status" ]] || return 1
    if [[ "$action34k_expected_status" -eq 0 ]]; then
        grep -Fq 'production_payload_validation=reached' "$action34k_case_stdout" || return 1
        grep -Fq 'production_mutation_boundary=reached_without_mutation' \
            "$action34k_case_stdout" || return 1
        grep -Fq 'production_ownership_rewrite=preserved' "$action34k_case_stdout" || return 1
    fi
}

production_path_test() {
    local action34k_test_root
    action34k_test_root=$(mktemp -d /tmp/caddy-action34k-production-path.XXXXXX) || return 1
    # Expand the validated mktemp path now; the local variable is unavailable at EXIT.
    # shellcheck disable=SC2064
    trap "rm -rf -- '$action34k_test_root'" EXIT
    printf 'production_path_dispatch_entry=true\n'
    production_path_run_case node-b-queue-absent node-b 0 "$action34k_test_root" || return 1
    printf 'production_path_node_b_queue_absent=true\n'
    printf 'production_path_payload_validation_reached=true\n'
    printf 'production_path_mutation_boundary_reached=true\n'
    production_path_run_case node-b-exact-two-records node-b 0 "$action34k_test_root" || return 1
    printf 'production_path_node_b_exact_two_records=true\n'
    production_path_run_case node-b-one-record node-b 1 "$action34k_test_root" || return 1
    printf 'production_path_node_b_one_record_rejected=true\n'
    production_path_run_case node-b-extra-record node-b 1 "$action34k_test_root" || return 1
    printf 'production_path_node_b_extra_record_rejected=true\n'
    production_path_run_case node-b-unsafe-metadata node-b 1 "$action34k_test_root" || return 1
    printf 'production_path_node_b_unsafe_metadata_rejected=true\n'
    production_path_run_case node-b-symlink node-b 1 "$action34k_test_root" || return 1
    printf 'production_path_node_b_symlink_rejected=true\n'
    production_path_run_case node-b-malformed-record node-b 1 "$action34k_test_root" || return 1
    printf 'production_path_node_b_malformed_record_rejected=true\n'
    production_path_run_case node-a-queue-absent node-a 0 "$action34k_test_root" || return 1
    printf 'production_path_node_a_queue_absent=true\n'
    rm -rf -- "$action34k_test_root" || return 1
    trap - EXIT
}

exercise_queue() {
    local action34h_before action34h_after action34h_record action34h_now
    local action34h_controlled=$runtime_root/action34h-controlled-$run_token
    local action34h_controlled_evidence=$evidence_root/controlled-records
    local action34h_pi_identity

    systemctl stop caddy-apprise-worker.path caddy-apprise-worker.timer \
        caddy-apprise-worker.service || return 1
    dispose_stale_worker_lock_at "$runtime_root" || return 1
    action34h_before=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' | wc -l) || return 1
    /usr/local/libexec/lsyncd-sync-failure-notify.sh 'Action 34h controlled enqueue test' || return 1
    /usr/local/bin/keepalived-notify.sh GROUP PIHOLE_DUALSTACK TEST || return 1
    install -o root -g root -m 0600 /dev/null "$action34h_controlled_evidence" || return 1
    for action34h_record in "$queue_root/pending/"*.json; do
        if jq -e '
            (.source == "caddy-sync" and (.payload.body | contains("Action 34h controlled enqueue test"))) or
            (.source == "keepalived" and (.payload.body | contains("state change to: TEST")))
        ' "$action34h_record" >/dev/null; then
            printf '%s\n' "${action34h_record##*/}" >>"$action34h_controlled_evidence"
        fi
    done
    gate controlled_record_count test "$(wc -l <"$action34h_controlled_evidence")" -eq 2 || return 1
    gate controlled_record_evidence_metadata test "$(stat -c '%U:%G:%a' "$action34h_controlled_evidence")" = root:root:600 || return 1
    install -o pi -g pi -m 0600 "$action34h_controlled_evidence" "$action34h_controlled" || return 1
    action34h_after=$(find "$queue_root/pending" -maxdepth 1 -type f -name '*.json' | wc -l) || return 1
    gate producer_enqueue_count test "$((action34h_after - action34h_before))" -eq 2 || return 1
    grep -Fq 'curl' /usr/local/libexec/lsyncd-sync-failure-notify.sh && return 1
    grep -Eq '\bcurl\b|APPRISE_(URL|KEY|ENDPOINT)' /usr/local/bin/keepalived-notify.sh && return 1
    gate runtime_metadata test "$(stat -c '%U:%G:%a' "$runtime_root")" = pi:pi:700 || return 1
    action34h_pi_identity=$(id -u pi):$(id -g pi)
    while IFS= read -r action34h_controlled_name; do
        [[ "$action34h_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 1
        gate "record_owner_${action34h_controlled_name%.json}" test \
            "$(stat -c '%u:%g:%a' "$queue_root/pending/$action34h_controlled_name")" = \
            "$action34h_pi_identity:600" || return 1
    done <"$action34h_controlled_evidence"

    validate_controlled_worker_prerequisites_at retry "$retry_transport" "$action34h_controlled" 2 || return 1
    capture_command controlled_worker_retry runuser --user pi -- \
        env CADDY_APPRISE_TEST_MODE=1 \
        CADDY_APPRISE_CURL="$retry_transport" \
        CADDY_APPRISE_EVENT_ALLOWLIST="$action34h_controlled" \
        /usr/local/libexec/caddy-apprise-delivery-worker || return 1
    while IFS= read -r action34h_controlled_name; do
        [[ "$action34h_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 1
        action34h_record=$queue_root/pending/$action34h_controlled_name
        [[ -f "$action34h_record" && ! -L "$action34h_record" ]] || return 1
        gate "retry_attempt_${action34h_controlled_name%.json}" test \
            "$(jq -r '.retry.attempt' "$action34h_record")" -eq 1 || return 1
    done <"$action34h_controlled_evidence"
    action34h_now=$(date +%s)
    while IFS= read -r action34h_controlled_name; do
        [[ "$action34h_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 1
        action34h_record=$queue_root/pending/$action34h_controlled_name
        [[ -f "$action34h_record" && ! -L "$action34h_record" ]] || return 1
        force_record_eligible_at "$action34h_record" "$action34h_now" \
            "$(id -u pi)" "$(id -g pi)" || return 1
        gate "forced_eligibility_owner_${action34h_controlled_name%.json}" test \
            "$(stat -c '%u:%g:%a' "$action34h_record")" = \
            "$action34h_pi_identity:600" || return 1
    done <"$action34h_controlled_evidence"
    validate_controlled_worker_prerequisites_at delivery "$delivery_transport" "$action34h_controlled" 2 || return 1
    capture_command controlled_worker_delivery runuser --user pi -- \
        env CADDY_APPRISE_TEST_MODE=1 \
        CADDY_APPRISE_CURL="$delivery_transport" \
        CADDY_APPRISE_EVENT_ALLOWLIST="$action34h_controlled" \
        /usr/local/libexec/caddy-apprise-delivery-worker || return 1
    gate controlled_queue_empty test "$(find "$queue_root/pending" "$queue_root/inflight" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 0 || return 1
    gate controlled_dead_letter_empty test "$(find "$queue_root/dead-letter" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 0 || return 1
    while IFS= read -r action34h_controlled_name; do
        [[ "$action34h_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 1
        rm -f -- "$queue_root/delivered/$action34h_controlled_name" || return 1
    done <"$action34h_controlled_evidence"
    rm -f -- "$action34h_controlled" || return 1
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
    local action34h_stage
    local action34h_manifest
    local action34h_cursor

    [[ "$PWD" = / ]] || return 1
    if [[ "$production_path_test_mode" = true ]]; then
        install -d -m 0700 "$evidence_root" || return 1
        action34h_cursor=production-path-test
    else
        install -d -o root -g root -m 0700 "$evidence_root" || return 1
        journalctl --show-cursor -n 0 -o cat >"$evidence_root/journal.cursor" || return 1
        action34h_cursor=$(sed -n 's/^-- cursor: //p' "$evidence_root/journal.cursor")
        [[ -n "$action34h_cursor" ]] || return 1
    fi
    baseline || return 1
    if [[ "$production_path_test_mode" = true ]]; then
        dispose_action34g_residue_at "$queue_root" "$evidence_root" "$role" \
            "$(id -u)" "$(id -g)" || return 1
    else
        dispose_action34g_residue_at "$queue_root" "$evidence_root" "$role" \
            "$(id -u pi)" "$(id -g pi)" || return 1
    fi
    gate queue_baseline_absent test ! -e "$queue_root" || return 1
    [[ ! -e "$backup_root" ]] || return 1
    if [[ "$production_path_test_mode" = true ]]; then
        action34h_stage=$(mktemp -d "$production_path_test_root/stage.XXXXXX") || return 1
    else
        action34h_stage=$(mktemp -d /run/caddy-action34k-stage.XXXXXX) || return 1
    fi
    stage_path=$action34h_stage
    chmod 0700 "$action34h_stage" || return 1
    validate_payload "$action34h_stage" || return 1
    if [[ "$production_path_test_mode" = true ]]; then
        production_path_verify_ownership_rewrite || return 1
        printf '%s_%s_production_mutation_boundary=reached_without_mutation\n' \
            "$prefix" "${role//-/_}"
        return 0
    fi
    action34h_manifest=$action34h_stage/$artifact_manifest_relative
    gate action32g_runtime_baseline verify_runtime_baseline \
        "$action34h_stage/$runtime_baseline_relative" || return 1
    cleanup_failed_action34_payload || return 1
    verify_resume_baseline "$action34h_manifest" || return 1
    backup_artifacts "$action34h_stage" || return 1
    install_artifacts "$action34h_stage" || return 1
    systemctl daemon-reload || return 1
    systemd-tmpfiles --create /etc/tmpfiles.d/caddy-ha.conf || return 1
    verify_candidate_artifacts "$action34h_manifest" || return 1
    gate queue_metadata test "$(stat -c '%U:%G:%a' "$queue_root")" = pi:pi:700 || return 1
    exercise_queue || return 1
    gate path_enabled systemctl is-enabled --quiet caddy-apprise-worker.path || return 1
    gate path_active systemctl is-active --quiet caddy-apprise-worker.path || return 1
    gate timer_enabled systemctl is-enabled --quiet caddy-apprise-worker.timer || return 1
    gate timer_active systemctl is-active --quiet caddy-apprise-worker.timer || return 1
    gate worker_static test "$(systemctl is-enabled caddy-apprise-worker.service 2>&1 || true)" = static || return 1
    baseline || return 1
    journalctl --after-cursor "$action34h_cursor" -o short-iso --no-pager \
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
    local action34h_state action34h_target
    [[ -f "$backup_root/mutation-started" && ! -L "$backup_root/mutation-started" ]] || return 125
    [[ -f "$backup_root/backup-complete" && ! -L "$backup_root/backup-complete" ]] || return 125
    [[ -f "$backup_root/baseline.tsv" && ! -L "$backup_root/baseline.tsv" ]] || return 125
    systemctl disable --now caddy-apprise-worker.path caddy-apprise-worker.timer >/dev/null 2>&1 || true
    while IFS=$'\t' read -r action34h_state action34h_target; do
        case "$action34h_state" in
            present)
                [[ -e "$backup_root/files$action34h_target" || -L "$backup_root/files$action34h_target" ]] || return 125
                cp -a --remove-destination "$backup_root/files$action34h_target" "$action34h_target" || return 125
                ;;
            absent) rm -f -- "$action34h_target" || return 125 ;;
            *) return 125 ;;
        esac
    done <"$backup_root/baseline.tsv"
    if [[ -f "$evidence_root/controlled-records" && ! -L "$evidence_root/controlled-records" ]]; then
        while IFS= read -r action34h_controlled_name; do
            [[ "$action34h_controlled_name" =~ ^[0-9a-f]{64}\.json$ ]] || return 125
            rm -f -- "$queue_root"/{pending,inflight,dead-letter,delivered}/"$action34h_controlled_name" || return 125
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
    [[ "$payload_archive" = /tmp/caddy-action34k-payload-* ]] || return 0
    if [[ -e "$payload_archive" || -L "$payload_archive" ]]; then
        [[ -f "$payload_archive" && ! -L "$payload_archive" ]] || return 1
        [[ "$(file_hash "$payload_archive")" = "$payload_sha256" ]] || return 1
        rm -f -- "$payload_archive" || return 1
    fi
    [[ ! -e "$payload_archive" && ! -L "$payload_archive" ]]
}

cleanup_unmutated_backup() {
    [[ "$backup_root" =~ ^/var/backups/caddy-ha/action34k-node-[ab]-[0-9]{10,20}-[0-9]+$ ]] || return 1
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
    local action34h_manifest=$backup_root/artifacts.tsv
    baseline || return 1
    verify_candidate_artifacts "$action34h_manifest" || return 1
    gate action32g_runtime_baseline verify_runtime_baseline \
        "$backup_root/runtime-baseline.tsv" "$action34h_manifest" || return 1
    gate pending_empty test "$(find "$queue_root/pending" "$queue_root/inflight" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 0 || return 1
    gate dead_letter_empty test "$(find "$queue_root/dead-letter" -maxdepth 1 -type f -name '*.json' | wc -l)" -eq 0 || return 1
    gate path_enabled systemctl is-enabled --quiet caddy-apprise-worker.path || return 1
    gate timer_enabled systemctl is-enabled --quiet caddy-apprise-worker.timer || return 1
    printf '%s_%s_verify_complete=true\n' "$prefix" "${role//-/_}"
}

# shellcheck disable=SC2317
cleanup_on_exit() {
    local action34h_status=$?
    trap - EXIT
    [[ -z "$stage_path" ]] || rm -rf -- "$stage_path"
    if [[ "$action34h_status" -ne 0 && "$mutation_started" = true ]]; then
        if rollback_action; then
            printf '%s_%s_automatic_rollback=true\n' "$prefix" "${role//-/_}" >&2
        else
            printf '%s_%s_manual_intervention_required=true\n' "$prefix" "${role//-/_}" >&2
            exit 125
        fi
    elif [[ "$action34h_status" -ne 0 ]]; then
        if cleanup_current_payload && cleanup_unmutated_backup; then
            printf '%s_%s_pre_mutation_cleanup_complete=true\n' \
                "$prefix" "${role//-/_}" >&2
        else
            printf '%s_%s_pre_mutation_cleanup_incomplete=true\n' \
                "$prefix" "${role//-/_}" >&2
        fi
    fi
    exit "$action34h_status"
}

if [[ "$mode" = --library-test ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi

trap cleanup_on_exit EXIT

case "$mode" in
    --apply) apply_action ;;
    --production-path-case) apply_action ;;
    --production-path-test) production_path_test ;;
    --rollback) rollback_action ;;
    --recover) recover_action ;;
    --verify-current) verify_current ;;
    *) exit 64 ;;
esac
