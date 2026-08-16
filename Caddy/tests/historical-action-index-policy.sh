#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=historical_action_index_policy
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly manifest=${CADDY_HISTORICAL_ACTION_MANIFEST:-$test_directory/historical-actions.yaml}

record_check() {
    local historical_index_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$historical_index_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$historical_index_label" >&2
    return 1
}

regular_file() {
    local historical_index_path=$1

    [[ -f "$historical_index_path" && ! -L "$historical_index_path" ]]
}

schema_valid() {
    jq -e '
        .schema_version == 1 and
        .historical_suite.default_selected == false and
        (.historical_suite.host_entrypoint == "Caddy/tests/run.sh") and
        (.historical_suite.container_entrypoint == "Caddy/tests/integration.sh") and
        (.actions | type == "array" and length > 0) and
        ([.actions[].id] | length == (unique | length)) and
        ([.actions[].focused_test] | length == (unique | length)) and
        all(.actions[];
            (.id | test("^action[0-9][a-z0-9-]*$")) and
            (.lifecycle == "accepted-executed" or .lifecycle == "historical-preserved") and
            (.focused_test | test("^Caddy/tests/action.*-focused-validation\\.sh$")) and
            (.host_tests == [.focused_test]) and
            (.debian_tests == [.focused_test]) and
            (.policies == []))
    ' "$manifest" >/dev/null
}

paths_safe() {
    local historical_index_relative
    local historical_index_path

    while IFS= read -r historical_index_relative; do
        [[ "$historical_index_relative" =~ ^Caddy/tests/action[A-Za-z0-9._/-]+\.sh$ ]] || return 1
        [[ "$historical_index_relative" != *..* ]] || return 1
        historical_index_path=$repository_root/$historical_index_relative
        regular_file "$historical_index_path" || return 1
        [[ -x "$historical_index_path" ]] || return 1
        [[ "$(git -C "$repository_root" ls-files -s -- "$historical_index_relative" | awk '{ print $1 }')" = 100755 ]] || return 1
    done < <(jq -r '.actions[].focused_test' "$manifest")
}

inventory_complete() {
    local historical_index_expected=$work_root/expected
    local historical_index_observed=$work_root/observed

    git -C "$repository_root" ls-files \
        'Caddy/tests/action*-focused-validation.sh' | LC_ALL=C sort \
        >"$historical_index_expected" || return 1
    jq -r '.actions[].focused_test' "$manifest" | LC_ALL=C sort \
        >"$historical_index_observed" || return 1
    cmp -s "$historical_index_expected" "$historical_index_observed"
}

work_root=$(mktemp -d /tmp/caddy-historical-action-index.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM

case "${1:-}" in
    --check)
        [[ $# -eq 1 ]] || exit 64
        record_check manifest_regular regular_file "$manifest" || exit 1
        record_check manifest_json jq empty "$manifest" || exit 1
        record_check schema schema_valid || exit 1
        record_check paths paths_safe || exit 1
        record_check inventory inventory_complete || exit 1
        printf '%s_complete=true\n' "$prefix"
        ;;
    *)
        printf 'Usage: %s --check\n' "${0##*/}" >&2
        exit 64
        ;;
esac
