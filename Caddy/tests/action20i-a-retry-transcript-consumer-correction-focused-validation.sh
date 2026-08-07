#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_20i_a_retry_consumer_correction_focused
readonly expected_builder_sha256=d9eece3f68b3962cda15e88b733d29af72e7d7533dc29ac28f0ffcf569593c72
readonly expected_outer_sha256=7d48e4f7ab1b0de37d78ae36c8d8e4724643229cdefa209f1da12e5624cbd772
readonly expected_fixture_sha256=29bf6526fa942e82031669be0e4d9c0e726afd01b909467a7fdc0e2cff289186

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly builder=$caddy_root/scripts/build-action20i-a-retry-transcript-consumer-correction.sh
readonly outer=$caddy_root/scripts/run-action20i-a-retry-transcript-consumer-correction.sh
readonly fixture=$test_directory/fixtures/action20i-a-retry-remote-stdout.txt

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20i_a_consumer_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" \
            "$action20i_a_consumer_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" \
        "$action20i_a_consumer_focused_label" >&2
    return 1
}

record_check builder_hash test "$(file_hash "$builder")" = \
    "$expected_builder_sha256"
record_check outer_hash test "$(file_hash "$outer")" = \
    "$expected_outer_sha256"
record_check fixture_hash test "$(file_hash "$fixture")" = \
    "$expected_fixture_sha256"
record_check fixture_bytes test "$(wc -c <"$fixture")" -eq 7036
record_check fixture_lines test "$(awk 'END { print NR }' "$fixture")" -eq 111
record_check syntax /bin/bash -n "$builder" "$outer" "$0"
record_check shellcheck shellcheck "$builder" "$outer" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" \
    --check "$builder" "$outer" "$0"
record_check collision_policy /bin/bash \
    "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$outer" "$0"
record_check builder_self_test /bin/bash "$builder" --self-test
record_check outer_self_test /bin/bash "$outer" --self-test
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_action_executed=false\n' "$prefix"
printf '%s_persistent_mutations=false\n' "$prefix"
printf '%s_node_b_vrrp_activation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
