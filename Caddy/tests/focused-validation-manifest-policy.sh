#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=focused_validation_manifest_policy
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly manifest=${CADDY_FOCUSED_VALIDATION_MANIFEST:-$test_directory/focused-validation.yaml}

record_check() {
    local focused_manifest_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$focused_manifest_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$focused_manifest_label" >&2
    return 1
}

regular_file() {
    local focused_manifest_path=$1

    [[ -f "$focused_manifest_path" && ! -L "$focused_manifest_path" ]]
}

executable_file() {
    local focused_manifest_relative=$1
    local focused_manifest_path=$repository_root/$focused_manifest_relative

    regular_file "$focused_manifest_path" || return 1
    [[ -x "$focused_manifest_path" ]] || return 1
    [[ "$(git -C "$repository_root" ls-files -s -- "$focused_manifest_relative" | awk '{ print $1 }')" = 100755 ]]
}

schema_valid() {
    jq -e '
        .schema_version == 3 and
        .historical_actions_manifest == "Caddy/tests/historical-actions.yaml" and
        (.policy_ids | type == "array" and length > 0 and length == (unique | length)) and
        (.profiles | type == "object" and length > 0) and
        (has("actions") | not) and
        (has("historical_suite") | not) and
        all(.profiles[];
            (.description | type == "string" and length > 0) and
            (.path_patterns | type == "array" and length > 0 and length == (unique | length)) and
            (.debian_path_patterns | type == "array" and length == (unique | length)) and
            (.shell_files | type == "array" and length == (unique | length)) and
            (.host_tests | type == "array" and length == (unique | length)) and
            (.debian_tests | type == "array" and length == (unique | length)) and
            (.policies | type == "array" and length == (unique | length)) and
            all(.policies[];
                . == "selected-shell" or
                . == "accepted-live-hashes" or
                . == "conditional-validator" or
                . == "executable-modes" or
                . == "remote-cwd" or
                . == "ssh-evidence" or
                . == "systemd-boot" or
                . == "template-lifecycle" or
                . == "deployment-lifecycle" or
                . == "deployable-successor" or
                . == "environment-v2" or
                . == "historical-action-index" or
                . == "test-lifecycle"))
    ' "$manifest" >/dev/null
}

paths_safe() {
    local focused_manifest_relative

    while IFS= read -r focused_manifest_relative; do
        [[ "$focused_manifest_relative" =~ ^Caddy/(scripts|tests)/[A-Za-z0-9._/-]+\.sh$ ]] || return 1
        [[ "$focused_manifest_relative" != *..* ]] || return 1
        executable_file "$focused_manifest_relative" || return 1
    done < <(
        jq -r '
            [.profiles[].shell_files[], .profiles[].host_tests[],
             .profiles[].debian_tests[]] | unique[]
        ' "$manifest"
    )
}

no_hash_duplication() {
    ! grep -Eq '[0-9a-f]{64}' "$manifest"
}

current_profiles_exclude_action_tests() {
    ! jq -e '
        [.profiles[].host_tests[], .profiles[].debian_tests[]] |
        any(test("(^|/)[^/]*action[0-9]"))
    ' "$manifest" >/dev/null
}

work_root=$(mktemp -d /tmp/caddy-focused-manifest-policy.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM

case "${1:-}" in
    --check)
        [[ $# -eq 1 ]] || exit 64
        record_check manifest_regular regular_file "$manifest" || exit 1
        record_check manifest_json_yaml jq empty "$manifest" || exit 1
        record_check schema schema_valid || exit 1
        record_check paths paths_safe || exit 1
        record_check no_hash_duplication no_hash_duplication || exit 1
        record_check current_profiles_exclude_action_tests \
            current_profiles_exclude_action_tests || exit 1
        printf '%s_complete=true\n' "$prefix"
        ;;
    *)
        printf 'Usage: %s --check\n' "${0##*/}" >&2
        exit 64
        ;;
esac
