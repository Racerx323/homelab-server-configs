#!/usr/bin/env bash
# shellcheck disable=SC2016 # Render literal Bash source.

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly historical_driver_sha256=916f8b8a109494523906d189f8cabec834ccf40fd04a38cb5686f355f3aee631
readonly instrumentation_sha256=6335840327e600ee4c2ded4e6e5090ded0e2aafa2c2d25643c6efd063ad5934c

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly historical_driver="$script_dir/stage-node-b-unbound-local-zone-action17f.sh"
readonly instrumentation="$script_dir/instrument-node-b-unbound-local-zone-action17f-retry.sh"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

verify_file() {
    local source_path=$1
    local expected_hash=$2

    [[ -f "$source_path" && ! -L "$source_path" ]]
    [[ "$(file_hash "$source_path")" == "$expected_hash" ]]
}

verify_sources() {
    verify_file "$historical_driver" "$historical_driver_sha256"
    verify_file "$instrumentation" "$instrumentation_sha256"
    bash -n "$historical_driver" "$instrumentation"
}

render_transactional_driver() {
    verify_sources
    awk '
        $0 == "    local state_hash" {
            print "    local state_hash state_snapshot"
            declaration_changed++
            next
        }
        $0 == "    state_hash=$(live_state | sha256sum | awk '\''{ print $1 }'\'')" {
            print "    state_snapshot=$(live_state)"
            print "    state_hash=$("
            print "        printf '\''%s'\'' \"$state_snapshot\" |"
            print "            sha256sum | awk '\''{ print $1 }'\''"
            print "    )"
            hash_changed++
            next
        }
        { print }
        END {
            if (declaration_changed != 1 || hash_changed != 1) {
                exit 42
            }
        }
    ' "$historical_driver"
}

render_driver() {
    local corrected_driver_b64 corrected_driver_hash

    verify_sources
    corrected_driver_b64=$(render_transactional_driver | base64 -w 0)
    corrected_driver_hash=$(
        printf '%s' "$corrected_driver_b64" |
            base64 -d |
            sha256sum |
            awk '{ print $1 }'
    )
    "$instrumentation" --render-driver |
        awk \
            -v driver_b64="$corrected_driver_b64" \
            -v driver_hash="$corrected_driver_hash" '
            /^readonly transactional_driver_b64=/ {
                print "readonly transactional_driver_b64=" driver_b64
                payload_changed++
                next
            }
            /^readonly transactional_driver_sha256=/ {
                print "readonly transactional_driver_sha256=" driver_hash
                hash_changed++
                next
            }
            { print }
            END {
                if (payload_changed != 1 || hash_changed != 1) {
                    exit 42
                }
            }
        '
}

render_runner() {
    local corrected_driver_hash=$1
    local corrected_regression_hash=$2

    [[ "$corrected_driver_hash" =~ ^[0-9a-f]{64}$ ]]
    [[ "$corrected_regression_hash" =~ ^[0-9a-f]{64}$ ]]
    verify_sources
    "$instrumentation" --render-runner |
        awk \
            -v driver_hash="$corrected_driver_hash" \
            -v regression_hash="$corrected_regression_hash" '
            /^readonly driver_sha256=/ {
                print "readonly driver_sha256=" driver_hash
                driver_changed++
                next
            }
            /^readonly regression_sha256=/ {
                print "readonly regression_sha256=" regression_hash
                regression_changed++
                next
            }
            { print }
            END {
                if (driver_changed != 1 || regression_changed != 1) {
                    exit 42
                }
            }
        '
}

usage() {
    printf '%s\n' \
        "Usage: ${0##*/} --render-transactional-driver" \
        "       ${0##*/} --render-driver" \
        "       ${0##*/} --render-runner DRIVER_SHA256 REGRESSION_SHA256" \
        "       ${0##*/} --self-test"
}

case "${1:-}" in
    --render-transactional-driver)
        [[ $# -eq 1 ]] || {
            usage >&2
            exit 2
        }
        render_transactional_driver
        ;;
    --render-driver)
        [[ $# -eq 1 ]] || {
            usage >&2
            exit 2
        }
        render_driver
        ;;
    --render-runner)
        [[ $# -eq 3 ]] || {
            usage >&2
            exit 2
        }
        render_runner "$2" "$3"
        ;;
    --self-test)
        [[ $# -eq 1 ]]
        verify_sources
        test_dir=$(mktemp -d /tmp/caddy-action17f-normalized-correction.XXXXXX)
        trap 'rm -rf -- "$test_dir"' EXIT
        render_transactional_driver >"$test_dir/transactional-driver"
        render_driver >"$test_dir/driver"
        bash -n "$test_dir/transactional-driver" "$test_dir/driver"
        grep -Fq 'state_snapshot=$(live_state)' \
            "$test_dir/transactional-driver"
        grep -Fq "printf '%s' \"\$state_snapshot\"" \
            "$test_dir/transactional-driver"
        if grep -Fq \
            "state_hash=\$(live_state | sha256sum | awk '{ print \$1 }')" \
            "$test_dir/transactional-driver"; then
            exit 1
        fi
        printf 'action_17f_normalized_correction_self_test_complete=true\n'
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
