#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly action_prefix=action_17p_node_a
readonly source_release=/etc/caddy/releases/action16ar-retry-node-a-default-deny
readonly expected_current_target="$source_release"
readonly parent_revision=action15-health-follow-redirects
readonly revision=action17p-node-a-to-node-b-bootstrap
readonly outbound_root=/var/lib/caddy-sync/outbound
readonly release_dir="$outbound_root/$revision"
readonly node_a_ipv6=fd36:5aa8:6971:1::53
readonly node_b_fqdn=pihole00.local.theama.co
readonly sync_user=caddy-sync
readonly private_key=/var/lib/caddy-sync/.ssh/id_ed25519
readonly known_hosts=/var/lib/caddy-sync/.ssh/known_hosts

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

source_manifest_hashes_valid() {
    (
        cd "$source_release" || exit
        sha256sum --check manifest.sha256
    )
}

record_common_preflight() {
    record_command identity_root test "$(id -u)" -eq 0
    record_command working_directory_root test "$(pwd -P)" = /
    record_command hostname_node_a test "$(hostname)" = j1-svpihole0
    record_command current_link_exact \
        test "$(readlink /etc/caddy/current 2>/dev/null || true)" = \
        "$expected_current_target"
    record_command current_target_exact \
        test "$(readlink -e /etc/caddy/current 2>/dev/null || true)" = \
        "$expected_current_target"
    record_command source_release_regular_directory test -d "$source_release"
    record_command source_release_not_symlink test ! -L "$source_release"
    record_command source_revision_exact \
        test "$(jq -r '.revision // empty' \
            "$source_release/release-manifest.json" 2>/dev/null || true)" = \
        action16ar-retry-node-a-default-deny
    record_command source_manifest_hashes_valid source_manifest_hashes_valid
    record_command source_completion_marker_regular \
        test -f "$source_release/.complete"
    record_command source_completion_marker_empty \
        test ! -s "$source_release/.complete"
    record_command private_key_regular test -f "$private_key"
    record_command private_key_not_symlink test ! -L "$private_key"
    record_command known_hosts_regular test -f "$known_hosts"
    record_command caddy_active \
        test "$(systemctl is-active caddy.service 2>/dev/null || true)" = active
    record_command lsyncd_inactive \
        test "$(systemctl is-active lsyncd.service 2>/dev/null || true)" = inactive
    record_command caddy_lsyncd_inactive \
        test "$(systemctl is-active caddy-lsyncd.service 2>/dev/null || true)" = \
        inactive
}

remote_shell_value() {
    printf '%s' \
        "ssh -6 -F /dev/null -b $node_a_ipv6" \
        " -i $private_key -o BatchMode=yes" \
        " -o ClearAllForwardings=yes -o ConnectTimeout=5" \
        " -o GlobalKnownHostsFile=/dev/null" \
        " -o HostKeyAlias=$node_b_fqdn -o IdentitiesOnly=yes" \
        " -o KbdInteractiveAuthentication=no" \
        " -o PasswordAuthentication=no" \
        " -o PreferredAuthentications=publickey" \
        " -o ServerAliveCountMax=2 -o ServerAliveInterval=2" \
        " -o StrictHostKeyChecking=yes -o UpdateHostKeys=no" \
        " -o UserKnownHostsFile=$known_hosts"
}

transfer_payload() {
    local remote_shell
    local rsync_error
    local rsync_output
    local rsync_status=0
    local transfer_root

    remote_shell=$(remote_shell_value)
    rsync_output=$(mktemp /tmp/caddy-action17p-payload-out.XXXXXX)
    rsync_error=$(mktemp /tmp/caddy-action17p-payload-err.XXXXXX)
    transfer_root=$(mktemp -d "$outbound_root/.action17p-transfer.XXXXXX")
    trap 'rm -rf -- "$transfer_root"' EXIT
    install -d -o caddy-sync -g caddy-sync -m 0750 \
        "$transfer_root/node-a"
    cp -al -- "$release_dir" "$transfer_root/node-a/$revision"
    chown caddy-sync:caddy-sync "$transfer_root"
    chmod 0750 "$transfer_root"
    runuser -u "$sync_user" -- \
        timeout --signal=TERM --kill-after=5s 45s \
        rsync \
        --archive \
        --checksum \
        --delay-updates \
        --exclude=.complete \
        --itemize-changes \
        --no-owner \
        --no-group \
        --rsh="$remote_shell" \
        "$transfer_root/node-a" \
        "$sync_user@$node_b_fqdn:/" \
        >"$rsync_output" 2>"$rsync_error" ||
        rsync_status=$?
    record_command payload_rsync_status test "$rsync_status" -eq 0
    record_command payload_rsync_stderr_empty test ! -s "$rsync_error"
    printf '%s_value_payload_rsync_stdout_lines=%s\n' \
        "$action_prefix" "$(wc -l <"$rsync_output")"
    printf '%s_value_payload_rsync_stdout_sha256=%s\n' \
        "$action_prefix" "$(file_hash "$rsync_output")"
    rm -rf -- "$transfer_root"
    trap - EXIT
    rm -f -- "$rsync_output" "$rsync_error"
}

