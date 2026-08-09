#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20p_a_retry_outer
readonly source_inspector_sha256=55bf9878744e75ff7f79cb93d565cd4c5bb3e500bc2a575c04333e94456ee2f8
readonly source_outer_sha256=e2450fc5d10115d7576d8ad39535688e5abf29c43f028b8b27de03e4d30730e3
readonly rendered_inspector_sha256=a72b9ae988513de85bc0dc15bcdb777482e2d769e4458a6046fd4da90c678663
readonly rendered_core_sha256=bd1e83db6c7682385a5497df9a9aa20813016cb63a5fc86a400e103b6e00efb7
readonly regression_sha256=63b5de59aee07c623064a20653643de2c92f1698852c8adbcc696c87f90de1fc
readonly maximum_stream_bytes=4194304
readonly maximum_stream_lines=32768

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly source_inspector=$script_directory/inspect-dual-node-keepalived-post-action20p-a.sh
readonly source_outer=$script_directory/run-dual-node-keepalived-post-action20p-a-outer.sh
readonly regression=$caddy_root/tests/action20p-a-retry-dual-node-postactivation-regression.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs)
            [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || return 1
            return 0
            ;;
        *) return 1 ;;
    esac
}
render_inspector() {
    local action20pa_retry_rendered_inspector=$1
    local action20pa_retry_include_corrected=$2

    sed 's@include /etc/keepalived/conf.d/\*\.conf@include /etc/keepalived/conf.d/caddy-ha.conf@g' \
        "$source_inspector" >"$action20pa_retry_include_corrected" || return 1
    awk '
        /^normalized_list_hash\(\) \{/ { skip_normalizer=1; next }
        skip_normalizer { if ($0 == "}") skip_normalizer=0; next }
        /^state_snapshot\(\) \{/ {
            print "state_snapshot() {"
            print "    printf \047files=%s|%s|%s\\n\047 \\"
            print "        \042$(file_hash \042$main_configuration\042 2>/dev/null || printf unavailable)\042 \\"
            print "        \042$(file_hash \042$fragment\042 2>/dev/null || printf unavailable)\042 \\"
            print "        \042$(file_hash \042$health_helper\042 2>/dev/null || printf unavailable)\042"
            print "    printf \047services=%s|%s|%s|%s|%s\\n\047 \\"
            print "        \042$(systemctl is-active keepalived.service 2>/dev/null || printf unavailable)\042 \\"
            print "        \042$(systemctl is-active caddy.service 2>/dev/null || printf unavailable)\042 \\"
            print "        \042$(systemctl is-active lighttpd.service 2>/dev/null || printf unavailable)\042 \\"
            print "        \042$(systemctl show keepalived.service -p MainPID --value 2>/dev/null || printf unavailable)\042 \\"
            print "        \042$(systemctl show keepalived.service -p NRestarts --value 2>/dev/null || printf unavailable)\042"
            print "    printf \047addresses=%s|%s|%s|%s|%s|%s\\n\047 \\"
            print "        \042$action20pa_ip4_status\042 \042$action20pa_ip6_status\042 \\"
            print "        \042$(address_count \042$action20pa_ip4_status\042 \042$action20pa_ip4_output\042 \042$caddy_ipv4_cidr\042 || printf query_failed)\042 \\"
            print "        \042$(address_count \042$action20pa_ip6_status\042 \042$action20pa_ip6_output\042 \042$caddy_ipv6_cidr\042 || printf query_failed)\042 \\"
            print "        \042$(address_count \042$action20pa_ip4_status\042 \042$action20pa_ip4_output\042 \042$dns_ipv4_cidr\042 || printf query_failed)\042 \\"
            print "        \042$(address_count \042$action20pa_ip6_status\042 \042$action20pa_ip6_output\042 \042$dns_ipv6_cidr\042 || printf query_failed)\042"
            print "    printf \047vrrp=%s\\n\047 \042$(sed -n \0471p\047 /run/caddy-ha/vrrp-state 2>/dev/null || printf unavailable)\042"
            print "    printf \047dbus=%s|%s|%s|%s|%s|%s|%s\\n\047 \\"
            print "        \042$action20pa_dbus_list_status\042 \042$action20pa_dbus_tree_status\042 \\"
            print "        \042$(printf \047%s\\n\047 \042$action20pa_dbus_list_output\042 | awk -v expected=\042$dbus_service\042 \047$1 == expected { count++ } END { print count + 0 }\047)\042 \\"
            print "        \042$(printf \047%s\\n\047 \042$action20pa_dbus_tree_output\042 | awk -v expected=\042$dbus_ipv4_object\042 \047$0 == expected { count++ } END { print count + 0 }\047)\042 \\"
            print "        \042$(printf \047%s\\n\047 \042$action20pa_dbus_tree_output\042 | awk -v expected=\042$dbus_ipv6_object\042 \047$0 == expected { count++ } END { print count + 0 }\047)\042 \\"
            print "        \042$action20pa_dbus_ipv4_state_output\042 \042$action20pa_dbus_ipv6_state_output\042"
            print "}"
            skip_snapshot=1
            next
        }
        skip_snapshot { if ($0 == "}") skip_snapshot=0; next }
        { print }
    ' "$action20pa_retry_include_corrected" >"$action20pa_retry_rendered_inspector" || return 1
}
render_core() {
    local action20pa_retry_rendered_core=$1

    # The environment expression must remain literal in the rendered core.
    # shellcheck disable=SC2016
    sed \
        -e 's/readonly prefix=action_20p_a_outer/readonly prefix=action_20p_a_retry_core/' \
        -e "s/readonly inspector_sha256=$source_inspector_sha256/readonly inspector_sha256=$rendered_inspector_sha256/" \
        -e 's@readonly inspector=$script_directory/inspect-dual-node-keepalived-post-action20p-a.sh@readonly inspector=${CADDY_ACTION20PA_RETRY_INSPECTOR:?}@' \
        "$source_outer" >"$action20pa_retry_rendered_core" || return 1
}
render_artifacts() {
    local action20pa_retry_root=$1

    render_inspector "$action20pa_retry_root/inspector" "$action20pa_retry_root/include-corrected" || return 1
    render_core "$action20pa_retry_root/core" || return 1
    chmod 0700 "$action20pa_retry_root/inspector" "$action20pa_retry_root/core" || return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory source_inspector_regular source_inspector_executable \
        source_inspector_hash source_outer_regular source_outer_executable source_outer_hash \
        regression_regular regression_executable regression_hash rendered_inspector_hash \
        rendered_core_hash rendered_syntax rendered_shellcheck include_exact_once \
        include_terminal_exact wildcard_include_absent raw_snapshot_hashing_absent \
        semantic_snapshot_present source_inspector_self_test collision_policy \
        conditional_policy output_evidence_policy multifile_grep_policy portable_awk_policy \
        root_cwd_policy
}
run_gate() {
    local action20pa_retry_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20pa_retry_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20pa_retry_gate_label" >&2
    return 1
}
run_local_gates() {
    local action20pa_retry_root=$1
    local action20pa_retry_run_regression=$2

    run_gate working_directory working_directory_approved || return 1
    run_gate source_inspector_regular test -f "$source_inspector" || return 1
    run_gate source_inspector_executable test -x "$source_inspector" || return 1
    run_gate source_inspector_hash test "$(file_hash "$source_inspector")" = "$source_inspector_sha256" || return 1
    run_gate source_outer_regular test -f "$source_outer" || return 1
    run_gate source_outer_executable test -x "$source_outer" || return 1
    run_gate source_outer_hash test "$(file_hash "$source_outer")" = "$source_outer_sha256" || return 1
    run_gate regression_regular test -f "$regression" || return 1
    run_gate regression_executable test -x "$regression" || return 1
    run_gate regression_hash test "$(file_hash "$regression")" = "$regression_sha256" || return 1
    run_gate rendered_inspector_hash test "$(file_hash "$action20pa_retry_root/inspector")" = "$rendered_inspector_sha256" || return 1
    run_gate rendered_core_hash test "$(file_hash "$action20pa_retry_root/core")" = "$rendered_core_sha256" || return 1
    run_gate rendered_syntax /bin/bash -n "$action20pa_retry_root/inspector" "$action20pa_retry_root/core" "$0" || return 1
    run_gate rendered_shellcheck shellcheck "$action20pa_retry_root/inspector" "$action20pa_retry_root/core" "$0" || return 1
    run_gate include_exact_once test "$(grep -Fc 'include /etc/keepalived/conf.d/caddy-ha.conf' "$action20pa_retry_root/inspector")" -eq 2 || return 1
    run_gate include_terminal_exact grep -Fq "= 'include /etc/keepalived/conf.d/caddy-ha.conf'" "$action20pa_retry_root/inspector" || return 1
    run_gate wildcard_include_absent test "$(grep -Fc 'include /etc/keepalived/conf.d/*.conf' "$action20pa_retry_root/inspector" || true)" -eq 0 || return 1
    # The dollar-prefixed names are literal rendered-source patterns.
    # shellcheck disable=SC2016
    run_gate raw_snapshot_hashing_absent test "$(grep -Ec 'normalized_list_hash|text_hash \"\$action20pa_ip[46]_output\"' "$action20pa_retry_root/inspector" || true)" -eq 0 || return 1
    run_gate semantic_snapshot_present test "$(grep -Ec "printf 'addresses=|printf 'dbus=" "$action20pa_retry_root/inspector")" -eq 2 || return 1
    run_gate source_inspector_self_test /bin/bash "$source_inspector" --self-test || return 1
    run_gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" "$0" || return 1
    run_gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    run_gate output_evidence_policy /bin/bash "$caddy_root/tests/transaction-output-evidence-policy-regression.sh" || return 1
    run_gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check "$0" || return 1
    run_gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check "$0" || return 1
    run_gate root_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" --check "$action20pa_retry_root/core" || return 1
    if [[ "$action20pa_retry_run_regression" = true ]]; then
        if /bin/bash "$regression" >/dev/null; then
            printf '%s_regression=true\n' "$prefix"
        else
            printf '%s_regression=false\n' "$prefix" >&2
            return 1
        fi
    else
        printf '%s_regression_skipped_for_transport_test=true\n' "$prefix"
    fi
}
safe_stream() {
    local action20pa_retry_stream=$1

    [[ "$(wc -c <"$action20pa_retry_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action20pa_retry_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action20pa_retry_stream" >/dev/null || return 1
    ! grep -Eqi \
        'BEGIN [A-Z ]*PRIVATE KEY|CADDY_TLS_PRIVATE_KEY_PEM|PRIVATE_KEY=|DOPPLER_TOKEN|Authorization:[[:space:]]*Bearer' \
        "$action20pa_retry_stream"
}
emit_stream() {
    local action20pa_retry_stream_label=$1
    local action20pa_retry_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action20pa_retry_stream_label" "$(wc -c <"$action20pa_retry_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action20pa_retry_stream_label" "$(line_count "$action20pa_retry_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action20pa_retry_stream_label" "$(file_hash "$action20pa_retry_stream")"
    if safe_stream "$action20pa_retry_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action20pa_retry_stream_label"
        if [[ -s "$action20pa_retry_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action20pa_retry_stream_label"
            cat "$action20pa_retry_stream"
            printf '%s_%s_end\n' "$prefix" "$action20pa_retry_stream_label"
        else
            printf '%s_%s_content=empty\n' "$prefix" "$action20pa_retry_stream_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action20pa_retry_stream_label" >&2
    return 97
}
run_core() {
    local action20pa_retry_root=$1
    local action20pa_retry_status=0
    local action20pa_retry_ssh=${CADDY_ACTION20PA_RETRY_SSH_BIN:-/usr/bin/ssh}

    CADDY_ACTION20PA_RETRY_INSPECTOR=$action20pa_retry_root/inspector \
        CADDY_ACTION20PA_SSH_BIN=$action20pa_retry_ssh \
        /bin/bash "$action20pa_retry_root/core" --transport-test \
        >"$action20pa_retry_root/stdout" 2>"$action20pa_retry_root/stderr" || action20pa_retry_status=$?
    emit_stream core_stdout "$action20pa_retry_root/stdout" || return $?
    emit_stream core_stderr "$action20pa_retry_root/stderr" || return $?
    printf '%s_core_status=%s\n' "$prefix" "$action20pa_retry_status"
    [[ "$action20pa_retry_status" -eq 0 ]] || return "$action20pa_retry_status"
    [[ ! -s "$action20pa_retry_root/stderr" ]] || return 97
    grep -Fqx 'action_20p_a_retry_core_complete=true' "$action20pa_retry_root/stdout" || return 97
    printf '%s_node_a_contacted=true\n' "$prefix"
    printf '%s_node_b_contacted=true\n' "$prefix"
    printf '%s_read_only=true\n' "$prefix"
    printf '%s_keepalived_reload=false\n' "$prefix"
    printf '%s_keepalived_restart=false\n' "$prefix"
    printf '%s_persistent_live_mutations=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}
run_action() (
    local action20pa_retry_run_regression=$1
    local action20pa_retry_root

    action20pa_retry_root=$(mktemp -d /tmp/caddy-action20p-a-retry-outer.XXXXXX) || return 1
    trap 'rm -rf -- "$action20pa_retry_root"' EXIT INT TERM
    install -m 0600 /dev/null "$action20pa_retry_root/stdout" || return 1
    install -m 0600 /dev/null "$action20pa_retry_root/stderr" || return 1
    render_artifacts "$action20pa_retry_root" || return 1
    run_local_gates "$action20pa_retry_root" "$action20pa_retry_run_regression" || return 1
    run_core "$action20pa_retry_root"
)
self_test() (
    local action20pa_retry_root

    action20pa_retry_root=$(mktemp -d /tmp/caddy-action20p-a-retry-self-test.XXXXXX) || return 1
    trap 'rm -rf -- "$action20pa_retry_root"' EXIT INT TERM
    render_artifacts "$action20pa_retry_root" || return 1
    run_local_gates "$action20pa_retry_root" false || return 1
    printf '%s_node_a_contacted=false\n' "$prefix"
    printf '%s_node_b_contacted=false\n' "$prefix"
    printf '%s_self_test_complete=true\n' "$prefix"
)
render_hashes() (
    local action20pa_retry_root

    action20pa_retry_root=$(mktemp -d /tmp/caddy-action20p-a-retry-render.XXXXXX) || return 1
    trap 'rm -rf -- "$action20pa_retry_root"' EXIT INT TERM
    render_artifacts "$action20pa_retry_root" || return 1
    printf 'rendered_inspector_sha256=%s\n' "$(file_hash "$action20pa_retry_root/inspector")"
    printf 'rendered_core_sha256=%s\n' "$(file_hash "$action20pa_retry_root/core")"
)
render_check() (
    local action20pa_retry_root

    action20pa_retry_root=$(mktemp -d /tmp/caddy-action20p-a-retry-check.XXXXXX) || return 1
    trap 'rm -rf -- "$action20pa_retry_root"' EXIT INT TERM
    render_artifacts "$action20pa_retry_root" || return 1
    /bin/bash -n "$action20pa_retry_root/inspector" "$action20pa_retry_root/core" || return 1
    shellcheck "$action20pa_retry_root/inspector" "$action20pa_retry_root/core"
)
validate_fixture_pair() (
    local action20pa_retry_node_a_fixture=$1
    local action20pa_retry_node_b_fixture=$2
    local action20pa_retry_root

    action20pa_retry_root=$(mktemp -d /tmp/caddy-action20p-a-retry-fixture.XXXXXX) || return 1
    trap 'rm -rf -- "$action20pa_retry_root"' EXIT INT TERM
    render_artifacts "$action20pa_retry_root" || return 1
    CADDY_ACTION20PA_RETRY_INSPECTOR=$action20pa_retry_root/inspector \
        /bin/bash "$action20pa_retry_root/core" --validate-transcript \
        "$action20pa_retry_node_a_fixture" node-a || return 1
    CADDY_ACTION20PA_RETRY_INSPECTOR=$action20pa_retry_root/inspector \
        /bin/bash "$action20pa_retry_root/core" --validate-transcript \
        "$action20pa_retry_node_b_fixture" node-b
)

case "${1:-}" in
    --render-hashes)
        [[ $# -eq 1 ]] || exit 64
        render_hashes
        ;;
    --render-check)
        [[ $# -eq 1 ]] || exit 64
        render_check
        ;;
    --expected-local-gates)
        [[ $# -eq 1 ]] || exit 64
        expected_local_gates
        ;;
    --validate-fixtures)
        [[ $# -eq 3 && -f "$2" && -f "$3" ]] || exit 64
        validate_fixture_pair "$2" "$3"
        ;;
    --self-test)
        [[ $# -eq 1 ]] || exit 64
        self_test
        ;;
    --transport-test)
        [[ $# -eq 1 && -n "${CADDY_ACTION20PA_RETRY_SSH_BIN:-}" ]] || exit 64
        run_action false
        ;;
    "")
        [[ $# -eq 0 ]] || exit 64
        run_action true
        ;;
    *) exit 64 ;;
esac
