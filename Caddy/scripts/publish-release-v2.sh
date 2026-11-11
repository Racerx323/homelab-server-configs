#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly dns_ipv4_cidr=10.1.0.55/22
readonly dns_ipv6_cidr=fd36:5aa8:6971:1::55/128
readonly caddy_ipv4_cidr=10.1.0.56/22
readonly caddy_ipv6_cidr=fd36:5aa8:6971:1::56/128
readonly ipv4_object=/org/keepalived/Vrrp1/Instance/eth0/100/IPv4
readonly ipv6_object=/org/keepalived/Vrrp1/Instance/eth0/101/IPv6

usage() {
    printf 'Usage: %s --source DIRECTORY --node-role node-a|node-b [--emergency] [--prepare-only] | --expose REVISION --manifest-sha256 HASH --node-role node-a\n' \
        "${0##*/}" >&2
}

require_check() {
    local check_label=$1

    shift
    if "$@"; then
        return 0
    fi
    printf 'caddy_sync_publish_v2_check_%s=false expected=command_success observed=command_failure command=' "$check_label" >&2
    printf '%q ' "$@" >&2
    printf '\n' >&2
    return 1
}

address_count() {
    local publish_family=$1
    local publish_cidr=$2

    ip -o "-$publish_family" address show dev eth0 |
        awk -v expected="$publish_cidr" \
            '$4 == expected { count++ } END { print count + 0 }'
}

coupled_master() {
    [[ "$(timeout 3 busctl get-property org.keepalived.Vrrp1 \
        "$ipv4_object" org.keepalived.Vrrp1.Instance State)" = '(us) 2 "Master"' ]] || return 1
    [[ "$(timeout 3 busctl get-property org.keepalived.Vrrp1 \
        "$ipv6_object" org.keepalived.Vrrp1.Instance State)" = '(us) 2 "Master"' ]] || return 1
    [[ "$(address_count 4 "$dns_ipv4_cidr")" -eq 1 ]] || return 1
    [[ "$(address_count 6 "$dns_ipv6_cidr")" -eq 1 ]] || return 1
    [[ "$(address_count 4 "$caddy_ipv4_cidr")" -eq 1 ]] || return 1
    [[ "$(address_count 6 "$caddy_ipv6_cidr")" -eq 1 ]]
}

source_dir=
node_role=
emergency=false
prepare_only=false
expose_revision=
expose_manifest=

while (($#)); do
    case "$1" in
        --source)
            source_dir=${2:-}
            shift 2
            ;;
        --node-role)
            node_role=${2:-}
            shift 2
            ;;
        --prepare-only)
            prepare_only=true
            shift
            ;;
        --expose)
            expose_revision=${2:-}
            shift 2
            ;;
        --manifest-sha256)
            expose_manifest=${2:-}
            shift 2
            ;;
        --emergency)
            emergency=true
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if [[ ! "$node_role" =~ ^node-[ab]$ ||
    (-z "$expose_revision" && (! -d "$source_dir" || -L "$source_dir")) ]]; then
    usage
    exit 2
fi

if [[ -r /etc/default/caddy-ha ]]; then
    set -a
    # shellcheck disable=SC1091
    source /etc/default/caddy-ha
    set +a
fi

if [[ "$node_role" == node-b ]]; then
    if [[ "$emergency" != true ]]; then
        printf 'Node B publishing requires --emergency.\n' >&2
        exit 1
    fi
    if ! coupled_master; then
        printf 'Node B may publish only while coupled PIHOLE_IPV4 and PIHOLE_IPV6 are MASTER with all shared VIPs.\n' >&2
        exit 1
    fi
fi

