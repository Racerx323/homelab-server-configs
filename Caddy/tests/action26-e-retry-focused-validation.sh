#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_e_retry_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly source_inspector=$caddy_root/scripts/inspect-workstation-wsl-mirrored-postrestart-action26-d.sh
readonly adapter=$caddy_root/scripts/run-workstation-wsl-mirrored-postrestart-action26-e-retry.sh
readonly validator=$caddy_root/scripts/run-workstation-wsl-mirrored-postrestart-action26-e-outer.sh
readonly outer=$caddy_root/scripts/run-workstation-wsl-mirrored-postrestart-action26-e-retry-outer.sh
readonly regression=$test_directory/action26-e-retry-postrestart-regression.sh
readonly focused=$test_directory/action26-e-retry-focused-validation.sh
readonly manifest=$caddy_root/manifests/wsl-ipv6-integration-action26-e-retry.yaml
readonly source_sha256=c28daa30a7b127d8d6b4ca9e669564350367695e8be4986112b4478d37d23a1d
readonly adapter_sha256=e495dc337390b6861d5077d7b043a4887d6819e3f05106a576efb5180bb6663e
readonly validator_sha256=d5ecf40a30450962ef7ce79f4cce02331f53a4c924650518208808adf86b8133
readonly outer_sha256=b2f313b4713c9af2c668d21130642838522d6e921fb959387d93ab50191f0270
readonly regression_sha256=6de59bd6f99ddc8a828636ca69f462395e051130ab2fef37d1bb039c7b06a554
readonly manifest_sha256=373b825a2393dcbb4d21854a38c802e2563b2abf282a5682c7a3952950ed662b

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action26e_retry_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26e_retry_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26e_retry_focused_label" >&2
    return 1
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 26e_retry' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    grep -Fq 'sha256: 04d050670b39c4febb632de69e144a7c3f979c168fe8f326832b1af932300435' \
        "$manifest" || return 1
    grep -Fq 'generated_sha256: a8684d98d63282540e003e344694f80f41230943136b5174d838e940f5c16b30' \
        "$manifest" || return 1
    grep -Fq 'wsl_shutdown: false' "$manifest" || return 1
    ! grep -Eq 'wsl(\.exe)?[[:space:]]+--shutdown|Invoke-WorkstationWslMirroredActivationAction26d' \
        "$adapter" "$outer" "$regression" || return 1
    ! grep -Eq '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' \
        "$adapter" "$outer" "$regression"
}
no_live_execution_path() {
    ! grep -Eq '^[[:space:]]*(wslinfo|ip|dig|curl)[[:space:]]' "$0"
}

record_check source_hash test "$(file_hash "$source_inspector")" = "$source_sha256"
record_check adapter_hash test "$(file_hash "$adapter")" = "$adapter_sha256"
record_check validator_hash test "$(file_hash "$validator")" = "$validator_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$source_inspector" "$adapter" "$validator" "$outer" "$regression" "$0"
record_check shellcheck shellcheck "$adapter" "$outer" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$adapter" "$outer" "$regression" "$0"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
record_check adapter_check_count test "$(/bin/bash "$adapter" --expected-checks | wc -l)" -eq 6
record_check outer_gate_count test "$(/bin/bash "$outer" --expected-local-gates | wc -l)" -eq 19
record_check contract contract_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$adapter" "$outer" "$regression" "$0"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$adapter" "$outer" "$regression" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$adapter" "$outer" "$regression" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check outer_gate_policy /bin/bash "$test_directory/outer-local-gate-label-policy-regression.sh" \
    --runner "$outer"
record_check no_live_execution_path no_live_execution_path
for action26e_retry_entrypoint in "$adapter" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action26e_retry_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action26e_retry_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_wsl_shutdown=false\n' "$prefix"
printf '%s_live_network_probe=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