transfer_completion_marker() {
    local remote_shell
    local rsync_error
    local rsync_output
    local rsync_status=0

    remote_shell=$(remote_shell_value)
    rsync_output=$(mktemp /tmp/caddy-action17p-complete-out.XXXXXX)
    rsync_error=$(mktemp /tmp/caddy-action17p-complete-err.XXXXXX)
    runuser -u "$sync_user" -- \
        timeout --signal=TERM --kill-after=5s 30s \
        rsync \
        --archive \
        --checksum \
        --itemize-changes \
        --no-owner \
        --no-group \
        --rsh="$remote_shell" \
        "$release_dir/.complete" \
        "$sync_user@$node_b_fqdn:/node-a/$revision/.complete" \
        >"$rsync_output" 2>"$rsync_error" ||
        rsync_status=$?
    record_command completion_rsync_status test "$rsync_status" -eq 0
    record_command completion_rsync_stderr_empty test ! -s "$rsync_error"
    printf '%s_value_completion_rsync_stdout_lines=%s\n' \
        "$action_prefix" "$(wc -l <"$rsync_output")"
    printf '%s_value_completion_rsync_stdout_sha256=%s\n' \
        "$action_prefix" "$(file_hash "$rsync_output")"
    rm -f -- "$rsync_output" "$rsync_error"
}

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "$revision" == action17p-node-a-to-node-b-bootstrap ]]
    [[ "$parent_revision" == action15-health-follow-redirects ]]
    [[ "$source_release" == /etc/caddy/releases/action16ar-retry-node-a-default-deny ]]
    [[ "$node_a_ipv6" == fd36:5aa8:6971:1::53 ]]
    [[ "$node_b_fqdn" == pihole00.local.theama.co ]]
    [[ "$(remote_shell_value)" == *"-b $node_a_ipv6"* ]]
    printf 'action_17p_node_a_self_test_complete=true\n'
    exit 0
fi

if [[ $# -ne 1 || ! "${1:-}" =~ ^--(payload|complete)$ ]]; then
    printf 'Usage: %s --payload|--complete\n' "${0##*/}" >&2
    exit 2
fi

readonly phase=${1#--}
record_common_preflight

if [[ "$phase" == payload ]]; then
    record_command release_absent_before test ! -e "$release_dir"
    if [[ "$checks_failed" -eq 0 ]]; then
        staging_dir=$(mktemp -d "$outbound_root/.action17p.XXXXXX")
        readonly staging_dir
        cleanup_staging() {
            # shellcheck disable=SC2317
            if [[ -d "$staging_dir" ]]; then
                rm -rf -- "$staging_dir"
            fi
        }
        trap cleanup_staging EXIT

        cp -a -- "$source_release/." "$staging_dir/"
        rm -f -- \
            "$staging_dir/.complete" \
            "$staging_dir/manifest.sha256" \
            "$staging_dir/release-manifest.json"
        jq -n \
            --arg release_revision "$revision" \
            --arg release_parent "$parent_revision" \
            --arg release_source node-a \
            --arg release_created_at "$(date --iso-8601=seconds)" \
            '{
                revision: $release_revision,
                parent_revision: $release_parent,
                source_node: $release_source,
                created_at: $release_created_at
            }' >"$staging_dir/release-manifest.json"
        (
            cd "$staging_dir" || exit
            find . -type f \
                ! -name manifest.sha256 \
                ! -name .complete \
                -print0 |
                LC_ALL=C sort -z |
                xargs -0 sha256sum
        ) >"$staging_dir/manifest.sha256"
        : >"$staging_dir/.complete"
        chown -R caddy-sync:caddy-sync "$staging_dir"
        find "$staging_dir" -type d -exec chmod 0550 {} +
        find "$staging_dir" -type f -exec chmod 0440 {} +
        mv -- "$staging_dir" "$release_dir"
        trap - EXIT
    fi

    record_command release_regular_directory test -d "$release_dir"
    record_command release_not_symlink test ! -L "$release_dir"
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
    record_command certificate_parse \
        openssl x509 -in "$release_dir/tls/fullchain.pem" -noout
    record_command private_key_parse \
        openssl pkey -in "$release_dir/tls/privkey.pem" -noout
    record_command certificate_key_match key_pair_matches
    record_command caddy_configuration_valid \
        env CADDY_CONFIG_ROOT="$release_dir" \
        NODE_FQDN=pihole0.local.theama.co \
        NODE_IPV4=10.1.0.53 \
        NODE_IPV6=fd36:5aa8:6971:1::53 \
        caddy validate --config "$release_dir/Caddyfile" \
        --adapter caddyfile
    record_command completion_marker_local_regular \
        test -f "$release_dir/.complete"
    record_command completion_marker_local_empty \
        test ! -s "$release_dir/.complete"

    record_command release_directories_metadata \
        test -z "$(find "$release_dir" -type d \
            \( ! -user caddy-sync -o ! -group caddy-sync -o ! -perm 0550 \) \
            -print -quit)"
    record_command release_files_metadata \
        test -z "$(find "$release_dir" -type f \
            \( ! -user caddy-sync -o ! -group caddy-sync -o ! -perm 0440 \) \
            -print -quit)"
    if [[ "$checks_failed" -eq 0 ]]; then
        transfer_payload
    fi
elif [[ "$phase" == complete ]]; then
    record_command release_regular_directory test -d "$release_dir"
    record_command release_symlinks_absent \
        test -z "$(find "$release_dir" -type l -print -quit)"
    record_command completion_marker_local_regular \
        test -f "$release_dir/.complete"
    record_command completion_marker_local_empty \
        test ! -s "$release_dir/.complete"
    record_command manifest_hashes_valid manifest_hashes_valid
    if [[ "$checks_failed" -eq 0 ]]; then
        transfer_completion_marker
    fi
fi

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