# Prepared releases are outside lsyncd's outbound tree. Only root can expose
# them, after the coordinator has checked the selected primary and its routes.
readonly prepared_root=/var/lib/caddy-sync/prepared
readonly outbound_root=/var/lib/caddy-sync/outbound
if [[ "$prepare_only" = true || -n "$expose_revision" ]]; then
    require_check primary_role test "$node_role" = node-a
    require_check normal_publication test "$emergency" = false
    require_check prepared_root_not_symlink test ! -L "$prepared_root"
    install -d -o root -g root -m 0700 "$prepared_root"
    exec 9>"$prepared_root/.publisher.lock"
    flock -n 9 || {
        printf 'publisher_lock expected=available observed=busy\n' >&2
        exit 1
    }
fi
if [[ -n "$expose_revision" ]]; then
    [[ -z "$source_dir" && "$prepare_only" = false &&
        "$expose_revision" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ &&
        "$expose_manifest" =~ ^[0-9a-f]{64}$ ]] || exit 64
    expose_source=$prepared_root/$expose_revision
    require_check prepared_regular test -d "$expose_source"
    require_check prepared_not_symlink test ! -L "$expose_source"
    require_check prepared_symlinks_absent test -z "$(find "$expose_source" -type l -print -quit)"
    require_check prepared_special_files_absent test -z "$(find "$expose_source" ! -type f ! -type d -print -quit)"
    require_check prepared_hardlinks_absent test -z "$(find "$expose_source" -type f -links +1 -print -quit)"
    require_check prepared_manifest test "$(sha256sum "$expose_source/manifest.sha256" | awk '{print $1}')" = "$expose_manifest"
    require_check primary_selected test "$(readlink -f /etc/caddy/current)" = "/etc/caddy/releases/$expose_revision"
    require_check prepared_identity test "$(jq -r .revision "$expose_source/release-manifest.json")" = "$expose_revision"
    require_check prepared_completion_absent test ! -e "$expose_source/.complete"
    # Recheck the sealed payload, not only the manifest file's identity.
    # shellcheck disable=SC2016
    require_check prepared_integrity bash -c 'cd "$1" && sha256sum --strict --check manifest.sha256 >/dev/null' _ "$expose_source"
    require_check prepared_payload_matches_active diff -qr --exclude=.complete "$expose_source" /etc/caddy/current
    require_check outbound_root_not_symlink test ! -L "$outbound_root"
    install -d -o caddy-sync -g caddy-sync -m 0750 "$outbound_root"
    require_check exposure_absent test ! -e "$outbound_root/$expose_revision"
    require_check exposure_not_symlink test ! -L "$outbound_root/$expose_revision"
    mv -T -- "$expose_source" "$outbound_root/$expose_revision"
    printf 'Exposed primary-accepted protocol-v2 release %s.\n' "$expose_revision"
    exit 0
fi
[[ -z "$expose_manifest" ]] || exit 64

for required_path in Caddyfile conf.d tls/leaf.pem tls/intermediates.pem \
    tls/fullchain.pem tls/privkey.pem tls/certificate-manifest.json; do
    if [[ ! -e "$source_dir/$required_path" || -L "$source_dir/$required_path" ]]; then
        printf 'Incomplete release: missing %s\n' "$required_path" >&2
        exit 1
    fi
done
for required_path in leaf.pem intermediates.pem fullchain.pem privkey.pem certificate-manifest.json; do
    if [[ ! -s "$source_dir/tls/$required_path" || ! -f "$source_dir/tls/$required_path" ]]; then
        printf 'Incomplete release: invalid tls/%s\n' "$required_path" >&2
        exit 1
    fi
done

require_check source_symlinks_absent \
    test -z "$(find "$source_dir" -type l -print -quit)"
require_check source_hardlinks_absent \
    test -z "$(find "$source_dir" -type f -links +1 -print -quit)"
require_check source_nested_control_files_absent \
    test -z "$(find "$source_dir" -mindepth 2 \
        \( -name .finalize-request -o -name .complete \
        -o -name .complete.pending \) -print -quit)"
require_check source_pending_marker_absent \
    test ! -e "$source_dir/.complete.pending"
