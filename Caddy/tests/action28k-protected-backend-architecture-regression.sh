#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly backend=$caddy_root/templates/pihole-admin-backend.Caddyfile.in
readonly frontend=$caddy_root/templates/pihole-admin-dns-owner.caddy.in
readonly service=$caddy_root/systemd/caddy-pihole-backend.service
readonly manifest=$caddy_root/manifests/pihole-admin-backend-action28k.yaml

check_architecture() {
    local action28k_architecture_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf 'action_28k_architecture_check_%s=true\n' "$action28k_architecture_label"
        return 0
    fi
    printf 'action_28k_architecture_check_%s=false\n' "$action28k_architecture_label" >&2
    return 1
}

exact_count() {
    local action28k_architecture_pattern=$1
    local action28k_architecture_file=$2

    awk -v wanted="$action28k_architecture_pattern" '
        $0 == wanted { count++ }
        END { exit count == 1 ? 0 : 1 }
    ' "$action28k_architecture_file"
}

reject_pattern() {
    local action28k_architecture_pattern=$1
    local action28k_architecture_file=$2

    if grep -Eq -- "$action28k_architecture_pattern" "$action28k_architecture_file"; then
        return 1
    fi
    return 0
}

command_rejected() {
    if "$@" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

check_architecture backend_regular test -f "$backend"
check_architecture frontend_regular test -f "$frontend"
check_architecture service_regular test -f "$service"
check_architecture manifest_regular test -f "$manifest"
check_architecture backend_ipv4_dns_vip exact_count \
    $'\tbind 10.1.0.55 fd36:5aa8:6971:1::55' "$backend"
check_architecture backend_no_wildcard reject_pattern \
    '^[[:space:]]*bind[[:space:]]+(0[.]0[.]0[.]0|::)([[:space:]]|$)' "$backend"
check_architecture backend_no_physical_ipv4 reject_pattern \
    '10[.]1[.]0[.](53|54)' "$backend"
check_architecture backend_loopback_upstream exact_count \
    $'\t\treverse_proxy 127.0.0.1:8080' "$backend"
check_architecture backend_mtls_mode exact_count \
    $'\t\t\tmode require_and_verify' "$backend"
check_architecture backend_client_ca exact_count \
    $'\t\t\t\tpem_file {$PIHOLE_BACKEND_CLIENT_CA_FILE}' "$backend"
check_architecture frontend_ipv4_dns_vip grep -Fq \
    'reverse_proxy https://10.1.0.55:8443 ' "$frontend"
check_architecture frontend_ipv6_dns_vip grep -Fq \
    'https://[fd36:5aa8:6971:1::55]:8443 {' "$frontend"
check_architecture frontend_deterministic_primary exact_count \
    $'\t\tlb_policy first' "$frontend"
check_architecture frontend_server_name exact_count \
    $'\t\t\ttls_server_name pihole-backend.local.theama.co' "$frontend"
check_architecture frontend_server_ca exact_count \
    $'\t\t\ttls_trust_pool file {$PIHOLE_BACKEND_SERVER_CA_FILE}' "$frontend"
check_architecture frontend_client_identity exact_count \
    $'\t\t\ttls_client_auth {$PIHOLE_BACKEND_CLIENT_CERT_FILE} {$PIHOLE_BACKEND_CLIENT_KEY_FILE}' \
    "$frontend"
check_architecture shared_route_remote exact_count \
    $'\timport pihole_ui_dns_owner' "$frontend"
check_architecture node_route_local exact_count \
    $'\timport pihole_ui_local' "$frontend"
check_architecture node_local_upstream exact_count \
    $'\treverse_proxy 127.0.0.1:8080 {' "$frontend"
check_architecture frontend_no_raw_http_backend reject_pattern \
    'reverse_proxy[[:space:]]+http://(10[.]1[.]0[.](53|54|55)|\[fd36:)' "$frontend"
check_architecture independent_backend_unit exact_count \
    'Description=Protected Pi-hole backend for the DNS VIP owner' "$service"
check_architecture backend_requires_lighttpd exact_count \
    'Requires=lighttpd.service' "$service"
check_architecture backend_does_not_require_frontend reject_pattern \
    '^(Requires|BindsTo)=caddy[.]service$' "$service"
check_architecture manifest_execution_false exact_count \
    '  execution: false' "$manifest"
check_architecture manifest_raw_8080_prohibited exact_count \
    '  raw_lighttpd_exposure: prohibited' "$manifest"
check_architecture manifest_owner_match_required exact_count \
    '  dns_vip_owner_must_match_across_families: true' "$manifest"
check_architecture manifest_backend_identity_required exact_count \
    '  shared_ui_hostname_must_equal_dns_owner_hostname: true' "$manifest"
check_architecture manifest_node_a_identity_required exact_count \
    '  node_a_ui_hostname_must_equal_node_a: true' "$manifest"
check_architecture manifest_node_b_identity_required exact_count \
    '  node_b_ui_hostname_must_equal_node_b: true' "$manifest"

action28k_architecture_tmp=$(mktemp -d)
readonly action28k_architecture_tmp
trap 'rm -rf -- "$action28k_architecture_tmp"' EXIT
sed 's/bind 10[.]1[.]0[.]55 fd36:5aa8:6971:1::55/bind 0.0.0.0 ::/' \
    "$backend" >"$action28k_architecture_tmp/backend-wildcard.Caddyfile"
sed '/mode require_and_verify/d' \
    "$backend" >"$action28k_architecture_tmp/backend-no-mtls.Caddyfile"
sed 's#https://10[.]1[.]0[.]55:8443#http://10.1.0.55:8080#' \
    "$frontend" >"$action28k_architecture_tmp/frontend-raw.Caddyfile"
check_architecture wildcard_listener_fixture_rejected command_rejected reject_pattern \
    '^[[:space:]]*bind[[:space:]]+(0[.]0[.]0[.]0|::)([[:space:]]|$)' \
    "$action28k_architecture_tmp/backend-wildcard.Caddyfile"
check_architecture absent_mtls_fixture_rejected command_rejected exact_count \
    $'\t\t\tmode require_and_verify' \
    "$action28k_architecture_tmp/backend-no-mtls.Caddyfile"
check_architecture raw_lighttpd_fixture_rejected command_rejected reject_pattern \
    'reverse_proxy[[:space:]]+http://(10[.]1[.]0[.](53|54|55)|\[fd36:)' \
    "$action28k_architecture_tmp/frontend-raw.Caddyfile"

if command -v caddy >/dev/null 2>&1; then
    {
        printf '%s\n' '{' $'\tadmin off' $'\tauto_https off' '}'
        printf '%s\n' '(local_tls) {' \
            $'\ttls /tmp/action28k-cert.pem /tmp/action28k-key.pem' '}'
        cat -- "$frontend"
    } >"$action28k_architecture_tmp/frontend.Caddyfile"
    check_architecture backend_caddy_adapt env \
        PIHOLE_BACKEND_SERVER_CERT_FILE=/tmp/action28k-server.pem \
        PIHOLE_BACKEND_SERVER_KEY_FILE=/tmp/action28k-server.key \
        PIHOLE_BACKEND_CLIENT_CA_FILE=/tmp/action28k-client-ca.pem \
        caddy adapt --adapter caddyfile --config "$backend"
    check_architecture frontend_caddy_adapt env \
        NODE_FQDN=pihole0.local.theama.co NODE_IPV4=10.1.0.53 \
        NODE_IPV6=fd36:5aa8:6971:1::53 \
        PIHOLE_BACKEND_SERVER_CA_FILE=/tmp/action28k-server-ca.pem \
        PIHOLE_BACKEND_CLIENT_CERT_FILE=/tmp/action28k-client.pem \
        PIHOLE_BACKEND_CLIENT_KEY_FILE=/tmp/action28k-client.key \
        caddy adapt --adapter caddyfile \
        --config "$action28k_architecture_tmp/frontend.Caddyfile"
else
    printf 'action_28k_architecture_check_backend_caddy_adapt=skipped_command_absent\n'
    printf 'action_28k_architecture_check_frontend_caddy_adapt=skipped_command_absent\n'
fi

printf 'action_28k_architecture_node_a_contacted=false\n'
printf 'action_28k_architecture_node_b_contacted=false\n'
printf 'action_28k_architecture_live_mutation=false\n'
printf 'action_28k_architecture_complete=true\n'
