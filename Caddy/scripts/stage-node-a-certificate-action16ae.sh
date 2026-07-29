#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly stage=/var/tmp/caddy-cert-node-a-action16ae
readonly baseline=/var/backups/caddy-ha/predeploy-node-a-20260728T184626Z
readonly lighttpd_live=/etc/lighttpd
readonly lighttpd_candidate=/var/tmp/caddy-ha-lighttpd-node-a-action16ab
readonly sysctl_target=/etc/sysctl.d/70-caddy-ha.conf

readonly leaf_sha256=4d0eb710b9920f2017ff2ac84f80ae5784deaad4ace7b4f4dafb9537347ef319
readonly intermediates_sha256=6802a694f52e6c9c9f6ea7f960a815e50b600a1592bbd325bcaf42dee8e6e50d
readonly fullchain_sha256=d8d850a9e8ce026939ce4505fda50ab2578d3b0fe55580fbcf24f6004ec7aa83
readonly manifest_sha256=0a910e43586e42110247d13bd148272a61717699379019b22ef25ed60d7e39df
readonly expected_not_after='Jan 19 23:59:59 2027 GMT'
readonly live_main_sha256=568507d5604cb2794106de3de29d1603c3f12c9045bf7fc1ad4342592a1395c1
readonly live_external_sha256=6da587363054a4db69fb742d23bddde06aec866e11fb7a91bff1a8d75a713f7a
readonly live_tree_sha256=b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92
readonly candidate_main_sha256=c48b3f0a8c256185233b302952f0b4ee138e745fb17ede92ae3f16d7fa4a6a99
readonly candidate_tree_sha256=6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13
readonly keepalived_main_sha256=cf4858888ae80772f1a50dda7c0ea120ff083eafae33a0ad4ca291d44755c1e2
readonly sysctl_target_sha256=d7036eaead2f5ef20afa8bdf20a7a353ee700532a095822320a1b9efad4846e8

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

assert_masked_inactive() {
    local unit=$1

    [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" == inactive ]]
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == masked ]]
}

protected_state_matches() {
    [[ "$(package_inventory)" == "$inventory_before" ]] &&
        [[ "$(identity_state)" == "$identities_before" ]] &&
        [[ "$(protected_service_state)" == "$services_before" ]] &&
        [[ "$(listener_snapshot)" == "$listeners_before" ]] &&
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
    printf 'certificate_transfer_action16ae_rollback_started=true\n' >&2
    if [[ "$stage_attempted" == true ]]; then
        rm -rf --one-file-system -- "$stage" || rollback_failed=true
    fi
    [[ ! -e "$stage" && ! -L "$stage" ]] || rollback_failed=true
    if [[ -n "${inventory_before:-}" ]]; then
        protected_state_matches || rollback_failed=true
    fi

    if [[ "$rollback_failed" == true ]]; then
        printf 'certificate_transfer_action16ae_rollback_complete=false\n' >&2
        printf 'manual_intervention_required=true\n' >&2
        exit 97
    fi
    printf 'certificate_transfer_action16ae_rollback_complete=true\n' >&2
    exit "$original_rc"
}

if [[ "${1:-}" == --self-test ]]; then
    [[ "$stage" == /var/tmp/caddy-cert-node-a-action16ae ]]
    [[ "$leaf_sha256" == 4d0eb710b9920f2017ff2ac84f80ae5784deaad4ace7b4f4dafb9537347ef319 ]]
    [[ "$intermediates_sha256" == 6802a694f52e6c9c9f6ea7f960a815e50b600a1592bbd325bcaf42dee8e6e50d ]]
    [[ "$fullchain_sha256" == d8d850a9e8ce026939ce4505fda50ab2578d3b0fe55580fbcf24f6004ec7aa83 ]]
    [[ "$manifest_sha256" == 0a910e43586e42110247d13bd148272a61717699379019b22ef25ed60d7e39df ]]
    [[ "$live_tree_sha256" == b15ff54d2e91bbecd1d21b762818599d732f01b66ee5d1ef7c24147c72e2cb92 ]]
    [[ "$candidate_tree_sha256" == 6e178911d34a783e16fca001f7c91dc29098598043bd4c4c4c19af59e81a6c13 ]]
    printf 'action_16ae_certificate_stage_self_test_complete=true\n'
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

