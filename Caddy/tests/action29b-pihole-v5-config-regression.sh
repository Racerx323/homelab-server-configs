#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_29b_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/apply-pihole-v5-config-action29b.sh
readonly outer=$caddy_root/scripts/run-dual-node-pihole-v5-config-action29b-outer.sh
fixture_root=

check() {
    local action29b_regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$action29b_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action29b_regression_label" >&2
    return 1
}
run_outer_success() {
    local action29b_regression_status=0

    ACTION29B_FAKE_CALLS=$fixture_root/success.calls \
        CADDY_ACTION29B_SSH_BIN=$fixture_root/fake-ssh \
        CADDY_ACTION29B_EVIDENCE_ROOT=$fixture_root/success-evidence \
        CADDY_ACTION29B_SKIP_REGRESSION=true \
        /bin/bash "$outer" >"$fixture_root/success.stdout" \
        2>"$fixture_root/success.stderr" || action29b_regression_status=$?
    if [[ "$action29b_regression_status" -ne 0 ]]; then
        printf '%s_observed_success_status=%s\n' "$prefix" "$action29b_regression_status" >&2
        sed 's/^/action_29b_regression_observed_success_stdout=/' \
            "$fixture_root/success.stdout" >&2
        sed 's/^/action_29b_regression_observed_success_stderr=/' \
            "$fixture_root/success.stderr" >&2
        return 1
    fi
}
run_outer_recovery() {
    local action29b_regression_status=0

    ACTION29B_FAKE_CALLS=$fixture_root/recovery.calls \
        ACTION29B_FAKE_FAIL='--verify-target node-b' \
        CADDY_ACTION29B_SSH_BIN=$fixture_root/fake-ssh \
        CADDY_ACTION29B_EVIDENCE_ROOT=$fixture_root/recovery-evidence \
        CADDY_ACTION29B_SKIP_REGRESSION=true \
        /bin/bash "$outer" >"$fixture_root/recovery.stdout" \
        2>"$fixture_root/recovery.stderr" || action29b_regression_status=$?
    [[ "$action29b_regression_status" -eq 1 ]] || return 1
    grep -Fqx 'action_29b_outer_recovery_proven=true' "$fixture_root/recovery.stdout"
}
run_regression() {
    fixture_root=$(mktemp -d /tmp/action29b-regression.XXXXXX) || return 1
    trap 'rm -rf -- "$fixture_root"' EXIT INT TERM
    cat >"$fixture_root/fake-ssh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
command_line=${!#}
cat >/dev/null
printf '%s\n' "$command_line" >>"$ACTION29B_FAKE_CALLS"
if [[ -n ${ACTION29B_FAKE_FAIL:-} && $command_line == *"$ACTION29B_FAKE_FAIL"* ]]; then
    exit 1
fi
case "$command_line" in
    *'--apply node-a'*) printf 'action_29b_remote_node_a_complete=true\n' ;;
    *'--apply node-b'*) printf 'action_29b_remote_node_b_complete=true\n' ;;
    *'--verify-target node-a'*) printf 'action_29b_remote_node_a_verify_target_complete=true\n' ;;
    *'--verify-target node-b'*) printf 'action_29b_remote_node_b_verify_target_complete=true\n' ;;
    *'--rollback-committed node-a'*) printf 'action_29b_remote_node_a_rollback_committed_complete=true\n' ;;
    *'--rollback-committed node-b'*) printf 'action_29b_remote_node_b_rollback_committed_complete=true\n' ;;
    *'--verify-continuity node-a'*) printf 'action_29b_remote_node_a_check_dns_record_families=true\n' ;;
    *'--verify-continuity node-b'*) printf 'action_29b_remote_node_b_check_dns_record_families=true\n' ;;
    *) exit 64 ;;
esac
EOF
    chmod 0755 "$fixture_root/fake-ssh" || return 1

    # conditional-validator-explicit-failures-begin
    check node_a_payload_self_test /bin/bash "$transaction" --self-test node-a || return 1
    check node_b_payload_self_test /bin/bash "$transaction" --self-test node-b || return 1
    check production_remote_cwd grep -Fq \
        "\"cd / && sudo -n /bin/bash -s -- \$action29b_mode \$action29b_role\"" "$outer" || return 1
    check malformed_remote_shell_absent test -z "$(grep -F '/bin/bash -s/' "$outer" || true)" || return 1
    check capture_before_ssh grep -Fq \
        "prepare_capture \"\$action29b_stdout\" \"\$action29b_stderr\" \"\$action29b_status_file\"" \
        "$outer" || return 1
    check parser_before_restart awk '
        /check ftl_configuration_test/ { parser = NR }
        /check restartdns/ { restart = NR }
        END { exit !(parser > 0 && restart > parser) }
    ' "$transaction" || return 1
    check standby_first_source awk '
        /run_remote node-b-apply/ { standby = NR }
        /run_remote node-a-apply/ { primary = NR }
        END { exit !(standby > 0 && primary > standby) }
    ' "$outer" || return 1
    check reverse_rollback_source awk '
        /run_remote node-a-rollback/ { primary = NR }
        /run_remote node-b-rollback/ { standby = NR }
        END { exit !(primary > 0 && standby > primary) }
    ' "$outer" || return 1
    check success_actual_production_path run_outer_success || return 1
    check success_complete grep -Fqx 'action_29b_outer_complete=true' \
        "$fixture_root/success.stdout" || return 1
    check success_order diff -u - "$fixture_root/success.calls" <<'EOF' || return 1
cd / && sudo -n /bin/bash -s -- --apply node-b
cd / && sudo -n /bin/bash -s -- --verify-continuity node-a
cd / && sudo -n /bin/bash -s -- --apply node-a
cd / && sudo -n /bin/bash -s -- --verify-target node-b
cd / && sudo -n /bin/bash -s -- --verify-target node-a
EOF
    check recovery_actual_production_path run_outer_recovery || return 1
    check recovery_reverse_order awk '
        /--rollback-committed node-a/ { primary = NR }
        /--rollback-committed node-b/ { standby = NR }
        END { exit !(primary > 0 && standby > primary) }
    ' "$fixture_root/recovery.calls" || return 1
    check recovery_manual_intervention_absent test -z \
        "$(grep -F 'manual_intervention_required=true' "$fixture_root/recovery.stderr" || true)" || return 1
    # conditional-validator-explicit-failures-end

    printf '%s_actual_production_path=true\n' "$prefix"
    printf '%s_negative_recovery_coverage=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

run_regression
