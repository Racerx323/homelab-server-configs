#!/usr/bin/env bash

set -Euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action_prefix=action_17p_node_b
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly parent_revision=action15-health-follow-redirects
readonly accepted_release=/etc/caddy/releases/action15-health-follow-redirects
readonly release_dir="/var/lib/caddy-sync/incoming/node-a/$revision"
readonly receiver=/usr/local/libexec/caddy-sync-rsync-receiver
readonly receiver_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134

checks_total=0
checks_passed=0
checks_failed=0
first_failure=none

record_result() {
    local result_label=$1
    local result_value=$2

    checks_total=$((checks_total + 1))
    if [[ "$result_value" == true ]]; then
        printf '%s_check_%s=true\n' "$action_prefix" "$result_label"
        checks_passed=$((checks_passed + 1))
    else
        printf '%s_check_%s=false\n' "$action_prefix" "$result_label" >&2
        checks_failed=$((checks_failed + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$result_label
        fi
    fi
}

record_command() {
    local command_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        record_result "$command_label" true
    else
        record_result "$command_label" false
    fi
}

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

key_pair_matches() {
    local certificate_public_key
    local private_public_key

    certificate_public_key=$(
        openssl x509 -in "$release_dir/tls/fullchain.pem" -pubkey -noout |
            openssl pkey -pubin -outform DER 2>/dev/null |
            sha256sum |
            awk '{ print $1 }'
    )
    private_public_key=$(
        openssl pkey -in "$release_dir/tls/privkey.pem" -pubout \
            -outform DER 2>/dev/null |
            sha256sum |
            awk '{ print $1 }'
    )
    [[ "$certificate_public_key" == "$private_public_key" ]]
}

manifest_hashes_valid() {
    (
        cd "$release_dir" || exit
        sha256sum --check manifest.sha256
    )
}

record_continuity() {
    record_command identity_root test "$(id -u)" -eq 0
    record_command working_directory_root test "$(pwd -P)" = /
    record_command hostname_node_b test "$(hostname)" = j1-svpihole00
    record_command current_link_exact \
        test "$(readlink /etc/caddy/current 2>/dev/null || true)" = \
        "$accepted_release"
    record_command current_target_exact \
        test "$(readlink -e /etc/caddy/current 2>/dev/null || true)" = \
        "$accepted_release"
    record_command current_revision_exact \
        test "$(jq -r '.revision // empty' \
            /etc/caddy/current/release-manifest.json 2>/dev/null || true)" = \
        "$parent_revision"
    record_command receiver_regular test -f "$receiver"
    record_command receiver_not_symlink test ! -L "$receiver"
    record_command receiver_hash \
        test "$(file_hash "$receiver" 2>/dev/null || true)" = "$receiver_sha256"
    record_command caddy_active \
        test "$(systemctl is-active caddy.service 2>/dev/null || true)" = active
    record_command lsyncd_inactive \
        test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
    record_command caddy_lsyncd_inactive \
        test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = \
        inactive
    record_command reconcile_path_inactive \
        test "$(systemctl is-active caddy-sync-reconcile.path \
            2>/dev/null || true)" = inactive
    record_command reconcile_service_inactive \
        test "$(systemctl is-active caddy-sync-reconcile.service \
            2>/dev/null || true)" = inactive
}

record_release_payload() {
    record_command release_regular_directory test -d "$release_dir"
    record_command release_not_symlink test ! -L "$release_dir"
    record_command source_directory_metadata \
        test "$(stat -c '%U:%G:%a' \
            /var/lib/caddy-sync/incoming/node-a 2>/dev/null || true)" = \
        caddy-sync:caddy-sync:750
    record_command release_symlinks_absent \
        test -z "$(find "$release_dir" -type l -print -quit)"
    record_command release_revision_exact \
        test "$(jq -r '.revision // empty' \
            "$release_dir/release-manifest.json" 2>/dev/null || true)" = \
        "$revision"
    record_command release_parent_exact \
        test "$(jq -r '.parent_revision // empty' \
            "$release_dir/release-manifest.json" 2>/dev/null || true)" = \
        "$parent_revision"
    record_command release_source_exact \
        test "$(jq -r '.source_node // empty' \
            "$release_dir/release-manifest.json" 2>/dev/null || true)" = node-a
    record_command manifest_hashes_valid manifest_hashes_valid
    record_command release_directories_metadata \
        test -z "$(find "$release_dir" -type d \
            \( ! -user caddy-sync -o ! -group caddy-sync -o ! -perm 0550 \) \
            -print -quit)"
    record_command release_files_metadata \
        test -z "$(find "$release_dir" -type f \
            \( ! -user caddy-sync -o ! -group caddy-sync -o ! -perm 0440 \) \
            -print -quit)"
    record_command certificate_parse \
        openssl x509 -in "$release_dir/tls/fullchain.pem" -noout
    record_command private_key_parse \
        openssl pkey -in "$release_dir/tls/privkey.pem" -noout
    record_command certificate_key_match key_pair_matches
    record_command caddy_configuration_valid \
        env CADDY_CONFIG_ROOT="$release_dir" \
        NODE_FQDN=pihole00.local.theama.co \
        NODE_IPV4=10.1.0.54 \
        NODE_IPV6=fd36:5aa8:6971:1::54 \
        caddy validate --config "$release_dir/Caddyfile" \
        --adapter caddyfile
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$revision" == action17p-node-a-to-node-b-bootstrap ]]
    [[ "$parent_revision" == action15-health-follow-redirects ]]
    [[ "$accepted_release" == /etc/caddy/releases/action15-health-follow-redirects ]]
    printf 'action_17p_node_b_self_test_complete=true\n'
    exit 0
fi

if [[ $# -ne 1 || ! "${1:-}" =~ ^--(preflight|payload|complete)$ ]]; then
    printf 'Usage: %s --preflight|--payload|--complete\n' \
        "${0##*/}" >&2
    exit 2
fi

readonly phase=${1#--}
record_continuity

case "$phase" in
    preflight)
        record_command incoming_node_a_absent \
            test ! -e /var/lib/caddy-sync/incoming/node-a
        record_command incoming_node_b_absent \
            test ! -e /var/lib/caddy-sync/incoming/node-b
        ;;
    payload)
        record_release_payload
        record_command completion_marker_absent test ! -e "$release_dir/.complete"
        ;;
    complete)
        record_release_payload
        record_command completion_marker_regular test -f "$release_dir/.complete"
        record_command completion_marker_not_symlink test ! -L "$release_dir/.complete"
        record_command completion_marker_empty test ! -s "$release_dir/.complete"
        ;;
esac

manifest_sha256=unavailable
if [[ -f "$release_dir/manifest.sha256" ]]; then
    manifest_sha256=$(file_hash "$release_dir/manifest.sha256")
fi
printf '%s_value_phase=%s\n' "$action_prefix" "$phase"
printf '%s_value_revision=%s\n' "$action_prefix" "$revision"
printf '%s_value_parent_revision=%s\n' "$action_prefix" "$parent_revision"
printf '%s_value_manifest_sha256=%s\n' "$action_prefix" "$manifest_sha256"
printf '%s_checks_total=%s\n' "$action_prefix" "$checks_total"
printf '%s_checks_passed=%s\n' "$action_prefix" "$checks_passed"
printf '%s_checks_failed=%s\n' "$action_prefix" "$checks_failed"
printf '%s_first_failure=%s\n' "$action_prefix" "$first_failure"
printf '%s_service_mutations=false\n' "$action_prefix"
printf '%s_reconciliation_executed=false\n' "$action_prefix"
printf '%s_caddy_selection_changed=false\n' "$action_prefix"

if [[ "$checks_failed" -ne 0 ]]; then
    printf '%s_acceptance=false\n' "$action_prefix" >&2
    exit 1
fi

printf '%s_acceptance=true\n' "$action_prefix"
