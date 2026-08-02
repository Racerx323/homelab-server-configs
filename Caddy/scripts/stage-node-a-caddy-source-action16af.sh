#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly stage=/var/tmp/caddy-source-node-a-action16af
readonly certificate_stage=/var/tmp/caddy-cert-node-a-action16ae
readonly baseline=/var/backups/caddy-ha/predeploy-node-a-20260728T184626Z
readonly lighttpd_live=/etc/lighttpd
readonly lighttpd_candidate=/var/tmp/caddy-ha-lighttpd-node-a-action16ab
readonly sysctl_target=/etc/sysctl.d/70-caddy-ha.conf

readonly live_tree_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_tree_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly keepalived_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly sysctl_target_sha256=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8

readonly expected_files=(
    Caddy/configs/caddy/Caddyfile
    Caddy/configs/caddy/conf.d/00-health.caddy
    Caddy/configs/caddy/conf.d/10-pihole-admin.caddy
    Caddy/configs/caddy/conf.d/90-default-deny.caddy
    Caddy/manifests/dependencies.yaml
    Caddy/manifests/deployment.yaml
    Caddy/manifests/dns-records.yaml
    Caddy/scripts/install-caddy-ha.sh
    Caddy/scripts/render-node-config.sh
    Caddy/templates/caddy-ha.env.in
    Caddy/templates/keepalived-caddy-ha.conf.in
    Caddy/templates/lsyncd-caddy.lua.in
)

readonly expected_checksums=(
    'a41c7816e927c16278fab018675a3f2db5b2aae89dd5b181f1ecb06ec9beb86e  Caddy/configs/caddy/Caddyfile'
    '05fa1d2875ee0639601447ccd31284d3df55fc8d5e8cedef4a291c61d44f4b27  Caddy/configs/caddy/conf.d/00-health.caddy'
    '5621134920da9dde97122fe9968a2debdd0c980ac0e432323fb46e0c1139798c  Caddy/configs/caddy/conf.d/10-pihole-admin.caddy'
    '9ce8430d11882f4e2008ff27f4f4a2fcad568f81081629289f64ad2450316b27  Caddy/configs/caddy/conf.d/90-default-deny.caddy'
    '0a9c6632171c7490b030f9e4ebc2a122342c0eb8c08f95db0becf09a3f965696  Caddy/manifests/dependencies.yaml'
    'ee58ae3d2af19c6b5fd45b8c87d9c4866450d1a2d737c277c26442db36ebcfd0  Caddy/manifests/deployment.yaml'
    '809c3734dccafc743ced9db81c03db94d1bf9f6918de68b6cc38383a204ebf22  Caddy/manifests/dns-records.yaml'
    '851e93e7b32b907374dfedab8c91867b74fda50243b10f9859128c24f6149ab7  Caddy/scripts/install-caddy-ha.sh'
    'd7fa1c57a4d74edd966b78cf66d79e534f49c09a7265c2ad326f00018fa4c1c2  Caddy/scripts/render-node-config.sh'
    'bbd5ff898e49b70e4d3dbac247c5ea11b762035404f5b58e2928d3dd5dc03679  Caddy/templates/caddy-ha.env.in'
    'ebc60650edd4cb384000604b402ce1e99153b50d505c7e13289b6b33d7abdd09  Caddy/templates/keepalived-caddy-ha.conf.in'
    '5091566ae9f8165d502305ce08dad75cf1c78b417eca3dbd1dca8efa7eff105a  Caddy/templates/lsyncd-caddy.lua.in'
)

package_inventory() {
    dpkg-query -W \
        -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' |
        sort
}

protected_service_state() {
    local service

    for service in \
        lighttpd.service keepalived.service ssh.service unbound.service \
        pihole-FTL.service munin-node.service caddy.service \
        caddy-api.service lsyncd.service uuidd.service uuidd.socket; do
        printf '### %s\n' "$service"
        systemctl show "$service" --no-pager \
            -p ActiveState -p SubState -p MainPID -p NRestarts
        printf 'unit_file_state=%s\n' \
            "$(systemctl is-enabled "$service" 2>/dev/null || true)"
    done
}

