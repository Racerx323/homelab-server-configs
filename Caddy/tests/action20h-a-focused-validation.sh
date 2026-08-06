#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_a_focused
readonly builder_sha256=dd59e60ebc384e25b4d4faabc718cface0044a079413a3954295d39c08ca3e3f
readonly outer_sha256=a0ce95eb0fb355b3ef8ee6e167431b746e6c69b00f31d6b315ee7c631ee38e4c
readonly inspector_sha256=9bef62fec313eb8565abc148d9f6741c8ef2c4ac80c72e1f68a97ea80100b4cf
readonly runner_sha256=728397374d6984a710b7de19f5800d4dca56b7239f5df69b3cc96b53fa860dc5
readonly regression_sha256=1eb5c1dd507bd1081324093e96869ea71789e6e1c2b7722f559f3eacb6641c90

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly builder=$caddy_root/scripts/build-node-a-caddy-health-helper-postinstall-action20h-a.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action20h_a_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20h_a_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20h_a_focused_label" >&2
    return 1
}
generated_sources_exact() {
    local action20h_a_focused_generated_root=$1

    [[ "$(file_hash "$action20h_a_focused_generated_root/scripts/inspect-node-a-caddy-health-helper-postinstall-action20h-a.sh")" = "$inspector_sha256" ]] || return 1
    [[ "$(file_hash "$action20h_a_focused_generated_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a.sh")" = "$runner_sha256" ]] || return 1
    [[ "$(file_hash "$action20h_a_focused_generated_root/tests/action20h-a-postinstall-regression.sh")" = "$regression_sha256" ]] || return 1
}

check builder_hash test "$(file_hash "$builder")" = "$builder_sha256" || exit 1
check outer_hash test "$(file_hash "$outer")" = "$outer_sha256" || exit 1
check builder_mode test "$(stat -c '%a' "$builder")" = 755 || exit 1
check outer_mode test "$(stat -c '%a' "$outer")" = 755 || exit 1
check syntax /bin/bash -n "$builder" "$outer" "$0" || exit 1
check shellcheck shellcheck "$builder" "$outer" "$0" || exit 1
check canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
    "$builder" "$outer" "$0" || exit 1
check collision_policy /bin/bash \
    "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$outer" "$0" || exit 1
check multifile_count_policy /bin/bash \
    "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
    "$builder" "$outer" "$0" || exit 1

work_root=$(mktemp -d /tmp/caddy-action20h-a-focused.XXXXXX)
readonly work_root
trap 'rm -rf -- "$work_root"' EXIT INT TERM
readonly generated_root=$work_root/generated
check builder_execution /bin/bash "$builder" --output "$generated_root" || exit 1
check generated_hashes generated_sources_exact "$generated_root" || exit 1
check inspector_assertions_unique /bin/bash -c \
    'test "$("$1" --expected-assertions | wc -l)" -eq "$("$1" --expected-assertions | LC_ALL=C sort -u | wc -l)"' \
    _ "$generated_root/scripts/inspect-node-a-caddy-health-helper-postinstall-action20h-a.sh" || exit 1
check production_regression /bin/bash \
    "$generated_root/tests/action20h-a-postinstall-regression.sh" || exit 1
check outer_self_test /bin/bash "$outer" --self-test || exit 1
check no_node_b_contract grep -Fq \
    "printf '%s_node_b_contacted=false" "$outer" || exit 1
check no_mutation_contract grep -Fq \
    "printf '%s_persistent_mutations=false" "$outer" || exit 1
printf '%s_complete=true\n' "$prefix"
