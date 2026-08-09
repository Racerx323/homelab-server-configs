#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20p_focused_validation
readonly transaction_sha256=b97d189689e6c6c9f043731c4ae824650c6000b5f609ecb75b7b943cb03bceec
readonly observer_sha256=386032ec1d8f8545e1222acdd81f667a05bd2908a8acc7778f4e5008aa57fc60
readonly outer_sha256=8480382a4b2810d578a6936c2eb0f124f1c7b3ac3b1b608189f19273d5397b4b
readonly regression_sha256=fc8304aa5988e233c9b9bc1b10cc128b6cab2cd33731270840652b3606c0585d

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly transaction=$caddy_root/scripts/activate-node-a-keepalived-dbus-action20p.sh
readonly observer=$caddy_root/scripts/inspect-node-b-node-a-dbus-peer-action20p.sh
readonly outer=$caddy_root/scripts/run-node-a-keepalived-dbus-action20p-outer.sh
readonly regression=$test_directory/action20p-node-a-keepalived-dbus-regression.sh
readonly focused=$test_directory/action20p-focused-validation.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20p_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20p_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20p_focused_label" >&2
    return 1
}

record_check transaction_hash test "$(file_hash "$transaction")" = "$transaction_sha256"
record_check observer_hash test "$(file_hash "$observer")" = "$observer_sha256"
record_check outer_hash test "$(file_hash "$outer")" = "$outer_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check regression /bin/bash "$regression"
record_check syntax /bin/bash -n "$transaction" "$observer" "$outer" "$regression" "$focused"
record_check shellcheck shellcheck "$transaction" "$observer" "$outer" "$regression" "$focused"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$transaction" "$observer" "$outer" "$regression" "$focused"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check root_cwd_policy /bin/bash "$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$outer"
for action20p_focused_entrypoint in "$transaction" "$observer" "$outer" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action20p_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action20p_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_keepalived_reload=false\n' "$prefix"
printf '%s_dbus_runtime_mutation=false\n' "$prefix"
printf '%s_vrrp_transition=false\n' "$prefix"
printf '%s_vip_mutation=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_repository_policies_validated_separately=true\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
