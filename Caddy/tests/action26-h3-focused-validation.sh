#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/local/go/bin:/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_26_h3_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly core=$caddy_root/scripts/run-workstation-caddy-http3-action26-h3.sh
readonly outer=$caddy_root/scripts/run-workstation-caddy-http3-action26-h3-outer.sh
readonly predecessor=$caddy_root/scripts/run-workstation-caddy-protocols-action26-retry-outer.sh
readonly regression=$test_directory/action26-h3-http3-evidence-regression.sh
readonly focused=$test_directory/action26-h3-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-validation-action26-h3.yaml
readonly core_sha256=9ba836518103e5142ee41eb12dc33bf9e20a7cfd07f580fe337a863b4192ab6a
readonly outer_sha256=94e4adc81918fdef056e720d91df1b26bce57154bd65c15b09e7b16b6d553c9a
readonly predecessor_sha256=8458f79c24c56f70ab39cd6ad80d99519821227adca272da5f1a618a8a1b0a15
readonly regression_sha256=0228bdb586bdd811fd32ffbba1bdff6bb014890df024d1b9f8c5cf9881cf5e7f
readonly manifest_sha256=923dcadd0904cd62b13205bdcd5b6a41656d856d67b1587b59c0033fa0dd0f0b

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action26_h3_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26_h3_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26_h3_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 26_h3' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    grep -Fq 'per_stream_maximum_bytes: 8192' "$manifest" || return 1
    grep -Fq 'predecessor_observed_stderr_bytes: 2533' "$manifest" || return 1
    grep -Fq 'safe_stream_content_emitted_before_evaluation: true' "$manifest" || return 1
    grep -Fq 'exact_probe_count: 2' "$manifest" || return 1
    grep -Fq 'action26_h3_observed_failure_bytes" -gt 2533' "$regression" || return 1
    ! grep -Eq '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' "$core" "$outer" "$regression"
}

record_check core_hash test "$(file_hash "$core")" = "$core_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check predecessor_hash test "$(file_hash "$predecessor")" = "$predecessor_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$core" "$outer" "$regression" "$0"
record_check shellcheck shellcheck "$core" "$outer" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$core" "$outer" "$regression" "$0"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
record_check core_check_count test "$(/bin/bash "$core" --expected-checks | wc -l)" -eq 25
record_check outer_gate_count test "$(/bin/bash "$outer" --expected-local-gates | wc -l)" -eq 21
record_check contract contract_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$core" "$outer" "$regression" "$0"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$core" "$outer" "$regression" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$core" "$outer" "$regression" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
for action26_h3_entrypoint in "$core" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action26_h3_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action26_h3_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_live_protocol_probe=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
