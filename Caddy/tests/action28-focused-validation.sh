#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly driver=$caddy_root/scripts/transfer-node-a-release-to-node-b-action28.sh
readonly inspector=$caddy_root/scripts/inspect-node-b-incoming-release-action28.sh
readonly runner=$caddy_root/scripts/run-node-a-to-node-b-release-transfer-action28.sh
readonly outer=$caddy_root/scripts/run-node-a-to-node-b-release-transfer-action28-outer.sh
readonly regression=$test_directory/action28-node-a-to-node-b-release-transfer-regression.sh
readonly focused=$test_directory/action28-focused-validation.sh
readonly manifest=$caddy_root/manifests/protocol-v2-a-to-b-action28.yaml
readonly driver_sha256=25d62e26123ff2fc468db5cba92aeb9cd54befe69c51f9c48ba3586407182234
readonly inspector_sha256=026766ca4085b5a696be3f0f14f9d74321f4d27b2aa33db1aced86689702f34a
readonly runner_sha256=0e0399f47f9941d30ee86ffbdf48e10692a4e84593adae53599d30b2db53d495
readonly regression_sha256=53318a12afd2d4695e523d59b8bbe1896668366a43112abca616996636b56945
readonly outer_sha256=1eb4691c631e58893fad47b04d01738a8ed545c3dc8453a3479196a7e0fd3b74
readonly manifest_sha256=77bcb17af9b9e4e27af7946881c0dd0b1b1eaa32b33273d2d913103518192cab

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

record_check() {
    local action28_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28_focused_label" >&2
    return 1
}

contract_check() {
    grep -Fq 'readonly publisher=/usr/local/libexec/publish-release-v2.sh' \
        "$driver" || return 1
    grep -Fq 'record_command publisher_hash_exact' "$driver" || return 1
    grep -Fq 'record_command vrrp_state_master' "$driver" || return 1
    grep -Fq 'record_historical_continuity' "$inspector" || return 1
    grep -Fq 'remote_delete_executed=false' "$driver" "$runner" || return 1
    if grep -Fq -- '--emergency' "$driver"; then
        return 1
    fi
    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
        "$driver" "$inspector" "$runner"; then
        return 1
    fi
}

yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 28' "$manifest" || return 1
    grep -Fqx 'status: defined_not_executed' "$manifest"
}

record_check driver_hash test "$(file_hash "$driver")" = "$driver_sha256"
record_check inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256"
record_check runner_hash test "$(file_hash "$runner")" = "$runner_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check syntax /bin/bash -n "$driver" "$inspector" "$runner" "$outer" \
    "$regression" "$focused"
record_check shellcheck shellcheck "$driver" "$inspector" "$runner" "$outer" \
    "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$driver" "$inspector" "$runner" "$outer" "$regression" "$focused"
record_check yaml yaml_check
record_check regression /bin/bash "$regression"
record_check outer_self_test /bin/bash "$outer" --self-test
record_check outer_contract_test /bin/bash "$outer" --contract-test
record_check contract contract_check
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$driver" "$inspector" "$runner" "$outer" "$regression" "$focused"
record_check scalar_grep_policy /bin/bash \
    "$test_directory/multifile-grep-count-policy.sh" --check \
    "$driver" "$inspector" "$runner" "$outer" "$regression" "$focused"
record_check portable_awk_policy /bin/bash \
    "$test_directory/portable-awk-policy.sh" --check \
    "$driver" "$inspector" "$runner" "$outer" "$regression" "$focused"
record_check accepted_live_hash_policy /bin/bash \
    "$test_directory/accepted-live-hash-policy.sh" --check

for action28_focused_entrypoint in "$driver" "$inspector" "$runner" "$outer" \
    "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action28_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- \
            "Caddy/${action28_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = \
        100755
done

printf '%s_node_contact=false\n' "$prefix"
printf '%s_publisher_invocation=false\n' "$prefix"
printf '%s_release_transfer=false\n' "$prefix"
printf '%s_finalizer_invocation=false\n' "$prefix"
printf '%s_persistent_mutation=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
