#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-final-deployment-action29.sh
readonly outer=$caddy_root/scripts/run-final-deployment-acceptance-action29-outer.sh
readonly regression=$test_directory/action29-final-deployment-acceptance-regression.sh
readonly manifest=$caddy_root/manifests/caddy-final-deployment-acceptance-action29.yaml

/bin/bash -n "$inspector" "$outer" "$regression"
/bin/bash "$regression"
shellcheck "$inspector" "$outer" "$regression"
/bin/bash "$test_directory/shfmt-canonical.sh" --check "$inspector" "$outer" "$regression"
/bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$inspector" "$outer" "$regression"
/bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
/bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$inspector" "$outer" "$regression"
/bin/bash "$test_directory/portable-awk-policy.sh" --check "$inspector" "$outer" "$regression"
/bin/bash "$test_directory/remote-streamed-bash-cwd-precommit.sh" "$outer"
/bin/bash "$test_directory/ssh-stream-local-evidence-policy.sh" --check "$outer"
/bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
/bin/bash "$test_directory/executable-wrapper-policy-regression.sh"
if command -v yamllint >/dev/null 2>&1; then
    yamllint -s "$manifest"
    printf 'action_29_focused_yaml_validation=passed\n'
else
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
    printf 'action_29_focused_yaml_validation=host_authoritative\n'
fi
/bin/bash "$outer" --self-test
printf 'action_29_focused_validation_complete=true\n'
