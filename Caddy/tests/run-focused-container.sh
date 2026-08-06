#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=focused_container_wrapper
readonly validation_image=localhost/caddy-ha-validation:latest

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly workspace_root=${repository_root%/homelab-server-configs}
readonly containerfile="$test_directory/Containerfile"

record_gate() {
    local gate_label=$1

    shift
    if "$@"; then
        printf '%s_gate_%s=true\n' "$prefix" "$gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$gate_label" >&2
    return 1
}
source_contract() {
    grep -Fqx 'ENTRYPOINT ["/bin/bash"]' "$containerfile" || return 1
    grep -Fq -- '--network none' "$0" || return 1
    grep -Fq -- '--env CADDY_VALIDATION_CONTAINER=1' "$0" || return 1
    # These patterns intentionally match literal wrapper source.
    # shellcheck disable=SC2016
    grep -Fq -- '"$workspace_root:/workspace:ro"' "$0" || return 1
    grep -Fq -- "'$1'" "$0" || return 1
    # shellcheck disable=SC2016
    grep -Fq 'exec /bin/bash "$1"' "$0" || return 1
    # shellcheck disable=SC2016
    ! grep -Eq '"\$validation_image"[[:space:]]+/bin/bash' "$0" || return 1
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        record_gate container_entrypoint_exact grep -Fqx \
            'ENTRYPOINT ["/bin/bash"]' "$containerfile"
        # The child Bash expands its positional parameter.
        # shellcheck disable=SC2016
        record_gate wrapper_source_contract source_contract \
            'cd /workspace/homelab-server-configs && exec /bin/bash "$1"'
        printf '%s_self_test_complete=true\n' "$prefix"
        exit 0
        ;;
    "")
        printf 'Usage: %s TEST_SCRIPT\n' "${0##*/}" >&2
        exit 64
        ;;
esac

[[ $# -eq 1 ]] || {
    printf 'Usage: %s TEST_SCRIPT\n' "${0##*/}" >&2
    exit 64
}
requested_script=$1
readonly requested_script
[[ "$requested_script" != /* ]] || {
    printf 'TEST_SCRIPT must be repository-relative.\n' >&2
    exit 64
}
resolved_script=$(realpath -e -- "$repository_root/$requested_script")
readonly resolved_script
case "$resolved_script" in
    "$test_directory"/*.sh) ;;
    *)
        printf 'TEST_SCRIPT must be a regular Caddy/tests shell entry point.\n' >&2
        exit 64
        ;;
esac
[[ -f "$resolved_script" && ! -L "$repository_root/$requested_script" ]] || exit 64
relative_script=${resolved_script#"$repository_root"/}
readonly relative_script
readonly container_script=/workspace/homelab-server-configs/$relative_script

exec podman run --rm --network none \
    --env CADDY_VALIDATION_CONTAINER=1 \
    --volume "$workspace_root:/workspace:ro" \
    "$validation_image" -lc \
    'cd /workspace/homelab-server-configs && exec /bin/bash "$1"' \
    _ "$container_script"
