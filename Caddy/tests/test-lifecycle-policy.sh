#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=test_lifecycle_policy
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly registry=${CADDY_TEST_LIFECYCLE_REGISTRY:-$test_directory/test-lifecycle.tsv}

record_check() {
    local test_lifecycle_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$test_lifecycle_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$test_lifecycle_label" >&2
    return 1
}

registry_schema_valid() {
    # conditional-validator-explicit-failures-begin
    [[ -f "$registry" && ! -L "$registry" ]] || return 1
    [[ "$(sed -n '1p' "$registry")" = $'path\tlifecycle\texecution_scope\trationale' ]] || return 1
    awk -F '\t' '
        NR == 1 { next }
        NF != 4 { exit 1 }
        $1 !~ /^Caddy\/tests\/[A-Za-z0-9._\/-]+$/ { exit 1 }
        $2 !~ /^(production-current|historical-preserved|test-fixture)$/ { exit 1 }
        $3 !~ /^(current-focused|historical-opt-in|support)$/ { exit 1 }
        $4 == "" { exit 1 }
        seen[$1]++ { exit 1 }
        END { exit !(NR > 1) }
    ' "$registry" || return 1
    # conditional-validator-explicit-failures-end
}

inventory_complete() {
    local test_lifecycle_expected=$work_root/expected
    local test_lifecycle_observed=$work_root/observed

    git -C "$repository_root" ls-files Caddy/tests |
        LC_ALL=C sort -u >"$test_lifecycle_expected" || return 1
    awk -F '\t' 'NR > 1 { print $1 }' "$registry" |
        LC_ALL=C sort >"$test_lifecycle_observed" || return 1
    cmp -s "$test_lifecycle_expected" "$test_lifecycle_observed"
}

classification_valid() {
    # conditional-validator-explicit-failures-begin
    awk -F '\t' '
        NR == 1 { next }
        $1 ~ /^Caddy\/tests\/action.*[.]sh$/ && $2 != "historical-preserved" { exit 1 }
        ($1 == "Caddy/tests/run.sh" || $1 == "Caddy/tests/integration.sh") &&
            ($2 != "historical-preserved" || $3 != "historical-opt-in") { exit 1 }
        $1 ~ /^Caddy\/tests\/fixtures\// && $2 != "test-fixture" { exit 1 }
        $2 == "production-current" && $3 == "historical-opt-in" { exit 1 }
        $2 == "historical-preserved" && $3 != "historical-opt-in" { exit 1 }
    ' "$registry" || return 1
    # conditional-validator-explicit-failures-end
}

work_root=$(mktemp -d /tmp/caddy-test-lifecycle-policy.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM

case "${1:-}" in
    --check)
        [[ $# -eq 1 ]] || exit 64
        record_check schema registry_schema_valid || exit 1
        record_check inventory inventory_complete || exit 1
        record_check classification classification_valid || exit 1
        printf '%s_complete=true\n' "$prefix"
        ;;
    *)
        printf 'Usage: %s --check\n' "${0##*/}" >&2
        exit 64
        ;;
esac
