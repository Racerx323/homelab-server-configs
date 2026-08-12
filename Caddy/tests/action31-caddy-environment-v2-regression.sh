#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_31_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly transaction=$repository_root/Caddy/scripts/apply-caddy-environment-v2-action31.sh
readonly outer=$repository_root/Caddy/scripts/run-dual-node-caddy-environment-v2-action31-outer.sh
readonly expected_transaction_sha256=7c55166f6bad1830335d8f66aabacb2f0716a82b1dad7dc5b83bcd730f732caf
fixture_root=$(mktemp -d /tmp/action31-regression.XXXXXX)
readonly fixture_root
trap 'rm -rf -- "$fixture_root"' EXIT

check() {
    local action31_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action31_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action31_regression_label" >&2
    return 1
}
source_contract() {
    # conditional-validator-explicit-failures-begin
    grep -Fq 'candidate_sha256=209e31e11a72660b7ebada372278c8482d9d1e65c6d83f6aa9510634d78f5ee3' "$transaction" || return 1
    grep -Fq 'candidate_sha256=580d79608bb99567c1831d073785cdba9d9d02efeaa33717c8f8e0dca266b226' "$transaction" || return 1
    grep -Fq 'expected_legacy_sha256=2e439dd4c868736fd7a9dceff7ba3627a1d9fe8780ba7dcef2ce5d0e5e62a2b8' "$transaction" || return 1
    grep -Fq 'expected_legacy_sha256=f692d5b7e0a7e0f0ab142e36face6a8cc8c6680a44a2bcaf6a992247ec4c8113' "$transaction" || return 1
    grep -Fq 'install -o root -g caddy-tls -m 0640' "$transaction" || return 1
    grep -Fq 'systemctl reload caddy.service' "$transaction" || return 1
    ! grep -Eq 'systemctl (reload|restart) (keepalived|caddy-lsyncd|caddy-sync-reconcile)' "$transaction" || return 1
    ! grep -Eq '(publish-release|reconcile-release-v2).*--' "$transaction" || return 1
    grep -Fq 'check trusted_https trusted_https' "$transaction" || return 1
    grep -Fq 'check health_helper setpriv --reuid keepalived_script --regid caddy-tls' "$transaction" || return 1
    grep -Fq 'check reconciliation_path_active systemctl is-active --quiet caddy-sync-reconcile.path' "$transaction" || return 1
    # shellcheck disable=SC2016
    grep -Fq 'verify_state "$expected_legacy_sha256"' "$transaction" || return 1
    grep -Fq 'return 125' "$outer" || return 1
    awk '
        /run_remote node-b-apply/ { standby = NR }
        /run_remote node-a-apply/ { primary = NR }
        END { exit !(standby > 0 && primary > standby) }
    ' "$outer" || return 1
    awk '
        /run_remote node-a-rollback/ { primary = NR }
        /run_remote node-b-rollback/ { standby = NR }
        END { exit !(primary > 0 && standby > primary) }
    ' "$outer" || return 1
    # conditional-validator-explicit-failures-end
}

fake_ssh=$fixture_root/ssh
readonly fake_ssh
cat >"$fake_ssh" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
command_text=${!#}
mode=$(sed -nE 's/.* (--(apply|verify-current|verify-legacy|rollback-committed)) (node-[ab])$/\1/p' <<<"$command_text")
role=$(sed -nE 's/.* (--(apply|verify-current|verify-legacy|rollback-committed)) (node-[ab])$/\3/p' <<<"$command_text")
[[ -n "$mode" && -n "$role" ]]
payload_hash=$(sha256sum | awk '{ print $1 }')
printf '%s %s\n' "$mode" "$role" >>"$ACTION31_FAKE_ROOT/calls"
printf '%s\n' "$payload_hash" >>"$ACTION31_FAKE_ROOT/payload-hashes"
if [[ "${ACTION31_FAIL_MATCH:-}" == "$mode $role" ]]; then
    exit 1
fi
token=${role//-/_}
case "$mode" in
    --apply) printf 'action_31_remote_%s_apply_complete=true\n' "$token" ;;
    --verify-current) printf 'action_31_remote_%s_verify_current_complete=true\n' "$token" ;;
    --verify-legacy) printf 'action_31_remote_%s_verify_legacy_complete=true\n' "$token" ;;
    --rollback-committed) printf 'action_31_remote_%s_rollback_committed_complete=true\n' "$token" ;;
esac
FAKE
chmod 0755 "$fake_ssh"

run_outer() {
    local action31_regression_fail_match=${1:-}
    local action31_regression_status=0

    install -m 0600 /dev/null "$fixture_root/outer.stdout"
    install -m 0600 /dev/null "$fixture_root/outer.stderr"
    ACTION31_FAKE_ROOT=$fixture_root \
        ACTION31_FAIL_MATCH=$action31_regression_fail_match \
        CADDY_ACTION31_SSH_BIN=$fake_ssh \
        CADDY_ACTION31_EVIDENCE_ROOT=$fixture_root/evidence \
        CADDY_ACTION31_SKIP_REGRESSION=true \
        /bin/bash "$outer" >"$fixture_root/outer.stdout" \
        2>"$fixture_root/outer.stderr" || action31_regression_status=$?
    printf '%s\n' "$action31_regression_status" >"$fixture_root/outer.status"
}

check transaction_hash test "$(sha256sum "$transaction" | awk '{ print $1 }')" = \
    "$expected_transaction_sha256"
check source_contract source_contract
: >"$fixture_root/calls"
: >"$fixture_root/payload-hashes"
run_outer
check success_status test "$(cat "$fixture_root/outer.status")" -eq 0
check success_complete grep -Fqx 'action_31_outer_complete=true' \
    "$fixture_root/outer.stdout"
check success_order diff -u - "$fixture_root/calls" <<'ORDER'
--apply node-b
--verify-legacy node-a
--apply node-a
--verify-current node-b
--verify-current node-a
ORDER
# shellcheck disable=SC2016
check exact_streamed_transaction awk -v expected="$expected_transaction_sha256" '
    $0 != expected { exit 1 }
    END { exit !(NR == 5) }
' "$fixture_root/payload-hashes"

: >"$fixture_root/calls"
: >"$fixture_root/payload-hashes"
run_outer '--verify-current node-b'
check recovery_status test "$(cat "$fixture_root/outer.status")" -eq 1
check recovery_proven grep -Fqx 'action_31_outer_recovery_proven=true' \
    "$fixture_root/outer.stdout"
check reverse_rollback_order awk '
    /--rollback-committed node-a/ { primary = NR }
    /--rollback-committed node-b/ { standby = NR }
    END { exit !(primary > 0 && standby > primary) }
' "$fixture_root/calls"
check recovery_legacy_both grep -Fxc -- '--verify-legacy node-a' \
    "$fixture_root/calls"
check recovery_legacy_node_b grep -Fxc -- '--verify-legacy node-b' \
    "$fixture_root/calls"

: >"$fixture_root/calls"
: >"$fixture_root/payload-hashes"
run_outer '--apply node-b'
check entrypoint_failure_status test "$(cat "$fixture_root/outer.status")" -eq 1
check entrypoint_failure_rollback grep -Fqx -- '--rollback-committed node-b' \
    "$fixture_root/calls"
check entrypoint_failure_legacy_node_a grep -Fqx -- '--verify-legacy node-a' \
    "$fixture_root/calls"
check entrypoint_failure_legacy_node_b grep -Fqx -- '--verify-legacy node-b' \
    "$fixture_root/calls"

printf '%s_actual_generated_remote_program=true\n' "$prefix"
printf '%s_capture_path_covered=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
