#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly builder=$caddy_root/scripts/build-node-a-to-node-b-retained-release-action28g.sh
readonly source_runner=$caddy_root/scripts/run-node-a-to-node-b-retained-release-action28f.sh
readonly driver=$caddy_root/scripts/transfer-retained-node-a-release-action28f.sh
readonly inspector=$caddy_root/scripts/inspect-node-b-incoming-release-action28f.sh
readonly outer=$caddy_root/scripts/run-node-a-to-node-b-retained-release-action28g-outer.sh
readonly regression=$test_directory/action28g-phase-specific-identity-regression.sh

/bin/bash -n "$builder" "$source_runner" "$driver" "$inspector" "$outer" "$regression" "$0"
shellcheck "$builder" "$source_runner" "$driver" "$inspector" "$outer" "$regression" "$0"
"$test_directory/shfmt-canonical.sh" --check \
    "$builder" "$source_runner" "$driver" "$inspector" "$outer" "$regression" "$0"
"$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$builder" "$source_runner" "$driver" "$inspector" "$outer" "$regression" "$0"
"$test_directory/multifile-grep-count-policy.sh" --check \
    "$builder" "$source_runner" "$driver" "$inspector" "$outer" "$regression" "$0"
"$test_directory/portable-awk-policy.sh" --check \
    "$builder" "$source_runner" "$driver" "$inspector" "$outer" "$regression" "$0"
"$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
/bin/bash "$regression"
/bin/bash "$outer" --self-test
printf 'action_28g_focused_validation_complete=true\n'