group_names() {
    id -nG "$1" |
        tr ' ' '\n' |
        sed '/^$/d' |
        sort
}

group_members() {
    getent group "$1" |
        cut -d: -f4 |
        tr ',' '\n' |
        sed '/^$/d' |
        sort
}

identity_state() {
    id caddy
    id caddy-sync
    id keepalived_script
    passwd --status caddy-sync
    passwd --status keepalived_script
    getent group caddy-tls
    stat -c '%n %U:%G:%a' \
        /etc/caddy/releases \
        /var/lib/caddy-sync \
        /var/lib/caddy-sync/outbound \
        /var/lib/caddy-sync/incoming \
        /var/lib/caddy-sync/quarantine \
        /var/lib/caddy-sync/.ssh
}

tree_hash() {
    local root=$1

    (
        cd "$root"
        find . -type f -print0 |
            sort -z |
            xargs -0 sha256sum
    ) | sha256sum | awk '{ print $1 }'
}

listener_snapshot() {
    ss -H -lntup | sort
}

certificate_stage_state() {
    stat -c '%n|%U:%G:%a:%s:%Y:%i' \
        "$certificate_stage" \
        "$certificate_stage/certificate-manifest.json" \
        "$certificate_stage/fullchain.pem" \
        "$certificate_stage/intermediates.pem" \
        "$certificate_stage/leaf.pem" \
        "$certificate_stage/privkey.pem"
    sha256sum \
        "$certificate_stage/certificate-manifest.json" \
        "$certificate_stage/fullchain.pem" \
        "$certificate_stage/intermediates.pem" \
        "$certificate_stage/leaf.pem" \
        "$certificate_stage/privkey.pem"
}

