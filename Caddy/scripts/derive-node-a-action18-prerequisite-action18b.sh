#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action_prefix=action_18b
readonly historical_installer_sha256=211855a78eaf61df0ba3604810577b65ec1d00ef42a4e135354a472f4a569cc9
readonly historical_runner_sha256=1311e702980f4fce53d90154e5a5999f1e492de01de0e37194c6d43c4bd8a4e7
readonly historical_regression_sha256=02b349abc875f0321c3f816ec32df396b9288d045717383846cb91f50319c2ee
readonly receiver_sha256=a94c7a45531787055da622a0dac180f98e52bd0ba967424a4cf22a4852539d9e
readonly finalizer_sha256=15d858774a17369f31261f7f94bea72d575f269fdb3e8e991534f66dd4f4902d
readonly authorization_template_sha256=e64a603dc93bebbac065955031f36048d551cac295e19dd497c7c6ed9b8cec32
readonly old_authorization_sha256=6ef8d656053aba6508524aaebd3d215ef9036f8bb6fd1f56cd8b4a654649f968
readonly new_authorization_sha256=3df0ffaaf4d0f1007a9d7214eefc81f4f08df00ad840ea1d3f83e8b72b0e2331
readonly rendered_installer_name=install-node-a-action18-prerequisite-action18b.sh
readonly rendered_runner_name=run-node-a-action18-prerequisite-action18b.sh

derivation_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly derivation_directory
readonly caddy_root=${derivation_directory%/scripts}
readonly historical_installer="$derivation_directory/install-node-b-protocol-v2-action17q-retry.sh"
readonly historical_runner="$derivation_directory/run-node-b-protocol-v2-install-action17q-retry.sh"
readonly historical_regression="$caddy_root/tests/action17q-retry-node-b-protocol-v2-install-regression.sh"
readonly receiver="$derivation_directory/caddy-sync-release-receiver-v2"
readonly finalizer="$derivation_directory/finalize-incoming-release-v2-stderr-safe-action17u.sh"
readonly authorization_template="$caddy_root/templates/authorized-key-receiver-finalized-v2.in"

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_source_hash() {
    local expected_hash=$1
    local source_path=$2

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1
    [[ "$(file_hash "$source_path")" == "$expected_hash" ]] || return 1
}

verify_sources() {
    require_source_hash "$historical_installer_sha256" "$historical_installer"
    require_source_hash "$historical_runner_sha256" "$historical_runner"
    require_source_hash "$historical_regression_sha256" "$historical_regression"
    require_source_hash "$receiver_sha256" "$receiver"
    require_source_hash "$finalizer_sha256" "$finalizer"
    require_source_hash "$authorization_template_sha256" "$authorization_template"
}

render_installer() {
    local output_path=$1

    awk \
        -v old_authorization_hash="$old_authorization_sha256" \
        -v new_authorization_hash="$new_authorization_sha256" \
        -v corrected_finalizer_hash="$finalizer_sha256" '
        {
            line = $0
            gsub(/action_17q_retry/, "action_18b", line)
            gsub(/action17q-retry/, "action18b", line)
            gsub(/incoming\/node-a/, "outbound", line)
            gsub(/action15-health-follow-redirects/,
                "action16ar-retry-node-a-default-deny", line)
            gsub(/expected_node_a_fingerprint/,
                "expected_node_b_fingerprint", line)
            gsub(/SHA256:QVvqXXcmH7JqqpqddUFjTdyxIvC\/nb56VfAQpK4Y8V0/,
                "SHA256:ykJmrl499fd2qRm9bYjgyrgeiTCA1rzTelBBKX0gy5g", line)
            gsub(/hostname_node_b/, "hostname_node_a", line)
            gsub(/j1-svpihole00/, "j1-svpihole0", line)
            gsub(/action18b-node-b-protocol-v2/,
                "action18b-node-a-prerequisite", line)
            gsub(/node_b_protocol_v2_install_complete/,
                "node_a_prerequisite_install_complete", line)
            if (line ~ /^readonly expected_finalizer_v2_sha256=/) {
                line = "readonly expected_finalizer_v2_sha256=" corrected_finalizer_hash
            } else if (line ~ /^readonly expected_old_authorization_sha256=/) {
                line = "readonly expected_old_authorization_sha256=" old_authorization_hash
            } else if (line ~ /^readonly expected_new_authorization_sha256=/) {
                line = "readonly expected_new_authorization_sha256=" new_authorization_hash
            }
            if (line == "        find . -type f ! -name .complete -print0 |") {
                print "        find . -type f ! -name .complete \\"
                print "            ! -name .complete.pending ! -name .finalize-request -print0 |"
                next
            }
            print line
        }
    ' "$historical_installer" >"$output_path"
    chmod 0755 "$output_path"
}

