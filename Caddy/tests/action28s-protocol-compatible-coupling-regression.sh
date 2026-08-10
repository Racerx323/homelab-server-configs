#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28s
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly workspace_root=${caddy_root%/homelab-server-configs/Caddy}
readonly node_a_config=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
readonly node_b_config=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
readonly retained_template=$caddy_root/templates/keepalived-caddy-ha-v2.conf.in
readonly manifest=$caddy_root/manifests/caddy-protocol-compatible-coupling-action28s.yaml

record_check() {
    local action28s_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28s_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28s_label" >&2
    return 1
}

instance_body() {
    local action28s_instance=$1
    local action28s_file=$2

    awk -v wanted="$action28s_instance" '
        $1 == "vrrp_instance" && $2 == wanted { inside = 1; depth = 0 }
        inside {
            print
            depth += gsub(/\{/, "{")
            depth -= gsub(/\}/, "}")
            if (depth == 0) exit
        }
    ' "$action28s_file"
}

block_body() {
    local action28s_block=$1

    awk -v wanted="$action28s_block" '
        $1 == wanted && $2 == "{" { inside = 1; depth = 0 }
        inside {
            print
            depth += gsub(/\{/, "{")
            depth -= gsub(/\}/, "}")
            if (depth == 0) exit
        }
    '
}

validate_instance() {
    local action28s_instance=$1
    local action28s_config=$2
    local action28s_dns_vip=$3
    local action28s_caddy_vip=$4
    local action28s_peer=$5
    local action28s_body
    local action28s_advertised
    local action28s_excluded

    action28s_body=$(instance_body "$action28s_instance" "$action28s_config") || return 1
    action28s_advertised=$(block_body virtual_ipaddress <<<"$action28s_body") || return 1
    action28s_excluded=$(block_body virtual_ipaddress_excluded <<<"$action28s_body") || return 1
    [[ "$(grep -Fxc "        $action28s_dns_vip" <<<"$action28s_advertised" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc "        $action28s_caddy_vip" <<<"$action28s_advertised" || true)" -eq 0 ]] || return 1
    [[ "$(grep -Fxc "        $action28s_caddy_vip" <<<"$action28s_excluded" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc "        $action28s_dns_vip" <<<"$action28s_excluded" || true)" -eq 0 ]] || return 1
    [[ "$(grep -Ec '^[[:space:]]*unicast_ttl[[:space:]]+255[[:space:]]*$' <<<"$action28s_body" || true)" -eq 1 ]] || return 1
    [[ "$(grep -Fxc "        $action28s_peer min_ttl 255 max_ttl 255" <<<"$action28s_body" || true)" -eq 1 ]]
}

validate_node() {
    local action28s_config=$1
    local action28s_priority=$2
    local action28s_ipv4_peer=$3
    local action28s_ipv6_peer=$4

    [[ -f "$action28s_config" && ! -L "$action28s_config" ]] || return 1
    validate_instance PIHOLE_IPV4 "$action28s_config" \
        '10.1.0.55/22 dev eth0' '10.1.0.56/22 dev eth0' "$action28s_ipv4_peer" || return 1
    validate_instance PIHOLE_IPV6 "$action28s_config" \
        'fd36:5aa8:6971:1::55/128 dev eth0 preferred_lft forever' \
        'fd36:5aa8:6971:1::56/128 dev eth0 preferred_lft forever' \
        "$action28s_ipv6_peer" || return 1
    [[ "$(grep -Ec "^[[:space:]]*priority[[:space:]]+$action28s_priority$" "$action28s_config" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Fxc '    unicast_ttl 255' "$action28s_config" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Ec 'min_ttl[[:space:]]+255[[:space:]]+max_ttl[[:space:]]+255' "$action28s_config" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Fxc '    virtual_ipaddress {' "$action28s_config" || true)" -eq 2 ]] || return 1
    [[ "$(grep -Fxc '    virtual_ipaddress_excluded {' "$action28s_config" || true)" -eq 2 ]] || return 1
    ! grep -Eq 'check[_-]?caddy|CADDY_(IPV4|IPV6|DUALSTACK)' "$action28s_config"
}

