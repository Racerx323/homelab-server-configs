#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_29_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-final-deployment-action29.sh
readonly outer=$caddy_root/scripts/run-final-deployment-acceptance-action29-outer.sh
fixture_root=

check() {
    local action29_regression_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action29_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action29_regression_label" >&2
    return 1
}
accept_node() {
    local action29_regression_role=$1
    local action29_regression_stdout=$2

    /bin/bash "$outer" --validate-node-transcript "$action29_regression_role" \
        "$action29_regression_stdout" 0 "$fixture_root/empty"
}
reject_node() {
    local action29_regression_role=$1
    local action29_regression_stdout=$2

    if accept_node "$action29_regression_role" "$action29_regression_stdout"; then
        return 1
    fi
}
accept_component() {
    local action29_regression_label=$1
    local action29_regression_stdout=$2

    /bin/bash "$outer" --validate-component-transcript "$action29_regression_label" \
        "$action29_regression_stdout" 0 "$fixture_root/empty"
}
reject_component() {
    local action29_regression_label=$1
    local action29_regression_stdout=$2

    if accept_component "$action29_regression_label" "$action29_regression_stdout"; then
        return 1
    fi
}
run_regression() {
    local action29_regression_role
    local action29_regression_token
    local action29_regression_valid
    local action29_regression_altered
    local action29_regression_marker
    local action29_regression_component

    fixture_root=$(mktemp -d /tmp/action29-regression.XXXXXX) || return 1
    trap 'rm -rf -- "$fixture_root"' EXIT INT TERM
    install -m 0600 /dev/null "$fixture_root/empty" || return 1

    # conditional-validator-explicit-failures-begin
    for action29_regression_role in node-a node-b; do
        action29_regression_token=${action29_regression_role//-/_}
        action29_regression_valid=$fixture_root/$action29_regression_token.valid
        /bin/bash "$inspector" --self-test-node "$action29_regression_role" \
            >"$action29_regression_valid" || return 1
        check "${action29_regression_token}_real_producer_accepted" accept_node \
            "$action29_regression_role" "$action29_regression_valid" || return 1

        action29_regression_altered=$fixture_root/$action29_regression_token.false
        sed '0,/=true$/s//=false/' "$action29_regression_valid" >"$action29_regression_altered" || return 1
        check "${action29_regression_token}_false_rejected" reject_node \
            "$action29_regression_role" "$action29_regression_altered" || return 1

        action29_regression_altered=$fixture_root/$action29_regression_token.missing
        sed '1d' "$action29_regression_valid" >"$action29_regression_altered" || return 1
        check "${action29_regression_token}_missing_rejected" reject_node \
            "$action29_regression_role" "$action29_regression_altered" || return 1

        action29_regression_altered=$fixture_root/$action29_regression_token.duplicate
        cp -- "$action29_regression_valid" "$action29_regression_altered" || return 1
        sed -n '1p' "$action29_regression_valid" >>"$action29_regression_altered" || return 1
        check "${action29_regression_token}_duplicate_rejected" reject_node \
            "$action29_regression_role" "$action29_regression_altered" || return 1
    done

    for action29_regression_component in dns web protocol tls; do
        case "$action29_regression_component" in
            dns) action29_regression_marker=action_24_retry_outer_complete=true ;;
            web) action29_regression_marker=action_25_retry2_outer_complete=true ;;
            protocol) action29_regression_marker=action_26_h3_retry_complete=true ;;
            tls) action29_regression_marker=action_27_retry3_outer_complete=true ;;
            *) return 64 ;;
        esac
        printf '%s\n' "$action29_regression_marker" >"$fixture_root/$action29_regression_component.valid"
        check "${action29_regression_component}_component_accepted" accept_component \
            "$action29_regression_component" "$fixture_root/$action29_regression_component.valid" || return 1
        install -m 0600 /dev/null "$fixture_root/$action29_regression_component.missing" || return 1
        check "${action29_regression_component}_missing_rejected" reject_component \
            "$action29_regression_component" "$fixture_root/$action29_regression_component.missing" || return 1
        {
            printf '%s\n' "$action29_regression_marker"
            printf 'fixture_check_injected=false\n'
        } >"$fixture_root/$action29_regression_component.false"
        check "${action29_regression_component}_false_rejected" reject_component \
            "$action29_regression_component" "$fixture_root/$action29_regression_component.false" || return 1
    done
    # shellcheck disable=SC2016
    check production_remote_cwd grep -Fq \
        '"cd / && sudo -n /bin/bash -s -- --node $action29_outer_role"' "$outer" || return 1
    # shellcheck disable=SC2016
    check production_inspector_stream grep -Fq '<"$inspector"' "$outer" || return 1
    # shellcheck disable=SC2016
    check production_capture_before_ssh grep -Fq \
        'prepare_capture "$action29_outer_stdout" "$action29_outer_stderr" "$action29_outer_status_file"' \
        "$outer" || return 1
    check no_mutation_commands test -z \
        "$(grep -E 'systemctl (start|stop|restart|reload|enable|disable)|install -[A-Za-z]*m [^0].* /etc/' \
            "$inspector" || true)" || return 1
    # conditional-validator-explicit-failures-end

    printf '%s_real_producer_coverage=true\n' "$prefix"
    printf '%s_negative_coverage=true\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

run_regression
