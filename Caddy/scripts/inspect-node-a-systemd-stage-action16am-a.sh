#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly stage=/var/tmp/caddy-systemd-node-a-action16am
readonly retained_sync_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj-e
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
readonly effective_caddy_sha256=3a5f3f84e08686a1cb6d247ee84698b896bf025203a2f74ab4cd578dee731a40
readonly effective_lighttpd_sha256=fdd4ccfc6ffcf219d2d51e721798ee7fee0393356198e294e03b6e69f3c8ec67
readonly expected_node_a_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'
readonly stage_digest_sha256=305120fdb6b9c970a2aab12aa21ed88c06c3f77b9f63654cd0487fc2656e6e15
readonly -a expected_files=(
    scripts/check-certificate-expiry.sh
    scripts/lsyncd-sync-failure-notify.sh
    scripts/reconcile-release.sh
    scripts/validate-sync-health.sh
    systemd/caddy-cert-expiry.service
    systemd/caddy-cert-expiry.timer
    systemd/caddy-lsyncd.service
    systemd/caddy-sync-failure@.service
    systemd/caddy-sync-health.service
    systemd/caddy-sync-health.timer
    systemd/caddy-sync-reconcile.path
    systemd/caddy-sync-reconcile.service
    systemd/caddy-validate-reload.path
    systemd/caddy-validate-reload.service
    systemd/caddy.service.d/override.conf
    systemd/lighttpd.service.d/caddy-ha.conf
)
readonly -a expected_directories=(
    scripts
    systemd
    systemd/caddy.service.d
    systemd/lighttpd.service.d
)
readonly -a expected_checksums=(
    'b4fec5ef37353aa944a3f319503b96ed60768e8bb1a204c539182f8aae1ee80f  scripts/check-certificate-expiry.sh'
    'cf59ceab47ae48e2793205c90cf39fccec236d21b1d55e39821560899dc83cd6  scripts/lsyncd-sync-failure-notify.sh'
    '9dcf65119599060b064ee820655f8e8d18839fdee1d1d2526d0e3e1c3eedbc1b  scripts/reconcile-release.sh'
    '77c5ab2ada350d24bf890eb055db58e6e46086cda6e023b533c7c793c181f56b  scripts/validate-sync-health.sh'
    '8c03321c483b5761266837b35b70b388430de0781dad24e4d6b489026b22a393  systemd/caddy-cert-expiry.service'
    '409a4494eff683c602ceced8d076eed1e9681e5d351665b54a3e614afb7f05f7  systemd/caddy-cert-expiry.timer'
    '93cbc36cea03b8b7e1605c44667463592cf64e0293ded9f816d1e34760a69ac8  systemd/caddy-lsyncd.service'
    'c8cf411dba10e1344d3fa14ba0006fb8e35eda1621630d5287d8619d0dda6286  systemd/caddy-sync-failure@.service'
    '1f89ac7a444ea7f92b6f7369df4efb3f73e2a5493693e15a4522015d86ac5b78  systemd/caddy-sync-health.service'
    '65bd3ff8f969301f17d6fdf457a8b6b1676489f5e536612cab57d61e0c6bdf8e  systemd/caddy-sync-health.timer'
    '1b2084ce0a382114c10a1211dbdec1628c9b32cd84450c9d7b09a3ba0a6425fc  systemd/caddy-sync-reconcile.path'
    '848787b77cc03fe3855961cc94ad2e6aa4e05934851a98643edcdf17d84bf8eb  systemd/caddy-sync-reconcile.service'
    'f7fde941ae045e5697aa9e966e4f9a40d55a1f08f413f02cf9f8775046331bb7  systemd/caddy-validate-reload.path'
    '51be7495194143210bf805fdaa78072162eed028e8da3b3507f73f416cde8322  systemd/caddy-validate-reload.service'
    'a292487f4cbde99abce048b97ec15dbae8ef511ec845dcf5740f343e143f39df  systemd/caddy.service.d/override.conf'
    '6856404c78b9fbc7b8d0f2ddd8b184abe039df28a0d4dc0762dc7ef66747487e  systemd/lighttpd.service.d/caddy-ha.conf'
)
readonly -a live_targets=(
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
    /usr/local/libexec/check-certificate-expiry.sh
    /usr/local/libexec/lsyncd-sync-failure-notify.sh
    /usr/local/libexec/reconcile-release.sh
    /usr/local/libexec/validate-sync-health.sh
)
readonly -a custom_units=(
    caddy-cert-expiry.service
    caddy-cert-expiry.timer
    caddy-lsyncd.service
    caddy-sync-failure@action16am-a-inspection.service
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
    [[ "${#expected_files[@]}" -eq 16 ]]
    [[ "${#expected_directories[@]}" -eq 4 ]]
    [[ "${#expected_checksums[@]}" -eq 16 ]]
    [[ "${#live_targets[@]}" -eq 16 ]]
    [[ "${#custom_units[@]}" -eq 10 ]]
    [[ "${#expected_libexec_files[@]}" -eq 3 ]]
    [[ "$stage_digest_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$expected_node_a_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    printf 'action_16am_a_systemd_stage_inspector_self_test_complete=true\n'
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

printf 'action_16am_a_remote_reached=true\n'
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
for target in "${live_targets[@]}"; do
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

tcp_frontend=$(
    ss -H -ltnp 2>/dev/null |
        awk '$4 ~ /:80$|:443$/ { print }' |
        sort
)
record_command tcp_frontend_present test -n "$tcp_frontend"
tcp_frontend_lighttpd_only=true
if [[ -n "$tcp_frontend" ]] &&
    grep -Fv 'users:(("lighttpd"' <<<"$tcp_frontend" >/dev/null; then
    tcp_frontend_lighttpd_only=false
fi
record_result tcp_frontend_lighttpd_only "$tcp_frontend_lighttpd_only"
record_equal udp_443_listener_count \
    "$(ss -H -lunp 2>/dev/null |
        awk '$4 ~ /:443$/ { count++ } END { print count + 0 }')" 0

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

record_command retained_sync_stage_directory test -d "$retained_sync_stage"
record_equal retained_sync_stage_meta \
    "$(stat -c '%U:%G:%a' "$retained_sync_stage" 2>/dev/null || true)" \
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
record_equal effective_caddy_unit_hash \
    "$effective_caddy_unit_sha256" "$effective_caddy_sha256"
printf 'effective_caddy_unit_sha256=%s\n' "$effective_caddy_unit_sha256"

effective_lighttpd_status=0
effective_lighttpd_unit_sha256=$(
    systemctl cat lighttpd.service 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
) || effective_lighttpd_status=$?
record_equal effective_lighttpd_unit_status "$effective_lighttpd_status" 0
record_equal effective_lighttpd_unit_hash \
    "$effective_lighttpd_unit_sha256" "$effective_lighttpd_sha256"
printf 'effective_lighttpd_unit_sha256=%s\n' "$effective_lighttpd_unit_sha256"

record_command stage_directory test -d "$stage"
record_equal stage_root_meta \
    "$(stat -c '%U:%G:%a' "$stage" 2>/dev/null || true)" root:root:750
mapfile -t actual_files < <(
    find "$stage" -type f -printf '%P\n' 2>/dev/null |
        sort
)
mapfile -t actual_directories < <(
    find "$stage" -mindepth 1 -type d -printf '%P\n' 2>/dev/null |
        sort
)
record_equal stage_file_set "${actual_files[*]}" "${expected_files[*]}"
record_equal stage_directory_set \
    "${actual_directories[*]}" "${expected_directories[*]}"
record_equal stage_file_count_valid "${#actual_files[@]}" 16
record_equal stage_directory_count "${#actual_directories[@]}" 4
record_equal stage_symlink_count \
    "$(find "$stage" -type l -print 2>/dev/null | wc -l)" 0

for checksum in "${expected_checksums[@]}"; do
    expected_hash=${checksum%% *}
    relative_path=${checksum#*  }
    label=${relative_path//[^A-Za-z0-9]/_}
    record_equal "stage_hash_$label" \
        "$(sha256sum "$stage/$relative_path" 2>/dev/null |
            awk '{ print $1 }')" \
        "$expected_hash"
    record_equal "stage_owner_$label" \
        "$(stat -c '%U:%G' "$stage/$relative_path" \
            2>/dev/null || true)" \
        root:root
    case "$relative_path" in
        scripts/*)
            expected_mode=755
            ;;
        *)
            expected_mode=644
            ;;
    esac
    record_equal "stage_mode_$label" \
        "$(stat -c '%a' "$stage/$relative_path" \
            2>/dev/null || true)" \
        "$expected_mode"
done
for script in "$stage"/scripts/*.sh; do
    record_command "stage_syntax_${script##*/}" bash -n "$script"
done
observed_stage_digest=$(
    cd "$stage" 2>/dev/null || exit 1
    printf '%s\n' "${expected_files[@]}" |
        sort |
        xargs sha256sum 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
)
record_equal stage_digest_valid \
    "$observed_stage_digest" "$stage_digest_sha256"

journal_status=0
journal_disk_usage=$(journalctl --disk-usage 2>/dev/null) || journal_status=$?
record_equal journal_disk_usage_status "$journal_status" 0
record_command journal_disk_usage_present test -n "$journal_disk_usage"
printf 'journal_disk_usage=%s\n' "$journal_disk_usage"
printf 'protected_package_inventory_sha256=%s\n' \
    "$observed_package_inventory_sha256"
printf 'stage_path=%s\n' "$stage"
printf 'stage_owner_mode=%s\n' \
    "$(stat -c '%U:%G:%a' "$stage" 2>/dev/null || true)"
printf 'stage_file_count=%s\n' "${#actual_files[@]}"
printf 'stage_digest=%s\n' "$observed_stage_digest"
printf 'inspection_mismatch_count=%s\n' "$mismatch_count"
printf 'first_failure=%s\n' "$first_failure"
printf 'peer_connections=false\n'
printf 'installed_helper_execution=false\n'
printf 'systemd_daemon_reload_performed=false\n'
printf 'service_mutations=false\n'
if [[ "$mismatch_count" -eq 0 ]]; then
    printf 'action_16am_a_stage_and_protected_state_valid=true\n'
    printf 'action_16am_a_read_only_inspection_complete=true\n'
    exit 0
fi
printf 'action_16am_a_stage_and_protected_state_valid=false\n'
printf 'action_16am_a_read_only_inspection_complete=true\n'
exit 1
