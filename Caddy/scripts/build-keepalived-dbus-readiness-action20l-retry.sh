#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20l_retry_builder
readonly source_inspector_sha256=4e3d6139778108fd5aed4cfbcd5175322e0c590404cc106e3b0dac8c66369875
readonly source_outer_sha256=5369e6bff8171344c75e8d31e910748b99c0fab70320e865c9437440ad5b44a7
readonly source_regression_sha256=61f5d58af87e5828de5ffbb08ca4ce3e7ee2c554343c9d0ae4e298323f3546c6

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly source_inspector=$script_directory/inspect-keepalived-dbus-readiness-action20l.sh
readonly source_outer=$script_directory/run-dual-node-keepalived-dbus-readiness-action20l-outer.sh
readonly source_regression=$caddy_root/tests/action20l-keepalived-dbus-readiness-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20l_retry_builder_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20l_retry_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20l_retry_builder_label" >&2
    return 1
}
render_inspector() {
    local action20l_retry_builder_output=$1

    awk '
        /^readonly prefix=action_20l$/ {
            print "readonly prefix=action_20l_retry"
            next
        }
        /^record_check health_metadata_exact / {
            print "action20l_retry_health_metadata_observed=$(stat -c '\''%U:%G:%a'\'' \"$health_helper\" 2>/dev/null || true)"
            print "readonly action20l_retry_health_metadata_observed"
            print "record_check health_metadata_exact test \"$action20l_retry_health_metadata_observed\" = root:root:755"
            next
        }
        /^printf '\''%s_value_node=/ {
            print "printf '\''%s_value_health_metadata=%s\\n'\'' \"$prefix\" \"$action20l_retry_health_metadata_observed\""
        }
        { print }
    ' "$source_inspector" >"$action20l_retry_builder_output" || return 1
}
render_outer() {
    local action20l_retry_builder_inspector_hash=$1
    local action20l_retry_builder_output=$2
    local action20l_retry_builder_stage=$3

    sed \
        -e 's/action_20l_/action_20l_retry_/g' \
        -e 's/CADDY_ACTION20L/CADDY_ACTION20L_RETRY/g' \
        -e 's/caddy-action20l-/caddy-action20l-retry-/g' \
        -e 's/inspect-keepalived-dbus-readiness-action20l\.sh/inspect-keepalived-dbus-readiness-action20l-retry.sh/g' \
        -e 's/readonly expected_remote_line_count=86/readonly expected_remote_line_count=87/' \
        -e "s/$source_inspector_sha256/$action20l_retry_builder_inspector_hash/g" \
        "$source_outer" >"$action20l_retry_builder_stage" || return 1
    awk '
        /^readonly caddy_root=|^readonly shfmt_canonical=/ {
            next
        }
        /run_gate canonical_format \/bin\/bash "\$shfmt_canonical"/ {
            print "    run_gate canonical_format shfmt -d -i 4 -ci \"$inspector\" \"$0\" || return 1"
            next
        }
        /action_20l_retry_value_node action_20l_retry_value_expected_check_count/ {
            sub(/action_20l_retry_value_node/, "action_20l_retry_value_health_metadata action_20l_retry_value_node")
        }
        /require_one_line "action_20l_retry_value_node=/ {
            print "    require_one_line '\''action_20l_retry_value_health_metadata=root:root:755'\'' \"$action20l_outer_stdout\" || return 1"
        }
        { print }
    ' "$action20l_retry_builder_stage" >"$action20l_retry_builder_output" || return 1
}
render_regression() {
    local action20l_retry_builder_inspector_hash=$1
    local action20l_retry_builder_outer_hash=$2
    local action20l_retry_builder_output=$3
    local action20l_retry_builder_stage=$4

    sed \
        -e 's/action_20l_/action_20l_retry_/g' \
        -e 's/action20l_regression/action20l_retry_regression/g' \
        -e 's/ACTION20L_/ACTION20L_RETRY_/g' \
        -e 's/caddy-action20l-/caddy-action20l-retry-/g' \
        -e 's/inspect-keepalived-dbus-readiness-action20l\.sh/inspect-keepalived-dbus-readiness-action20l-retry.sh/g' \
        -e 's/run-dual-node-keepalived-dbus-readiness-action20l-outer\.sh/run-dual-node-keepalived-dbus-readiness-action20l-retry-generated.sh/g' \
        -e 's/readonly expected_remote_line_count=86/readonly expected_remote_line_count=87/' \
        -e "s/$source_inspector_sha256/$action20l_retry_builder_inspector_hash/g" \
        -e "s/$source_outer_sha256/$action20l_retry_builder_outer_hash/g" \
        "$source_regression" >"$action20l_retry_builder_stage" || return 1
    awk '
        /"action_20l_retry_value_node=\$action20l_retry_regression_node"/ {
            printf "%s%c\n", "            '\''action_20l_retry_value_health_metadata=root:root:755'\'' ", 92
        }
        /record_gate reordered_assertion_rejected run_intercepted_case/ {
            print
            getline
            print
            print ""
            printf "%s%c\n", "sed '\''s/action_20l_retry_value_health_metadata=root:root:755/action_20l_retry_value_health_metadata=root:caddy-tls:750/'\'' ", 92
            print "    \"$valid_node_b\" >\"$regression_root/node-b.candidate-metadata\""
            printf "%s%c\n", "record_gate candidate_stage_metadata_rejected run_intercepted_case ", 92
            print "    \"$regression_root/candidate-metadata\" \"$valid_node_a\" \"$regression_root/node-b.candidate-metadata\" 0 97"
            next
        }
        /printf '\''%s_false_positive_reordered_assertion_rejected=true/ {
            print
            print "printf '\''%s_false_positive_candidate_stage_metadata_rejected=true\\n'\'' \"$prefix\""
            next
        }
        { print }
    ' "$action20l_retry_builder_stage" >"$action20l_retry_builder_output" || return 1
}
build() (
    local action20l_retry_builder_output_root=$1
    local action20l_retry_builder_scripts=$action20l_retry_builder_output_root/scripts
    local action20l_retry_builder_tests=$action20l_retry_builder_output_root/tests
    local action20l_retry_builder_inspector=$action20l_retry_builder_scripts/inspect-keepalived-dbus-readiness-action20l-retry.sh
    local action20l_retry_builder_outer=$action20l_retry_builder_scripts/run-dual-node-keepalived-dbus-readiness-action20l-retry-generated.sh
    local action20l_retry_builder_regression=$action20l_retry_builder_tests/action20l-retry-keepalived-dbus-readiness-regression.sh
    local action20l_retry_builder_outer_stage=$action20l_retry_builder_output_root/outer.stage
    local action20l_retry_builder_regression_stage=$action20l_retry_builder_output_root/regression.stage
    local action20l_retry_builder_inspector_hash
    local action20l_retry_builder_outer_hash

    install -d -m 0700 "$action20l_retry_builder_output_root" \
        "$action20l_retry_builder_scripts" "$action20l_retry_builder_tests" || return 1
    record_check source_inspector_hash test "$(file_hash "$source_inspector")" = "$source_inspector_sha256" || return 1
    record_check source_outer_hash test "$(file_hash "$source_outer")" = "$source_outer_sha256" || return 1
    record_check source_regression_hash test "$(file_hash "$source_regression")" = "$source_regression_sha256" || return 1
    render_inspector "$action20l_retry_builder_inspector" || return 1
    chmod 0755 "$action20l_retry_builder_inspector" || return 1
    action20l_retry_builder_inspector_hash=$(file_hash "$action20l_retry_builder_inspector") || return 1
    render_outer "$action20l_retry_builder_inspector_hash" \
        "$action20l_retry_builder_outer" "$action20l_retry_builder_outer_stage" || return 1
    rm -f -- "$action20l_retry_builder_outer_stage" || return 1
    chmod 0755 "$action20l_retry_builder_outer" || return 1
    action20l_retry_builder_outer_hash=$(file_hash "$action20l_retry_builder_outer") || return 1
    render_regression "$action20l_retry_builder_inspector_hash" \
        "$action20l_retry_builder_outer_hash" "$action20l_retry_builder_regression" \
        "$action20l_retry_builder_regression_stage" || return 1
    rm -f -- "$action20l_retry_builder_regression_stage" || return 1
    chmod 0755 "$action20l_retry_builder_regression" || return 1
    printf '%s_value_inspector_sha256=%s\n' "$prefix" "$action20l_retry_builder_inspector_hash"
    printf '%s_value_outer_sha256=%s\n' "$prefix" "$action20l_retry_builder_outer_hash"
    printf '%s_value_regression_sha256=%s\n' "$prefix" "$(file_hash "$action20l_retry_builder_regression")"
    printf '%s_complete=true\n' "$prefix"
)
self_test() (
    local action20l_retry_builder_self_root

    action20l_retry_builder_self_root=$(mktemp -d /tmp/caddy-action20l-retry-builder.XXXXXX) || return 1
    trap 'rm -rf -- "$action20l_retry_builder_self_root"' EXIT
    build "$action20l_retry_builder_self_root/output" >/dev/null || return 1
    /bin/bash -n \
        "$action20l_retry_builder_self_root/output/scripts/inspect-keepalived-dbus-readiness-action20l-retry.sh" \
        "$action20l_retry_builder_self_root/output/scripts/run-dual-node-keepalived-dbus-readiness-action20l-retry-generated.sh" \
        "$action20l_retry_builder_self_root/output/tests/action20l-retry-keepalived-dbus-readiness-regression.sh" || return 1
    /bin/bash "$action20l_retry_builder_self_root/output/scripts/inspect-keepalived-dbus-readiness-action20l-retry.sh" \
        --self-test >/dev/null || return 1
    printf '%s_self_test_complete=true\n' "$prefix"
)

case "${1:-}" in
    --output)
        [[ $# -eq 2 && "$2" = /* && ! -e "$2" ]] || exit 64
        build "$2"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        ;;
    *)
        printf 'Usage: %s --output ABSENT_ABSOLUTE_DIRECTORY | --self-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
