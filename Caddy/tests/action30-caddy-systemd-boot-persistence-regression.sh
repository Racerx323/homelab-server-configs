#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_30_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/apply-caddy-systemd-boot-persistence-action30.sh
readonly outer=$caddy_root/scripts/run-dual-node-caddy-systemd-boot-persistence-action30-outer.sh
fixture_root=

check() {
    local action30_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action30_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action30_regression_label" >&2
    return 1
}
run_outer() {
    local action30_regression_fail=${1:-}
    local action30_regression_status=0

    ACTION30_FAKE_CALLS=$fixture_root/calls \
        ACTION30_FAKE_PAYLOADS=$fixture_root/payloads \
        ACTION30_FAKE_FAIL=$action30_regression_fail \
        CADDY_ACTION30_SSH_BIN=$fixture_root/fake-ssh \
        CADDY_ACTION30_EVIDENCE_ROOT=$fixture_root/evidence \
        CADDY_ACTION30_SKIP_REGRESSION=true \
        CADDY_ACTION30_SKIP_REPEATED_POLICIES=true \
        /bin/bash "$outer" >"$fixture_root/outer.stdout" \
        2>"$fixture_root/outer.stderr" || action30_regression_status=$?
    printf '%s\n' "$action30_regression_status" >"$fixture_root/outer.status"
}
run_regression() {
    local action30_regression_transaction_sha256

    fixture_root=$(mktemp -d /tmp/action30-regression.XXXXXX) || return 1
    trap 'rm -rf -- "$fixture_root"' EXIT INT TERM
    action30_regression_transaction_sha256=$(sha256sum "$transaction" | awk '{ print $1 }') || return 1
    cat >"$fixture_root/fake-ssh" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
command_line=${!#}
payload=$(mktemp "$ACTION30_FAKE_PAYLOADS/payload.XXXXXX")
cat >"$payload"
printf '%s\n' "$command_line" >>"$ACTION30_FAKE_CALLS"
printf '%s\n' "$(sha256sum "$payload" | awk '{ print $1 }')" >>"$ACTION30_FAKE_PAYLOADS/hashes"
if [[ -n ${ACTION30_FAKE_FAIL:-} && $command_line == *"$ACTION30_FAKE_FAIL"* ]]; then
    exit 1
fi
case "$command_line" in
    *'--apply node-a') printf 'action_30_remote_node_a_complete=true\n' ;;
    *'--apply node-b') printf 'action_30_remote_node_b_complete=true\n' ;;
    *'--verify node-a') printf 'action_30_remote_node_a_verify_complete=true\n' ;;
    *'--verify node-b') printf 'action_30_remote_node_b_verify_complete=true\n' ;;
    *'--verify-continuity node-a') printf 'action_30_remote_node_a_verify_continuity_complete=true\n' ;;
    *'--verify-continuity node-b') printf 'action_30_remote_node_b_verify_continuity_complete=true\n' ;;
    *'--rollback node-a') printf 'action_30_remote_node_a_rollback_complete=true\n' ;;
    *'--rollback node-b') printf 'action_30_remote_node_b_rollback_complete=true\n' ;;
    *) exit 64 ;;
esac
FAKE
    chmod 0755 "$fixture_root/fake-ssh" || return 1
    install -d -m 0700 "$fixture_root/payloads" || return 1
    install -m 0600 /dev/null "$fixture_root/calls" || return 1
    install -m 0600 /dev/null "$fixture_root/payloads/hashes" || return 1

    # conditional-validator-explicit-failures-begin
    check transaction_node_a_self_test /bin/bash "$transaction" --self-test node-a || return 1
    check transaction_node_b_self_test /bin/bash "$transaction" --self-test node-b || return 1
    check obsolete_source_units_absent test ! -e "$caddy_root/systemd/caddy-validate-reload.path" || return 1
    check obsolete_source_service_absent test ! -e "$caddy_root/systemd/caddy-validate-reload.service" || return 1
    check caddy_enabled_target grep -Fq 'caddy.service' "$transaction" || return 1
    check timers_enabled_target grep -Fq 'caddy-cert-expiry.timer' "$transaction" || return 1
    check health_timer_enabled_target grep -Fq 'caddy-sync-health.timer' "$transaction" || return 1
    check static_units_not_enabled test -z \
        "$(grep -E 'systemctl enable.*caddy-(cert-expiry|sync-health|sync-reconcile)[.]service' "$transaction" || true)" || return 1
    check distribution_lsyncd_masked grep -Fq 'mask_distribution_lsyncd' "$transaction" || return 1
    check emergency_service_static grep -Fqx '    emergency.service' "$transaction" || return 1
    check emergency_service_not_enabled test -z \
        "$(grep -E 'systemctl enable.*emergency[.]service' "$transaction" || true)" || return 1
    check obsolete_pair_moved grep -Fq 'mv -- "$obsolete_service"' "$transaction" || return 1
    check rollback_restores_pair grep -Fq '"$backup_directory/caddy-validate-reload.service" "$obsolete_service"' "$transaction" || return 1
    check standby_first_source awk '
        /run_remote node-b-apply/ { standby = NR }
        /run_remote node-a-apply/ { primary = NR }
        END { exit !(standby > 0 && primary > standby) }
    ' "$outer" || return 1
    run_outer || return 1
    check success_status test "$(cat "$fixture_root/outer.status")" -eq 0 || return 1
    check success_complete grep -Fqx 'action_30_outer_complete=true' "$fixture_root/outer.stdout" || return 1
    check success_order diff -u - "$fixture_root/calls" <<'ORDER' || return 1
cd / && sudo -n /bin/bash -s -- --apply node-b
cd / && sudo -n /bin/bash -s -- --verify-continuity node-a
cd / && sudo -n /bin/bash -s -- --apply node-a
cd / && sudo -n /bin/bash -s -- --verify node-b
cd / && sudo -n /bin/bash -s -- --verify node-a
ORDER
    check exact_generated_payload awk -v expected="$action30_regression_transaction_sha256" '
        $0 != expected { exit 1 }
        END { exit !(NR == 5) }
    ' "$fixture_root/payloads/hashes" || return 1
    : >"$fixture_root/calls"
    : >"$fixture_root/payloads/hashes"
    run_outer '--verify node-b' || return 1
    check recovery_status test "$(cat "$fixture_root/outer.status")" -eq 1 || return 1
    check recovery_proven grep -Fqx 'action_30_outer_recovery_proven=true' "$fixture_root/outer.stdout" || return 1
    check reverse_rollback_order awk '
        /--rollback node-a/ { primary = NR }
        /--rollback node-b/ { standby = NR }
        END { exit !(primary > 0 && standby > primary) }
    ' "$fixture_root/calls" || return 1
    # conditional-validator-explicit-failures-end
    printf '%s_actual_generated_remote_program=true\n' "$prefix"
    printf '%s_capture_path_covered=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

run_regression
