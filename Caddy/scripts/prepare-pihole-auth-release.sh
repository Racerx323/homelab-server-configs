#!/usr/bin/env bash
# Prepare and validate an unpublished candidate; never contact an HA node.
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly auth_caddy_root=${script_directory%/scripts}
[[ $# = 2 ]] || {
    printf 'Usage: %s EMPTY_PROTECTED_TMP_DIRECTORY TLS_DIRECTORY\n' "$0" >&2
    exit 64
}
readonly auth_output=$1
readonly auth_tls=$2
[[ "$auth_output" == /tmp/* && "$(realpath -e -- "$auth_output")" = "$auth_output" ]]
[[ -d "$auth_output" && ! -L "$auth_output" && "$(stat -c '%u:%a' "$auth_output")" = "$(id -u):700" ]]
[[ -z "$(find "$auth_output" -mindepth 1 -print -quit)" ]]
[[ -d "$auth_tls" && ! -L "$auth_tls" ]]
for auth_name in fullchain.pem privkey.pem; do
    [[ -f "$auth_tls/$auth_name" && ! -L "$auth_tls/$auth_name" && "$(stat -c '%h' "$auth_tls/$auth_name")" = 1 ]]
done
# Verify accepted non-secret sources before applying the exact proposed delta.
while IFS=$'\t' read -r auth_source auth_target auth_hash auth_payload auth_lifecycle; do
    [[ "$auth_source" != \#* && -n "$auth_source" ]] || continue
    [[ "$auth_lifecycle" = production-current && "$auth_payload" =~ ^[a-f0-9]{64}$ ]]
    [[ "$auth_source" = "Caddy/configs/caddy/$auth_target" && "$auth_target" != *..* && "$auth_target" != /* ]]
    [[ -f "$auth_caddy_root/../$auth_source" && ! -L "$auth_caddy_root/../$auth_source" ]]
    [[ "$(sha256sum "$auth_caddy_root/../$auth_source" | awk '{print $1}')" = "$auth_hash" ]]
    install -D -m 0600 "$auth_caddy_root/../$auth_source" "$auth_output/$auth_target"
done <"$auth_caddy_root/manifests/caddy-release-source.tsv"
readonly auth_fragment=$auth_output/conf.d/10-pihole-admin.caddy
[[ "$(grep -Fc 'fail_duration 30s' "$auth_fragment")" = 1 ]]
sed -i '/^[[:space:]]*fail_duration 30s$/c\			transport http {\n\t\t\t\tkeepalive off\n\t\t\t}' "$auth_fragment"
install -d -m 0700 "$auth_output/tls"
install -m 0600 "$auth_tls/fullchain.pem" "$auth_output/tls/fullchain.pem"
install -m 0600 "$auth_tls/privkey.pem" "$auth_output/tls/privkey.pem"
openssl x509 -in "$auth_output/tls/fullchain.pem" -noout >/dev/null
openssl pkey -in "$auth_output/tls/privkey.pem" -noout >/dev/null
[[ "$(caddy version)" = v2.11.4\ * ]]
for auth_node in a b; do
    if [[ "$auth_node" = a ]]; then
        export NODE_FQDN=pihole0.local.theama.co NODE_IPV4=10.1.0.53 NODE_IPV6=fd36:5aa8:6971:1::53
    else
        export NODE_FQDN=pihole00.local.theama.co NODE_IPV4=10.1.0.54 NODE_IPV6=fd36:5aa8:6971:1::54
    fi
    export CADDY_CONFIG_ROOT=$auth_output
    caddy adapt --validate --adapter caddyfile --config "$auth_output/Caddyfile" >/dev/null
    caddy validate --adapter caddyfile --config "$auth_output/Caddyfile" >/dev/null
done
printf 'prepared_release=%s\npublication=not-performed\n' "$auth_output"