protected_state_matches() {
    [[ "$(package_inventory)" == "$inventory_before" ]] &&
        [[ "$(identity_state)" == "$identities_before" ]] &&
        [[ "$(protected_service_state)" == "$services_before" ]] &&
        [[ "$(listener_snapshot)" == "$listeners_before" ]] &&
        [[ "$(certificate_stage_state)" == "$certificate_before" ]] &&
        [[ "$(tree_hash "$lighttpd_live")" == "$live_tree_sha256" ]] &&
        [[ "$(tree_hash "$lighttpd_candidate")" == "$candidate_tree_sha256" ]] &&
        [[ "$(
            sha256sum -- \
                "$lighttpd_live/lighttpd.conf" \
                "$lighttpd_live/conf-enabled/external.conf" \
                "$lighttpd_candidate/lighttpd.conf" \
                /etc/keepalived/keepalived.conf \
                "$sysctl_target"
        )" == "$protected_hashes_before" ]] &&
        [[ "$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind)" == 1 ]] &&
        [[ "$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind)" == 1 ]] &&
        [[ ! -e /etc/caddy/releases/bootstrap &&
            ! -L /etc/caddy/releases/bootstrap ]] &&
        [[ ! -e /etc/caddy/current && ! -L /etc/caddy/current ]] &&
        [[ ! -e /etc/default/caddy-ha && ! -L /etc/default/caddy-ha ]] &&
        [[ -z "$(dpkg --audit)" ]]
}

stage_attempted=false
transaction_complete=false
rollback() {
    local original_rc=$?
    local rollback_failed=false

    trap - EXIT
    if [[ "$transaction_complete" == true ]]; then
        exit "$original_rc"
    fi

    set +e
    printf 'source_transfer_action16af_rollback_started=true\n' >&2
    if [[ "$stage_attempted" == true ]]; then
        rm -rf --one-file-system -- "$stage" || rollback_failed=true
    fi
    [[ ! -e "$stage" && ! -L "$stage" ]] || rollback_failed=true
    if [[ -n "${inventory_before:-}" ]]; then
        protected_state_matches || rollback_failed=true
    fi

    if [[ "$rollback_failed" == true ]]; then
        printf 'source_transfer_action16af_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 97
    fi
    printf 'source_transfer_action16af_rollback_complete=true\n' >&2
    exit "$original_rc"
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$stage" == /var/tmp/caddy-source-node-a-action16af ]]
    [[ "${#expected_files[@]}" -eq 12 ]]
    [[ "${#expected_checksums[@]}" -eq 12 ]]
    [[ "$live_tree_sha256" == b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92 ]]
    [[ "$candidate_tree_sha256" == 6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13 ]]
    printf 'action_16af_caddy_source_stage_self_test_complete=true\n'
    exit 0
elif (($#)); then
    printf 'Usage: %s [--self-test]\n' "${0##*/}" >&2
    exit 2
fi

[[ "$(id -u)" -eq 0 ]]
[[ "$(hostname)" == j1-svpihole0 ]]
grep -Fq '10.1.0.53/22' < <(ip -o -4 address show dev eth0)
[[ "$(dpkg --print-architecture)" == arm64 ]]
[[ -d "$baseline" && ! -L "$baseline" ]]
(
    cd "$baseline"
    sha256sum --check --status configuration.tar.sha256
    grep -Fxq 'backup_complete=true' backup-manifest.txt
)

[[ ! -e "$stage" && ! -L "$stage" ]]
[[ ! -e /etc/caddy/releases/bootstrap &&
    ! -L /etc/caddy/releases/bootstrap ]]
[[ ! -e /etc/caddy/current && ! -L /etc/caddy/current ]]
[[ ! -e /etc/default/caddy-ha && ! -L /etc/default/caddy-ha ]]
[[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]]

[[ -d "$certificate_stage" && ! -L "$certificate_stage" ]]
[[ "$(stat -c '%U:%G:%a' "$certificate_stage")" == root:caddy-tls:750 ]]
mapfile -t certificate_files < <(
    find "$certificate_stage" -mindepth 1 -maxdepth 1 -printf '%f\n' |
        sort
)
expected_certificate_files=(
    certificate-manifest.json
    fullchain.pem
    intermediates.pem
    leaf.pem
    privkey.pem
)
[[ "${certificate_files[*]}" == "${expected_certificate_files[*]}" ]]
if find "$certificate_stage" -type l -print -quit | grep -q .; then
    exit 1
fi
for public_file in \
    certificate-manifest.json fullchain.pem intermediates.pem leaf.pem; do
    [[ "$(stat -c '%U:%G:%a' "$certificate_stage/$public_file")" == root:caddy-tls:644 ]]
done
[[ "$(stat -c '%U:%G:%a' "$certificate_stage/privkey.pem")" == root:caddy-tls:640 ]]
[[ "$(sha256sum "$certificate_stage/leaf.pem" | awk '{ print $1 }')" == 4d0eb710b9920f2017ff2ac84f80ae5784deaad4ace7b4f4dafb9537347ef319 ]]
[[ "$(sha256sum "$certificate_stage/intermediates.pem" |
    awk '{ print $1 }')" == 6802a694f52e6c9c9f6ea7f960a815e50b600a1592bbd325bcaf42dee8e6e50d ]]
[[ "$(sha256sum "$certificate_stage/fullchain.pem" | awk '{ print $1 }')" == d8d850a9e8ce026939ce4505fda50ab2578d3b0fe55580fbcf24f6004ec7aa83 ]]
[[ "$(sha256sum "$certificate_stage/certificate-manifest.json" |
    awk '{ print $1 }')" == 0a910e43586e42110247d13bd148272a61717699379019b22ef25ed60d7e39df ]]

[[ "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' caddy)" == 'ii :2.11.4:arm64' ]]
[[ "$(id -u caddy)" -eq 995 ]]
[[ "$(id -g caddy)" -eq 992 ]]
[[ "$(group_names caddy)" == $'caddy\ncaddy-tls\nwww-data' ]]
[[ "$(id -u caddy-sync)" -eq 994 ]]
[[ "$(id -g caddy-sync)" -eq 990 ]]
[[ "$(group_names caddy-sync)" == $'caddy-sync\ncaddy-tls' ]]
[[ "$(id -u keepalived_script)" -eq 993 ]]
[[ "$(id -g keepalived_script)" -eq 989 ]]
[[ "$(group_names keepalived_script)" == $'caddy-tls\nkeepalived_script' ]]
[[ "$(getent group caddy-tls | cut -d: -f3)" -eq 991 ]]
[[ "$(group_members caddy-tls)" == $'caddy\ncaddy-sync\nkeepalived_script' ]]
for unit in \
    caddy.service caddy-api.service lsyncd.service uuidd.service uuidd.socket; do
    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
done
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
done
if pgrep -x caddy >/dev/null ||
    pgrep -x lsyncd >/dev/null ||
    pgrep -x uuidd >/dev/null; then
    printf 'Unexpected protected process before source transfer.\n' >&2
    exit 1
fi
[[ "$(tree_hash "$lighttpd_live")" == "$live_tree_sha256" ]]
[[ "$(tree_hash "$lighttpd_candidate")" == "$candidate_tree_sha256" ]]
[[ "$(sha256sum /etc/keepalived/keepalived.conf | awk '{ print $1 }')" == "$keepalived_main_sha256" ]]
[[ "$(sha256sum "$sysctl_target" | awk '{ print $1 }')" == "$sysctl_target_sha256" ]]
[[ "$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind)" == 1 ]]
[[ "$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind)" == 1 ]]

inventory_before=$(package_inventory)
identities_before=$(identity_state)
services_before=$(protected_service_state)
listeners_before=$(listener_snapshot)
certificate_before=$(certificate_stage_state)
protected_hashes_before=$(
    sha256sum -- \
        "$lighttpd_live/lighttpd.conf" \
        "$lighttpd_live/conf-enabled/external.conf" \
        "$lighttpd_candidate/lighttpd.conf" \
        /etc/keepalived/keepalived.conf \
        "$sysctl_target"
)
[[ -z "$(dpkg --audit)" ]]

trap rollback EXIT
stage_attempted=true
install -d -o root -g root -m 0750 -- "$stage"
tar --no-same-owner --no-same-permissions -xf - -C "$stage"

mapfile -t actual_files < <(
    find "$stage" -type f -printf '%P\n' |
        sort
)
[[ "${actual_files[*]}" == "${expected_files[*]}" ]]
if find "$stage" -type l -print -quit | grep -q .; then
    printf 'source_stage_contains_symlink=true\n' >&2
    exit 1
fi

chown -R root:root -- "$stage"
find "$stage" -type d -exec chmod 0750 '{}' +
find "$stage" -type f -exec chmod 0640 '{}' +
chmod 0750 -- \
    "$stage/Caddy/scripts/install-caddy-ha.sh" \
    "$stage/Caddy/scripts/render-node-config.sh"

for checksum in "${expected_checksums[@]}"; do
    expected_hash=${checksum%% *}
    relative_path=${checksum#*  }
    [[ "$(sha256sum "$stage/$relative_path" | awk '{ print $1 }')" == "$expected_hash" ]]
done

[[ "$(stat -c '%U:%G:%a' "$stage")" == root:root:750 ]]
[[ "$(stat -c '%U:%G:%a' "$stage/Caddy/scripts/install-caddy-ha.sh")" == root:root:750 ]]
[[ "$(stat -c '%U:%G:%a' "$stage/Caddy/scripts/render-node-config.sh")" == root:root:750 ]]
for relative_path in "${expected_files[@]}"; do
    case "$relative_path" in
        Caddy/scripts/install-caddy-ha.sh | \
            Caddy/scripts/render-node-config.sh) ;;
        *)
            [[ "$(stat -c '%U:%G:%a' "$stage/$relative_path")" == root:root:640 ]]
            ;;
    esac
done

protected_state_matches

transaction_complete=true
trap - EXIT
printf 'remote_source_stage=%s\n' "$stage"
printf 'remote_source_stage_mode=root:root:750\n'
printf 'source_file_count=12\n'
printf 'source_bundle_hashes_valid=true\n'
printf 'certificate_stage_unchanged=true\n'
printf 'protected_state_unchanged=true\n'
printf 'source_transfer_action16af_complete=true\n'
