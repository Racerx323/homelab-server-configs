#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/local/go/bin:/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_26_h3_retry_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly outer=$caddy_root/scripts/run-workstation-caddy-http3-action26-h3-retry-outer.sh
readonly predecessor=$caddy_root/scripts/run-workstation-caddy-http3-action26-h3-outer.sh
readonly regression=$test_directory/action26-h3-retry-packet-connection-regression.sh
readonly focused=$test_directory/action26-h3-retry-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-validation-action26-h3-retry.yaml
readonly source_root=$caddy_root/tools/http3-probe-v2
readonly outer_sha256=289fd577f78aea2015b162f534b3a6819ba92965a67c579a3b6f6e32bf4d60b2
readonly predecessor_sha256=94e4adc81918fdef056e720d91df1b26bce57154bd65c15b09e7b16b6d553c9a
readonly regression_sha256=24b2f0f1d34d284bb0775865d969350b7090d339d68d368b601e80ed0f7c23b0
readonly manifest_sha256=aca29780b7cd96e8b1ee4360418f9085a3b2cabe9628234e8cd5bc51033ad4b9

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action26_h3_retry_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26_h3_retry_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26_h3_retry_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 26_h3_retry' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    grep -Fq '&quic.Transport{Conn: packetConn}' "$source_root/main.go" || return 1
    grep -Fq 'resources.quicTransport.Close(), resources.packetConn.Close()' \
        "$source_root/main.go" || return 1
    grep -Fq 'TestHistoricalZeroValueTransportPanics' "$source_root/main_test.go" || return 1
    grep -Fq 'TestCorrectedTransportInitializesAndClosesPacketConn' \
        "$source_root/main_test.go" || return 1
    grep -Fq 'exact_probe_count: 2' "$manifest" || return 1
    ! grep -Eq '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' "$outer" "$regression"
}

record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check predecessor_hash test "$(file_hash "$predecessor")" = "$predecessor_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$outer" "$regression" "$0"
record_check shellcheck shellcheck "$outer" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$outer" "$regression" "$0"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
record_check outer_gate_count test "$(/bin/bash "$outer" --expected-local-gates | wc -l)" -eq 18
record_check contract contract_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$outer" "$regression" "$0"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$outer" "$regression" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$outer" "$regression" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
for action26_h3_retry_entrypoint in "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action26_h3_retry_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action26_h3_retry_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_live_protocol_probe=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
