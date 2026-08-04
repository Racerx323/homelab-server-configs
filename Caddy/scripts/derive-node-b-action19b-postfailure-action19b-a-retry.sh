#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_19b_a_retry
readonly base_inspector_sha256=71159ea5e0fa7c62f984ebe47742d9d0f235d570d3be948406ed93ad20cfe544
readonly base_runner_sha256=f865fc624d2fa10adb7c95d7dbc9570bef848dabb9281f31b78e4dd7595c72e5
readonly rendered_inspector_name=inspect-node-b-action19b-postfailure-action19b-a-retry.sh
readonly rendered_runner_name=run-node-b-action19b-postfailure-action19b-a-retry.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly base_inspector="$script_directory/inspect-node-b-action19b-postfailure-action19b-a.sh"
readonly base_runner="$script_directory/run-node-b-action19b-postfailure-action19b-a.sh"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

verify_sources() {
    [[ -f "$base_inspector" && ! -L "$base_inspector" ]] || return 1
    [[ -f "$base_runner" && ! -L "$base_runner" ]] || return 1
    [[ "$(file_hash "$base_inspector")" = "$base_inspector_sha256" ]] ||
        return 1
    [[ "$(file_hash "$base_runner")" = "$base_runner_sha256" ]] ||
        return 1
}

transform_inspector() {
    awk '
        /^readonly prefix=action_19b_a$/ {
            print "readonly prefix=action_19b_a_retry"
            prefix_changed++
            next
        }
        /caddy-action19b-a-/ {
            gsub(/caddy-action19b-a-/, "caddy-action19b-a-retry-")
        }
        /^[[:space:]]*"[$]baseline_inspector"/ {
            sub(/"[$]baseline_inspector"/, "/bin/bash \"$baseline_inspector\"")
            baseline_invocations_changed++
        }
        {
            print
        }
        /test "[$][(]stat -c .*[$]baseline_inspector.*root:root:700/ {
            print "record_command historical_action19b_a_remote_bundle_stage_absent \\\n+    test -z \"$(find /run -mindepth 1 -maxdepth 1 \\\n+        -name \047caddy-action19b-a-stage.*\047 -print -quit 2>/dev/null)\""
            residue_check_added++
        }
        END {
            if (prefix_changed != 1 || baseline_invocations_changed != 4 ||
                residue_check_added != 1) {
                printf "action_19b_a_retry_inspector_transform_counts=%d,%d,%d\n",
                    prefix_changed, baseline_invocations_changed,
                    residue_check_added > "/dev/stderr"
                exit 42
            }
        }
    ' "$base_inspector"
}

transform_runner() {
    local inspector_hash=$1

    awk -v inspector_hash="$inspector_hash" '
        /^readonly prefix=action_19b_a$/ {
            print "readonly prefix=action_19b_a_retry"
            prefix_changed++
            next
        }
        /^readonly expected_assertions=88$/ {
            print "readonly expected_assertions=89"
            count_changed++
            next
        }
        /^readonly inspector_sha256=/ {
            print "readonly inspector_sha256=" inspector_hash
            hash_changed++
            next
        }
        /^readonly inspector=/ {
            print "readonly inspector=\"$script_directory/inspect-node-b-action19b-postfailure-action19b-a-retry.sh\""
            path_changed++
            next
        }
        {
            gsub(/caddy-action19b-a-/, "caddy-action19b-a-retry-")
            gsub(/inspect-node-b-action19b-postfailure-action19b-a[.]sh/,
                "inspect-node-b-action19b-postfailure-action19b-a-retry.sh")
            print
        }
        END {
            if (prefix_changed != 1 || count_changed != 1 ||
                hash_changed != 1 || path_changed != 1) {
                printf "action_19b_a_retry_runner_transform_counts=%d,%d,%d,%d\n",
                    prefix_changed, count_changed, hash_changed,
                    path_changed > "/dev/stderr"
                exit 42
            }
        }
    ' "$base_runner"
}

render_directory() {
    local output_directory=$1
    local inspector_path="$output_directory/$rendered_inspector_name"
    local runner_path="$output_directory/$rendered_runner_name"
    local inspector_hash

    install -d -m 0700 "$output_directory"
    transform_inspector >"$inspector_path"
    chmod 0755 "$inspector_path"
    inspector_hash=$(file_hash "$inspector_path")
    transform_runner "$inspector_hash" >"$runner_path"
    chmod 0755 "$runner_path"
    bash -n "$inspector_path" "$runner_path"
    printf '%s\n' "$inspector_path" "$runner_path"
}

self_test() {
    local test_root
    local inspector_path
    local runner_path

    verify_sources
    test_root=$(mktemp -d /tmp/caddy-action19b-a-retry-derive.XXXXXX)
    trap 'rm -rf -- "$test_root"' RETURN
    mapfile -t rendered_paths < <(render_directory "$test_root")
    inspector_path=${rendered_paths[0]}
    runner_path=${rendered_paths[1]}
    # shellcheck disable=SC2016
    grep -Fq '/bin/bash "$baseline_inspector" --expected-assertions' \
        "$inspector_path"
    grep -Fq 'historical_action19b_a_remote_bundle_stage_absent' \
        "$inspector_path"
    grep -Fq 'readonly expected_assertions=89' "$runner_path"
    grep -Fq 'caddy-action19b-a-retry-stage.' "$runner_path"
    printf '%s_derivation_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        ;;
    --output-directory)
        [[ $# -eq 2 ]] || exit 64
        verify_sources
        render_directory "$2"
        ;;
    *)
        printf 'Usage: %s --self-test | --output-directory DIR\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
