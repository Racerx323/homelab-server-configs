#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20e_retry_a_probe
readonly installed_config=/etc/tmpfiles.d/caddy-ha.conf
readonly state_directory=/run/caddy-ha
readonly notify_directory=/run/caddy-ha-notify
readonly backup_root=/var/backups/caddy-ha
readonly notifier=/usr/local/libexec/lsyncd-ha-failover-notify.sh
readonly expected_notifier_sha256=5862b494301f972d039477d4ed93a7d56156b141cba31c41ccd61d7f843321d8
readonly expected_config_sha256=9d36d8b3e6a872bed9a435f569b543db8517e6ee79c2aa089583b8ca3dac6bc2
readonly caddy_ipv4=10.1.0.56/22
readonly caddy_ipv6=fd36:5aa8:6971:1::56/128
readonly dns_ipv4=10.1.0.55/22
readonly dns_ipv6=fd36:5aa8:6971:1::55/128
readonly maximum_stream_bytes=65536
readonly maximum_stream_lines=512

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
address_count() {
    local address_family=$1
    local expected_address=$2

    ip -o "-$address_family" address show dev eth0 2>/dev/null |
        awk -v expected="$expected_address" '$4 == expected { count++ }
            END { print count + 0 }'
}
safe_stream() {
    local inspected_path=$1

    [[ "$(wc -c <"$inspected_path")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$inspected_path")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$inspected_path" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$inspected_path"
}
emit_stream() {
    local emitted_label=$1
    local emitted_path=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$emitted_label" "$(wc -c <"$emitted_path")"
    printf '%s_%s_lines=%s\n' "$prefix" "$emitted_label" "$(line_count "$emitted_path")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$emitted_label" "$(file_hash "$emitted_path")"
    if [[ ! -s "$emitted_path" ]]; then
        printf '%s_%s_content_secured=empty\n' "$prefix" "$emitted_label"
        return 0
    fi
    printf '%s_%s_begin\n' "$prefix" "$emitted_label"
    cat "$emitted_path"
    printf '%s_%s_end\n' "$prefix" "$emitted_label"
}
snapshot_state() {
    local unit_name

    printf 'keepalived=%s\n' "$(file_hash /etc/keepalived/keepalived.conf)"
    printf 'fragment=%s\n' "$(file_hash /etc/keepalived/conf.d/caddy-ha.conf)"
    printf 'notifier=%s\n' "$(file_hash "$notifier")"
    printf 'addresses=%s:%s:%s:%s\n' \
        "$(address_count 4 "$caddy_ipv4")" "$(address_count 6 "$caddy_ipv6")" \
        "$(address_count 4 "$dns_ipv4")" "$(address_count 6 "$dns_ipv6")"
    for unit_name in keepalived.service caddy.service lighttpd.service; do
        printf 'unit=%s:%s:%s:%s\n' "$unit_name" \
            "$(systemctl is-active "$unit_name")" \
            "$(systemctl show -p MainPID --value "$unit_name")" \
            "$(systemctl show -p NRestarts --value "$unit_name")"
    done
}
path_not_writable_by() {
    local inspected_user=$1
    local inspected_path=$2

    ! runuser -u "$inspected_user" -- test -w "$inspected_path"
}
expected_assertions() {
    printf '%s\n' \
        identity_root working_directory_root node_role_exact hostname_exact architecture_arm64 \
        config_regular config_not_symlink config_metadata_exact config_hash_exact \
        config_line_count_exact config_header_exact state_rule_exact notify_rule_exact \
        tmpfiles_setup_loaded tmpfiles_setup_static tmpfiles_setup_active \
        version_status_zero version_stdout_safe version_stderr_safe \
        state_directory_regular state_directory_not_symlink state_directory_metadata_exact \
        state_readable_by_pi state_writable_by_pi state_searchable_by_pi \
        state_readable_by_caddy_sync state_searchable_by_caddy_sync \
        state_not_writable_by_caddy_sync notify_directory_regular notify_directory_not_symlink \
        notify_directory_metadata_exact notify_readable_by_pi notify_writable_by_pi \
        notify_searchable_by_pi notifier_not_invoked backup_count_one backup_directory_regular \
        backup_directory_not_symlink backup_directory_metadata_exact backup_manifest_regular \
        backup_manifest_not_symlink backup_manifest_metadata_exact backup_manifest_line_count_exact \
        backup_manifest_action_exact backup_manifest_node_exact backup_manifest_config_absent \
        backup_manifest_state_absent backup_manifest_notify_absent notifier_regular \
        notifier_not_symlink notifier_metadata_exact notifier_hash_exact notifier_inherits_pi \
        keepalived_active caddy_active lighttpd_active caddy_ipv4_absent caddy_ipv6_absent \
        dns_ipv4_role_exact dns_ipv6_role_exact before_snapshot_complete after_snapshot_complete \
        state_unchanged
}
record_assertion() {
    local assertion_label=$1

    shift
    if "$@"; then
        printf '%s_assertion_%s=true\n' "$prefix" "$assertion_label"
        return 0
    fi
    printf '%s_assertion_%s=false\n' "$prefix" "$assertion_label" >&2
    return 1
}

case "${1:-}" in
    --expected-assertions)
        [[ $# -eq 1 ]] || exit 64
        expected_assertions
        exit 0
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        [[ "$(expected_assertions | wc -l)" -eq "$(expected_assertions | LC_ALL=C sort -u | wc -l)" ]]
        ! expected_assertions | grep -Ev '^[a-z0-9_]+$' | grep -q .
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    --node)
        [[ $# -eq 2 ]] || exit 64
        node_role=$2
        ;;
    *)
        printf 'Usage: %s --node node-a|node-b | --expected-assertions | --self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
case "$node_role" in
    node-a)
        expected_hostname=j1-svpihole0
        expected_dns_count=1
        ;;
    node-b)
        expected_hostname=j1-svpihole00
        expected_dns_count=0
        ;;
    *) exit 64 ;;