command_rejected() {
    if "$@" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

record_check node_a_contract validate_node "$node_a_config" 150 10.1.0.54 fd36:5aa8:6971:1::54
record_check node_b_contract validate_node "$node_b_config" 100 10.1.0.53 fd36:5aa8:6971:1::53
record_check node_a_source_hash grep -Fqx \
    '    sha256: d8f96c4f018f90370aea38fc3ef932af649158f6edc99cc7e95dea1edff4908a' "$manifest"
record_check node_b_source_hash grep -Fqx \
    '    sha256: 034ee9c45acaca4e48e2faeda24cd371e945bdb52a117b5871403958ab36794c' "$manifest"
record_check ttl_required grep -Fqx '  required: true' "$manifest"
record_check sender_ttl grep -Fqx '  outgoing_per_instance: unicast_ttl 255' "$manifest"
record_check receiver_ttl grep -Fqx '  incoming_per_peer: min_ttl 255 max_ttl 255' "$manifest"
record_check node_b_first grep -Fq 'phase: 1_node_b_transaction_definition' "$manifest"
record_check node_b_acceptance_second grep -Fq 'phase: 2_node_b_independent_acceptance' "$manifest"
record_check node_a_third grep -Fq 'phase: 3_node_a_transaction_definition' "$manifest"
record_check simultaneous_reload_prohibited grep -Fqx '  simultaneous_reload: prohibited' "$manifest"
record_check execution_false grep -Fqx '  execution: false' "$manifest"
record_check retained_template_sender_ttl_count test \
    "$(grep -Fxc '    unicast_ttl 255' "$retained_template" || true)" -eq 2
record_check retained_template_receiver_ttl_count test \
    "$(grep -Ec 'min_ttl 255 max_ttl 255$' "$retained_template" || true)" -eq 2

fixture_root=$(mktemp -d /tmp/caddy-action28s-regression.XXXXXX)
readonly fixture_root
cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT HUP INT TERM

cp -- "$node_a_config" "$fixture_root/caddy-advertised.conf"
sed -i '/virtual_ipaddress_excluded {/,/^    }/s/virtual_ipaddress_excluded/virtual_ipaddress/' \
    "$fixture_root/caddy-advertised.conf"
record_check reject_caddy_advertised command_rejected validate_node \
    "$fixture_root/caddy-advertised.conf" 150 10.1.0.54 fd36:5aa8:6971:1::54

cp -- "$node_a_config" "$fixture_root/missing-sender-ttl.conf"
sed -i '0,/^    unicast_ttl 255$/{/^    unicast_ttl 255$/d;}' \
    "$fixture_root/missing-sender-ttl.conf"
record_check reject_missing_sender_ttl command_rejected validate_node \
    "$fixture_root/missing-sender-ttl.conf" 150 10.1.0.54 fd36:5aa8:6971:1::54

cp -- "$node_a_config" "$fixture_root/missing-receiver-ttl.conf"
sed -i '0,/ min_ttl 255 max_ttl 255$/s/ min_ttl 255 max_ttl 255//' \
    "$fixture_root/missing-receiver-ttl.conf"
record_check reject_missing_receiver_ttl command_rejected validate_node \
    "$fixture_root/missing-receiver-ttl.conf" 150 10.1.0.54 fd36:5aa8:6971:1::54

cp -- "$node_a_config" "$fixture_root/missing-excluded-vip.conf"
sed -i '0,/10[.]1[.]0[.]56\/22 dev eth0/{/10[.]1[.]0[.]56\/22 dev eth0/d;}' \
    "$fixture_root/missing-excluded-vip.conf"
record_check reject_missing_excluded_vip command_rejected validate_node \
    "$fixture_root/missing-excluded-vip.conf" 150 10.1.0.54 fd36:5aa8:6971:1::54

printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
