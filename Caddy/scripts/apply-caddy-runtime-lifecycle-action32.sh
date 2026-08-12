#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_32_remote
readonly evidence_root=/tmp/caddy-action32
readonly backup_root=/var/backups/caddy-ha
readonly manifest_relative=Caddy/manifests/caddy-runtime-lifecycle-action32.tsv
readonly manifest_sha256=5c381af6311e0a8ef1827d7519f5d297c67e4ca298f068e9818a0d9eb1c60f7c
readonly dns_ipv4=10.1.0.55
readonly dns_ipv6=fd36:5aa8:6971:1::55
readonly caddy_ipv4=10.1.0.56
readonly caddy_ipv6=fd36:5aa8:6971:1::56
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6

# Registered accepted-live prerequisites. Keep node identities separate even
# where both nodes currently have identical bytes.
readonly node_a_cert_expiry_helper_sha256=b4fec5ef37353aa944a3f319503b96ed60768e8bb1a204c539182f8aae1ee80f
readonly node_b_cert_expiry_helper_sha256=b4fec5ef37353aa944a3f319503b96ed60768e8bb1a204c539182f8aae1ee80f
readonly node_a_protocol_v2_reconciler_sha256=1aab5c5029fb028f4832a52ade12a47e2f30a0716903eedab4fc6afded2034b4
readonly node_b_protocol_v2_reconciler_sha256=1aab5c5029fb028f4832a52ade12a47e2f30a0716903eedab4fc6afded2034b4
readonly node_a_sync_health_worker_sha256=91df406d38b3fbceec28a1adb188da0d996b3916521934318948b4e289fb85d4
readonly node_b_sync_health_worker_sha256=91df406d38b3fbceec28a1adb188da0d996b3916521934318948b4e289fb85d4
readonly node_a_cert_expiry_service_sha256=8c03321c483b5761266837b35b70b388430de0781dad24e4d6b489026b22a393
readonly node_b_cert_expiry_service_sha256=8c03321c483b5761266837b35b70b388430de0781dad24e4d6b489026b22a393
readonly node_a_lsyncd_unit_sha256=e9139d40f7891485ea423d4a064b9cb162ff1b6234bf27e83d2bb9fbce4c02d2
readonly node_b_lsyncd_unit_sha256=e9139d40f7891485ea423d4a064b9cb162ff1b6234bf27e83d2bb9fbce4c02d2
readonly node_a_sync_failure_unit_sha256=c8cf411dba10e1344d3fa14ba0006fb8e35eda1621630d5287d8619d0dda6286
readonly node_b_sync_failure_unit_sha256=c8cf411dba10e1344d3fa14ba0006fb8e35eda1621630d5287d8619d0dda6286
readonly node_a_sync_health_service_sha256=1f89ac7a444ea7f92b6f7369df4efb3f73e2a5493693e15a4522015d86ac5b78
readonly node_b_sync_health_service_sha256=1f89ac7a444ea7f92b6f7369df4efb3f73e2a5493693e15a4522015d86ac5b78
readonly node_a_sync_health_timer_sha256=65bd3ff8f969301f17d6fdf457a8b6b1676489f5e536612cab57d61e0c6bdf8e
readonly node_b_sync_health_timer_sha256=65bd3ff8f969301f17d6fdf457a8b6b1676489f5e536612cab57d61e0c6bdf8e
readonly node_a_reconcile_service_sha256=848787b77cc03fe3855961cc94ad2e6aa4e05934851a98643edcdf17d84bf8eb
readonly node_b_reconcile_service_sha256=848787b77cc03fe3855961cc94ad2e6aa4e05934851a98643edcdf17d84bf8eb
readonly node_a_caddy_override_sha256=a292487f4cbde99abce048b97ec15dbae8ef511ec845dcf5740f343e143f39df
readonly node_b_caddy_override_sha256=a292487f4cbde99abce048b97ec15dbae8ef511ec845dcf5740f343e143f39df