esac
readonly node_role expected_hostname expected_dns_count

capture_root=$(mktemp -d /run/caddy-action20e-retry-a-probe.XXXXXX)
readonly capture_root
retain_evidence=false
cleanup() {
    # shellcheck disable=SC2317
    if [[ "$retain_evidence" = true ]]; then
        printf '%s_protected_evidence=%s\n' "$prefix" "$capture_root" >&2
    else
        rm -rf -- "$capture_root"
    fi
}
trap cleanup EXIT
readonly version_stdout=$capture_root/tmpfiles-version.stdout
readonly version_stderr=$capture_root/tmpfiles-version.stderr
touch "$version_stdout" "$version_stderr"
chmod 0600 "$version_stdout" "$version_stderr"

failures=0
first_failure=none
run_assertion() {
    local assertion_label=$1

    shift
    if ! record_assertion "$assertion_label" "$@"; then
        failures=$((failures + 1))
        if [[ "$first_failure" = none ]]; then first_failure=$assertion_label; fi
    fi
}

before_status=0
before_snapshot=$(snapshot_state) || before_status=$?
readonly before_snapshot before_status
run_assertion identity_root test "$(id -u)" -eq 0
run_assertion working_directory_root test "$(pwd -P)" = /
run_assertion node_role_exact test -n "$node_role"
run_assertion hostname_exact test "$(hostname)" = "$expected_hostname"
run_assertion architecture_arm64 test "$(dpkg --print-architecture)" = arm64
run_assertion config_regular test -f "$installed_config"
run_assertion config_not_symlink test ! -L "$installed_config"
run_assertion config_metadata_exact test "$(stat -c '%U:%G:%a' "$installed_config" 2>/dev/null || true)" = root:root:644
run_assertion config_hash_exact test "$(file_hash "$installed_config" 2>/dev/null || true)" = "$expected_config_sha256"
run_assertion config_line_count_exact test "$(awk 'END { print NR }' "$installed_config" 2>/dev/null || true)" -eq 3
run_assertion config_header_exact grep -Fqx '# Caddy HA runtime state. Recreated by systemd-tmpfiles during boot.' "$installed_config"
run_assertion state_rule_exact test "$(grep -Fxc 'd /run/caddy-ha 0750 pi caddy-sync -' "$installed_config" 2>/dev/null || true)" -eq 1
run_assertion notify_rule_exact test "$(grep -Fxc 'd /run/caddy-ha-notify 0700 pi pi -' "$installed_config" 2>/dev/null || true)" -eq 1
run_assertion tmpfiles_setup_loaded test "$(systemctl show -p LoadState --value systemd-tmpfiles-setup.service)" = loaded
run_assertion tmpfiles_setup_static test "$(systemctl is-enabled systemd-tmpfiles-setup.service 2>/dev/null || true)" = static
run_assertion tmpfiles_setup_active test "$(systemctl is-active systemd-tmpfiles-setup.service)" = active
version_status=0
systemd-tmpfiles --version >"$version_stdout" 2>"$version_stderr" || version_status=$?
readonly version_status
run_assertion version_status_zero test "$version_status" -eq 0
run_assertion version_stdout_safe safe_stream "$version_stdout"
run_assertion version_stderr_safe safe_stream "$version_stderr"
run_assertion state_directory_regular test -d "$state_directory"
run_assertion state_directory_not_symlink test ! -L "$state_directory"
run_assertion state_directory_metadata_exact test "$(stat -c '%U:%G:%a' "$state_directory" 2>/dev/null || true)" = pi:caddy-sync:750
run_assertion state_readable_by_pi runuser -u pi -- test -r "$state_directory"
run_assertion state_writable_by_pi runuser -u pi -- test -w "$state_directory"
run_assertion state_searchable_by_pi runuser -u pi -- test -x "$state_directory"
run_assertion state_readable_by_caddy_sync runuser -u caddy-sync -- test -r "$state_directory"
run_assertion state_searchable_by_caddy_sync runuser -u caddy-sync -- test -x "$state_directory"
run_assertion state_not_writable_by_caddy_sync path_not_writable_by caddy-sync "$state_directory"
run_assertion notify_directory_regular test -d "$notify_directory"
run_assertion notify_directory_not_symlink test ! -L "$notify_directory"
run_assertion notify_directory_metadata_exact test "$(stat -c '%U:%G:%a' "$notify_directory" 2>/dev/null || true)" = pi:pi:700
run_assertion notify_readable_by_pi runuser -u pi -- test -r "$notify_directory"
run_assertion notify_writable_by_pi runuser -u pi -- test -w "$notify_directory"
run_assertion notify_searchable_by_pi runuser -u pi -- test -x "$notify_directory"
run_assertion notifier_not_invoked test ! -e "$state_directory/vrrp-state"
backup_count=$(find "$backup_root" -mindepth 1 -maxdepth 1 -type d -name "action20e-${node_role}-runtime-directories.*" -print | wc -l)
readonly backup_count
backup_directory=$(find "$backup_root" -mindepth 1 -maxdepth 1 -type d -name "action20e-${node_role}-runtime-directories.*" -print -quit)
readonly backup_directory
run_assertion backup_count_one test "$backup_count" -eq 1
run_assertion backup_directory_regular test -d "$backup_directory"
run_assertion backup_directory_not_symlink test ! -L "$backup_directory"
run_assertion backup_directory_metadata_exact test "$(stat -c '%U:%G:%a' "$backup_directory" 2>/dev/null || true)" = root:root:700
run_assertion backup_manifest_regular test -f "$backup_directory/manifest"
run_assertion backup_manifest_not_symlink test ! -L "$backup_directory/manifest"
run_assertion backup_manifest_metadata_exact test "$(stat -c '%U:%G:%a' "$backup_directory/manifest" 2>/dev/null || true)" = root:root:600
run_assertion backup_manifest_line_count_exact test "$(awk 'END { print NR }' "$backup_directory/manifest" 2>/dev/null || true)" -eq 5
run_assertion backup_manifest_action_exact grep -Fxq 'action=20e' "$backup_directory/manifest"
run_assertion backup_manifest_node_exact grep -Fxq "node=$node_role" "$backup_directory/manifest"
run_assertion backup_manifest_config_absent grep -Fxq 'tmpfiles_config=absent' "$backup_directory/manifest"
run_assertion backup_manifest_state_absent grep -Fxq 'state_directory=absent' "$backup_directory/manifest"
run_assertion backup_manifest_notify_absent grep -Fxq 'notify_directory=absent' "$backup_directory/manifest"
run_assertion notifier_regular test -f "$notifier"
run_assertion notifier_not_symlink test ! -L "$notifier"
run_assertion notifier_metadata_exact test "$(stat -c '%U:%G:%a' "$notifier")" = root:root:755
run_assertion notifier_hash_exact test "$(file_hash "$notifier")" = "$expected_notifier_sha256"
run_assertion notifier_inherits_pi test "$(grep -Fxc '    script_user pi' /etc/keepalived/keepalived.conf 2>/dev/null || true)" -eq 1
run_assertion keepalived_active test "$(systemctl is-active keepalived.service)" = active
run_assertion caddy_active test "$(systemctl is-active caddy.service)" = active
run_assertion lighttpd_active test "$(systemctl is-active lighttpd.service)" = active
run_assertion caddy_ipv4_absent test "$(address_count 4 "$caddy_ipv4")" -eq 0
run_assertion caddy_ipv6_absent test "$(address_count 6 "$caddy_ipv6")" -eq 0
run_assertion dns_ipv4_role_exact test "$(address_count 4 "$dns_ipv4")" -eq "$expected_dns_count"
run_assertion dns_ipv6_role_exact test "$(address_count 6 "$dns_ipv6")" -eq "$expected_dns_count"
run_assertion before_snapshot_complete test "$before_status" -eq 0
after_status=0
after_snapshot=$(snapshot_state) || after_status=$?
readonly after_snapshot after_status
run_assertion after_snapshot_complete test "$after_status" -eq 0
run_assertion state_unchanged test "$after_snapshot" = "$before_snapshot"

emit_status=0
emit_stream version_stdout "$version_stdout" || emit_status=$?
emit_stream version_stderr "$version_stderr" || emit_status=$?
if [[ "$emit_status" -ne 0 ]]; then
    retain_evidence=true
    failures=$((failures + 1))
    if [[ "$first_failure" = none ]]; then first_failure=output_evidence_unsafe; fi
fi
printf '%s_assertion_count=%s\n' "$prefix" "$(expected_assertions | wc -l)"
printf '%s_failed_assertion_count=%s\n' "$prefix" "$failures"
printf '%s_first_failure=%s\n' "$prefix" "$first_failure"
printf '%s_node_role=%s\n' "$prefix" "$node_role"
printf '%s_backup_path=%s\n' "$prefix" "$backup_directory"
printf '%s_keepalived_mutated=false\n' "$prefix"
printf '%s_service_mutations=false\n' "$prefix"
printf '%s_vrrp_mutated=false\n' "$prefix"
printf '%s_vip_mutated=false\n' "$prefix"
printf '%s_notifier_invoked=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_inspection_complete=true\n' "$prefix"
[[ "$failures" -eq 0 ]]