render_runner() {
    local installer_hash=$1
    local output_path=$2

    awk \
        -v corrected_installer_hash="$installer_hash" \
        -v corrected_finalizer_hash="$finalizer_sha256" \
        -v corrected_authorization_hash="$new_authorization_sha256" '
        function transform(value) {
            gsub(/action_17q_retry/, "action_18b", value)
            gsub(/action17q-retry/, "action18b", value)
            gsub(/ACTION17Q_RETRY_ARCHIVE/, "ACTION18B_ARCHIVE", value)
            gsub(/Node B/, "Node A", value)
            gsub(/install-node-b-protocol-v2-action18b.sh/,
                "install-node-a-action18-prerequisite-action18b.sh", value)
            gsub(/install-node-b-protocol-v2-action17q-retry.sh/,
                "install-node-a-action18-prerequisite-action18b.sh", value)
            gsub(/pi@10.1.0.54/, "pi@NODE_A_TARGET", value)
            gsub(/pihole00.local.theama.co/, "pihole0.local.theama.co", value)
            gsub(/node_a_public_key/, "node_b_public_key", value)
            gsub(/AAAAC3NzaC1lZDI1NTE5AAAAIG3MEgLhf8tsImyjkCZpQU4H7X8Xdac\+iOUCxRTMM0tA/,
                "AAAAC3NzaC1lZDI1NTE5AAAAIBwBAlvUOqcazWjzfUOnwk1AHath8Xn8eoUDXBFQIG7e", value)
            gsub(/10.1.0.53/, "10.1.0.54", value)
            gsub(/fd36:5aa8:6971:1::53/, "fd36:5aa8:6971:1::54", value)
            gsub(/s\/@PEER_ROLE@\/node-a\/g/,
                "s/@PEER_ROLE@/node-b/g", value)
            gsub(/pi@NODE_A_TARGET/, "pi@10.1.0.53", value)
            gsub(/action18b-node-b-protocol-v2/,
                "action18b-node-a-prerequisite", value)
            gsub(/node_b_protocol_v2_install_complete/,
                "node_a_prerequisite_install_complete", value)
            return value
        }
        BEGIN {
            validator = ""
        }
        /^validate_success[(][)]/ {
            validator = "success"
            print "# conditional-validator-" "explicit-failures-begin"
        }
        /^validate_failure[(][)]/ {
            validator = "failure"
        }
        {
            line = transform($0)
            if (line ~ /^readonly installer_sha256=/) {
                line = "readonly installer_sha256=" corrected_installer_hash
            } else if (line ~ /^readonly finalizer_sha256=/) {
                line = "readonly finalizer_sha256=" corrected_finalizer_hash
            } else if (line ~ /^readonly finalizer=/) {
                line = "readonly finalizer=\"$script_directory/finalize-incoming-release-v2-stderr-safe-action17u.sh\""
            } else if (line ~ /^readonly expected_authorization_sha256=/) {
                line = "readonly expected_authorization_sha256=" corrected_authorization_hash
            }
            if (validator == "success" &&
                (line == "    [[ \"$ssh_status\" -eq 0 ]]" ||
                line == "    [[ ! -s \"$error_transcript\" ]]")) {
                line = line " || return 1"
            }
            if (validator == "failure" &&
                line == "    [[ \"$ssh_status\" -ne 0 ]]") {
                line = line " || return 1"
            }
            if (validator == "success" &&
                line == "        \"$output_transcript\")\" -eq 1 ]]") {
                line = line " || return 1"
            }
            if (validator != "" && line == "}") {
                print "    return 0"
                print line
                if (validator == "failure") {
                    print "# conditional-validator-" "explicit-failures-end"
                }
                validator = ""
                next
            }
            print line
        }
    ' "$historical_runner" >"$output_path"
    chmod 0755 "$output_path"
}

render_pair() {
    local output_directory=$1
    local rendered_installer="$output_directory/$rendered_installer_name"
    local rendered_runner="$output_directory/$rendered_runner_name"
    local rendered_installer_hash

    [[ -d "$output_directory" && ! -L "$output_directory" ]] || return 1
    render_installer "$rendered_installer"
    rendered_installer_hash=$(file_hash "$rendered_installer")
    render_runner "$rendered_installer_hash" "$rendered_runner"
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        self_test_directory=$(mktemp -d /tmp/caddy-action18b-derive.XXXXXX)
        readonly self_test_directory
        trap 'rm -rf -- "$self_test_directory"' EXIT
        render_pair "$self_test_directory"
        bash -n "$self_test_directory/$rendered_installer_name" \
            "$self_test_directory/$rendered_runner_name"
        "$self_test_directory/$rendered_installer_name" --self-test >/dev/null
        "$self_test_directory/$rendered_runner_name" --self-test >/dev/null
        "$self_test_directory/$rendered_runner_name" --contract-test >/dev/null
        printf '%s_derivation_self_test_complete=true\n' "$action_prefix"
        ;;
    --output-directory)
        [[ $# -eq 2 ]] || exit 64
        verify_sources
        render_pair "$2"
        printf '%s_derivation_render_complete=true\n' "$action_prefix"
        ;;
    *)
        printf 'Usage: %s --self-test|--output-directory DIRECTORY\n' \
            "${0##*/}" >&2
        exit 64
        ;;
esac
