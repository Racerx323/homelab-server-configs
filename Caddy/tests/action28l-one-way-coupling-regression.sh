#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28l_coupling
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
workspace_root=${caddy_root%/homelab-server-configs/Caddy}
readonly workspace_root
readonly node_a_config=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
readonly node_b_config=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
readonly manifest=$caddy_root/manifests/caddy-dns-ownership-coupling-action28l.yaml

record_check() {
    local action28l_coupling_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28l_coupling_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28l_coupling_label" >&2
    return 1
}

instance_body() {
    local action28l_instance=$1
    local action28l_file=$2

    awk -v wanted="$action28l_instance" '
        $1 == "vrrp_instance" && $2 == wanted { inside = 1; depth = 0 }
        inside {
            print
            depth += gsub(/\{/, "{")
            depth -= gsub(/\}/, "}")
            if (depth == 0) exit
        }
    ' "$action28l_file"
}

validate_coupled_config() {
    local action28l_config=$1
    local action28l_expected_priority=$2
    local action28l_ipv4
    local action28l_ipv6

    [[ -f "$action28l_config" && ! -L "$action28l_config" ]] || return 1
    action28l_ipv4=$(instance_body PIHOLE_IPV4 "$action28l_config") || return 1
    action28l_ipv6=$(instance_body PIHOLE_IPV6 "$action28l_config") || return 1
    [[ $(grep -Fxc '        10.1.0.55/22 dev eth0' <<<"$action28l_ipv4") -eq 1 ]] || return 1
    [[ $(grep -Fxc '        10.1.0.56/22 dev eth0' <<<"$action28l_ipv4") -eq 1 ]] || return 1
    [[ $(grep -Fxc '        fd36:5aa8:6971:1::55/128 dev eth0 preferred_lft forever' <<<"$action28l_ipv6") -eq 1 ]] || return 1
    [[ $(grep -Fxc '        fd36:5aa8:6971:1::56/128 dev eth0 preferred_lft forever' <<<"$action28l_ipv6") -eq 1 ]] || return 1
    [[ $(grep -Ec '^[[:space:]]*priority[[:space:]]+' "$action28l_config") -eq 2 ]] || return 1
    [[ $(grep -Ec "^[[:space:]]*priority[[:space:]]+$action28l_expected_priority$" "$action28l_config") -eq 2 ]] || return 1
    ! grep -Eq 'check[_-]?caddy|caddy[.]service|caddy_endpoint' "$action28l_config" || return 1
    ! grep -Eq 'CADDY_(IPV4|IPV6|DUALSTACK)' "$action28l_config" || return 1
}

command_rejected() {
    if "$@" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

record_check node_a_contract validate_coupled_config "$node_a_config" 150
record_check node_b_contract validate_coupled_config "$node_b_config" 100
record_check direction_exact grep -Fqx '  direction: caddy_follows_dns_only' "$manifest"
record_check caddy_cannot_move_dns grep -Fqx '  caddy_health_may_move_dns: false' "$manifest"
record_check mtls_not_required grep -Fqx '  additional_backend_certificate_required: false' "$manifest"
record_check transition_node_a_service_first grep -Fq \
    'phase: 1_retire_node_a_caddy_vrrp_and_restore_service' "$manifest"
record_check transition_node_b_relinquish_second grep -Fq 'phase: 2_relinquish_node_b_caddy_vrrp' "$manifest"
record_check transition_node_a_acquire_third grep -Fq 'phase: 3_acquire_coupled_vips_on_node_a' "$manifest"
record_check transition_node_b_standby_fourth grep -Fq 'phase: 4_install_coupled_standby_on_node_b' "$manifest"
record_check no_simultaneous_reload grep -Fq 'Never reload both nodes in one transaction or authorization.' "$manifest"
record_check phase2_rollback grep -Fq 'phase_2_failure:' "$manifest"
record_check phase3_rollback grep -Fq 'phase_3_failure:' "$manifest"
record_check phase4_rollback grep -Fq 'phase_4_failure:' "$manifest"
record_check execution_prohibited grep -Fqx '  execution: false' "$manifest"

fixture_root=$(mktemp -d)
readonly fixture_root
cleanup() {
    rm -rf -- "$fixture_root"
}
trap cleanup EXIT HUP INT TERM

cp -- "$node_a_config" "$fixture_root/missing-caddy-vip.conf"
sed -i '/10[.]1[.]0[.]56\/22 dev eth0/d' "$fixture_root/missing-caddy-vip.conf"
record_check reject_missing_caddy_ipv4 command_rejected \
    validate_coupled_config "$fixture_root/missing-caddy-vip.conf" 150

cp -- "$node_a_config" "$fixture_root/caddy-health-dependency.conf"
sed -i '/track_script {/a\        check_caddy' "$fixture_root/caddy-health-dependency.conf"
record_check reject_caddy_health_dependency command_rejected \
    validate_coupled_config "$fixture_root/caddy-health-dependency.conf" 150

cp -- "$node_a_config" "$fixture_root/wrong-instance.conf"
sed -i '/10[.]1[.]0[.]56\/22 dev eth0/d' "$fixture_root/wrong-instance.conf"
sed -i '/fd36:5aa8:6971:1::55\/128/a\        10.1.0.56/22 dev eth0' "$fixture_root/wrong-instance.conf"
record_check reject_wrong_instance command_rejected \
    validate_coupled_config "$fixture_root/wrong-instance.conf" 150

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
