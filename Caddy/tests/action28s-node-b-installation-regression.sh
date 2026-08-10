#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28s_install_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/install-node-b-protocol-compatible-coupling-action28s.sh
readonly outer=$caddy_root/scripts/run-node-b-protocol-compatible-coupling-action28s-outer.sh
readonly source_configuration=${caddy_root%/homelab-server-configs/Caddy}/homelab-dns/Keepalived/configs/keepalived-pihole00.conf

record_check() {
    local action28s_install_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28s_install_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28s_install_label" >&2
    return 1
}
command_rejected() {
    if "$@" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
emit_checks() {
    local action28s_install_source=$1
    local action28s_install_option=$2
    local action28s_install_output_prefix=$3

    while IFS= read -r action28s_install_check; do
        printf '%s_check_%s=true\n' "$action28s_install_output_prefix" "$action28s_install_check"
    done < <("$action28s_install_source" "$action28s_install_option")
}
write_mock() {
    local action28s_install_mock=$1

    # The single-quoted body is the generated mock program.
    # shellcheck disable=SC2016
    {
        printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' 'set +x' 'umask 077' \
            'PATH=/usr/bin:/bin' 'export PATH' \
            'count_file=${ACTION28S_MOCK_COUNT_FILE:?}' \
            'capture_root=${ACTION28S_MOCK_CAPTURE_ROOT:?}' \
            'transaction=${ACTION28S_MOCK_TRANSACTION:?}' \
            'node_a_inspector=${ACTION28S_MOCK_NODE_A_INSPECTOR:?}' \
            'node_b_inspector=${ACTION28S_MOCK_NODE_B_INSPECTOR:?}' \
            'count=$(cat "$count_file" 2>/dev/null || printf 0)' \
            'count=$((count + 1))' 'printf '\''%s\n'\'' "$count" >"$count_file"' \
            'printf '\''%s\0'\'' "$@" >"$capture_root/args.$count"' \
            'cat >"$capture_root/stdin.$count"' \
            'emit() { while IFS= read -r check; do printf '\''%s_check_%s=true\n'\'' "$1" "$check"; done; }' \
            'case "$count" in' \
            '1|4) emit action_28m_b < <("$node_a_inspector" --expected-checks); printf '\''%s\n'\'' action_28m_b_first_failure=none action_28m_b_mutation=false action_28m_b_acceptance=true ;;' \
            '2) emit action_28p_a_node_b < <("$node_b_inspector" --expected-checks); printf '\''%s\n'\'' action_28p_a_node_b_first_failure=none action_28p_a_node_b_mutation=false action_28p_a_node_b_acceptance=true ;;' \
            '3) emit action_28s_node_b < <("$transaction" --expected-checks); if [[ "${ACTION28S_MOCK_FALSE_TRANSACTION:-}" = 1 ]]; then printf '\''%s\n'\'' action_28s_node_b_check_source_contract=false; fi; printf '\''%s\n'\'' action_28s_node_b_first_failure=none action_28s_node_b_node=node_b action_28s_node_b_advertised_ipv4_count=1 action_28s_node_b_advertised_ipv6_count=1 action_28s_node_b_caddy_vips_excluded=true action_28s_node_b_keepalived_reload=true action_28s_node_b_mutation=true action_28s_node_b_acceptance=true ;;' \
            '*) exit 64 ;;' 'esac'
    } >"$action28s_install_mock"
    chmod 0700 "$action28s_install_mock"
}
run_outer_fixture() {
    local action28s_install_fixture=$1
    local action28s_install_false=${2:-0}

    install -m 0600 /dev/null "$action28s_install_fixture/count"
    printf '0\n' >"$action28s_install_fixture/count"
    ACTION28S_MOCK_COUNT_FILE=$action28s_install_fixture/count \
        ACTION28S_MOCK_CAPTURE_ROOT=$action28s_install_fixture \
        ACTION28S_MOCK_TRANSACTION=$transaction \
        ACTION28S_MOCK_NODE_A_INSPECTOR=$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-b.sh \
        ACTION28S_MOCK_NODE_B_INSPECTOR=$caddy_root/scripts/inspect-node-b-caddy-vrrp-relinquish-action28p-a.sh \
        ACTION28S_MOCK_FALSE_TRANSACTION=$action28s_install_false \
        CADDY_ACTION28S_TEST_MODE=1 \
        CADDY_ACTION28S_TEST_SKIP_LOCAL_GATES=1 \
        CADDY_ACTION28S_SSH_BIN=$action28s_install_fixture/ssh \
        CADDY_ACTION28S_EVIDENCE_ROOT=$action28s_install_fixture/evidence \
        "$outer"
}

record_check transaction_self_test "$transaction" --self-test
record_check expected_checks_unique test \
    "$("$transaction" --expected-checks | LC_ALL=C sort -u | wc -l)" -eq \
    "$("$transaction" --expected-checks | wc -l)"
record_check expected_rollback_checks_unique test \
    "$("$transaction" --expected-rollback-checks | LC_ALL=C sort -u | wc -l)" -eq \
    "$("$transaction" --expected-rollback-checks | wc -l)"
record_check source_hash_exact test \
    "$(sha256sum "$source_configuration" | awk '{ print $1 }')" = \
    034ee9c45acaca4e48e2faeda24cd371e945bdb52a117b5871403958ab36794c
record_check production_source_contract /bin/bash "$test_directory/action28s-protocol-compatible-coupling-regression.sh"
record_check outer_uses_root_cwd grep -Fq \
    "'cd / && sudo -n /bin/bash -s --'" "$outer"
record_check outer_uses_local_tmp_evidence grep -Fq \
    '/tmp/caddy-ssh-evidence/action28s' "$outer"
record_check outer_no_action_28r_rerun test \
    "$(grep -Ec 'run-node-a-coupled-vip-acquisition-action28r|action28r-outer' "$outer" || true)" -eq 0

fixture_root=$(mktemp -d /tmp/caddy-action28s-install-regression.XXXXXX)
readonly fixture_root
cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT HUP INT TERM
write_mock "$fixture_root/ssh"
record_check intercepted_production_path run_outer_fixture "$fixture_root"
record_check intercepted_call_count test "$(<"$fixture_root/count")" -eq 4
record_check transaction_bundle_contains_candidate grep -Fq \
    'keepalived-pihole00.conf' "$fixture_root/stdin.3"
record_check node_a_preflight_target grep -Fq 'pi@10.1.0.53' "$fixture_root/args.1"
record_check node_b_preflight_target grep -Fq 'pi@10.1.0.54' "$fixture_root/args.2"
record_check node_b_transaction_target grep -Fq 'pi@10.1.0.54' "$fixture_root/args.3"
record_check node_a_postflight_target grep -Fq 'pi@10.1.0.53' "$fixture_root/args.4"

false_fixture=$fixture_root/false
install -d -m 0700 "$false_fixture"
write_mock "$false_fixture/ssh"
record_check reject_false_transaction command_rejected run_outer_fixture "$false_fixture" 1

printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
