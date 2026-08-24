#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=caddy_environment_v2_policy
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
validate_template() {
    local environment_policy_template=$1

    [[ -f "$environment_policy_template" && ! -L "$environment_policy_template" ]] || return 1
    [[ "$(wc -l <"$environment_policy_template")" -eq 3 ]] || return 1
    [[ "$(grep -Fxc 'NODE_FQDN=@NODE_FQDN@' "$environment_policy_template")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'NODE_IPV4=@NODE_IPV4@' "$environment_policy_template")" -eq 1 ]] || return 1
    [[ "$(grep -Fxc 'NODE_IPV6=@NODE_IPV6@' "$environment_policy_template")" -eq 1 ]] || return 1
    ! grep -Eq '^(NODE_ROLE|PEER_ROLE|PEER_IPV4|PEER_IPV6|CADDY_PRIORITY|NETWORK_INTERFACE|SYNC_TARGET)=' \
        "$environment_policy_template" || return 1
    ! grep -Eq '[[:cntrl:]]|[[:space:]]$|(^|=)[^=@A-Za-z0-9_.:-]' \
        "$environment_policy_template"
}

run_self_test() (
    local environment_policy_work_directory
    local environment_policy_fixture
    local environment_policy_defect
    local environment_policy_node_role
    local environment_policy_output_directory
    local environment_policy_expected_fqdn
    local environment_policy_expected_ipv4
    local environment_policy_expected_ipv6
    local environment_policy_renderer=$repository_root/Caddy/scripts/render-node-config.sh
    local environment_policy_template=$repository_root/Caddy/templates/caddy-ha.env-v2.in

    environment_policy_work_directory=$(mktemp -d /tmp/caddy-environment-v2.XXXXXX)
    trap 'rm -rf -- "$environment_policy_work_directory"' EXIT
    validate_template "$environment_policy_template" || return 1

    for environment_policy_defect in missing extra duplicate unsafe obsolete; do
        environment_policy_fixture=$environment_policy_work_directory/$environment_policy_defect.in
        case "$environment_policy_defect" in
            missing)
                printf '%s\n' 'NODE_FQDN=@NODE_FQDN@' 'NODE_IPV4=@NODE_IPV4@' >"$environment_policy_fixture"
                ;;
            extra)
                cp -- "$environment_policy_template" "$environment_policy_fixture"
                printf '%s\n' 'EXTRA=value' >>"$environment_policy_fixture"
                ;;
            duplicate)
                cp -- "$environment_policy_template" "$environment_policy_fixture"
                printf '%s\n' 'NODE_IPV6=@NODE_IPV6@' >>"$environment_policy_fixture"
                ;;
            unsafe)
                # This is deliberately literal unsafe input for the negative control.
                # shellcheck disable=SC2016
                printf '%s\n' 'NODE_FQDN=$(id)' 'NODE_IPV4=@NODE_IPV4@' \
                    'NODE_IPV6=@NODE_IPV6@' >"$environment_policy_fixture"
                ;;
            obsolete)
                printf '%s\n' 'NODE_FQDN=@NODE_FQDN@' 'NODE_IPV4=@NODE_IPV4@' \
                    'SYNC_TARGET=peer' >"$environment_policy_fixture"
                ;;
        esac
        ! validate_template "$environment_policy_fixture" || return 1
    done

    for environment_policy_node_role in node-a node-b; do
        environment_policy_output_directory=$environment_policy_work_directory/$environment_policy_node_role
        /bin/bash "$environment_policy_renderer" --node "$environment_policy_node_role" \
            --output "$environment_policy_output_directory" >/dev/null || return 1
        case "$environment_policy_node_role" in
            node-a)
                environment_policy_expected_fqdn=pihole0.local.theama.co
                environment_policy_expected_ipv4=10.1.0.53
                environment_policy_expected_ipv6=fd36:5aa8:6971:1::53
                ;;
            node-b)
                environment_policy_expected_fqdn=pihole00.local.theama.co
                environment_policy_expected_ipv4=10.1.0.54
                environment_policy_expected_ipv6=fd36:5aa8:6971:1::54
                ;;
        esac
        grep -Fxq "NODE_FQDN=$environment_policy_expected_fqdn" \
            "$environment_policy_output_directory/caddy-ha.env" || return 1
        grep -Fxq "NODE_IPV4=$environment_policy_expected_ipv4" \
            "$environment_policy_output_directory/caddy-ha.env" || return 1
        grep -Fxq "NODE_IPV6=$environment_policy_expected_ipv6" \
            "$environment_policy_output_directory/caddy-ha.env" || return 1
    done
    printf '%s_self_test=true\n' "$prefix"
)

case "${1:---self-test}" in
    --check)
        if [[ $# -eq 1 ]]; then
            template=$repository_root/Caddy/templates/caddy-ha.env-v2.in
        elif [[ $# -eq 3 && $2 == --template && $3 == /tmp/* ]]; then
            template=$3
        else
            exit 64
        fi
        validate_template "$template" || exit 1
        printf '%s_check_exact_variables=true\n' "$prefix"
        printf '%s_check_obsolete_variables_absent=true\n' "$prefix"
        printf '%s_check_values_safe=true\n' "$prefix"
        printf '%s_complete=true\n' "$prefix"
        ;;
    --self-test)
        [[ $# -le 1 ]] || exit 64
        run_self_test || exit 1
        printf '%s_complete=true\n' "$prefix"
        ;;
    *)
        printf 'Usage: %s --check [--template /tmp/PATH]|--self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
