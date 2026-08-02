#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
server_repository=$(cd -- "$script_directory/../.." && pwd)
readonly server_repository

validate_executable_mode_contract() {
    local contract_path=$1
    local working_tree_executable=$2
    local index_mode=$3

    if [[ "$working_tree_executable" != 1 ]]; then
        printf 'executable_policy_assertion_working_tree_executable=false path=%s\n' \
            "$contract_path" >&2
        return 1
    fi
    if [[ "$index_mode" != 100755 ]]; then
        printf 'executable_policy_assertion_index_mode=false path=%s observed=%s expected=100755\n' \
            "$contract_path" "$index_mode" >&2
        return 1
    fi
}

if ! validate_executable_mode_contract fixture-valid 1 100755 >/dev/null; then
    printf 'executable_policy_regression_valid_fixture=false\n' >&2
    exit 1
fi
if validate_executable_mode_contract fixture-index-mode-0644 1 100644 \
    >/dev/null 2>&1; then
    printf 'executable_policy_regression_index_mode_false_negative=true\n' >&2
    exit 1
fi
if validate_executable_mode_contract fixture-working-tree-mode-0644 0 100755 \
    >/dev/null 2>&1; then
    printf 'executable_policy_regression_working_tree_false_negative=true\n' >&2
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    printf 'executable_policy_assertion_git_available=false\n' >&2
    exit 1
fi
if ! git -C "$server_repository" rev-parse --is-inside-work-tree \
    >/dev/null 2>&1; then
    printf 'executable_policy_assertion_repository_context=false\n' >&2
    exit 1
fi

mapfile -d '' tracked_shell_entrypoints < <(
    git -C "$server_repository" ls-files -z -- \
        'Caddy/scripts/*.sh' \
        'Caddy/tests/*.sh'
)
if ((${#tracked_shell_entrypoints[@]} == 0)); then
    printf 'executable_policy_assertion_tracked_entrypoints_present=false\n' >&2
    exit 1
fi

validated_entrypoint_count=0
for tracked_shell_entrypoint in "${tracked_shell_entrypoints[@]}"; do
    absolute_entrypoint="$server_repository/$tracked_shell_entrypoint"
    if [[ ! -f "$absolute_entrypoint" ]]; then
        printf 'executable_policy_assertion_regular_file=false path=%s\n' \
            "$tracked_shell_entrypoint" >&2
        exit 1
    fi
    if [[ -L "$absolute_entrypoint" ]]; then
        printf 'executable_policy_assertion_not_symlink=false path=%s\n' \
            "$tracked_shell_entrypoint" >&2
        exit 1
    fi
    if [[ $(head -n 1 -- "$absolute_entrypoint") != '#!/usr/bin/env bash' ]]; then
        printf 'executable_policy_assertion_bash_shebang=false path=%s\n' \
            "$tracked_shell_entrypoint" >&2
        exit 1
    fi

    working_tree_executable=0
    if [[ -x "$absolute_entrypoint" ]]; then
        working_tree_executable=1
    fi
    index_mode=$(
        git -C "$server_repository" ls-files --stage -- \
            "$tracked_shell_entrypoint" |
            awk 'NR == 1 { print $1 }'
    )
    if ! validate_executable_mode_contract \
        "$tracked_shell_entrypoint" \
        "$working_tree_executable" \
        "$index_mode"; then
        exit 1
    fi
    ((validated_entrypoint_count += 1))
done

printf 'executable_policy_regression_valid_fixture=true\n'
printf 'executable_policy_regression_index_mode_0644_rejected=true\n'
printf 'executable_policy_regression_working_tree_mode_0644_rejected=true\n'
printf 'executable_policy_validated_entrypoint_count=%s\n' \
    "$validated_entrypoint_count"
printf 'executable_wrapper_policy_regression_complete=true\n'
