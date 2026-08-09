#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_23a_a_consumer_focused
readonly runner_sha256=d7ca02d4475c5d28524242d029d0ced32036b134b887fc7efafab927360edadc
readonly regression_sha256=b5dfa8bb92cc8c1c776ab35648de3b17babf86282ee6c42e12c7797d8af36f15
readonly inspector_sha256=f348010dc1de51317cf49047ef52cfc2122a5f3c0624ea848c2be22e6cf4399b
readonly outer_sha256=25c4f430edd1bb0fee0ff636e14a6844dd2fe80a12f57643a0d1bd368f34a50e

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly runner=$caddy_root/scripts/run-action23a-a-transcript-consumer-correction.sh
readonly regression=$test_directory/action23a-a-transcript-consumer-correction-regression.sh
readonly focused=$test_directory/action23a-a-transcript-consumer-correction-focused-validation.sh
readonly inspector=$caddy_root/scripts/inspect-node-b-unbound-a-records-post-action23a-a.sh
readonly outer=$caddy_root/scripts/run-node-b-unbound-a-records-post-action23a-a-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action23aa_consumer_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action23aa_consumer_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action23aa_consumer_focused_label" >&2
    return 1
}
no_node_transport() {
    ! grep -Eq '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' "$runner" "$regression"
}

record_check runner_hash test "$(file_hash "$runner")" = "$runner_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check inspector_immutable test "$(file_hash "$inspector")" = "$inspector_sha256"
record_check outer_immutable test "$(file_hash "$outer")" = "$outer_sha256"
record_check syntax /bin/bash -n "$runner" "$regression" "$focused"
record_check shellcheck shellcheck "$runner" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$runner" "$regression" "$focused"
record_check no_node_transport no_node_transport
record_check regression /bin/bash "$regression"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$runner" "$regression" "$focused"
record_check conditional_policy /bin/bash \
    "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash \
    "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$runner" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$runner" "$regression" "$focused"
record_check transcript_contract_policy /bin/bash \
    "$test_directory/transcript-contract-ratchet-policy-regression.sh"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check

for action23aa_consumer_focused_entrypoint in "$runner" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action23aa_consumer_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action23aa_consumer_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_23a_rerun=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_filesystem_mutation=false\n' "$prefix"
printf '%s_service_mutation=false\n' "$prefix"
printf '%s_dns_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
