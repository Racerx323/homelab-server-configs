#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
repo_root=$(cd -- "$script_dir/../.." && pwd)
readonly repo_root
readonly ignore_file="$repo_root/.gitignore"

cleanup() {
    # shellcheck disable=SC2317
    if [[ -n "${probe_path:-}" ]]; then
        rm -f -- "$probe_path"
    fi
}
trap cleanup EXIT

[[ -d "$repo_root/.git" ]]
[[ -f "$ignore_file" ]]
[[ "$(grep -Fxc '!/.vscode/' "$ignore_file")" -eq 1 ]]
[[ "$(grep -Fxc '!/.vscode/**' "$ignore_file")" -eq 1 ]]
git -C "$repo_root" ls-files --error-unmatch -- .vscode/mcp.json >/dev/null
if git -C "$repo_root" check-ignore --no-index -q -- .vscode/mcp.json; then
    printf 'vscode_tracking_assertion_tracked_mcp_not_ignored=false\n' >&2
    exit 1
fi
printf 'vscode_tracking_assertion_tracked_mcp_not_ignored=true\n'

probe_path=$(mktemp "$repo_root/.vscode/.tracking-policy-probe.XXXXXX")
readonly probe_path
probe_relative=${probe_path#"$repo_root/"}
readonly probe_relative
if git -C "$repo_root" check-ignore --no-index -q -- "$probe_relative"; then
    printf 'vscode_tracking_assertion_new_vscode_file_not_ignored=false\n' >&2
    exit 1
fi
printf 'vscode_tracking_assertion_new_vscode_file_not_ignored=true\n'

probe_status=$(git -C "$repo_root" status --porcelain=v1 \
    --untracked-files=all -- "$probe_relative")
readonly probe_status
[[ "$probe_status" == "?? $probe_relative" ]]
printf 'vscode_tracking_assertion_new_vscode_file_visible=true\n'

git -C "$repo_root" check-ignore --no-index -q -- \
    .vexp/tracking-policy-positive-control
printf 'vscode_tracking_assertion_vexp_runtime_still_ignored=true\n'

cleanup
trap - EXIT
[[ ! -e "$probe_path" ]]
printf 'vscode_tracking_assertion_probe_cleanup=true\n'
printf 'vscode_tracking_policy_regression_complete=true\n'
