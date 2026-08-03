#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_inspector_sha256=38df35f89dc5732320e84ef9ec90ff8b0d5d1cee72d342b025c743c74a0d4210
readonly historical_runner_sha256=facbaeda449522296cb90febf8fc0cbe4472129a35f960f9415e5aa5fb248ea2
readonly corrected_inspector_sha256=d579c51913ab6fc664550f8f966ed49fac50fd37c6c22890a1d04097018806c5
readonly corrected_inner_runner_sha256=07e07a07c84a1d7b80792ff8f86bf420d4f323b51baf88fab424c49d93efc644

derivation_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly derivation_directory
readonly historical_inspector="$derivation_directory/inspect-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh"
readonly historical_runner="$derivation_directory/run-node-b-stderr-safe-finalizer-postinstall-action17u-a.sh"
readonly collision_checker="$derivation_directory/../tests/check-shell-readonly-local-collisions.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

render_inspector() {
    local inspector_source=$1

    [[ -f "$inspector_source" && ! -L "$inspector_source" ]] || return 1
    [[ "$(file_hash "$inspector_source")" == "$historical_inspector_sha256" ]] || return 1
    awk '
        {
            line = $0
            gsub(/action_17u_a/, "action_17u_c", line)
            gsub(/caddy-action17u-a/, "caddy-action17u-c", line)
            gsub(/postinstall/, "postrepair", line)
        }
        line ~ /lsyncd_configuration_not_symlink transaction_stage_count_zero/ {
            sub(/transaction_stage_count_zero/, "transaction_stage_count_zero repair_stage_count_zero", line)
            labels_changed++
        }
        line == "        [[ \"$(expected_check_labels | wc -l)\" -eq 71 ]] || exit 1" {
            sub(/71/, "72", line)
            counts_changed++
        }
        line == "        [[ \"$(expected_check_labels | sort -u | wc -l)\" -eq 71 ]] || exit 1" {
            sub(/71/, "72", line)
            counts_changed++
        }
        { print line }
        line ~ /^record_command transaction_stage_count_zero / {
            print "record_command repair_stage_count_zero test \"$(find /run -mindepth 1 -maxdepth 1 -type d -name '\''caddy-action17u-b.*'\'' -print 2>/dev/null | wc -l)\" -eq 0"
            checks_added++
        }
        END {
            if (labels_changed != 1 || counts_changed != 2 || checks_added != 1) {
                exit 42
            }
        }
    ' "$inspector_source"
}

render_runner() {
    local runner_source=$1

    [[ -f "$runner_source" && ! -L "$runner_source" ]] || return 1
    [[ "$(file_hash "$runner_source")" == "$historical_runner_sha256" ]] || return 1
    awk -v corrected_inspector_sha256="$corrected_inspector_sha256" '
        {
            line = $0
            gsub(/action_17u_a/, "action_17u_c", line)
            gsub(/caddy-action17u-a/, "caddy-action17u-c", line)
            gsub(/postinstall/, "postrepair", line)
        }
        line ~ /^readonly inspector_sha256=/ {
            line = "readonly inspector_sha256=" corrected_inspector_sha256
            hash_changed++
        }
        line ~ /^readonly inspector=/ {
            line = "readonly inspector=\"$script_directory/inspect-node-b-action17u-postrepair-acceptance-action17u-c.sh\""
            path_changed++
        }
        line == "    [[ \"$expected_count\" -eq 71 ]] || return 1" {
            sub(/71/, "72", line)
            count_changed++
        }
        { print line }
        END {
            if (hash_changed != 1 || path_changed != 1 || count_changed != 1) {
                exit 42
            }
        }
    ' "$runner_source"
}

self_test() {
    local self_root self_scripts self_tests rendered_inspector rendered_runner

    self_root=$(mktemp -d /tmp/caddy-action17u-c-derivation.XXXXXX)
    trap '[[ -z ${self_root:-} ]] || rm -rf -- "$self_root"' EXIT
    self_scripts="$self_root/Caddy/scripts"
    self_tests="$self_root/Caddy/tests"
    rendered_inspector="$self_scripts/inspect-node-b-action17u-postrepair-acceptance-action17u-c.sh"
    rendered_runner="$self_scripts/run-node-b-action17u-postrepair-acceptance-action17u-c.sh"
    install -d -m 0700 "$self_scripts" "$self_tests"
    install -m 0755 -- "$collision_checker" "$self_tests/${collision_checker##*/}"
    render_inspector "$historical_inspector" >"$rendered_inspector"
    render_runner "$historical_runner" >"$rendered_runner"
    [[ "$(file_hash "$rendered_inspector")" == "$corrected_inspector_sha256" ]]
    [[ "$(file_hash "$rendered_runner")" == "$corrected_inner_runner_sha256" ]]
    bash -n "$rendered_inspector" "$rendered_runner"
    chmod 0755 "$rendered_inspector" "$rendered_runner"
    "$rendered_inspector" --self-test >/dev/null
    "$rendered_runner" --contract-test >/dev/null
    rm -rf -- "$self_root"
    trap - EXIT
    printf 'action_17u_c_derivation_self_test_complete=true\n'
}

case "${1:-}" in
    --render-inspector)
        [[ $# -eq 2 ]] || exit 64
        render_inspector "$2"
        ;;
    --render-runner)
        [[ $# -eq 2 ]] || exit 64
        render_runner "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        ;;
    *)
        printf 'Usage: %s --render-inspector SOURCE | --render-runner SOURCE | --self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