require_check source_caddy_configuration_valid \
    env CADDY_CONFIG_ROOT="$source_dir" \
    caddy validate --config "$source_dir/Caddyfile" \
    --adapter caddyfile >/dev/null
require_check source_certificate_parse \
    openssl x509 -in "$source_dir/tls/fullchain.pem" -noout
require_check source_monitored_certificate_matches \
    cmp -s <(openssl x509 -in "$source_dir/tls/leaf.pem" -outform DER) \
    <(openssl x509 -in "$source_dir/tls/fullchain.pem" -outform DER)
require_check source_monitored_certificate_lifetime \
    openssl x509 -in "$source_dir/tls/leaf.pem" -checkend 2592000 -noout
require_check source_private_key_parse \
    openssl pkey -in "$source_dir/tls/privkey.pem" -noout

revision="$(date -u +%Y%m%dT%H%M%SZ)-$(uuidgen)"
readonly revision
parent_revision=
if [[ -r /etc/caddy/current/release-manifest.json ]]; then
    parent_revision=$(
        jq -r '.revision // ""' /etc/caddy/current/release-manifest.json
    )
fi
readonly parent_revision

publication_root=$outbound_root
if [[ "$prepare_only" = true ]]; then
    publication_root=$prepared_root
else
    require_check outbound_root_not_symlink test ! -L "$outbound_root"
    install -d -o caddy-sync -g caddy-sync -m 0750 "$outbound_root"
fi
readonly release_dir="$publication_root/$revision"
staging_dir=$(mktemp -d "$publication_root/.publish-v2.XXXXXX")
readonly staging_dir

cleanup_staging() {
    # shellcheck disable=SC2317
    if [[ -d "$staging_dir" ]]; then
        rm -rf -- "$staging_dir"
    fi
}
trap cleanup_staging EXIT

require_check release_absent_before test ! -e "$release_dir"
cp -a -- "$source_dir/." "$staging_dir/"
rm -f -- \
    "$staging_dir/.complete" \
    "$staging_dir/.complete.pending" \
    "$staging_dir/.finalize-request" \
    "$staging_dir/manifest.sha256" \
    "$staging_dir/release-manifest.json"

jq -n \
    --arg release_revision "$revision" \
    --arg release_parent "$parent_revision" \
    --arg release_source "$node_role" \
    --arg release_created_at "$(date --iso-8601=seconds)" \
    '{
        revision: $release_revision,
        parent_revision: $release_parent,
        source_node: $release_source,
        created_at: $release_created_at
    }' >"$staging_dir/release-manifest.json"

(
    cd "$staging_dir"
    find . -type f \
        ! -path ./manifest.sha256 \
        ! -path ./.finalize-request \
        ! -path ./.complete \
        ! -path ./.complete.pending \
        -print0 |
        LC_ALL=C sort -z |
        xargs -0 sha256sum
) >"$staging_dir/manifest.sha256"

: >"$staging_dir/.finalize-request"
chown -R caddy-sync:caddy-sync "$staging_dir"
find "$staging_dir" -type d -exec chmod 0550 {} +
find "$staging_dir" -type f -exec chmod 0440 {} +
require_check staged_directories_locked \
    test -z "$(find "$staging_dir" -type d ! -perm 0550 -print -quit)"
require_check staged_files_locked \
    test -z "$(find "$staging_dir" -type f ! -perm 0440 -print -quit)"
mv -- "$staging_dir" "$release_dir"
trap - EXIT
require_check release_regular_directory test -d "$release_dir"
require_check release_not_symlink test ! -L "$release_dir"
require_check release_request_regular \
    test -f "$release_dir/.finalize-request"
require_check release_completion_absent test ! -e "$release_dir/.complete"

if [[ "$prepare_only" = true ]]; then
    printf 'Prepared protocol-v2 release %s without transport exposure.\n' "$revision"
else
    printf 'Published protocol-v2 release %s for receiver validation.\n' "$revision"
fi
