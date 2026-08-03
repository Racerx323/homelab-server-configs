#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly action_prefix=action_18b_retry
readonly historical_derivation_sha256=8df318bb6af25a2891a431f90d4b970544901268c87a39dcec4258290643862c
readonly historical_outer_sha256=449700551e56791fd2d5a3bb4461ffe0ba8fc4e60d6831f452ebd234de6b12fd
readonly historical_regression_sha256=9493dc16753528703b3cfc8c620eb5491f7ade3d6e25f0d5356d651d97e860c0
readonly accepted_diagnostic_outer_sha256=e5e4d1cd1c7a033e7640753c3c94ac0f13b19062a610115ff20c72ebf1754aff
readonly accepted_diagnostic_regression_sha256=b3132608ad3316693d0c6c658ce979b99a3c279864055a1339379824e7658843
readonly historical_installer_sha256=9c2743e553cc52e53e57a880e3d386aba130bd7a610879159b1d36db6bf87e97
readonly historical_runner_sha256=44a57fbd90cf1c8dfb6d42b24e80df139d7e39132fe3914c187e8cdb0a27412e
readonly sender_complete_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
readonly rendered_installer_name=install-node-a-action18-prerequisite-action18b-retry.sh
readonly rendered_runner_name=run-node-a-action18-prerequisite-action18b-retry.sh

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly historical_derivation="$script_directory/derive-node-a-action18-prerequisite-action18b.sh"
readonly historical_outer="$script_directory/run-node-a-action18-prerequisite-action18b-outer.sh"
readonly historical_regression="$caddy_root/tests/action18b-node-a-prerequisite-regression.sh"
readonly accepted_diagnostic_outer="$script_directory/run-node-a-action18b-postfailure-action18b-a-retry-outer.sh"
readonly accepted_diagnostic_regression="$caddy_root/tests/action18b-a-retry-node-a-postfailure-regression.sh"

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
    require_source_hash "$historical_derivation_sha256" "$historical_derivation"
    require_source_hash "$historical_outer_sha256" "$historical_outer"
    require_source_hash "$historical_regression_sha256" "$historical_regression"
    require_source_hash "$accepted_diagnostic_outer_sha256" \
        "$accepted_diagnostic_outer"
    require_source_hash "$accepted_diagnostic_regression_sha256" \
        "$accepted_diagnostic_regression"
}

render_historical_pair() {
    local output_directory=$1

    "$historical_derivation" --output-directory "$output_directory" >/dev/null
    [[ "$(file_hash "$output_directory/install-node-a-action18-prerequisite-action18b.sh")" == "$historical_installer_sha256" ]] || return 1
    [[ "$(file_hash "$output_directory/run-node-a-action18-prerequisite-action18b.sh")" == "$historical_runner_sha256" ]] || return 1
}

