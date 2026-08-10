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
readonly driver=$caddy_root/scripts/transfer-retained-node-a-release-action28f.sh
readonly inspector=$caddy_root/scripts/inspect-node-b-incoming-release-action28f.sh
readonly runner=$caddy_root/scripts/run-node-a-to-node-b-retained-release-action28f.sh
readonly outer=$caddy_root/scripts/run-node-a-to-node-b-retained-release-action28f-outer.sh
readonly regression=$test_directory/action28f-retained-release-transfer-regression.sh

/bin/bash -n "$driver" "$inspector" "$runner" "$outer" "$regression" "$0"
shellcheck "$driver" "$inspector" "$runner" "$outer" "$regression" "$0"
"$test_directory/shfmt-canonical.sh" --check \
    "$driver" "$inspector" "$runner" "$outer" "$regression" "$0"
"$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$driver" "$inspector" "$runner" "$outer" "$regression" "$0"
"$test_directory/multifile-grep-count-policy.sh" --check \
    "$driver" "$inspector" "$runner" "$outer" "$regression" "$0"
"$test_directory/portable-awk-policy.sh" --check \
    "$driver" "$inspector" "$runner" "$outer" "$regression" "$0"
"$test_directory/remote-streamed-bash-cwd-policy.sh" --check "$runner"
"$test_directory/outer-local-gate-label-policy-regression.sh" --runner "$outer"
/bin/bash "$regression"
printf 'action_28f_focused_validation_complete=true\n'
