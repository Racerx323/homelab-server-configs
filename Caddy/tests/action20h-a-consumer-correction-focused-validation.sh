#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20h_a_consumer_focused
readonly builder_sha256=25cc3253bfd38721cd962f18214b2c82fc9684b14c28b92a4e1548ab96160021
readonly boundary_sha256=0eac506f0c59f14376b2d0230424db16c65a3bba131cd35e562938464d524f4e
readonly fixture_sha256=3947d0ce3bc2f953a55fb28ebfa9b4b006a47d3ddf530736bc4f9e35e7792757
readonly source_builder_sha256=dd59e60ebc384e25b4d4faabc718cface0044a079413a3954295d39c08ca3e3f
readonly corrected_runner_sha256=7abd7f22819a955462deb423764da334e5892a3431b4b9435bcbb50d7c41710c
readonly corrected_regression_sha256=c11af8e8dce950a6ae234bbfbee8a7cf22291c219a24c5cbe055db1fe0fbadb3

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly builder=$caddy_root/scripts/build-action20h-a-consumer-correction.sh
readonly boundary=$caddy_root/scripts/run-action20h-a-consumer-correction.sh
readonly fixture=$script_directory/fixtures/action20h-a-remote-stdout.txt
readonly source_builder=$caddy_root/scripts/build-node-a-caddy-health-helper-postinstall-action20h-a.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action20h_a_consumer_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20h_a_consumer_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" \
        "$action20h_a_consumer_focused_label" >&2
    return 1
}
corrected_sources_exact() {
    local action20h_a_consumer_focused_generated_root=$1

    [[ "$(file_hash "$action20h_a_consumer_focused_generated_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a-consumer-corrected.sh")" = "$corrected_runner_sha256" ]] || return 1
    [[ "$(file_hash "$action20h_a_consumer_focused_generated_root/tests/action20h-a-consumer-correction-regression.sh")" = "$corrected_regression_sha256" ]] || return 1
}

check builder_hash test "$(file_hash "$builder")" = "$builder_sha256" || exit 1
check boundary_hash test "$(file_hash "$boundary")" = "$boundary_sha256" || exit 1
check fixture_hash test "$(file_hash "$fixture")" = "$fixture_sha256" || exit 1
check fixture_bytes test "$(wc -c <"$fixture")" -eq 6000 || exit 1
check fixture_lines test "$(wc -l <"$fixture")" -eq 104 || exit 1
check source_builder_hash test "$(file_hash "$source_builder")" = \
    "$source_builder_sha256" || exit 1
check builder_mode test "$(stat -c '%a' "$builder")" = 755 || exit 1
check boundary_mode test "$(stat -c '%a' "$boundary")" = 755 || exit 1
check syntax /bin/bash -n "$builder" "$boundary" "$0" || exit 1
check shellcheck shellcheck "$builder" "$boundary" "$0" || exit 1
check canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
    "$builder" "$boundary" "$0" || exit 1
check collision_policy /bin/bash \
    "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$boundary" "$0" || exit 1
check multifile_count_policy /bin/bash \
    "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
    "$builder" "$boundary" "$0" || exit 1

work_root=$(mktemp -d /tmp/caddy-action20h-a-consumer-focused.XXXXXX)
readonly work_root
trap 'rm -rf -- "$work_root"' EXIT INT TERM
readonly source_root=$work_root/source
readonly corrected_root=$work_root/corrected
/bin/bash "$source_builder" --output "$source_root" >/dev/null
/bin/bash "$builder" --output "$corrected_root" >/dev/null
check corrected_sources corrected_sources_exact "$corrected_root" || exit 1
if /bin/bash \
    "$source_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a.sh" \
    --validate-transcript "$fixture" /dev/null 0 >/dev/null 2>&1; then
    printf '%s_check_stale_consumer_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_check_stale_consumer_rejected=true\n' "$prefix"
check corrected_consumer_accepts /bin/bash \
    "$corrected_root/scripts/run-node-a-caddy-health-helper-postinstall-action20h-a-consumer-corrected.sh" \
    --validate-transcript "$fixture" /dev/null 0 || exit 1
check corrected_regression /bin/bash \
    "$corrected_root/tests/action20h-a-consumer-correction-regression.sh" || exit 1
check boundary_self_test /bin/bash "$boundary" --self-test || exit 1
check no_ssh_invocation grep -Fq \
    "printf '%s_ssh_invoked=false" "$boundary" || exit 1
check no_node_contact grep -Fq \
    "printf '%s_node_a_contacted=false" "$boundary" || exit 1
check no_mutation grep -Fq \
    "printf '%s_persistent_mutations=false" "$boundary" || exit 1
printf '%s_complete=true\n' "$prefix"
