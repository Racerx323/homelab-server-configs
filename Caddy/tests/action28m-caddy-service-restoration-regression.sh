#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28m_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
workspace_root=${caddy_root%/homelab-server-configs/Caddy}
readonly workspace_root
readonly driver=$caddy_root/scripts/restore-node-a-caddy-service-action28m.sh
readonly inspector=$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-a.sh
readonly transaction_outer=$caddy_root/scripts/run-node-a-caddy-service-restoration-action28m-outer.sh
readonly acceptance_outer=$caddy_root/scripts/run-node-a-caddy-service-restoration-post-action28m-a-outer.sh

check() {
    local action28m_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action28m_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28m_regression_label" >&2
    return 1
}
command_rejected() {
    if "$@" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
mock_ssh_source() {
    cat <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
temp=$(mktemp)
trap 'rm -f -- "$temp"' EXIT
cat >"$temp"
chmod 0700 "$temp"
if grep -Fq 'readonly prefix=action_28m_a' "$temp"; then
    prefix=action_28m_a
    while IFS= read -r label; do
        [[ "${ACTION28M_MOCK_MODE:-}" == missing && "$label" == caddy_active_after ]] && continue
        printf '%s_check_%s=true\n' "$prefix" "$label"
    done < <(/bin/bash "$temp" --expected-checks)
    printf '%s_first_failure=none\n' "$prefix"
    printf '%s_value_state_sha256=%064d\n' "$prefix" 0
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_mutation=false\n' "$prefix"
    printf '%s_acceptance=true\n' "$prefix"
else
    prefix=action_28m
    while IFS= read -r label; do
        [[ "${ACTION28M_MOCK_MODE:-}" == missing && "$label" == caddy_active_after_start ]] && continue
        printf '%s_check_%s=true\n' "$prefix" "$label"
    done < <(/bin/bash "$temp" --expected-checks)
    printf '%s_check_count=%s\n' "$prefix" "$(/bin/bash "$temp" --expected-checks | wc -l)"
    printf '%s_value_first_failure=none\n' "$prefix"
    printf '%s_rollback_invoked=false\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_keepalived_reload_count=1\n' "$prefix"
    printf '%s_caddy_start_count=1\n' "$prefix"
    printf '%s_acceptance=true\n' "$prefix"
fi
MOCK
}

fixture_root=$(mktemp -d)
readonly fixture_root
cleanup() {
    rm -rf -- "$fixture_root"
}
trap cleanup EXIT HUP INT TERM

git -C "$workspace_root/homelab-dns" show \
    HEAD:Keepalived/configs/keepalived-pihole0.conf >"$fixture_root/valid.conf"
check candidate_valid /bin/bash "$driver" --candidate-test "$fixture_root/valid.conf"
cp -- "$fixture_root/valid.conf" "$fixture_root/include-present.conf"
printf '\ninclude /etc/keepalived/conf.d/caddy-ha.conf\n' >>"$fixture_root/include-present.conf"
check candidate_rejects_include command_rejected /bin/bash "$driver" \
    --candidate-test "$fixture_root/include-present.conf"
sed '/vrrp_instance PIHOLE_IPV6 {/d' "$fixture_root/valid.conf" >"$fixture_root/missing-instance.conf"
check candidate_rejects_missing_instance command_rejected /bin/bash "$driver" \
    --candidate-test "$fixture_root/missing-instance.conf"

mock_ssh=$fixture_root/mock-ssh
mock_ssh_source >"$mock_ssh"
chmod 0700 "$mock_ssh"
check transaction_production_path env CADDY_ACTION28M_TEST_MODE=1 \
    CADDY_ACTION28M_SSH_BIN="$mock_ssh" /bin/bash "$transaction_outer"
check transaction_rejects_missing_producer_label command_rejected env \
    ACTION28M_MOCK_MODE=missing CADDY_ACTION28M_TEST_MODE=1 \
    CADDY_ACTION28M_SSH_BIN="$mock_ssh" /bin/bash "$transaction_outer"
check acceptance_production_path env CADDY_ACTION28MA_TEST_MODE=1 \
    CADDY_ACTION28MA_SSH_BIN="$mock_ssh" /bin/bash "$acceptance_outer"
check acceptance_rejects_missing_producer_label command_rejected env \
    ACTION28M_MOCK_MODE=missing CADDY_ACTION28MA_TEST_MODE=1 \
    CADDY_ACTION28MA_SSH_BIN="$mock_ssh" /bin/bash "$acceptance_outer"
check transaction_remote_cwd grep -Fq '"cd / && sudo -n /bin/bash -s --"' "$transaction_outer"
check acceptance_remote_cwd grep -Fq '"cd / && sudo -n /bin/bash -s --"' "$acceptance_outer"
check node_b_target_absent command_rejected grep -Eq 'pi@10[.]1[.]0[.]54|pihole00' \
    "$driver" "$inspector" "$transaction_outer" "$acceptance_outer"
check rollback_exit_125 grep -Fq 'action28m_cleanup_status=125' "$driver"
check reload_before_start awk '
    /systemctl reload keepalived[.]service/ { reload = NR }
    /systemctl start caddy[.]service/ { start = NR }
    END { exit reload > 0 && start > reload ? 0 : 1 }
' "$driver"

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