render_installer() {
    local historical_installer=$1
    local output_path=$2

    awk -v sender_hash="$sender_complete_sha256" '
        function transform(value) {
            gsub(/action_18b/, "action_18b_retry", value)
            gsub(/action18b/, "action18b-retry", value)
            return value
        }
        function emit_sender_validator() {
            print "validate_sender_complete() {"
            print "    local sender_marker_label_prefix=$1"
            print "    local sender_marker_path=$2"
            print "    local sender_marker_expected_metadata=$3"
            print ""
            print "    require_check \"${sender_marker_label_prefix}_regular\" \\"
            print "        test -f \"$sender_marker_path\" || return 1"
            print "    require_check \"${sender_marker_label_prefix}_not_symlink\" \\"
            print "        test ! -L \"$sender_marker_path\" || return 1"
            print "    require_check \"${sender_marker_label_prefix}_metadata\" \\"
            print "        test \"$(stat -c \047%U:%G:%a\047 \"$sender_marker_path\")\" = \\"
            print "        \"$sender_marker_expected_metadata\" || return 1"
            print "    require_check \"${sender_marker_label_prefix}_empty\" \\"
            print "        test ! -s \"$sender_marker_path\" || return 1"
            print "    require_check \"${sender_marker_label_prefix}_bytes_zero\" \\"
            print "        test \"$(wc -c <\"$sender_marker_path\")\" -eq 0 || return 1"
            print "    require_check \"${sender_marker_label_prefix}_lines_zero\" \\"
            print "        test \"$(wc -l <\"$sender_marker_path\")\" -eq 0 || return 1"
            print "    require_check \"${sender_marker_label_prefix}_sha256\" \\"
            print "        test \"$(file_hash \"$sender_marker_path\")\" = \\"
            print "        \"$expected_sender_complete_sha256\" || return 1"
            print "    return 0"
            print "}"
            print ""
        }
        BEGIN {
            skip_pre_marker = 0
            skip_post_marker = 0
            inserted_constant = 0
            inserted_function = 0
            replaced_pre_marker = 0
            replaced_post_marker = 0
            inserted_self_test = 0
        }
        {
            raw = $0
            if (skip_pre_marker) {
                if (raw == "        test ! -L \"$retained_release/.complete\"") {
                    skip_pre_marker = 0
                    replaced_pre_marker = 1
                }
                next
            }
            if (skip_post_marker) {
                skip_post_marker = 0
                replaced_post_marker = 1
                next
            }
            if (raw ~ /^readonly expected_manifest_sha256=/) {
                print transform(raw)
                print "readonly expected_sender_complete_sha256=" sender_hash
                inserted_constant = 1
                next
            }
            if (raw == "validate_prestate() {") {
                emit_sender_validator()
                inserted_function = 1
            }
            if (raw == "    require_check retained_complete_absent \\") {
                print "    validate_sender_complete retained_complete \\"
                print "        \"$retained_release/.complete\" caddy-sync:caddy-sync:440"
                skip_pre_marker = 1
                next
            }
            if (raw == "require_check retained_complete_still_absent \\") {
                print "validate_sender_complete retained_complete_still \\"
                print "    \"$retained_release/.complete\" caddy-sync:caddy-sync:440"
                skip_post_marker = 1
                next
            }
            if (raw == "        \"$expected_payload_sha256\" \\") {
                print "        \"$expected_sender_complete_sha256\" \\"
                inserted_self_test = 1
            }
            print transform(raw)
        }
        END {
            if (!inserted_constant || !inserted_function ||
                !replaced_pre_marker || !replaced_post_marker ||
                !inserted_self_test || skip_pre_marker || skip_post_marker) {
                exit 91
            }
        }
    ' "$historical_installer" >"$output_path"
    chmod 0755 "$output_path"
}

render_runner() {
    local historical_runner=$1
    local installer_hash=$2
    local output_path=$3

    awk -v corrected_installer_hash="$installer_hash" '
        {
            line = $0
            gsub(/action_18b/, "action_18b_retry", line)
            gsub(/action18b/, "action18b-retry", line)
            gsub(/ACTION18B_ARCHIVE/, "ACTION18B_RETRY_ARCHIVE", line)
            gsub(/Action 17q retry/, "Action 18b retry", line)
            if (line ~ /^readonly installer_sha256=/) {
                line = "readonly installer_sha256=" corrected_installer_hash
            }
            print line
        }
    ' "$historical_runner" >"$output_path"
    chmod 0755 "$output_path"
}

render_pair() {
    local output_directory=$1
    local historical_directory
    local installer_hash
    local output_installer="$output_directory/$rendered_installer_name"
    local output_runner="$output_directory/$rendered_runner_name"

    [[ -d "$output_directory" && ! -L "$output_directory" ]] || return 1
    historical_directory=$(mktemp -d /tmp/caddy-action18b-retry-historical.XXXXXX)
    trap 'rm -rf -- "$historical_directory"' RETURN
    render_historical_pair "$historical_directory"
    render_installer \
        "$historical_directory/install-node-a-action18-prerequisite-action18b.sh" \
        "$output_installer"
    installer_hash=$(file_hash "$output_installer")
    render_runner \
        "$historical_directory/run-node-a-action18-prerequisite-action18b.sh" \
        "$installer_hash" "$output_runner"
    rm -rf -- "$historical_directory"
    trap - RETURN
}

case "${1:-}" in
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        verify_sources
        self_test_directory=$(mktemp -d /tmp/caddy-action18b-retry-derive.XXXXXX)
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
