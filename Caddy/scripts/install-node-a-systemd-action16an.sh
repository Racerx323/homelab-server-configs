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
readonly lsyncd_config=/etc/lsyncd/caddy.lua
readonly keepalived_fragment=/etc/keepalived/conf.d/caddy-ha.conf
readonly environment_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8
readonly live_lighttpd_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_lighttpd_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly keepalived_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly sysctl_sha256=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8
readonly package_inventory_sha256=6377ab1492b2da992dce53199e359c5a2faf3563abd8bf766e6d6967fa07da5c
readonly stage_digest_sha256=305120fdb6b9c970a2aab12aa21ed88c06c3f77b9f63654cd0487fc2656e6e15
readonly receiver_sha256=65d872f63a7a7e9dc108111057164c1785a77bf00429672452cfd3f9f3fe7134
readonly setup_helper_sha256=d1d1e4fd0fd3787e43d7801babfbcdec20015b6517282cdba67904aa1b554140
readonly validator_sha256=85df8a934c8dd9561a6f567f42549ebc01ee2605ca630150265004b9ec108072
readonly expected_node_a_fingerprint='SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC/nb56VfAQpK4Y8V0'

readonly -a relative_files=(
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
readonly -a sources=(
    "$stage/scripts/check-certificate-expiry.sh"
    "$stage/scripts/lsyncd-sync-failure-notify.sh"
    "$stage/scripts/reconcile-release.sh"
    "$stage/scripts/validate-sync-health.sh"
    "$stage/systemd/caddy-cert-expiry.service"
    "$stage/systemd/caddy-cert-expiry.timer"
    "$stage/systemd/caddy-lsyncd.service"
    "$stage/systemd/caddy-sync-failure@.service"
    "$stage/systemd/caddy-sync-health.service"
    "$stage/systemd/caddy-sync-health.timer"
    "$stage/systemd/caddy-sync-reconcile.path"
    "$stage/systemd/caddy-sync-reconcile.service"
    "$stage/systemd/caddy-validate-reload.path"
    "$stage/systemd/caddy-validate-reload.service"
    "$stage/systemd/caddy.service.d/override.conf"
    "$stage/systemd/lighttpd.service.d/caddy-ha.conf"
)
readonly -a targets=(
    /usr/local/libexec/check-certificate-expiry.sh
    /usr/local/libexec/lsyncd-sync-failure-notify.sh
    /usr/local/libexec/reconcile-release.sh
    /usr/local/libexec/validate-sync-health.sh
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
readonly -a custom_units=(
    caddy-cert-expiry.service
    caddy-cert-expiry.timer
    caddy-lsyncd.service
    caddy-sync-failure@action16an-validation.service
    caddy-sync-health.service
    caddy-sync-health.timer
    caddy-sync-reconcile.path
    caddy-sync-reconcile.service
    caddy-validate-reload.path
    caddy-validate-reload.service
)
readonly -a disabled_units=(
    caddy-cert-expiry.timer
    caddy-lsyncd.service
    caddy-sync-health.timer
    caddy-sync-reconcile.path
    caddy-validate-reload.path
)
readonly -a static_units=(
    caddy-cert-expiry.service
    caddy-sync-failure@action16an-validation.service
    caddy-sync-health.service
    caddy-sync-reconcile.service
    caddy-validate-reload.service
)

if [[ "${1:-}" == --self-test && $# -eq 1 ]]; then
    [[ "${#relative_files[@]}" -eq 16 ]]
    [[ "${#expected_checksums[@]}" -eq 16 ]]
    [[ "${#sources[@]}" -eq 16 ]]
    [[ "${#targets[@]}" -eq 16 ]]
    [[ "${#custom_units[@]}" -eq 10 ]]
    [[ "${#disabled_units[@]}" -eq 5 ]]
    [[ "${#static_units[@]}" -eq 5 ]]
    [[ "$stage_digest_sha256" =~ ^[0-9a-f]{64}$ ]]
    printf 'action_16an_systemd_installer_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

tree_hash() {
    local root=$1

    (
        cd "$root"
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

stage_digest() {
    (
        cd "$stage"
        printf '%s\n' "${relative_files[@]}" |
            sort |
            xargs sha256sum |
            sha256sum |
            awk '{ print $1 }'
    )
}

service_state() {
    local unit

    for unit in \
        caddy.service caddy-api.service lsyncd.service \
        uuidd.service uuidd.socket lighttpd.service keepalived.service \
        ssh.service unbound.service pihole-FTL.service munin-node.service; do
        printf '%s:%s:%s\n' \
            "$unit" \
            "$(unit_property "$unit" ActiveState)" \
            "$(unit_property "$unit" UnitFileState)"
    done
}

listener_state() {
    {
        ss -H -ltnp 2>/dev/null |
            awk '$4 ~ /:80$|:443$|:8080$|:2019$/ { print }'
        ss -H -lunp 2>/dev/null |
            awk '$4 ~ /:443$/ { print }'
    } | sort
}

protected_state() {
    printf 'packages=%s\n' "$(
        dpkg-query -W \
            -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
            sort |
            sha256sum |
            awk '{ print $1 }'
    )"
    printf 'services=%s\n' "$(service_state | sha256sum | awk '{ print $1 }')"
    printf 'listeners=%s\n' "$(listener_state | sha256sum | awk '{ print $1 }')"
    printf 'environment=%s\n' "$(sha256sum /etc/default/caddy-ha | awk '{ print $1 }')"
    printf 'release=%s\n' "$(readlink -e /etc/caddy/current)"
    printf 'lighttpd=%s\n' "$(tree_hash /etc/lighttpd)"
    printf 'candidate=%s\n' \
        "$(tree_hash /var/tmp/caddy-ha-lighttpd-node-a-action16ab)"
    printf 'keepalived=%s\n' \
        "$(sha256sum /etc/keepalived/keepalived.conf | awk '{ print $1 }')"
    printf 'sysctl=%s\n' \
        "$(sha256sum /etc/sysctl.d/70-caddy-ha.conf | awk '{ print $1 }')"
    printf 'sync-stage=%s\n' "$(tree_hash "$retained_sync_stage")"
    printf 'sync-stage-meta=%s\n' "$(stat -c '%U:%G:%a' "$retained_sync_stage")"
    printf 'sync-fingerprint=%s\n' "$(
        ssh-keygen -lf /var/lib/caddy-sync/.ssh/id_ed25519.pub \
            -E sha256 |
            awk '{ print $2 }'
    )"
    printf 'receiver=%s\n' \
        "$(sha256sum "$libexec/caddy-sync-rsync-receiver" | awk '{ print $1 }')"
    printf 'setup=%s\n' \
        "$(sha256sum "$libexec/setup-sync-ssh.sh" | awk '{ print $1 }')"
    printf 'validator=%s\n' \
        "$(sha256sum "$libexec/validate-sync-ssh.sh" | awk '{ print $1 }')"
}

assert_preflight() {
    local actual_files actual_directories checksum target unit

    [[ "$(id -u)" -eq 0 ]]
    [[ "$(hostname)" == j1-svpihole0 ]]
    ip -o -4 address show dev eth0 | grep -Fq '10.1.0.53/22'
    [[ "$(dpkg --print-architecture)" == arm64 ]]
    [[ "$(
        dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' \
            caddy
    )" == 'ii :2.11.4:arm64' ]]
    [[ "$(
        dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' \
            lsyncd
    )" == 'ii :2.2.3-1:arm64' ]]
    [[ "$(
        dpkg-query -W \
            -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
            sort |
            sha256sum |
            awk '{ print $1 }'
    )" == "$package_inventory_sha256" ]]
    [[ -z "$(dpkg --audit)" ]]

    [[ -d "$stage" && ! -L "$stage" ]]
    [[ "$(stat -c '%U:%G:%a' "$stage")" == root:root:750 ]]
    mapfile -t actual_files < <(
        find "$stage" -mindepth 1 -type f -printf '%P\n' | sort
    )
    [[ "${actual_files[*]}" == "${relative_files[*]}" ]]
    mapfile -t actual_directories < <(
        find "$stage" -mindepth 1 -type d -printf '%P\n' | sort
    )
    [[ "${actual_directories[*]}" == 'scripts systemd systemd/caddy.service.d systemd/lighttpd.service.d' ]]
    [[ "$(find "$stage" -type l -printf x | wc -c)" -eq 0 ]]
    (
        cd "$stage"
        printf '%s\n' "${expected_checksums[@]}" |
            sha256sum --check --status
    )
    [[ "$(stage_digest)" == "$stage_digest_sha256" ]]
    for checksum in "${expected_checksums[@]}"; do
        relative_path=${checksum#*  }
        case "$relative_path" in
            scripts/*)
                [[ "$(stat -c '%U:%G:%a' "$stage/$relative_path")" == root:root:755 ]]
                bash -n "$stage/$relative_path"
                ;;
            *)
                [[ "$(stat -c '%U:%G:%a' "$stage/$relative_path")" == root:root:644 ]]
                ;;
        esac
    done

    [[ ! -e /etc/systemd/system/caddy.service.d ]]
    [[ ! -L /etc/systemd/system/caddy.service.d ]]
    [[ ! -e /etc/systemd/system/lighttpd.service.d ]]
    [[ ! -L /etc/systemd/system/lighttpd.service.d ]]
    for target in "${targets[@]}"; do
        [[ ! -e "$target" && ! -L "$target" ]]
    done
    for unit in "${custom_units[@]}"; do
        [[ "$(unit_property "$unit" LoadState)" == not-found ]]
        [[ "$(unit_property "$unit" ActiveState)" == inactive ]]
        [[ -z "$(unit_property "$unit" UnitFileState)" ]]
    done

    for unit in \
        caddy.service caddy-api.service lsyncd.service \
        uuidd.service uuidd.socket; do
        [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
        [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
    done
    [[ "$(unit_property caddy-api.socket LoadState)" == not-found ]]
    [[ "$(unit_property caddy-api.socket ActiveState)" == inactive ]]
    [[ -z "$(unit_property caddy-api.socket UnitFileState)" ]]
    for unit in lighttpd.service keepalived.service ssh.service; do
        [[ "$(systemctl is-active "$unit")" == active ]]
        [[ "$(systemctl is-enabled "$unit")" == enabled ]]
    done
    for unit in unbound.service pihole-FTL.service munin-node.service; do
        [[ "$(systemctl is-active "$unit")" == active ]]
    done
    [[ "$(pgrep -xc caddy 2>/dev/null || true)" -eq 0 ]]
    [[ "$(pgrep -xc lsyncd 2>/dev/null || true)" -eq 0 ]]
    [[ -z "$(
        find /etc/systemd/system -type l -printf '%p -> %l\n' |
            grep -E \
                'caddy-(cert-expiry|lsyncd|sync-health|sync-reconcile|validate-reload)' ||
            true
    )" ]]

    [[ "$(sha256sum /etc/default/caddy-ha | awk '{ print $1 }')" == "$environment_sha256" ]]
    grep -Fxq 'NODE_ROLE=node-a' /etc/default/caddy-ha
    [[ "$(readlink -e /etc/caddy/current)" == /etc/caddy/releases/bootstrap ]]
    [[ "$(tree_hash /etc/lighttpd)" == "$live_lighttpd_sha256" ]]
    [[ "$(tree_hash /var/tmp/caddy-ha-lighttpd-node-a-action16ab)" == "$candidate_lighttpd_sha256" ]]
    [[ "$(sha256sum /etc/keepalived/keepalived.conf | awk '{ print $1 }')" == "$keepalived_sha256" ]]
    [[ "$(sha256sum /etc/sysctl.d/70-caddy-ha.conf | awk '{ print $1 }')" == "$sysctl_sha256" ]]
    [[ "$(sysctl -n net.ipv4.ip_nonlocal_bind)" == 1 ]]
    [[ "$(sysctl -n net.ipv6.ip_nonlocal_bind)" == 1 ]]
    [[ -d "$retained_sync_stage" && ! -L "$retained_sync_stage" ]]
    [[ "$(stat -c '%U:%G:%a' "$retained_sync_stage")" == root:root:750 ]]
    [[ "$(
        ssh-keygen -lf /var/lib/caddy-sync/.ssh/id_ed25519.pub \
            -E sha256 |
            awk '{ print $2 }'
    )" == "$expected_node_a_fingerprint" ]]
    [[ "$(sha256sum "$libexec/caddy-sync-rsync-receiver" | awk '{ print $1 }')" == "$receiver_sha256" ]]
    [[ "$(sha256sum "$libexec/setup-sync-ssh.sh" | awk '{ print $1 }')" == "$setup_helper_sha256" ]]
    [[ "$(sha256sum "$libexec/validate-sync-ssh.sh" | awk '{ print $1 }')" == "$validator_sha256" ]]
    [[ ! -e "$lsyncd_config" && ! -L "$lsyncd_config" ]]
    [[ ! -e "$keepalived_fragment" && ! -L "$keepalived_fragment" ]]
}

assert_postinstall() {
    local checksum expected_hash index target unit

    for index in "${!targets[@]}"; do
        target=${targets[$index]}
        checksum=${expected_checksums[$index]}
        expected_hash=${checksum%% *}
        [[ -f "$target" && ! -L "$target" ]]
        [[ "$(sha256sum "$target" | awk '{ print $1 }')" == "$expected_hash" ]]
        case "$target" in
            /usr/local/libexec/*)
                [[ "$(stat -c '%U:%G:%a' "$target")" == root:root:755 ]]
                ;;
            *)
                [[ "$(stat -c '%U:%G:%a' "$target")" == root:root:644 ]]
                ;;
        esac
    done
    [[ "$(stat -c '%U:%G:%a' /etc/systemd/system/caddy.service.d)" == root:root:755 ]]
    [[ "$(stat -c '%U:%G:%a' /etc/systemd/system/lighttpd.service.d)" == root:root:755 ]]

    systemd-analyze verify \
        /etc/systemd/system/caddy-cert-expiry.service \
        /etc/systemd/system/caddy-cert-expiry.timer \
        /etc/systemd/system/caddy-lsyncd.service \
        /etc/systemd/system/caddy-sync-failure@.service \
        /etc/systemd/system/caddy-sync-health.service \
        /etc/systemd/system/caddy-sync-health.timer \
        /etc/systemd/system/caddy-sync-reconcile.path \
        /etc/systemd/system/caddy-sync-reconcile.service \
        /etc/systemd/system/caddy-validate-reload.path \
        /etc/systemd/system/caddy-validate-reload.service

    for unit in "${custom_units[@]}"; do
        [[ "$(unit_property "$unit" LoadState)" == loaded ]]
        [[ "$(unit_property "$unit" ActiveState)" == inactive ]]
    done
    for unit in "${disabled_units[@]}"; do
        [[ "$(unit_property "$unit" UnitFileState)" == disabled ]]
    done
    for unit in "${static_units[@]}"; do
        [[ "$(unit_property "$unit" UnitFileState)" == static ]]
    done
    [[ "$(unit_property caddy.service DropInPaths)" == /etc/systemd/system/caddy.service.d/override.conf ]]
    [[ "$(unit_property lighttpd.service DropInPaths)" == /etc/systemd/system/lighttpd.service.d/caddy-ha.conf ]]
    grep -Fxq 'TimeoutStopSec=30s' \
        /etc/systemd/system/caddy.service.d/override.conf
    [[ -z "$(
        find /etc/systemd/system -type l -printf '%p -> %l\n' |
            grep -E \
                'caddy-(cert-expiry|lsyncd|sync-health|sync-reconcile|validate-reload)' ||
            true
    )" ]]
}

transaction_complete=false
mutation_started=false
pre_state=

rollback() {
    local exit_status=$?
    local rollback_failed=false
    local target

    if [[ "$transaction_complete" == true || "$mutation_started" == false ]]; then
        return
    fi

    trap - EXIT INT TERM HUP
    set +e
    printf 'action_16an_rollback_started=true\n' >&2
    for target in "${targets[@]}"; do
        rm -f -- "$target" || rollback_failed=true
    done
    rmdir -- /etc/systemd/system/caddy.service.d 2>/dev/null || {
        [[ ! -e /etc/systemd/system/caddy.service.d ]] ||
            rollback_failed=true
    }
    rmdir -- /etc/systemd/system/lighttpd.service.d 2>/dev/null || {
        [[ ! -e /etc/systemd/system/lighttpd.service.d ]] ||
            rollback_failed=true
    }
    systemctl daemon-reload || rollback_failed=true
    for target in "${targets[@]}"; do
        [[ ! -e "$target" && ! -L "$target" ]] || rollback_failed=true
    done
    for unit in "${custom_units[@]}"; do
        [[ "$(unit_property "$unit" LoadState)" == not-found ]] ||
            rollback_failed=true
        [[ "$(unit_property "$unit" ActiveState)" == inactive ]] ||
            rollback_failed=true
        [[ -z "$(unit_property "$unit" UnitFileState)" ]] ||
            rollback_failed=true
    done
    [[ "$(protected_state 2>/dev/null)" == "$pre_state" ]] ||
        rollback_failed=true
    [[ "$(stage_digest 2>/dev/null)" == "$stage_digest_sha256" ]] ||
        rollback_failed=true
    if [[ "$rollback_failed" == true ]]; then
        printf 'action_16an_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 97
    fi
    printf 'action_16an_rollback_complete=true\n' >&2
    exit "$exit_status"
}
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

printf 'action_16an_remote_reached=true\n'
assert_preflight
pre_state=$(protected_state)
printf 'action_16an_preflight_complete=true\n'

mutation_started=true
printf 'action_16an_mutation_started=true\n'
install -d -o root -g root -m 0755 \
    /etc/systemd/system/caddy.service.d \
    /etc/systemd/system/lighttpd.service.d
for index in "${!targets[@]}"; do
    case "${targets[$index]}" in
        /usr/local/libexec/*)
            install -o root -g root -m 0755 \
                "${sources[$index]}" "${targets[$index]}"
            ;;
        *)
            install -o root -g root -m 0644 \
                "${sources[$index]}" "${targets[$index]}"
            ;;
    esac
done
printf 'action_16an_files_installed=true\n'

systemctl daemon-reload
printf 'systemd_daemon_reload_performed=true\n'
assert_postinstall
printf 'action_16an_postinstall_systemd_valid=true\n'

[[ "$(protected_state)" == "$pre_state" ]]
[[ "$(stage_digest)" == "$stage_digest_sha256" ]]
printf 'action_16an_protected_state_unchanged=true\n'
printf 'stage_retained=true\n'
printf 'retained_sync_stage_preserved=true\n'
printf 'custom_units_enabled=false\n'
printf 'custom_units_active=false\n'
printf 'peer_connections=false\n'
printf 'installed_helper_execution=false\n'
printf 'service_mutations=false\n'
printf 'lsyncd_configuration_installed=false\n'
printf 'caddy_keepalived_fragment_installed=false\n'

transaction_complete=true
trap - EXIT INT TERM HUP
printf 'action_16an_systemd_install_complete=true\n'
