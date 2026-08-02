#!/usr/bin/env bash
# shellcheck disable=SC2016 # Match literal rendered production source.

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_driver_sha256=916f8b8a109494523906d189f8cabec834ccf40fd04a38cb5686f355f3aee631
readonly correction_sha256=7fc521452ac1f65c5e1cdc4025daa2f57c41819134af952bd9b60aaf7c493bd8

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly historical_driver="$caddy_root/scripts/stage-node-b-unbound-local-zone-action17f.sh"
readonly correction="$caddy_root/scripts/correct-node-b-unbound-local-zone-action17f-normalized-retry.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_sources() {
    [[ "$(file_hash "$historical_driver")" == "$historical_driver_sha256" ]]
    [[ "$(file_hash "$correction")" == "$correction_sha256" ]]
    bash -n "$historical_driver" "$correction"
}

run_static_test() {
    local test_dir

    verify_sources
    test_dir=$(mktemp -d /tmp/caddy-action17f-normalized-regression.XXXXXX)
    trap 'rm -rf -- "$test_dir"' RETURN
    "$correction" --render-transactional-driver >"$test_dir/corrected"
    bash -n "$test_dir/corrected"

    diff -U0 "$historical_driver" "$test_dir/corrected" \
        >"$test_dir/change.diff" || true
    [[ "$(grep -Ec '^-[^-]' "$test_dir/change.diff")" -eq 2 ]]
    [[ "$(grep -Ec '^\+[^+]' "$test_dir/change.diff")" -eq 6 ]]
    grep -Fq -- '-    local state_hash' "$test_dir/change.diff"
    grep -Fq -- '+    local state_hash state_snapshot' "$test_dir/change.diff"
    grep -Fq -- \
        "-    state_hash=\$(live_state | sha256sum | awk '{ print \$1 }')" \
        "$test_dir/change.diff"
    grep -Fq -- '+    state_snapshot=$(live_state)' "$test_dir/change.diff"
    grep -Fq -- "+        printf '%s' \"\$state_snapshot\" |" \
        "$test_dir/change.diff"

    if grep -Eq \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control|(^|[[:space:]])dig([[:space:]]|$)' \
        "$test_dir/corrected"; then
        exit 1
    fi
    printf 'action_17f_normalized_static_regression_complete=true\n'
}

run_byte_boundary_test() {
    local snapshot normalized_snapshot
    local raw_hash normalized_hash expected_raw_hash expected_normalized_hash

    snapshot=$(printf 'state-line-one\nstate-line-two\n\n')
    normalized_snapshot=$snapshot
    raw_hash=$(
        printf 'state-line-one\nstate-line-two\n\n' |
            sha256sum |
            awk '{ print $1 }'
    )
    normalized_hash=$(
        printf '%s' "$normalized_snapshot" |
            sha256sum |
            awk '{ print $1 }'
    )
    expected_raw_hash=$(
        printf 'state-line-one\nstate-line-two\n\n' |
            sha256sum |
            awk '{ print $1 }'
    )
    expected_normalized_hash=$(
        printf 'state-line-one\nstate-line-two' |
            sha256sum |
            awk '{ print $1 }'
    )

    [[ "$snapshot" == 'state-line-one
state-line-two' ]]
    [[ "$normalized_snapshot" == "$snapshot" ]]
    [[ "$raw_hash" == "$expected_raw_hash" ]]
    [[ "$normalized_hash" == "$expected_normalized_hash" ]]
    [[ "$raw_hash" != "$normalized_hash" ]]
    printf 'action_17f_raw_pipeline_trailing_newline_preserved=true\n'
    printf 'action_17f_command_substitution_trailing_newline_removed=true\n'
    printf 'action_17f_normalized_hash_boundary_regression_complete=true\n'
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]]
        run_static_test
        run_byte_boundary_test
        ;;
    --production-test)
        [[ $# -eq 1 ]]
        run_static_test
        run_byte_boundary_test
        ;;
    *)
        printf 'Usage: %s --self-test|--production-test\n' "${0##*/}" >&2
        exit 2
        ;;
esac
