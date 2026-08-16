#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s --node node-a|node-b [--root DIRECTORY]\n' "${0##*/}"
}

node_role=
root_prefix=/

while (($#)); do
    case "$1" in
        --node)
            node_role=${2:-}
            shift 2
            ;;
        --root)
            root_prefix=${2:-}
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! "$node_role" =~ ^node-[ab]$ || "$root_prefix" != /* ]]; then
    usage >&2
    exit 2
fi

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly script_directory caddy_root
readonly script_lifecycle=$caddy_root/manifests/script-lifecycle.tsv
readonly systemd_lifecycle=$caddy_root/manifests/systemd-lifecycle.tsv

root_path() {
    local validation_path=$1

    if [[ "$root_prefix" == / ]]; then
        printf '%s' "$validation_path"
    else
        printf '%s%s' "${root_prefix%/}" "$validation_path"
    fi
}

require_regular() {
    local validation_path=$1

    [[ -f "$(root_path "$validation_path")" && ! -L "$(root_path "$validation_path")" ]]
}

validate_registered() {
    local validation_registry=$1
    local validation_source
    local validation_lifecycle
    local validation_deployable
    local validation_target
    local validation_mode
    local validation_authority
    local validation_installed
    local validation_normalized_mode

    while IFS=$'\t' read -r validation_source validation_lifecycle \
        validation_deployable validation_target validation_mode \
        validation_authority; do
        [[ -n "$validation_source" && "$validation_source" != \#* ]] || continue
        : "$validation_authority"
        [[ "$validation_lifecycle" == production-current &&
            "$validation_deployable" == yes ]] || continue
        validation_installed=$(root_path "$validation_target")
        [[ -f "$validation_installed" && ! -L "$validation_installed" ]] || return 1
        cmp --silent "$caddy_root/${validation_source#Caddy/}" \
            "$validation_installed" || return 1
        validation_normalized_mode=${validation_mode#0}
        [[ "$(stat -c '%a' "$validation_installed")" == "$validation_normalized_mode" ]] || return 1
        if [[ "$root_prefix" == / ]]; then
            [[ "$(stat -c '%U:%G' "$validation_installed")" == root:root ]] || return 1
        fi
    done <"$validation_registry"
}

case "$node_role" in
    node-a)
        expected_fqdn=pihole0.local.theama.co
        expected_ipv4=10.1.0.53
        expected_ipv6=fd36:5aa8:6971:1::53
        lsyncd_source=$caddy_root/configs/lsyncd/caddy-node-a.lua
        ;;
    node-b)
        expected_fqdn=pihole00.local.theama.co
        expected_ipv4=10.1.0.54
        expected_ipv6=fd36:5aa8:6971:1::54
        lsyncd_source=$caddy_root/configs/lsyncd/caddy-node-b.lua
        ;;
esac
readonly expected_fqdn expected_ipv4 expected_ipv6 lsyncd_source

for validation_required in \
    /etc/default/caddy-ha \
    /etc/caddy/current \
    /usr/local/share/caddy-ha/lighttpd-desired-state.conf \
    /etc/lsyncd/caddy.lua \
    /etc/sysctl.d/70-caddy-ha.conf \
    /etc/tmpfiles.d/caddy-ha.conf; do
    if [[ ! -e "$(root_path "$validation_required")" &&
    ! -L "$(root_path "$validation_required")" ]]; then
        printf 'Missing installed path: %s\n' "$validation_required" >&2
        exit 1
    fi
done

current_link=$(root_path /etc/caddy/current)
if [[ -L "$current_link" ]]; then
    current_target=$(readlink "$current_link")
    if [[ "$current_target" == /* ]]; then
        current_release=$(root_path "$current_target")
    else
        current_release=$(dirname "$current_link")/$current_target
    fi
else
    current_release=$current_link
fi
readonly current_link current_release
[[ -f "$current_release/Caddyfile" && ! -L "$current_release/Caddyfile" ]] || exit 1
[[ -d "$current_release/conf.d" && ! -L "$current_release/conf.d" ]] || exit 1

expected_environment=$(mktemp /tmp/caddy-ha-environment-v2.XXXXXX)
readonly expected_environment
trap 'rm -f -- "$expected_environment"' EXIT
printf 'NODE_FQDN=%s\nNODE_IPV4=%s\nNODE_IPV6=%s\n' \
    "$expected_fqdn" "$expected_ipv4" "$expected_ipv6" >"$expected_environment"
cmp --silent "$expected_environment" "$(root_path /etc/default/caddy-ha)"

cmp --silent "$lsyncd_source" "$(root_path /etc/lsyncd/caddy.lua)"
cmp --silent "$caddy_root/configs/lighttpd/desired-state.conf" \
    "$(root_path /usr/local/share/caddy-ha/lighttpd-desired-state.conf)"
cmp --silent "$caddy_root/configs/sysctl/70-caddy-ha.conf" \
    "$(root_path /etc/sysctl.d/70-caddy-ha.conf)"
cmp --silent "$caddy_root/configs/tmpfiles.d/caddy-ha.conf" \
    "$(root_path /etc/tmpfiles.d/caddy-ha.conf)"
validate_registered "$script_lifecycle"
validate_registered "$systemd_lifecycle"

if grep -R -I -nE '@[A-Z0-9_]+@' \
    "$(root_path /etc/default/caddy-ha)" \
    "$(root_path /etc/lsyncd/caddy.lua)" \
    "$current_release/Caddyfile" \
    "$current_release/conf.d"; then
    printf 'Unresolved template placeholders found.\n' >&2
    exit 1
fi

if [[ "$root_prefix" == / ]]; then
    [[ "$(stat -c '%U:%G:%a' /etc/default/caddy-ha)" == root:caddy-tls:640 ]]
    set -a
    # shellcheck disable=SC1091
    source /etc/default/caddy-ha
    set +a
    caddy validate \
        --config "$current_release/Caddyfile" \
        --adapter caddyfile >/dev/null
fi

printf 'Validated current Caddy HA artifacts for %s under %s\n' \
    "$node_role" "$root_prefix"
