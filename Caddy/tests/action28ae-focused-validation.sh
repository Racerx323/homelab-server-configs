#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly -a shell_files=(
    "$caddy_root/scripts/transact-coupled-go-live-action28ae.sh"
    "$caddy_root/scripts/run-dual-node-coupled-go-live-action28ae-outer.sh"
    "$caddy_root/scripts/publish-release-v2.sh"
    "$caddy_root/scripts/reconcile-release-v2.sh"
    "$caddy_root/scripts/finalize-incoming-release-v2-stderr-safe-trigger-action28ac.sh"
    "$script_directory/action28ae-coupled-go-live-regression.sh"
    "$script_directory/action28ac-lsyncd-command-regression.sh"
    "$script_directory/action28ac-reconciliation-transaction-regression.sh"
    "$script_directory/action28ac-stderr-safe-finalizer-trigger-regression.sh"
    "$script_directory/conditional-validator-errexit-policy-regression.sh"
    "${BASH_SOURCE[0]}"
)

/bin/bash -n "${shell_files[@]}"
shellcheck "${shell_files[@]}"
/bin/bash "$script_directory/shfmt-canonical.sh" --check "${shell_files[@]}"
/bin/bash "$script_directory/check-shell-readonly-local-collisions-v2.sh" \
    "${shell_files[@]}"
/bin/bash "$script_directory/conditional-validator-errexit-policy-regression.sh"
/bin/bash "$script_directory/multifile-grep-count-policy.sh" --check \
    "${shell_files[@]}"
/bin/bash "$script_directory/portable-awk-policy.sh" --check \
    "${shell_files[@]}"
/bin/bash "$script_directory/remote-streamed-bash-cwd-precommit.sh" \
    "$caddy_root/scripts/run-dual-node-coupled-go-live-action28ae-outer.sh"
/bin/bash "$script_directory/ssh-stream-local-evidence-policy.sh" --check \
    "$caddy_root/scripts/run-dual-node-coupled-go-live-action28ae-outer.sh"
/bin/bash "$script_directory/action28ae-coupled-go-live-regression.sh"
/bin/bash "$script_directory/action28ac-lsyncd-command-regression.sh"
/bin/bash "$script_directory/action28ac-reconciliation-transaction-regression.sh"
/bin/bash "$script_directory/action28ac-stderr-safe-finalizer-trigger-regression.sh"
/bin/bash "$script_directory/receiver-finalization-protocol-v2-regression.sh"
if command -v yamllint >/dev/null 2>&1; then
    yamllint -s "$caddy_root/manifests/caddy-coupled-go-live-action28ae.yaml"
    printf 'action_28ae_focused_yaml_validation=passed\n'
else
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
    printf 'action_28ae_focused_yaml_validation=host_authoritative\n'
fi
printf 'action_28ae_focused_validation_complete=true\n'
