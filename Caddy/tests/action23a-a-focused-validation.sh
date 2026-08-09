#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_23a_a_focused_validation
readonly inspector_sha256=f348010dc1de51317cf49047ef52cfc2122a5f3c0624ea848c2be22e6cf4399b
readonly outer_sha256=25c4f430edd1bb0fee0ff636e14a6844dd2fe80a12f57643a0d1bd368f34a50e
readonly regression_sha256=8b0b40d9a9e4c6094a990b5dcbdeca0bd4299a3850ae6f0e4b0f58622219f60b

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-node-b-unbound-a-records-post-action23a-a.sh
readonly outer=$caddy_root/scripts/run-node-b-unbound-a-records-post-action23a-a-outer.sh
readonly regression=$test_directory/action23a-a-node-b-unbound-postinstall-regression.sh
readonly focused=$test_directory/action23a-a-focused-validation.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action23aa_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action23aa_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23aa_focused_label" >&2
    return 1
}
read_only_contract() {
    ! grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)|unbound-control[[:space:]]+reload|pihole[[:space:]]+restartdns|(^|[[:space:]])(install|mv|rm)[[:space:]]' \
        "$inspector"
}

record_check inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check syntax /bin/bash -n "$inspector" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$inspector" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check inspector_self_test /bin/bash "$inspector" --self-test
record_check expected_checks_nonempty test \
    "$(/bin/bash "$inspector" --expected-checks | wc -l)" -gt 0
record_check expected_checks_unique test \
    "$(/bin/bash "$inspector" --expected-checks | wc -l)" -eq \
    "$(/bin/bash "$inspector" --expected-checks | LC_ALL=C sort -u | wc -l)"
record_check contract_transcript /bin/bash "$inspector" --contract-transcript
record_check read_only_contract read_only_contract
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$inspector" "$outer" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash \
    "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$inspector" "$outer" "$regression" "$focused"
record_check remote_cwd_policy /bin/bash \
    "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
record_check transcript_contract_policy /bin/bash \
    "$test_directory/transcript-contract-ratchet-policy-regression.sh"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash \
    "$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"

for action23aa_focused_entrypoint in "$inspector" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action23aa_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action23aa_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_23a_rerun=false\n' "$prefix"
printf '%s_filesystem_mutation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_dns_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
