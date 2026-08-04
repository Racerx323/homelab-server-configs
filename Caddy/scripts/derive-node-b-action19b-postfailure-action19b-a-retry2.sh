#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19b_a_retry2
readonly base_derivation_sha256=56c28070d4ce346b9b8b7778edd7882a509018954e38670f7d58df75a474ab04
readonly base_rendered_inspector_sha256=69389a69710ea1ab9cd017c3723373eb7bd485d79c0ea469b8e56e9941e1104f
readonly base_rendered_runner_sha256=490b34a563f0975e99cff5818b6dd7318b203ee6dab66993b68b31b14651b6f2
readonly rendered_inspector_name=inspect-node-b-action19b-postfailure-action19b-a-retry2.sh
readonly rendered_runner_name=run-node-b-action19b-postfailure-action19b-a-retry2.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly base_derivation="$script_directory/derive-node-b-action19b-postfailure-action19b-a-retry.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

verify_source() {
    [[ -f "$base_derivation" && ! -L "$base_derivation" ]] || return 1
    [[ "$(file_hash "$base_derivation")" = "$base_derivation_sha256" ]]
}

render_base() {
    local output_directory=$1
    local base_inspector="$output_directory/inspect-node-b-action19b-postfailure-action19b-a-retry.sh"
    local base_runner="$output_directory/run-node-b-action19b-postfailure-action19b-a-retry.sh"

    "$base_derivation" --output-directory "$output_directory" >/dev/null ||
        return 1
    [[ "$(file_hash "$base_inspector")" = "$base_rendered_inspector_sha256" ]] || return 1
    [[ "$(file_hash "$base_runner")" = "$base_rendered_runner_sha256" ]] ||
        return 1
}

transform_inspector() {
    local base_inspector=$1

    awk '
        /^readonly prefix=action_19b_a_retry$/ {
            print "readonly prefix=action_19b_a_retry2"
            prefix_changed++
            next
        }
        /^write_contract_fixture[(][)]/ { in_fixture = 1 }
        /^case / { in_fixture = 0 }
        /^\+[[:space:]]/ {
            sub(/^\+/, "")
            plus_removed++
        }
        /[$][{]baseline_prefix[}]_state_unchanged=true/ {
            if (in_fixture) {
                state_fixture_removed++
                next
            }
            sub(/_state_unchanged=true/, "_assertion_state_unchanged=true")
            state_validation_changed++
        }
        /[$][{]baseline_prefix[}]_helper_invoked=false/ {
            sub(/_helper_invoked=false/, "_helper_execution=false")
            helper_markers_changed++
        }
        /[$][{]baseline_prefix[}]_persistent_mutation=false/ {
            sub(/_persistent_mutation=false/, "_persistent_mutations=false")
            persistent_markers_changed++
        }
        {
            gsub(/caddy-action19b-a-retry-/, "caddy-action19b-a-retry2-")
            print
        }
        END {
            if (prefix_changed != 1 || plus_removed != 2 ||
                state_validation_changed != 1 || state_fixture_removed != 1 ||
                helper_markers_changed != 2 || persistent_markers_changed != 2) {
                printf "action_19b_a_retry2_inspector_transform_counts=%d,%d,%d,%d,%d,%d\n",
                    prefix_changed, plus_removed, state_validation_changed,
                    state_fixture_removed, helper_markers_changed,
                    persistent_markers_changed > "/dev/stderr"
                exit 42
            }
        }
    ' "$base_inspector"
}

transform_runner() {
    local base_runner=$1
    local inspector_hash=$2

    awk -v inspector_hash="$inspector_hash" '
        /^readonly prefix=action_19b_a_retry$/ {
            print "readonly prefix=action_19b_a_retry2"
            prefix_changed++
            next
        }
        /^readonly inspector_sha256=/ {
            print "readonly inspector_sha256=" inspector_hash
            hash_changed++
            next
        }
        /^readonly inspector=/ {
            print "readonly inspector=\"$script_directory/inspect-node-b-action19b-postfailure-action19b-a-retry2.sh\""
            path_changed++
            next
        }
        {
            gsub(/caddy-action19b-a-retry-/, "caddy-action19b-a-retry2-")
            gsub(/inspect-node-b-action19b-postfailure-action19b-a-retry[.]sh/,
                "inspect-node-b-action19b-postfailure-action19b-a-retry2.sh")
            print
        }
        END {
            if (prefix_changed != 1 || hash_changed != 1 || path_changed != 1) {
                printf "action_19b_a_retry2_runner_transform_counts=%d,%d,%d\n",
                    prefix_changed, hash_changed, path_changed > "/dev/stderr"
                exit 42
            }
        }
    ' "$base_runner"
}

render_directory() {
    local output_directory=$1
    local base_directory
    local base_inspector
    local base_runner
    local inspector_path="$output_directory/$rendered_inspector_name"
    local runner_path="$output_directory/$rendered_runner_name"
    local inspector_hash

    install -d -m 0700 "$output_directory"
    base_directory=$(mktemp -d /tmp/caddy-action19b-a-retry2-base.XXXXXX)
    trap 'rm -rf -- "$base_directory"' RETURN
    render_base "$base_directory"
    base_inspector="$base_directory/inspect-node-b-action19b-postfailure-action19b-a-retry.sh"
    base_runner="$base_directory/run-node-b-action19b-postfailure-action19b-a-retry.sh"
    transform_inspector "$base_inspector" >"$inspector_path"
    chmod 0755 "$inspector_path"
    inspector_hash=$(file_hash "$inspector_path")
    transform_runner "$base_runner" "$inspector_hash" >"$runner_path"
    chmod 0755 "$runner_path"
    bash -n "$inspector_path" "$runner_path"
    printf '%s\n' "$inspector_path" "$runner_path"
}

self_test() {
    local test_root
    local inspector_path
    local runner_path

    verify_source
    test_root=$(mktemp -d /tmp/caddy-action19b-a-retry2-derive.XXXXXX)
    trap 'rm -rf -- "$test_root"' RETURN
    mapfile -t rendered_paths < <(render_directory "$test_root")
    inspector_path=${rendered_paths[0]}
    runner_path=${rendered_paths[1]}
    test "$(grep -Ec '^\+[[:space:]]' "$inspector_path" || true)" -eq 0
    # shellcheck disable=SC2016
    grep -Fq '${baseline_prefix}_assertion_state_unchanged=true' \
        "$inspector_path"
    # shellcheck disable=SC2016
    grep -Fq '${baseline_prefix}_helper_execution=false' "$inspector_path"
    # shellcheck disable=SC2016
    grep -Fq '${baseline_prefix}_persistent_mutations=false' "$inspector_path"
    grep -Fq 'caddy-action19b-a-retry2-stage.' "$runner_path"
    printf '%s_derivation_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        ;;
    --output-directory)
        [[ $# -eq 2 ]] || exit 64
        verify_source
        render_directory "$2"
        ;;
    *) exit 64 ;;
esac