[[ "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}:${Architecture}' caddy)" == 'ii :2.11.4:arm64' ]]
[[ "$(dpkg-query -W -f='${db:Status-Abbrev}:${Version}' lsyncd)" == 'ii :2.2.3-1' ]]
[[ "$(dpkg-query -W -f='${db:Status-Abbrev}' uuid-runtime)" == 'ii ' ]]

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

[[ -d "$lighttpd_live" && ! -L "$lighttpd_live" ]]
[[ -d "$lighttpd_candidate" && ! -L "$lighttpd_candidate" ]]
[[ "$(stat -c '%U:%G:%a' "$lighttpd_candidate")" == root:root:750 ]]
[[ "$(sha256sum "$lighttpd_live/lighttpd.conf" | awk '{ print $1 }')" == "$live_main_sha256" ]]
[[ "$(sha256sum "$lighttpd_live/conf-enabled/external.conf" |
    awk '{ print $1 }')" == "$live_external_sha256" ]]
[[ "$(sha256sum "$lighttpd_candidate/lighttpd.conf" |
    awk '{ print $1 }')" == "$candidate_main_sha256" ]]
[[ "$(tree_hash "$lighttpd_live")" == "$live_tree_sha256" ]]
[[ "$(tree_hash "$lighttpd_candidate")" == "$candidate_tree_sha256" ]]
[[ "$(sha256sum /etc/keepalived/keepalived.conf | awk '{ print $1 }')" == "$keepalived_main_sha256" ]]
[[ "$(sha256sum "$sysctl_target" | awk '{ print $1 }')" == "$sysctl_target_sha256" ]]

[[ "$(/usr/sbin/sysctl -n net.ipv4.ip_nonlocal_bind)" == 1 ]]
[[ "$(/usr/sbin/sysctl -n net.ipv6.ip_nonlocal_bind)" == 1 ]]
for unit in \
    caddy.service caddy-api.service lsyncd.service uuidd.service uuidd.socket; do
    assert_masked_inactive "$unit"
done
for service in lighttpd keepalived ssh unbound pihole-FTL munin-node; do
    systemctl is-active --quiet "$service"
done
[[ "$(systemctl is-enabled lighttpd)" == enabled ]]
[[ "$(systemctl is-enabled keepalived)" == enabled ]]
if pgrep -x caddy >/dev/null ||
    pgrep -x lsyncd >/dev/null ||
    pgrep -x uuidd >/dev/null; then
    printf 'Unexpected protected process before certificate transfer.\n' >&2
    exit 1
fi

inventory_before=$(package_inventory)
identities_before=$(identity_state)
services_before=$(protected_service_state)
listeners_before=$(listener_snapshot)
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
install -d -o root -g caddy-tls -m 0750 -- "$stage"
tar --no-same-owner --no-same-permissions -xf - -C "$stage"

expected_files=(
    certificate-manifest.json
    fullchain.pem
    intermediates.pem
    leaf.pem
    privkey.pem
)
mapfile -t actual_files < <(
    find "$stage" -mindepth 1 -maxdepth 1 -printf '%f\n' |
        sort
)
[[ "${actual_files[*]}" == "${expected_files[*]}" ]]
if find "$stage" -type l -print -quit | grep -q .; then
    printf 'remote_certificate_stage_contains_symlink=true\n' >&2
    exit 1
fi

chown root:caddy-tls -- \
    "$stage/certificate-manifest.json" \
    "$stage/fullchain.pem" \
    "$stage/intermediates.pem" \
    "$stage/leaf.pem" \
    "$stage/privkey.pem"
chmod 0644 -- \
    "$stage/certificate-manifest.json" \
    "$stage/fullchain.pem" \
    "$stage/intermediates.pem" \
    "$stage/leaf.pem"
chmod 0640 -- "$stage/privkey.pem"

[[ "$(stat -c '%U:%G:%a' "$stage")" == root:caddy-tls:750 ]]
for public_file in \
    certificate-manifest.json fullchain.pem intermediates.pem leaf.pem; do
    [[ "$(stat -c '%U:%G:%a' "$stage/$public_file")" == root:caddy-tls:644 ]]
done
[[ "$(stat -c '%U:%G:%a' "$stage/privkey.pem")" == root:caddy-tls:640 ]]

[[ "$(sha256sum "$stage/leaf.pem" | awk '{ print $1 }')" == "$leaf_sha256" ]]
[[ "$(sha256sum "$stage/intermediates.pem" | awk '{ print $1 }')" == "$intermediates_sha256" ]]
[[ "$(sha256sum "$stage/fullchain.pem" | awk '{ print $1 }')" == "$fullchain_sha256" ]]
[[ "$(sha256sum "$stage/certificate-manifest.json" | awk '{ print $1 }')" == "$manifest_sha256" ]]

openssl x509 -in "$stage/leaf.pem" -noout >/dev/null
openssl x509 -in "$stage/leaf.pem" -checkend 2592000 -noout >/dev/null
[[ "$(openssl x509 -in "$stage/leaf.pem" -noout -enddate |
    cut -d= -f2-)" == "$expected_not_after" ]]
openssl x509 -in "$stage/leaf.pem" -noout -ext subjectAltName |
    grep -Fq 'DNS:*.local.theama.co'
openssl pkey -in "$stage/privkey.pem" -check -noout >/dev/null 2>&1
certificate_key_hash=$(
    openssl x509 -in "$stage/leaf.pem" -pubkey -noout |
        openssl pkey -pubin -outform DER 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
)
private_key_public_hash=$(
    openssl pkey -in "$stage/privkey.pem" -pubout -outform DER 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
)
[[ "$certificate_key_hash" == "$private_key_public_hash" ]]
cmp -s "$stage/fullchain.pem" \
    <(cat "$stage/leaf.pem" "$stage/intermediates.pem")
openssl verify \
    -purpose sslserver \
    -CApath /etc/ssl/certs \
    -untrusted "$stage/intermediates.pem" \
    "$stage/leaf.pem" >/dev/null

jq -e '
  keys == [
    "fingerprint_sha256",
    "fullchain_sha256",
    "issuer",
    "leaf_sha256",
    "not_after",
    "not_before",
    "public_key_sha256",
    "subject",
    "subject_alt_names"
  ] and
  .leaf_sha256 == "4d0eb710b9920f2017ff2ac84f80ae5784deaad4ace7b4f4dafb9537347ef319" and
  .fullchain_sha256 == "d8d850a9e8ce026939ce4505fda50ab2578d3b0fe55580fbcf24f6004ec7aa83" and
  (.subject_alt_names | contains("DNS:*.local.theama.co"))
' "$stage/certificate-manifest.json" >/dev/null

protected_state_matches

transaction_complete=true
trap - EXIT
printf 'remote_certificate_stage=%s\n' "$stage"
printf 'remote_certificate_stage_mode=root:caddy-tls:750\n'
printf 'certificate_leaf_sha256=%s\n' "$leaf_sha256"
printf 'certificate_intermediates_sha256=%s\n' "$intermediates_sha256"
printf 'certificate_fullchain_sha256=%s\n' "$fullchain_sha256"
printf 'certificate_manifest_sha256=%s\n' "$manifest_sha256"
printf 'certificate_not_after=%s\n' "$expected_not_after"
printf 'certificate_wildcard_san_present=true\n'
printf 'certificate_key_match=true\n'
printf 'certificate_chain_complete=true\n'
printf 'protected_state_unchanged=true\n'
printf 'certificate_transfer_action16ae_complete=true\n'
