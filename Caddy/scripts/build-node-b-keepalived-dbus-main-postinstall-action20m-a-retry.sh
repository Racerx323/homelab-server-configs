#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20m_a_retry_builder
readonly source_inspector_sha256=a40acf039a4be8a47a3deb786ed241baf0c305fd4f8b25c4224781646ffca1df
readonly source_outer_sha256=cc6d8179dbb85bb4411043854ad8dde17c6f212fbcc397eb9a748e56525d47fe
readonly source_regression_sha256=833734a55bfc78c45bfcf9eeb7736d5823980e96b79e1ca9fde166502822dd18

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly source_inspector=$script_directory/inspect-node-b-keepalived-dbus-main-postinstall-action20m-a.sh
readonly source_outer=$script_directory/run-node-b-keepalived-dbus-main-postinstall-action20m-a-outer.sh
readonly source_regression=$caddy_root/tests/action20m-a-node-b-keepalived-dbus-main-postinstall-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action20ma_retry_builder_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action20ma_retry_builder_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action20ma_retry_builder_label" >&2
    return 1
}
render_regression() {
    local action20ma_retry_builder_output=$1
    local action20ma_retry_builder_stage=$2

    sed \
        -e 's/action_20m_a_regression/action_20m_a_retry_regression/g' \
        -e 's/action20ma_regression/action20ma_retry_regression/g' \
        -e 's/CADDY_ACTION20MA_/CADDY_ACTION20MA_RETRY_/g' \
        -e 's/caddy-action20m-a-regression/caddy-action20m-a-retry-regression/g' \
        -e 's/run-node-b-keepalived-dbus-main-postinstall-action20m-a-outer\.sh/run-node-b-keepalived-dbus-main-postinstall-action20m-a-retry-generated.sh/g' \
        -e 's/action_20m_a_outer_complete/action_20m_a_retry_complete/g' \
        "$source_regression" >"$action20ma_retry_builder_stage" || return 1
    awk '
        /^readonly caddy_root=/ {
            print "readonly caddy_root=${CADDY_ACTION20MA_RETRY_SOURCE_ROOT:?}"
            next
        }
        /^readonly outer=/ {
            print "readonly outer=$test_directory/../scripts/run-node-b-keepalived-dbus-main-postinstall-action20m-a-retry-generated.sh"
            next
        }
        /^readonly collision_checker=/ {
            print "readonly collision_checker=$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh"
            next
        }
        $0 == "        \047set -Eeuo pipefail\047 \\" {
            print
            print "        \047[[ \"${!#}\" = \"cd / && sudo -n /bin/bash -s --\" ]] || exit 71\047 \\"
            next
        }
        { print }
    ' "$action20ma_retry_builder_stage" >"$action20ma_retry_builder_output" || return 1
}
render_outer() {
    local action20ma_retry_builder_regression_hash=$1
    local action20ma_retry_builder_output=$2

    sed \
        -e 's/action_20m_a_outer/action_20m_a_retry/g' \
        -e 's/action20ma_outer/action20ma_retry/g' \
        -e 's/CADDY_ACTION20MA_/CADDY_ACTION20MA_RETRY_/g' \
        -e 's/caddy-action20m-a-outer/caddy-action20m-a-retry/g' \
        -e 's/action20m-a-node-b-keepalived-dbus-main-postinstall-regression\.sh/action20m-a-retry-node-b-keepalived-dbus-main-postinstall-regression.sh/g' \
        -e "s/$source_regression_sha256/$action20ma_retry_builder_regression_hash/g" \
        -e "s|'sudo -n /bin/bash -s'|'cd / \&\& sudo -n /bin/bash -s --'|" \
        "$source_outer" | awk '
            /^readonly caddy_root=/ {
                print "readonly caddy_root=${CADDY_ACTION20MA_RETRY_SOURCE_ROOT:?}"
                next
            }
            /^readonly regression=/ {
                print "readonly regression=$script_directory/../tests/action20m-a-retry-node-b-keepalived-dbus-main-postinstall-regression.sh"
                next
            }
            /^readonly shfmt_canonical=/ {
                next
            }
            /run_gate canonical_format \/bin\/bash "\$shfmt_canonical" --check/ {
                getline
                print "    run_gate canonical_format shfmt -d -i 4 -ci \"$inspector\" \"$regression\" \"$0\" || return 1"
                next
            }
            { print }
        ' >"$action20ma_retry_builder_output" || return 1
}
build() (
    local action20ma_retry_builder_output_root=$1
    local action20ma_retry_builder_scripts=$action20ma_retry_builder_output_root/scripts
    local action20ma_retry_builder_tests=$action20ma_retry_builder_output_root/tests
    local action20ma_retry_builder_inspector=$action20ma_retry_builder_scripts/inspect-node-b-keepalived-dbus-main-postinstall-action20m-a.sh
    local action20ma_retry_builder_outer=$action20ma_retry_builder_scripts/run-node-b-keepalived-dbus-main-postinstall-action20m-a-retry-generated.sh
    local action20ma_retry_builder_regression=$action20ma_retry_builder_tests/action20m-a-retry-node-b-keepalived-dbus-main-postinstall-regression.sh
    local action20ma_retry_builder_regression_stage=$action20ma_retry_builder_output_root/regression.stage
    local action20ma_retry_builder_regression_hash

    install -d -m 0700 "$action20ma_retry_builder_output_root" \
        "$action20ma_retry_builder_scripts" "$action20ma_retry_builder_tests" || return 1
    record_check source_inspector_hash test "$(file_hash "$source_inspector")" = "$source_inspector_sha256" || return 1
    record_check source_outer_hash test "$(file_hash "$source_outer")" = "$source_outer_sha256" || return 1
    record_check source_regression_hash test "$(file_hash "$source_regression")" = "$source_regression_sha256" || return 1
    install -m 0755 "$source_inspector" "$action20ma_retry_builder_inspector" || return 1
    render_regression "$action20ma_retry_builder_regression" \
        "$action20ma_retry_builder_regression_stage" || return 1
    rm -f -- "$action20ma_retry_builder_regression_stage" || return 1
    chmod 0755 "$action20ma_retry_builder_regression" || return 1
    action20ma_retry_builder_regression_hash=$(file_hash "$action20ma_retry_builder_regression") || return 1
    render_outer "$action20ma_retry_builder_regression_hash" \
        "$action20ma_retry_builder_outer" || return 1
    chmod 0755 "$action20ma_retry_builder_outer" || return 1
    printf '%s_value_inspector_sha256=%s\n' "$prefix" "$(file_hash "$action20ma_retry_builder_inspector")"
    printf '%s_value_outer_sha256=%s\n' "$prefix" "$(file_hash "$action20ma_retry_builder_outer")"
    printf '%s_value_regression_sha256=%s\n' "$prefix" "$action20ma_retry_builder_regression_hash"
    printf '%s_complete=true\n' "$prefix"
)
self_test() (
    local action20ma_retry_builder_root

    action20ma_retry_builder_root=$(mktemp -d /tmp/caddy-action20m-a-retry-builder.XXXXXX) || return 1
    trap 'rm -rf -- "$action20ma_retry_builder_root"' EXIT
    build "$action20ma_retry_builder_root/generated" >/dev/null || return 1
    /bin/bash -n \
        "$action20ma_retry_builder_root/generated/scripts/inspect-node-b-keepalived-dbus-main-postinstall-action20m-a.sh" \
        "$action20ma_retry_builder_root/generated/scripts/run-node-b-keepalived-dbus-main-postinstall-action20m-a-retry-generated.sh" \
        "$action20ma_retry_builder_root/generated/tests/action20m-a-retry-node-b-keepalived-dbus-main-postinstall-regression.sh" || return 1
    CADDY_ACTION20MA_RETRY_SOURCE_ROOT=$caddy_root /bin/bash \
        "$action20ma_retry_builder_root/generated/tests/action20m-a-retry-node-b-keepalived-dbus-main-postinstall-regression.sh" >/dev/null || return 1
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
