#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly stage=/var/tmp/caddy-systemd-node-a-action16am
readonly retained_sync_stage=/var/tmp/caddy-sync-ssh-node-a-action16aj-e
readonly libexec=/usr/local/libexec
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
    [[ "${#expected_libexec_files[@]}" -eq 3 ]]
    [[ "$stage_digest_sha256" =~ ^[0-9a-f]{64}$ ]]
    [[ "$expected_node_a_fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{43}$ ]]
    printf 'action_16am_systemd_stage_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

tree_hash() {
    local root=$1

    (
        cd "$root" || exit 1
        find . -type f -print0 |
            sort -z |
            xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

package_inventory_hash() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' \
        2>/dev/null |
        sort |
        sha256sum |
        awk '{ print $1 }'
}

effective_unit_hash() {
    systemctl cat "$1" 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
}

validate_live_state() {
    local service target
    local -a actual_libexec_files

    [[ "$(id -u 2>/dev/null || true)" == 0 ]]
    [[ "$(hostname 2>/dev/null || true)" == j1-svpihole0 ]]
    grep -Fq '10.1.0.53/22' \
        < <(ip -o -4 address show dev eth0 2>/dev/null)
    [[ "$(dpkg --print-architecture 2>/dev/null || true)" == arm64 ]]
    [[ "$(package_inventory_hash)" == "$package_inventory_sha256" ]]
    [[ -z "$(dpkg --audit 2>/dev/null || true)" ]]

    for target in "${live_targets[@]}"; do
        [[ ! -e "$target" && ! -L "$target" ]]
    done
    [[ ! -e /etc/systemd/system/caddy.service.d &&
        ! -L /etc/systemd/system/caddy.service.d ]]
    [[ ! -e /etc/systemd/system/lighttpd.service.d &&
        ! -L /etc/systemd/system/lighttpd.service.d ]]

    [[ "$(systemctl is-active caddy.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled caddy.service 2>/dev/null || true)" == masked ]]
    [[ "$(systemctl is-active caddy-api.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled caddy-api.service 2>/dev/null || true)" == masked ]]
    [[ "$(systemctl is-active lsyncd.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled lsyncd.service 2>/dev/null || true)" == masked ]]
    [[ "$(systemctl is-active uuidd.service 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled uuidd.service 2>/dev/null || true)" == masked ]]
    [[ "$(systemctl is-active uuidd.socket 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled uuidd.socket 2>/dev/null || true)" == masked ]]
    for service in lighttpd keepalived ssh; do
        [[ "$(systemctl is-active "$service" 2>/dev/null || true)" == active ]]
        [[ "$(systemctl is-enabled "$service" 2>/dev/null || true)" == enabled ]]
    done
    for service in unbound pihole-FTL munin-node; do
        [[ "$(systemctl is-active "$service" 2>/dev/null || true)" == active ]]
    done
    [[ "$(pgrep -xc caddy 2>/dev/null || true)" == 0 ]]
    [[ "$(pgrep -xc lsyncd 2>/dev/null || true)" == 0 ]]

    [[ "$(sha256sum /etc/default/caddy-ha 2>/dev/null |
        awk '{ print $1 }' || true)" == "$environment_sha256" ]]
    [[ "$(readlink /etc/caddy/current 2>/dev/null || true)" == /etc/caddy/releases/bootstrap ]]
    [[ "$(readlink -e /etc/caddy/current 2>/dev/null || true)" == /etc/caddy/releases/bootstrap ]]
    [[ "$(tree_hash /etc/lighttpd 2>/dev/null || true)" == "$live_lighttpd_sha256" ]]
    [[ "$(tree_hash /var/tmp/caddy-ha-lighttpd-node-a-action16ab \
        2>/dev/null || true)" == "$candidate_lighttpd_sha256" ]]
    [[ "$(sha256sum /etc/keepalived/keepalived.conf 2>/dev/null |
        awk '{ print $1 }' || true)" == "$keepalived_sha256" ]]
    [[ "$(sha256sum /etc/sysctl.d/70-caddy-ha.conf 2>/dev/null |
        awk '{ print $1 }' || true)" == "$sysctl_sha256" ]]
    [[ "$(sysctl -n net.ipv4.ip_nonlocal_bind 2>/dev/null || true)" == 1 ]]
    [[ "$(sysctl -n net.ipv6.ip_nonlocal_bind 2>/dev/null || true)" == 1 ]]
    [[ "$(effective_unit_hash caddy.service)" == "$effective_caddy_sha256" ]]
    [[ "$(effective_unit_hash lighttpd.service)" == "$effective_lighttpd_sha256" ]]
    [[ ! -e /etc/lsyncd/caddy.lua && ! -L /etc/lsyncd/caddy.lua ]]
    [[ ! -e /etc/keepalived/conf.d/caddy-ha.conf &&
        ! -L /etc/keepalived/conf.d/caddy-ha.conf ]]

    [[ "$(stat -c '%U:%G:%a' "$retained_sync_stage" \
        2>/dev/null || true)" == root:root:750 ]]
    [[ "$(ssh-keygen -lf /var/lib/caddy-sync/.ssh/id_ed25519.pub \
        -E sha256 2>/dev/null | awk '{ print $2 }' || true)" == "$expected_node_a_fingerprint" ]]
    [[ "$(wc -l </var/lib/caddy-sync/.ssh/authorized_keys \
        2>/dev/null || true)" == 1 ]]
    mapfile -t actual_libexec_files < <(
        find "$libexec" -mindepth 1 -maxdepth 1 -type f \
            -printf '%f\n' 2>/dev/null |
            sort
    )
    [[ "${actual_libexec_files[*]}" == "${expected_libexec_files[*]}" ]]
    [[ "$(sha256sum "$libexec/caddy-sync-rsync-receiver" 2>/dev/null |
        awk '{ print $1 }' || true)" == "$receiver_sha256" ]]
    [[ "$(sha256sum "$libexec/setup-sync-ssh.sh" 2>/dev/null |
        awk '{ print $1 }' || true)" == "$setup_helper_sha256" ]]
    [[ "$(sha256sum "$libexec/validate-sync-ssh.sh" 2>/dev/null |
        awk '{ print $1 }' || true)" == "$validator_sha256" ]]
}

protected_state() {
    local service

    printf 'package_inventory=%s\n' "$(package_inventory_hash)"
    printf 'environment=%s\n' \
        "$(sha256sum /etc/default/caddy-ha | awk '{ print $1 }')"
    printf 'lighttpd=%s\n' "$(tree_hash /etc/lighttpd)"
    printf 'candidate=%s\n' \
        "$(tree_hash /var/tmp/caddy-ha-lighttpd-node-a-action16ab)"
    printf 'keepalived=%s\n' \
        "$(sha256sum /etc/keepalived/keepalived.conf | awk '{ print $1 }')"
    printf 'sysctl=%s\n' \
        "$(sha256sum /etc/sysctl.d/70-caddy-ha.conf | awk '{ print $1 }')"
    printf 'caddy_unit=%s\n' "$(effective_unit_hash caddy.service)"
    printf 'lighttpd_unit=%s\n' "$(effective_unit_hash lighttpd.service)"
    printf 'libexec=%s\n' \
        "$(find "$libexec" -mindepth 1 -maxdepth 1 -type f \
            -printf '%f|%U:%G:%m:%s:%Y:%i\n' | sort)"
    for service in \
        lighttpd.service keepalived.service ssh.service unbound.service \
        pihole-FTL.service munin-node.service caddy.service \
        caddy-api.service lsyncd.service uuidd.service uuidd.socket; do
        printf 'service=%s|' "$service"
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts \
            2>/dev/null |
            tr '\n' ' '
        printf '|enabled=%s\n' \
            "$(systemctl is-enabled "$service" 2>/dev/null || true)"
    done
    ss -H -lntup 2>/dev/null | sort
}

fail_before_write() {
    local label=$1

    printf '%s=false\n' "$label"
    printf 'first_failure=%s\n' "$label"
    printf 'action_16am_preflight_valid=false\n'
    exit 1
}

require_preflight_command() {
    local label=$1
    shift

    if ! "$@" >/dev/null 2>&1; then
        fail_before_write "$label"
    fi
    printf '%s=true\n' "$label"
}

require_preflight_absent() {
    local label=$1
    local target=$2

    if [[ -e "$target" || -L "$target" ]]; then
        fail_before_write "$label"
    fi
    printf '%s=true\n' "$label"
}

printf 'action_16am_remote_reached=true\n'
require_preflight_command preflight_live_state validate_live_state
require_preflight_absent preflight_stage_absent "$stage"
protected_before=$(protected_state)
readonly protected_before
if [[ -z "$protected_before" ]]; then
    fail_before_write preflight_protected_state_capture
fi
printf 'preflight_protected_state_capture=true\n'
printf 'action_16am_preflight_valid=true\n'

success=false
stage_mutation_started=false
rollback() {
    local original_rc=$?
    local rollback_valid=true

    if [[ "$success" == true ]]; then
        return
    fi

    set +e
    if [[ "$stage_mutation_started" == true ]]; then
        rm -rf -- "$stage"
        if [[ -e "$stage" || -L "$stage" ]]; then
            rollback_valid=false
        fi
        validate_live_state || rollback_valid=false
        [[ "$(protected_state)" == "$protected_before" ]] ||
            rollback_valid=false
        printf 'action_16am_stage_rollback_complete=%s\n' \
            "$rollback_valid" >&2
        if [[ "$rollback_valid" != true ]]; then
            printf 'manual_intervention_required=true\n' >&2
            exit 97
        fi
    fi
    exit "$original_rc"
}
trap rollback EXIT

stage_fail() {
    local label=$1

    printf '%s=false\n' "$label"
    printf 'first_failure=%s\n' "$label"
    exit 1
}

require_stage_command() {
    local label=$1
    shift

    if ! "$@" >/dev/null 2>&1; then
        stage_fail "$label"
    fi
    printf '%s=true\n' "$label"
}

require_stage_equal() {
    local label=$1
    local observed=$2
    local expected=$3

    if [[ "$observed" != "$expected" ]]; then
        stage_fail "$label"
    fi
    printf '%s=true\n' "$label"
}

stage_mutation_started=true
printf 'action_16am_mutation_started=true\n'
require_stage_command stage_create \
    install -d -o root -g root -m 0750 "$stage"
require_stage_command stage_extract \
    tar --extract --file - --directory "$stage" \
    --no-same-owner --no-same-permissions
require_stage_command stage_owner \
    chown -R root:root "$stage"
require_stage_command stage_directory_modes \
    find "$stage" -type d -exec chmod 0750 {} +
require_stage_command stage_unit_modes \
    find "$stage/systemd" -type f -exec chmod 0644 {} +
require_stage_command stage_script_modes \
    find "$stage/scripts" -type f -exec chmod 0755 {} +

mapfile -t actual_files < <(
    find "$stage" -type f -printf '%P\n' 2>/dev/null |
        sort
)
mapfile -t actual_directories < <(
    find "$stage" -mindepth 1 -type d -printf '%P\n' 2>/dev/null |
        sort
)
require_stage_equal stage_file_set \
    "${actual_files[*]}" "${expected_files[*]}"
require_stage_equal stage_directory_set \
    "${actual_directories[*]}" "${expected_directories[*]}"
require_stage_equal stage_file_count "${#actual_files[@]}" 16
require_stage_equal stage_directory_count "${#actual_directories[@]}" 4
require_stage_equal stage_symlink_count \
    "$(find "$stage" -type l -print 2>/dev/null | wc -l)" 0
require_stage_equal stage_root_meta \
    "$(stat -c '%U:%G:%a' "$stage" 2>/dev/null || true)" root:root:750

for checksum in "${expected_checksums[@]}"; do
    expected_hash=${checksum%% *}
    relative_path=${checksum#*  }
    label=${relative_path//[^A-Za-z0-9]/_}
    require_stage_equal "hash_$label" \
        "$(sha256sum "$stage/$relative_path" 2>/dev/null |
            awk '{ print $1 }')" \
        "$expected_hash"
    require_stage_equal "owner_$label" \
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
    require_stage_equal "mode_$label" \
        "$(stat -c '%a' "$stage/$relative_path" \
            2>/dev/null || true)" \
        "$expected_mode"
done

for script in "$stage"/scripts/*.sh; do
    require_stage_command "syntax_${script##*/}" bash -n "$script"
done

stage_digest=$(
    cd "$stage" || exit 1
    printf '%s\n' "${expected_files[@]}" |
        sort |
        xargs sha256sum |
        sha256sum |
        awk '{ print $1 }'
)
require_stage_equal stage_digest "$stage_digest" "$stage_digest_sha256"
require_stage_command live_state_with_stage validate_live_state
require_stage_equal protected_state_unchanged \
    "$(protected_state)" "$protected_before"

printf 'first_failure=none\n'
printf 'stage_path=%s\n' "$stage"
printf 'stage_owner_mode=%s\n' "$(stat -c '%U:%G:%a' "$stage")"
printf 'stage_file_count=16\n'
printf 'stage_digest=%s\n' "$stage_digest"
printf 'stage_retained=true\n'
printf 'systemd_daemon_reload_performed=false\n'
printf 'service_mutations=false\n'
printf 'action_16am_systemd_stage_complete=true\n'
success=true
