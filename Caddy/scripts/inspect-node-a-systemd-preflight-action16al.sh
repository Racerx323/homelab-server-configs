#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly retained_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj-e
readonly ssh_dir=/var/lib/caddy-sync/.ssh
readonly libexec=/usr/local/libexec
readonly lsyncd_config=/etc/lsyncd/caddy.lua
readonly keepalived_fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly live_lighttpd_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_lighttpd_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly keepalived_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly sysctl_sha256=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8
readonly package_inventory_sha256=6377ab1492b2da992dce53199e359c5a2faf3563abd8bf766e6d6967fa07da5c
readonly receiver_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134
readonly setup_helper_sha256=d1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140
readonly validator_sha256=85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072
readonly expected_node_a_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly -a unit_targets=(
    /etc/systemd/system/caddy-cert-expiry.service
    /etc/systemd/system/caddy-cert-expiry.timer
    /etc/systemd/system/caddy-lsyncd.service
    /etc/systemd/system/caddy-sync-failure@.service
    /etc/systemd/system/caddy-sync-health.service
    /etc/systemd/system/caddy-sync-health.timer
    /etc/systemd/system/caddy-sync-reconcile.path
    /etc/systemd/system/caddy-sync-reconcile.service
    /etc/systemd/system/caddy-validate-reload.path
    /etc/systemd/system/caddy-validate-reload.service
    /etc/systemd/system/caddy.service.d/override.conf
    /etc/systemd/system/lighttpd.service.d/caddy-ha.conf
)
readonly -a systemd_helper_targets=(
    /usr/local/libexec/check-certificate-expiry.sh
    /usr/local/libexec/lsyncd-sync-failure-notify.sh
    /usr/local/libexec/reconcile-release.sh
    /usr/local/libexec/validate-sync-health.sh
)
readonly -a custom_units=(
    caddy-cert-expiry.service
    caddy-cert-expiry.timer
    caddy-lsyncd.service
    caddy-sync-failure@action16al-preflight.service
    caddy-sync-health.service
    caddy-sync-health.timer
    caddy-sync-reconcile.path
    caddy-sync-reconcile.service
    caddy-validate-reload.path
    caddy-validate-reload.service
)
readonly -a expected_libexec_files=(
    caddy-sync-rsync-receiver
    setup-sync-ssh.sh
    validate-sync-ssh.sh
)

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "${#unit_targets[@]}" -eq 12 ]]
    [[ "${#systemd_helper_targets[@]}" -eq 4 ]]
    [[ "${#custom_units[@]}" -eq 10 ]]
    [[ "${#expected_libexec_files[@]}" -eq 3 ]]
    [[ "$expected_node_a_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    printf 'action_16al_systemd_preflight_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

set +e
mismatch_count=0
first_failure=none

record_result() {
    local label=$1
    local matched=$2

    if [[ "$matched" != true ]]; then
        mismatch_count=$((mismatch_count + 1))
        if [[ "$first_failure" == none ]]; then
            first_failure=$label
        fi
    fi
    printf '%s=%s\n' "$label" "$matched"
}

record_equal() {
    local label=$1
    local observed=$2
    local expected=$3

    if [[ "$observed" == "$expected" ]]; then
        record_result "$label" true
    else
        record_result "$label" false
    fi
}

record_command() {
    local label=$1
    shift

    if "$@" >/dev/null 2>&1; then
        record_result "$label" true
    else
        record_result "$label" false
    fi
}

record_absent() {
    local label=$1
    local target=$2

    if [[ ! -e "$target" && ! -L "$target" ]]; then
        record_result "$label" true
    else
        record_result "$label" false
    fi
}

tree_hash() {
    local root=$1

    (
        cd "$root" || exit 1
        find . -type f -print0 |
            sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

unit_property() {
    local unit=$1
    local property=$2

    systemctl show "$unit" --property="$property" --value 2>/dev/null || true
}

printf 'action_16al_remote_reached=true\n'
record_equal root_effective_uid "$(id -u 2>/dev/null || true)" 0
record_equal node_hostname "$(hostname 2>/dev/null || true)" j1-svpihole0
record_command node_ipv4_present \
    grep -Fq '10.1.0.53/22' < <(ip -o -4 address show dev eth0 2>/dev/null)
record_equal node_architecture \
    "$(dpkg --print-architecture 2>/dev/null || true)" arm64
printf 'systemd_version=%s\n' \
    "$(systemctl --version 2>/dev/null | head -n 1)"

for command_name in \
    systemctl systemd-analyze caddy lsyncd jq curl openssl ssh rsync logger; do
    command_path=$(command -v "$command_name" 2>/dev/null || true)
    record_command "command_${command_name//-/_}_present" test -n "$command_path"
    printf 'command_%s_path=%s\n' \
        "${command_name//-/_}" "${command_path:-unavailable}"
done

record_equal caddy_package \
    "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' \
        caddy 2>/dev/null || true)" \
    'ii :2.11.4:arm64'
record_equal lsyncd_package \
    "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' \
        lsyncd 2>/dev/null || true)" \
    'ii :2.2.3-1:arm64'
observed_package_inventory_sha256=$(
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' \
        2>/dev/null |
        sort |
        sha256sum |
        awk '{ print $1 }'
)
record_equal protected_package_inventory \
    "$observed_package_inventory_sha256" "$package_inventory_sha256"
dpkg_audit_status=0
dpkg_audit=$(dpkg --audit 2>/dev/null) || dpkg_audit_status=$?
record_equal dpkg_audit_status "$dpkg_audit_status" 0
record_equal dpkg_audit_bytes "$(printf '%s' "$dpkg_audit" | wc -c)" 0

for directory in \
    /etc/systemd/system/caddy.service.d \
    /etc/systemd/system/lighttpd.service.d; do
    label=${directory//[^A-Za-z0-9]/_}
    record_absent "systemd_directory_${label}_absent" "$directory"
done
for target in "${unit_targets[@]}" "${systemd_helper_targets[@]}"; do
    label=${target//[^A-Za-z0-9]/_}
    record_absent "installation_target_${label}_absent" "$target"
done

for unit in "${custom_units[@]}"; do
    label=${unit//[^A-Za-z0-9]/_}
    load_state=$(unit_property "$unit" LoadState)
    active_state=$(unit_property "$unit" ActiveState)
    unit_file_state=$(unit_property "$unit" UnitFileState)
    printf 'custom_unit=%s load=%s active=%s unit_file=%s\n' \
        "$unit" "${load_state:-unavailable}" \
        "${active_state:-unavailable}" "${unit_file_state:-unavailable}"
    record_equal "custom_unit_${label}_load_not_found" \
        "$load_state" not-found
    record_equal "custom_unit_${label}_inactive" "$active_state" inactive
    record_equal "custom_unit_${label}_unit_file_absent" "$unit_file_state" ''
done

for unit in \
    caddy.service caddy-api.service lsyncd.service \
    uuidd.service uuidd.socket; do
    label=${unit//[^A-Za-z0-9]/_}
    record_equal "protected_unit_${label}_inactive" \
        "$(systemctl is-active "$unit" 2>/dev/null || true)" inactive
    record_equal "protected_unit_${label}_masked" \
        "$(systemctl is-enabled "$unit" 2>/dev/null || true)" masked
done
record_equal protected_caddy_api_socket_load \
    "$(unit_property caddy-api.socket LoadState)" not-found
record_equal protected_caddy_api_socket_active \
    "$(unit_property caddy-api.socket ActiveState)" inactive
record_equal protected_caddy_api_socket_unit_file \
    "$(unit_property caddy-api.socket UnitFileState)" ''

for unit in lighttpd.service keepalived.service ssh.service; do
    label=${unit//[^A-Za-z0-9]/_}
    record_equal "baseline_unit_${label}_active" \
        "$(systemctl is-active "$unit" 2>/dev/null || true)" active
    record_equal "baseline_unit_${label}_enabled" \
        "$(systemctl is-enabled "$unit" 2>/dev/null || true)" enabled
done
for unit in unbound.service pihole-FTL.service munin-node.service; do
    label=${unit//[^A-Za-z0-9]/_}
    record_equal "baseline_unit_${label}_active" \
        "$(systemctl is-active "$unit" 2>/dev/null || true)" active
done
record_equal caddy_process_count "$(pgrep -xc caddy 2>/dev/null || true)" 0
record_equal lsyncd_process_count "$(pgrep -xc lsyncd 2>/dev/null || true)" 0

custom_enablement_links=$(
    find /etc/systemd/system -type l -printf '%p -> %l\n' 2>/dev/null |
        grep -E \
            'caddy-(cert-expiry|lsyncd|sync-health|sync-reconcile|validate-reload)' ||
        true
)
record_equal custom_enablement_link_count \
    "$(printf '%s' "$custom_enablement_links" |
        awk 'NF { count++ } END { print count + 0 }')" 0

record_equal caddy_environment_hash \
    "$(sha256sum /etc/default/caddy-ha 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$environment_sha256"
record_command environment_node_role \
    grep -Fxq 'NODE_ROLE=node-a' /etc/default/caddy-ha
record_equal caddy_current_target \
    "$(readlink /etc/caddy/current 2>/dev/null || true)" \
    /etc/caddy/releases/bootstrap
record_equal caddy_current_resolved \
    "$(readlink -e /etc/caddy/current 2>/dev/null || true)" \
    /etc/caddy/releases/bootstrap
for prerequisite in \
    /etc/default/caddy-ha \
    /etc/caddy/current \
    /etc/caddy/current/Caddyfile \
    /etc/caddy/current/tls/leaf.pem \
    /var/lib/caddy-sync \
    /var/lib/caddy-sync/incoming; do
    label=${prerequisite//[^A-Za-z0-9]/_}
    record_command "prerequisite_${label}_present" \
        test -e "$prerequisite" -o -L "$prerequisite"
    stat --printf='prerequisite=%n owner=%U:%G mode=%a type=%F\n' \
        "$prerequisite" 2>/dev/null || true
done

record_command retained_stage_directory test -d "$retained_stage"
record_equal retained_stage_meta \
    "$(stat -c '%U:%G:%a' "$retained_stage" 2>/dev/null || true)" \
    root:root:750
record_equal caddy_sync_shell \
    "$(getent passwd caddy-sync 2>/dev/null | cut -d: -f7 || true)" /bin/sh
record_equal caddy_sync_password_state \
    "$(passwd --status caddy-sync 2>/dev/null | awk '{ print $2 }' || true)" L
record_equal caddy_sync_ssh_dir_meta \
    "$(stat -c '%U:%G:%a' "$ssh_dir" 2>/dev/null || true)" \
    caddy-sync:caddy-sync:700
record_equal node_a_sync_fingerprint \
    "$(ssh-keygen -lf "$ssh_dir/id_ed25519.pub" -E sha256 2>/dev/null |
        awk '{ print $2 }' || true)" \
    "$expected_node_a_fingerprint"
record_equal node_a_authorized_key_count \
    "$(wc -l <"$ssh_dir/authorized_keys" 2>/dev/null || true)" 1

mapfile -t actual_libexec_files < <(
    find "$libexec" -mindepth 1 -maxdepth 1 -type f \
        -printf '%f\n' 2>/dev/null |
        sort
)
record_equal libexec_file_set \
    "${actual_libexec_files[*]}" "${expected_libexec_files[*]}"
record_equal receiver_hash \
    "$(sha256sum "$libexec/caddy-sync-rsync-receiver" 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$receiver_sha256"
record_equal setup_helper_hash \
    "$(sha256sum "$libexec/setup-sync-ssh.sh" 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$setup_helper_sha256"
record_equal validator_hash \
    "$(sha256sum "$libexec/validate-sync-ssh.sh" 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$validator_sha256"

record_absent lsyncd_configuration_absent "$lsyncd_config"
record_absent caddy_keepalived_fragment_absent "$keepalived_fragment"
record_equal live_lighttpd_tree_hash \
    "$(tree_hash /etc/lighttpd 2>/dev/null || true)" \
    "$live_lighttpd_sha256"
record_equal candidate_lighttpd_tree_hash \
    "$(tree_hash /var/tmp/caddy-ha-lighttpd-node-a-action16ab \
        2>/dev/null || true)" \
    "$candidate_lighttpd_sha256"
record_equal keepalived_hash \
    "$(sha256sum /etc/keepalived/keepalived.conf 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$keepalived_sha256"
record_equal sysctl_file_hash \
    "$(sha256sum /etc/sysctl.d/70-caddy-ha.conf 2>/dev/null |
        awk '{ print $1 }' || true)" \
    "$sysctl_sha256"
record_equal ipv4_nonlocal_bind \
    "$(sysctl -n net.ipv4.ip_nonlocal_bind 2>/dev/null || true)" 1
record_equal ipv6_nonlocal_bind \
    "$(sysctl -n net.ipv6.ip_nonlocal_bind 2>/dev/null || true)" 1

effective_caddy_status=0
effective_caddy_unit_sha256=$(
    systemctl cat caddy.service 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
) || effective_caddy_status=$?
record_equal effective_caddy_unit_status "$effective_caddy_status" 0
printf 'effective_caddy_unit_sha256=%s\n' \
    "$effective_caddy_unit_sha256"

effective_lighttpd_status=0
effective_lighttpd_unit_sha256=$(
    systemctl cat lighttpd.service 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
) || effective_lighttpd_status=$?
record_equal effective_lighttpd_unit_status "$effective_lighttpd_status" 0
printf 'effective_lighttpd_unit_sha256=%s\n' \
    "$effective_lighttpd_unit_sha256"

journal_status=0
journal_disk_usage=$(journalctl --disk-usage 2>/dev/null) || journal_status=$?
record_equal journal_disk_usage_status "$journal_status" 0
record_command journal_disk_usage_present test -n "$journal_disk_usage"
printf 'journal_disk_usage=%s\n' "$journal_disk_usage"
printf 'protected_package_inventory_sha256=%s\n' \
    "$observed_package_inventory_sha256"
printf 'preflight_mismatch_count=%s\n' "$mismatch_count"
printf 'first_failure=%s\n' "$first_failure"
printf 'peer_connections=false\n'
printf 'installed_helper_execution=false\n'
printf 'service_mutations=false\n'
if [[ "$mismatch_count" -eq 0 ]]; then
    printf 'action_16al_preflight_valid=true\n'
    printf 'action_16al_read_only_inspection_complete=true\n'
    exit 0
fi
printf 'action_16al_preflight_valid=false\n'
printf 'action_16al_read_only_inspection_complete=true\n'
exit 1