role=
node_token=
expected_hostname=
expected_state=
expected_vip_count=
expected_environment_sha256=
backup_directory=
capture_directory=
stage_directory=
archive_path=
mutation_started=false
transaction_complete=false
journal_cursor=
before_release=
before_outbound=
before_incoming=
before_quarantine=

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
check() {
    local action32_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_%s_check_%s=true\n' "$prefix" "$node_token" "$action32_label"
        return 0
    fi
    printf '%s_%s_check_%s=false\n' "$prefix" "$node_token" "$action32_label" >&2
    return 1
}
safe_stream() {
    local action32_stream=$1

    [[ "$(wc -c <"$action32_stream")" -le 4194304 ]] || return 1
    [[ "$(line_count "$action32_stream")" -le 32768 ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action32_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action32_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
        "$action32_stream"
}
emit_stream() {
    local action32_label=$1
    local action32_stream=$2

    printf '%s_%s_%s_bytes=%s\n' "$prefix" "$node_token" "$action32_label" \
        "$(wc -c <"$action32_stream")"
    printf '%s_%s_%s_lines=%s\n' "$prefix" "$node_token" "$action32_label" \
        "$(line_count "$action32_stream")"
    printf '%s_%s_%s_sha256=%s\n' "$prefix" "$node_token" "$action32_label" \
        "$(file_hash "$action32_stream")"
    safe_stream "$action32_stream" || return 97
    printf '%s_%s_%s_classification=bounded_safe\n' "$prefix" "$node_token" "$action32_label"
    if [[ -s "$action32_stream" ]]; then
        printf '%s_%s_%s_begin\n' "$prefix" "$node_token" "$action32_label"
        cat "$action32_stream"
        printf '%s_%s_%s_end\n' "$prefix" "$node_token" "$action32_label"
    else
        printf '%s_%s_%s_content=empty\n' "$prefix" "$node_token" "$action32_label"
    fi
}
run_captured() {
    local action32_label=$1
    local action32_stdout=$capture_directory/$action32_label.stdout
    local action32_stderr=$capture_directory/$action32_label.stderr
    local action32_status_file=$capture_directory/$action32_label.status
    local action32_status=0

    shift
    install -m 0600 /dev/null "$action32_stdout" || return 1
    install -m 0600 /dev/null "$action32_stderr" || return 1
    install -m 0600 /dev/null "$action32_status_file" || return 1
    "$@" >"$action32_stdout" 2>"$action32_stderr" || action32_status=$?
    printf '%s\n' "$action32_status" >"$action32_status_file"
    printf '%s_%s_%s_status=%s\n' "$prefix" "$node_token" "$action32_label" "$action32_status"
    emit_stream "${action32_label}_stdout" "$action32_stdout" || return $?
    emit_stream "${action32_label}_stderr" "$action32_stderr" || return $?
    [[ "$action32_status" -eq 0 ]]
}
configure_role() {
    role=$1
    node_token=${role//-/_}
    case "$role" in
        node-a)
            expected_hostname=j1-svpihole0
            expected_state=Master
            expected_vip_count=1
            expected_environment_sha256=209e31e11a72660b7ebada372278c8482d9d1e65c6d83f6aa9510634d78f5ee3
            ;;
        node-b)
            expected_hostname=j1-svpihole00
            expected_state=Backup
            expected_vip_count=0
            expected_environment_sha256=580d79608bb99567c1831d073785cdba9d9d02efeaa33717c8f8e0dca266b226
            ;;
        *) return 64 ;;
    esac
    backup_directory=$backup_root/action32-$role-runtime-lifecycle
    capture_directory=$evidence_root/$node_token
}
dbus_state() {
    busctl get-property org.keepalived.Vrrp1 "$1" \
        org.keepalived.Vrrp1.Instance State |
        awk -F '"' 'NF == 3 { print $2 }'
}
address_count() {
    local action32_family=$1
    local action32_address=$2

    ip -o "$action32_family" address show |
        awk -v wanted="$action32_address" \
            '$4 ~ ("^" wanted "/") { count++ } END { print count + 0 }'
}
active_exact() { [[ "$(systemctl is-active "$1" 2>/dev/null || true)" = "$2" ]]; }
enabled_exact() { [[ "$(systemctl is-enabled "$1" 2>/dev/null || true)" = "$2" ]]; }
status_snapshot_valid() {
    local action32_snapshot=/run/caddy-lsyncd/status

    [[ -f "$action32_snapshot" && ! -L "$action32_snapshot" && -s "$action32_snapshot" ]] || return 1
    [[ "$(wc -c <"$action32_snapshot")" -le 1048576 ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action32_snapshot" >/dev/null 2>&1 || return 1
    grep -Eq '^Lsyncd status report at .+$' "$action32_snapshot" || return 1
    grep -Eq '^Sync[0-9]+ source=.+$' "$action32_snapshot"
}
continuity() {
    check uid_root test "$(id -u)" -eq 0 || return 1
    check working_directory_root test "$PWD" = / || return 1
    check hostname_exact test "$(hostname)" = "$expected_hostname" || return 1
    check caddy_active active_exact caddy.service active || return 1
    check keepalived_active active_exact keepalived.service active || return 1
    check lsyncd_active active_exact caddy-lsyncd.service active || return 1
    check reconcile_path_active active_exact caddy-sync-reconcile.path active || return 1
    check cert_timer_active active_exact caddy-cert-expiry.timer active || return 1
    check health_timer_active active_exact caddy-sync-health.timer active || return 1
    check caddy_enabled enabled_exact caddy.service enabled || return 1
    check lsyncd_enabled enabled_exact caddy-lsyncd.service enabled || return 1
    check reconcile_path_enabled enabled_exact caddy-sync-reconcile.path enabled || return 1
    check cert_timer_enabled enabled_exact caddy-cert-expiry.timer enabled || return 1
    check health_timer_enabled enabled_exact caddy-sync-health.timer enabled || return 1
    check caddy_api_masked enabled_exact caddy-api.service masked || return 1
    check distribution_lsyncd_masked enabled_exact lsyncd.service masked || return 1
    check environment_hash test "$(file_hash /etc/default/caddy-ha)" = \
        "$expected_environment_sha256" || return 1
    check ipv4_state test "$(dbus_state "$ipv4_object")" = "$expected_state" || return 1
    check ipv6_state test "$(dbus_state "$ipv6_object")" = "$expected_state" || return 1
    check dns_ipv4_count test "$(address_count -4 "$dns_ipv4")" -eq "$expected_vip_count" || return 1
    check dns_ipv6_count test "$(address_count -6 "$dns_ipv6")" -eq "$expected_vip_count" || return 1
    check caddy_ipv4_count test "$(address_count -4 "$caddy_ipv4")" -eq "$expected_vip_count" || return 1
    check caddy_ipv6_count test "$(address_count -6 "$caddy_ipv6")" -eq "$expected_vip_count" || return 1
    check status_snapshot status_snapshot_valid || return 1
}
artifact_rows() {
    sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$1"
}
accepted_hash_for_target() {
    local action32_target=$1

    case "$action32_target" in
        /usr/local/libexec/check-certificate-expiry.sh)
            [[ "$role" = node-a ]] && printf '%s\n' "$node_a_cert_expiry_helper_sha256" ||
                printf '%s\n' "$node_b_cert_expiry_helper_sha256"
            ;;
        /usr/local/libexec/reconcile-release.sh)
            [[ "$role" = node-a ]] && printf '%s\n' "$node_a_protocol_v2_reconciler_sha256" ||
                printf '%s\n' "$node_b_protocol_v2_reconciler_sha256"
            ;;
        /usr/local/libexec/validate-sync-health.sh)
            [[ "$role" = node-a ]] && printf '%s\n' "$node_a_sync_health_worker_sha256" ||
                printf '%s\n' "$node_b_sync_health_worker_sha256"
            ;;
        /etc/systemd/system/caddy-cert-expiry.service)
            [[ "$role" = node-a ]] && printf '%s\n' "$node_a_cert_expiry_service_sha256" ||
                printf '%s\n' "$node_b_cert_expiry_service_sha256"
            ;;
        /etc/systemd/system/caddy-lsyncd.service)
            [[ "$role" = node-a ]] && printf '%s\n' "$node_a_lsyncd_unit_sha256" ||
                printf '%s\n' "$node_b_lsyncd_unit_sha256"
            ;;
        /etc/systemd/system/caddy-sync-failure@.service)
            [[ "$role" = node-a ]] && printf '%s\n' "$node_a_sync_failure_unit_sha256" ||
                printf '%s\n' "$node_b_sync_failure_unit_sha256"
            ;;
        /etc/systemd/system/caddy-sync-health.service)
            [[ "$role" = node-a ]] && printf '%s\n' "$node_a_sync_health_service_sha256" ||
                printf '%s\n' "$node_b_sync_health_service_sha256"
            ;;
        /etc/systemd/system/caddy-sync-health.timer)
            [[ "$role" = node-a ]] && printf '%s\n' "$node_a_sync_health_timer_sha256" ||
                printf '%s\n' "$node_b_sync_health_timer_sha256"
            ;;
        /etc/systemd/system/caddy-sync-reconcile.service)
            [[ "$role" = node-a ]] && printf '%s\n' "$node_a_reconcile_service_sha256" ||
                printf '%s\n' "$node_b_reconcile_service_sha256"
            ;;
        /etc/systemd/system/caddy.service.d/override.conf)
            [[ "$role" = node-a ]] && printf '%s\n' "$node_a_caddy_override_sha256" ||
                printf '%s\n' "$node_b_caddy_override_sha256"
            ;;
        *) return 1 ;;
    esac
}
validate_manifest_contract() {
    local action32_manifest=$1

    [[ -f "$action32_manifest" && ! -L "$action32_manifest" ]] || return 1
    [[ "$(file_hash "$action32_manifest")" = "$manifest_sha256" ]] || return 1
    awk -F '\t' '
        /^[[:space:]]*(#|$)/ { next }
        NF != 5 { exit 1 }
        $1 !~ /^Caddy\/(scripts|systemd)\/[A-Za-z0-9._@+\/-]+$/ { exit 1 }
        $2 !~ /^\/(etc\/systemd\/system|usr\/local\/libexec)\/[A-Za-z0-9._@+\/-]+$/ { exit 1 }
        $3 !~ /^0(644|755)$/ { exit 1 }
        length($4) != 64 || $4 !~ /^[0-9a-f]+$/ { exit 1 }
        length($5) != 64 || $5 !~ /^[0-9a-f]+$/ { exit 1 }
        seen_source[$1]++ || seen_target[$2]++ { exit 1 }
        END { exit(count != 10) }
        { count++ }
    ' "$action32_manifest"
}
validate_payload() {
    local action32_archive=$1
    local action32_archive_sha256=$2
    local action32_manifest
    local action32_source
    local action32_target
    local action32_mode
    local action32_baseline
    local action32_candidate
    local action32_expected_baseline

    [[ -f "$action32_archive" && ! -L "$action32_archive" ]] || return 1
    [[ "$action32_archive_sha256" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$(file_hash "$action32_archive")" = "$action32_archive_sha256" ]] || return 1
    stage_directory=$(mktemp -d /run/caddy-runtime-action32.XXXXXX 2>/dev/null ||
        mktemp -d /tmp/caddy-runtime-action32.XXXXXX) || return 1
    chmod 0700 "$stage_directory" || return 1
    tar -xf "$action32_archive" -C "$stage_directory" || return 1
    action32_manifest=$stage_directory/$manifest_relative
    validate_manifest_contract "$action32_manifest" || return 1
    while IFS=$'\t' read -r action32_source action32_target action32_mode \
        action32_baseline action32_candidate; do
        : "$action32_target" "$action32_mode" "$action32_baseline"
        action32_expected_baseline=$(accepted_hash_for_target "$action32_target") || return 1
        [[ "$action32_baseline" = "$action32_expected_baseline" ]] || return 1
        [[ -f "$stage_directory/$action32_source" && ! -L "$stage_directory/$action32_source" ]] || return 1
        [[ "$(file_hash "$stage_directory/$action32_source")" = "$action32_candidate" ]] || return 1
        case "$action32_source" in
            Caddy/scripts/*) /bin/bash -n "$stage_directory/$action32_source" || return 1 ;;
        esac
    done < <(artifact_rows "$action32_manifest")
}
verify_artifacts() {
    local action32_identity=$1
    local action32_manifest=$stage_directory/$manifest_relative
    local action32_source
    local action32_target
    local action32_mode
    local action32_baseline
    local action32_candidate
    local action32_expected

    while IFS=$'\t' read -r action32_source action32_target action32_mode \
        action32_baseline action32_candidate; do
        case "$action32_identity" in
            baseline) action32_expected=$action32_baseline ;;
            candidate) action32_expected=$action32_candidate ;;
            *) return 64 ;;
        esac
        check "artifact_${action32_source//[^a-zA-Z0-9]/_}_regular" \
            test -f "$action32_target" || return 1
        check "artifact_${action32_source//[^a-zA-Z0-9]/_}_not_symlink" \
            test ! -L "$action32_target" || return 1
        check "artifact_${action32_source//[^a-zA-Z0-9]/_}_metadata" \
            test "$(stat -c '%U:%G:%a' "$action32_target")" = "root:root:${action32_mode#0}" || return 1
        check "artifact_${action32_source//[^a-zA-Z0-9]/_}_hash" \
            test "$(file_hash "$action32_target")" = "$action32_expected" || return 1
    done < <(artifact_rows "$action32_manifest")
}
safe_direct_inventory() {
    local action32_root=$1

    [[ -d "$action32_root" && ! -L "$action32_root" ]] || return 1
    find "$action32_root" -mindepth 1 -maxdepth 1 -printf '%f\t%y\n' |
        LC_ALL=C sort
}
incoming_has_finalized_candidate() {
    find /var/lib/caddy-sync/incoming -mindepth 2 -maxdepth 2 -type d \
        -exec test -f '{}/.finalize-request' ';' \
        -exec test -f '{}/.complete' ';' -print -quit | grep -q .
}
no_finalized_candidate() { ! incoming_has_finalized_candidate; }
capture_semantic_state() {
    run_captured current_release readlink -f /etc/caddy/current || return 1
    before_release=$(cat "$capture_directory/current_release.stdout") || return 1
    [[ "$before_release" == /etc/caddy/releases/* && -d "$before_release" && ! -L "$before_release" ]] || return 1
    run_captured outbound_inventory safe_direct_inventory /var/lib/caddy-sync/outbound || return 1
    run_captured incoming_inventory safe_direct_inventory /var/lib/caddy-sync/incoming || return 1
    run_captured quarantine_inventory safe_direct_inventory /var/lib/caddy-sync/quarantine || return 1
    before_outbound=$(file_hash "$capture_directory/outbound_inventory.stdout") || return 1
    before_incoming=$(file_hash "$capture_directory/incoming_inventory.stdout") || return 1
    before_quarantine=$(file_hash "$capture_directory/quarantine_inventory.stdout") || return 1
    check no_finalized_candidate no_finalized_candidate || return 1
    if [[ "$role" = node-b ]]; then
        check node_b_outbound_empty test ! -s "$capture_directory/outbound_inventory.stdout" || return 1
    else
        check node_a_outbound_present test -s "$capture_directory/outbound_inventory.stdout" || return 1
    fi
}
semantic_state_unchanged() {
    local action32_label=$1
    local action32_root=$2
    local action32_expected=$3

    run_captured "$action32_label" safe_direct_inventory "$action32_root" || return 1
    [[ "$(file_hash "$capture_directory/$action32_label.stdout")" = "$action32_expected" ]]
}
capture_journal_cursor() {
    run_captured journal_cursor journalctl --show-cursor -n 0 --no-pager || return 1
    journal_cursor=$(awk '/^-- cursor: s=/ { print substr($0, 12); found++ } END { if (found != 1) exit 1 }' \
        "$capture_directory/journal_cursor.stdout") || return 1
}
record_backup() {
    local action32_manifest=$stage_directory/$manifest_relative
    local action32_source
    local action32_target
    local action32_mode
    local action32_baseline
    local action32_candidate
    local action32_name
    local action32_staging=${backup_directory}.staging.$$

    [[ ! -e "$backup_directory" && ! -L "$backup_directory" ]] || return 1
    install -d -o root -g root -m 0700 "$action32_staging/files" || return 1
    while IFS=$'\t' read -r action32_source action32_target action32_mode \
        action32_baseline action32_candidate; do
        : "$action32_source" "$action32_mode" "$action32_candidate"
        action32_name=$(printf '%s' "$action32_target" | sha256sum | awk '{ print $1 }')
        install -o root -g root -m 0600 "$action32_target" \
            "$action32_staging/files/$action32_name" || return 1
        printf '%s\t%s\t%s\t%s\n' "$action32_target" "$action32_mode" \
            "$action32_baseline" "$action32_name" >>"$action32_staging/manifest"
    done < <(artifact_rows "$action32_manifest")
    install -o root -g root -m 0600 "$action32_manifest" \
        "$action32_staging/manifest.source" || return 1
    printf 'before_release=%s\n' "$before_release" >>"$action32_staging/state"
    chmod 0600 "$action32_staging/manifest" "$action32_staging/state" || return 1
    mv -- "$action32_staging" "$backup_directory"
}
install_candidates() {
    local action32_manifest=$stage_directory/$manifest_relative
    local action32_source
    local action32_target
    local action32_mode
    local action32_baseline
    local action32_candidate
    local action32_parent
    local action32_temporary

    while IFS=$'\t' read -r action32_source action32_target action32_mode \
        action32_baseline action32_candidate; do
        : "$action32_baseline"
        action32_parent=${action32_target%/*}
        install -d -o root -g root -m 0755 "$action32_parent" || return 1
        action32_temporary=$action32_parent/.action32.${action32_target##*/}.$$
        install -o root -g root -m "$action32_mode" \
            "$stage_directory/$action32_source" "$action32_temporary" || return 1
        [[ "$(file_hash "$action32_temporary")" = "$action32_candidate" ]] || return 1
        mv -fT "$action32_temporary" "$action32_target" || return 1
    done < <(artifact_rows "$action32_manifest")
}
restore_backup() {
    local action32_target
    local action32_mode
    local action32_baseline
    local action32_name
    local action32_parent
    local action32_temporary

    [[ -f "$backup_directory/manifest" && ! -L "$backup_directory/manifest" ]] || return 1
    systemctl stop caddy-sync-reconcile.path caddy-lsyncd.service >/dev/null 2>&1 || return 1
    while IFS=$'\t' read -r action32_target action32_mode action32_baseline action32_name; do
        [[ "$(file_hash "$backup_directory/files/$action32_name")" = "$action32_baseline" ]] || return 1
        action32_parent=${action32_target%/*}
        action32_temporary=$action32_parent/.action32.rollback.${action32_target##*/}.$$
        install -o root -g root -m "$action32_mode" \
            "$backup_directory/files/$action32_name" "$action32_temporary" || return 1
        mv -fT "$action32_temporary" "$action32_target" || return 1
    done <"$backup_directory/manifest"
    systemctl daemon-reload || return 1
    systemctl start caddy-lsyncd.service caddy-sync-reconcile.path \
        caddy-cert-expiry.timer caddy-sync-health.timer || return 1
    continuity
}
wait_for_lsyncd_stability() {
    local action32_first_pid=
    local action32_first_restarts=
    local action32_sample
    local action32_pid
    local action32_restarts

    for action32_sample in 1 2 3 4 5; do
        printf 'stability_sample=%s\n' "$action32_sample"
        systemctl is-active --quiet caddy-lsyncd.service || return 1
        action32_pid=$(systemctl show caddy-lsyncd.service -p MainPID --value) || return 1
        action32_restarts=$(systemctl show caddy-lsyncd.service -p NRestarts --value) || return 1
        [[ "$action32_pid" =~ ^[1-9][0-9]*$ && "$action32_restarts" =~ ^[0-9]+$ ]] || return 1
        status_snapshot_valid || return 1
        if [[ -z "$action32_first_pid" ]]; then
            action32_first_pid=$action32_pid
            action32_first_restarts=$action32_restarts
        else
            [[ "$action32_pid" = "$action32_first_pid" &&
                "$action32_restarts" = "$action32_first_restarts" ]] || return 1
        fi
        sleep 2
    done
    printf 'stable_pid=%s\nstable_nrestarts=%s\n' "$action32_first_pid" "$action32_first_restarts"
}
post_cursor_clean() {
    local action32_journal=$capture_directory/post_cursor_journal.stdout

    ! grep -Eqi 'quarantined divergent|transport.*fail|rsync.*(error|fail)|exited with status [1-9]|Failed with result' \
        "$action32_journal"
}
file_lacks_literal() {
    local action32_literal=$1
    local action32_file=$2

    ! grep -Fq "$action32_literal" "$action32_file"
}
target_contract() {
    continuity || return 1
    verify_artifacts candidate || return 1
    check mandatory_caddy_environment grep -Fxq 'EnvironmentFile=/etc/default/caddy-ha' \
        /etc/systemd/system/caddy.service.d/override.conf || return 1
    check lsyncd_write_isolation grep -Fxq 'ReadWritePaths=/run/caddy-lsyncd' \
        /etc/systemd/system/caddy-lsyncd.service || return 1
    check lsyncd_sync_root_readonly grep -Fxq 'ReadOnlyPaths=/etc/lsyncd /var/lib/caddy-sync' \
        /etc/systemd/system/caddy-lsyncd.service || return 1
    check cert_failure_owned_by_systemd grep -Fxq 'OnFailure=caddy-sync-failure@%n.service' \
        /etc/systemd/system/caddy-cert-expiry.service || return 1
    check health_failure_owned_by_systemd grep -Fxq 'OnFailure=caddy-sync-failure@%n.service' \
        /etc/systemd/system/caddy-sync-health.service || return 1
    check reconcile_failure_owned_by_systemd grep -Fxq 'OnFailure=caddy-sync-failure@%n.service' \
        /etc/systemd/system/caddy-sync-reconcile.service || return 1
    check no_direct_cert_notification file_lacks_literal lsyncd-sync-failure-notify.sh \
        /usr/local/libexec/check-certificate-expiry.sh || return 1
    check no_direct_health_notification file_lacks_literal lsyncd-sync-failure-notify.sh \
        /usr/local/libexec/validate-sync-health.sh || return 1
    check no_direct_reconcile_notification file_lacks_literal lsyncd-sync-failure-notify.sh \
        /usr/local/libexec/reconcile-release.sh || return 1
}
apply() {
    local action32_archive_sha256=$1

    install -d -o root -g root -m 0700 "$capture_directory" || return 1
    validate_payload "$archive_path" "$action32_archive_sha256" || return 1
    continuity || return 1
    verify_artifacts baseline || return 1
    capture_semantic_state || return 1
    capture_journal_cursor || return 1
    record_backup || return 1
    mutation_started=true
    run_captured stop_reconcile_path systemctl stop caddy-sync-reconcile.path || return 1
    run_captured stop_lsyncd systemctl stop caddy-lsyncd.service || return 1
    check outbound_unchanged_while_stopped semantic_state_unchanged \
        outbound_stopped /var/lib/caddy-sync/outbound "$before_outbound" || return 1
    check incoming_unchanged_while_stopped semantic_state_unchanged \
        incoming_stopped /var/lib/caddy-sync/incoming "$before_incoming" || return 1
    check quarantine_unchanged_while_stopped semantic_state_unchanged \
        quarantine_stopped /var/lib/caddy-sync/quarantine "$before_quarantine" || return 1
    install_candidates || return 1
    run_captured systemd_verify systemd-analyze verify \
        /etc/systemd/system/caddy-cert-expiry.service \
        /etc/systemd/system/caddy-lsyncd.service \
        /etc/systemd/system/caddy-sync-failure@.service \
        /etc/systemd/system/caddy-sync-health.service \
        /etc/systemd/system/caddy-sync-health.timer \
        /etc/systemd/system/caddy-sync-reconcile.service || return 1
    run_captured daemon_reload systemctl daemon-reload || return 1
    run_captured start_lsyncd systemctl start caddy-lsyncd.service || return 1
    run_captured lsyncd_stability wait_for_lsyncd_stability || return 1
    run_captured start_reconcile_path systemctl start caddy-sync-reconcile.path || return 1
    run_captured restart_cert_timer systemctl restart caddy-cert-expiry.timer || return 1
    run_captured restart_health_timer systemctl restart caddy-sync-health.timer || return 1
    run_captured certificate_worker systemctl start caddy-cert-expiry.service || return 1
    run_captured health_worker systemctl start caddy-sync-health.service || return 1
    check no_finalized_candidate_after no_finalized_candidate || return 1
    run_captured reconcile_noop systemctl start caddy-sync-reconcile.service || return 1
    check release_unchanged test "$(readlink -f /etc/caddy/current)" = "$before_release" || return 1
    run_captured post_cursor_journal journalctl \
        -u caddy-lsyncd.service -u caddy-sync-reconcile.service \
        -u caddy-sync-health.service -u caddy-cert-expiry.service \
        --after-cursor "$journal_cursor" --no-pager --no-hostname -o short-iso || return 1
    check post_cursor_clean post_cursor_clean || return 1
    check quarantine_unchanged_after semantic_state_unchanged \
        quarantine_after /var/lib/caddy-sync/quarantine "$before_quarantine" || return 1
    target_contract || return 1
    printf 'committed\n' >"$backup_directory/transaction.complete"
    chmod 0600 "$backup_directory/transaction.complete" || return 1
    transaction_complete=true
    rm -f -- "$archive_path"
    archive_path=
    rm -rf -- "$stage_directory"
    stage_directory=
    printf '%s_%s_apply_complete=true\n' "$prefix" "$node_token"
}
rollback() {
    install -d -o root -g root -m 0700 "$capture_directory" || return 1
    if [[ -e "$backup_directory" || -L "$backup_directory" ]]; then
        restore_backup || return 1
    else
        continuity || return 1
    fi
    if [[ -n "$archive_path" && "$archive_path" == /tmp/caddy-action32-payload-*.tar ]]; then
        rm -f -- "$archive_path"
        archive_path=
    fi
    printf '%s_%s_rollback_complete=true\n' "$prefix" "$node_token"
}
rollback_on_error() {
    local action32_status=$?

    trap - EXIT INT TERM
    [[ -z "$stage_directory" || ! -d "$stage_directory" ]] || rm -rf -- "$stage_directory"
    if [[ -n "$archive_path" && "$archive_path" == /tmp/caddy-action32-payload-*.tar ]]; then
        rm -f -- "$archive_path"
    fi
    if [[ "$transaction_complete" = true || "$mutation_started" = false ]]; then
        exit "$action32_status"
    fi
    printf '%s_%s_rollback_started=true\n' "$prefix" "$node_token" >&2
    if restore_backup; then
        printf '%s_%s_rollback_complete=true\n' "$prefix" "$node_token" >&2
        exit "$action32_status"
    fi
    printf '%s_%s_manual_intervention_required=true\n' "$prefix" "$node_token" >&2
    exit 125
}
verify_current() {
    install -d -o root -g root -m 0700 "$capture_directory" || return 1
    stage_directory=$(mktemp -d /run/caddy-runtime-action32.verify.XXXXXX) || return 1
    install -d -m 0700 "$stage_directory/Caddy/manifests" || return 1
    install -m 0600 "$backup_directory/manifest.source" \
        "$stage_directory/$manifest_relative" || return 1
    check transaction_committed test -f "$backup_directory/transaction.complete" || return 1
    target_contract || return 1
    rm -rf -- "$stage_directory"
    stage_directory=
    printf '%s_%s_verify_current_complete=true\n' "$prefix" "$node_token"
}
validate_payload_mode() {
    local action32_archive_sha256=$1

    capture_directory=$(mktemp -d /tmp/caddy-action32-validation.XXXXXX) || return 1
    trap 'rm -rf -- "${capture_directory:-}" "${stage_directory:-}"' EXIT INT TERM
    validate_payload "$archive_path" "$action32_archive_sha256" || return 1
    printf '%s_%s_validate_payload_complete=true\n' "$prefix" "$node_token"
}

mode=${1:-}
configure_role "${2:-}" || exit 64
case "$mode" in
    --validate-payload)
        [[ $# -eq 4 ]] || exit 64
        archive_path=$3
        validate_payload_mode "$4"
        ;;
    --apply)
        [[ $# -eq 4 && $3 == /tmp/caddy-action32-payload-*.tar ]] || exit 64
        archive_path=$3
        trap rollback_on_error EXIT INT TERM
        apply "$4"
        trap - EXIT INT TERM
        ;;
    --rollback)
        [[ $# -eq 3 && $3 == /tmp/caddy-action32-payload-*.tar ]] || exit 64
        archive_path=$3
        rollback
        ;;
    --verify-current)
        [[ $# -eq 2 ]] || exit 64
        verify_current
        ;;
    *) exit 64 ;;
esac
