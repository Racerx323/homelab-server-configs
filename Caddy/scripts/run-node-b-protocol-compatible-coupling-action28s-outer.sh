#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_28s_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly transaction_sha256=40649ef09d9b63be9094e29d132a14d55379e0c578e1a69eff18e0d8f4e80178
readonly node_b_inspector_sha256=9d835b805b21262b51c50749b5671223ced5f049991ffdf841054e413dec596b
readonly node_a_inspector_sha256=38bbc1b3fc4dc35bc3847fcbf3233d7e7822065f5c71bafb49ee999dab4c56d1
readonly source_sha256=034ee9c45acaca4e48e2faeda24cd371e945bdb52a117b5871403958ab36794c
readonly manifest_sha256=77977bfbfa5194436c3a8d574c878af5398c7f33631298f9d1f780fc0d7b21cd
readonly regression_sha256=175b38d4e41cdd93143e4f3d44917ffc701488b90ff5fb0cb943ae95daee86a7
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=16384
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly workspace_root=${caddy_root%/homelab-server-configs/Caddy}
readonly transaction=$script_directory/install-node-b-protocol-compatible-coupling-action28s.sh
readonly node_b_inspector=$script_directory/inspect-node-b-caddy-vrrp-relinquish-action28p-a.sh
readonly node_a_inspector=$script_directory/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly source_configuration=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
readonly manifest=$caddy_root/manifests/caddy-protocol-compatible-coupling-action28s.yaml
readonly regression=$caddy_root/tests/action28s-node-b-installation-regression.sh
evidence_root=${CADDY_ACTION28S_EVIDENCE_ROOT:-/tmp/caddy-ssh-evidence/action28s}
readonly evidence_root
ssh_binary=${CADDY_ACTION28S_SSH_BIN:-/usr/bin/ssh}

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_source() {
    local action28s_outer_hash=$1
    local action28s_outer_file=$2

    [[ -f "$action28s_outer_file" && ! -L "$action28s_outer_file" ]] || return 1
    [[ "$(file_hash "$action28s_outer_file")" = "$action28s_outer_hash" ]]
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs) [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] ;;
        *) return 1 ;;
    esac
}
gate() {
    local action28s_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28s_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28s_outer_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory transaction_source node_b_inspector_source \
        node_a_inspector_source source_configuration manifest regression_source \
        syntax transaction_self_test regression shellcheck canonical_format \
        collision_policy conditional_policy multifile_grep_policy portable_awk_policy \
        root_cwd_policy ssh_evidence_policy outer_labels accepted_live_hash_policy \
        evidence_root_created evidence_directory_created node_a_preflight \
        node_b_preflight node_b_transaction node_a_postflight
}
safe_stream() {
    local action28s_outer_stream=$1

    [[ "$(wc -c <"$action28s_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28s_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28s_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
        "$action28s_outer_stream"
}
emit_stream() {
    local action28s_outer_label=$1
    local action28s_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28s_outer_label" "$(wc -c <"$action28s_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28s_outer_label" "$(line_count "$action28s_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28s_outer_label" "$(file_hash "$action28s_outer_stream")"
    if safe_stream "$action28s_outer_stream"; then
        printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28s_outer_label"
        if [[ -s "$action28s_outer_stream" ]]; then
            printf '%s_%s_begin\n' "$prefix" "$action28s_outer_label"
            cat "$action28s_outer_stream"
            printf '%s_%s_end\n' "$prefix" "$action28s_outer_label"
        else
            printf '%s_%s_content=empty\n' "$prefix" "$action28s_outer_label"
        fi
        return 0
    fi
    printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28s_outer_label" >&2
    return 97
}
require_one() {
    local action28s_outer_line=$1
    local action28s_outer_file=$2

    [[ "$(grep -Fxc "$action28s_outer_line" "$action28s_outer_file" || true)" -eq 1 ]]
}
validate_ordered_checks() {
    local action28s_outer_source=$1
    local action28s_outer_output_prefix=$2
    local action28s_outer_stdout=$3
    local action28s_outer_status=$4
    local action28s_outer_option=$5
    local action28s_outer_expected=$6
    local action28s_outer_actual=$7

    [[ "$action28s_outer_status" -eq 0 ]] || return 1
    "$action28s_outer_source" "$action28s_outer_option" >"$action28s_outer_expected" || return 1
    sed -n "s/^${action28s_outer_output_prefix}_check_\\([a-z0-9_]*\\)=true$/\\1/p" \
        "$action28s_outer_stdout" >"$action28s_outer_actual" || return 1
    [[ -s "$action28s_outer_expected" ]] || return 1
    [[ "$(LC_ALL=C sort -u "$action28s_outer_expected" | wc -l)" -eq "$(line_count "$action28s_outer_expected")" ]] || return 1
    diff -u "$action28s_outer_expected" "$action28s_outer_actual" >/dev/null || return 1
    [[ "$(grep -Ec "^${action28s_outer_output_prefix}_check_[a-z0-9_]+=false$" "$action28s_outer_stdout" || true)" -eq 0 ]]
}
validate_node_a() {
    local action28s_outer_stdout=$1
    local action28s_outer_stderr=$2
    local action28s_outer_status=$3
    local action28s_outer_expected=$4
    local action28s_outer_actual=$5

    [[ ! -s "$action28s_outer_stderr" ]] || return 1
    validate_ordered_checks "$node_a_inspector" action_28m_b "$action28s_outer_stdout" \
        "$action28s_outer_status" --expected-checks "$action28s_outer_expected" \
        "$action28s_outer_actual" || return 1
    require_one 'action_28m_b_first_failure=none' "$action28s_outer_stdout" || return 1
    require_one 'action_28m_b_mutation=false' "$action28s_outer_stdout" || return 1
    require_one 'action_28m_b_acceptance=true' "$action28s_outer_stdout"
}
validate_node_b() {
    local action28s_outer_stdout=$1
    local action28s_outer_stderr=$2
    local action28s_outer_status=$3
    local action28s_outer_expected=$4
    local action28s_outer_actual=$5

    [[ ! -s "$action28s_outer_stderr" ]] || return 1
    validate_ordered_checks "$node_b_inspector" action_28p_a_node_b "$action28s_outer_stdout" \
        "$action28s_outer_status" --expected-checks "$action28s_outer_expected" \
        "$action28s_outer_actual" || return 1
    require_one 'action_28p_a_node_b_first_failure=none' "$action28s_outer_stdout" || return 1
    require_one 'action_28p_a_node_b_mutation=false' "$action28s_outer_stdout" || return 1
    require_one 'action_28p_a_node_b_acceptance=true' "$action28s_outer_stdout"
}
validate_transaction() {
    local action28s_outer_stdout=$1
    local action28s_outer_stderr=$2
    local action28s_outer_status=$3
    local action28s_outer_expected=$4
    local action28s_outer_actual=$5

    [[ ! -s "$action28s_outer_stderr" ]] || return 1
    validate_ordered_checks "$transaction" action_28s_node_b "$action28s_outer_stdout" \
        "$action28s_outer_status" --expected-checks "$action28s_outer_expected" \
        "$action28s_outer_actual" || return 1
    require_one 'action_28s_node_b_first_failure=none' "$action28s_outer_stdout" || return 1
    require_one 'action_28s_node_b_node=node_b' "$action28s_outer_stdout" || return 1
    require_one 'action_28s_node_b_advertised_ipv4_count=1' "$action28s_outer_stdout" || return 1
    require_one 'action_28s_node_b_advertised_ipv6_count=1' "$action28s_outer_stdout" || return 1
    require_one 'action_28s_node_b_caddy_vips_excluded=true' "$action28s_outer_stdout" || return 1
    require_one 'action_28s_node_b_keepalived_reload=true' "$action28s_outer_stdout" || return 1
    require_one 'action_28s_node_b_mutation=true' "$action28s_outer_stdout" || return 1
    require_one 'action_28s_node_b_acceptance=true' "$action28s_outer_stdout" || return 1
    [[ "$(grep -Ec '^action_28s_node_b_rollback_' "$action28s_outer_stdout" || true)" -eq 0 ]]
}
run_local_gates() {
    gate working_directory working_directory_approved
    gate transaction_source valid_source "$transaction_sha256" "$transaction"
    gate node_b_inspector_source valid_source "$node_b_inspector_sha256" "$node_b_inspector"
    gate node_a_inspector_source valid_source "$node_a_inspector_sha256" "$node_a_inspector"
    gate source_configuration valid_source "$source_sha256" "$source_configuration"
    gate manifest valid_source "$manifest_sha256" "$manifest"
    gate regression_source valid_source "$regression_sha256" "$regression"
    gate syntax /bin/bash -n "$transaction" "$regression" "${BASH_SOURCE[0]}"
    gate transaction_self_test "$transaction" --self-test
    gate regression /bin/bash "$regression"
    gate shellcheck shellcheck "$transaction" "$regression" "${BASH_SOURCE[0]}"
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$transaction" "$regression" "${BASH_SOURCE[0]}"
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$transaction" "$regression" "${BASH_SOURCE[0]}"
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh"
    gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" \
        --check "$transaction" "$regression" "${BASH_SOURCE[0]}"
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" \
        --check "$transaction" "$regression" "${BASH_SOURCE[0]}"
    gate root_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-precommit.sh" "${BASH_SOURCE[0]}"
    gate ssh_evidence_policy /bin/bash "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" --check "${BASH_SOURCE[0]}"
    gate outer_labels /bin/bash "$caddy_root/tests/outer-local-gate-label-policy-regression.sh" \
        --runner "${BASH_SOURCE[0]}"
    gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check
}
write_transaction_remote() {
    local action28s_outer_archive=$1
    local action28s_outer_remote=$2

    # shellcheck disable=SC2016
    {
        printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' 'set +x' 'umask 077' \
            'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
            'export PATH' 'cd /' \
            'stage=$(mktemp -d /run/caddy-action28s-bundle.XXXXXX)' \
            'cleanup_stage() { rm -rf -- "$stage"; }' \
            'trap cleanup_stage EXIT INT TERM' \
            'chown root:root "$stage"' 'chmod 0700 "$stage"' \
            'install -m 0600 /dev/null "$stage/payload.tar"' \
            'base64 -d >"$stage/payload.tar" <<'\''ACTION28S_ARCHIVE'\'''
        base64 "$action28s_outer_archive"
        printf '%s\n' 'ACTION28S_ARCHIVE' \
            'printf '\''%s\n'\'' install-node-b-protocol-compatible-coupling-action28s.sh keepalived-pihole00.conf >"$stage/expected"' \
            'tar -tf "$stage/payload.tar" | LC_ALL=C sort >"$stage/actual"' \
            'diff -u "$stage/expected" "$stage/actual" >/dev/null' \
            'tar -xf "$stage/payload.tar" -C "$stage" --no-same-owner --no-same-permissions' \
            'chown root:root "$stage/install-node-b-protocol-compatible-coupling-action28s.sh" "$stage/keepalived-pihole00.conf"' \
            'chmod 0700 "$stage/install-node-b-protocol-compatible-coupling-action28s.sh"' \
            'chmod 0600 "$stage/keepalived-pihole00.conf"' 'cd /' \
            '/bin/bash "$stage/install-node-b-protocol-compatible-coupling-action28s.sh" --stage "$stage"'
    } >"$action28s_outer_remote"
    chmod 0600 "$action28s_outer_remote"
    /bin/bash -n "$action28s_outer_remote"
}
run_ssh_phase() {
    local action28s_outer_phase=$1
    local action28s_outer_target=$2
    local action28s_outer_input=$3
    local remote_stdout=$evidence_directory/$action28s_outer_phase.stdout
    local remote_stderr=$evidence_directory/$action28s_outer_phase.stderr
    local status_file=$evidence_directory/$action28s_outer_phase.status
    local remote_status=0

    chmod 0600 "$remote_stdout" "$remote_stderr" "$status_file"

    "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
        -o StrictHostKeyChecking=yes "$action28s_outer_target" \
        'cd / && sudo -n /bin/bash -s --' <"$action28s_outer_input" \
        >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
    printf '%s\n' "$remote_status" >"$status_file"
    emit_stream remote_stdout "$remote_stdout"
    emit_stream remote_stderr "$remote_stderr"
    printf '%s_remote_phase=%s\n' "$prefix" "$action28s_outer_phase"
    printf '%s_%s_status=%s\n' "$prefix" "$action28s_outer_phase" "$remote_status"
}
run_rollback() {
    local action28s_outer_rollback=$outer_root/rollback.sh

    {
        printf '%s\n' '#!/usr/bin/env bash' 'set -- --rollback' \
            'set -Eeuo pipefail' 'set +x' 'umask 077' \
            'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
            'export PATH' 'cd /'
        sed '1d' "$transaction"
    } >"$action28s_outer_rollback"
    chmod 0600 "$action28s_outer_rollback"
    run_ssh_phase rollback "$node_b_target" "$action28s_outer_rollback"
    [[ "$(<"$evidence_directory/rollback.status")" -eq 0 ]] || return 125
    require_one 'action_28s_node_b_rollback_acceptance=true' "$evidence_directory/rollback.stdout" || return 125
}
self_test() {
    [[ "$(expected_local_gates | wc -l)" -eq 26 ]] || return 1
    [[ "$(expected_local_gates | LC_ALL=C sort -u | wc -l)" -eq 26 ]] || return 1
    [[ "$node_a_target" = pi@10.1.0.53 ]] || return 1
    [[ "$node_b_target" = pi@10.1.0.54 ]] || return 1
    while IFS= read -r action28s_outer_self_test_gate; do
        printf '%s_gate_%s=true\n' "$prefix" "$action28s_outer_self_test_gate"
    done < <(expected_local_gates)
}

case "${1:-}" in
    --expected-local-gates)
        expected_local_gates
        exit 0
        ;;
    --self-test)
        self_test
        exit $?
        ;;
    '') ;;
    *) exit 64 ;;
esac

if [[ "${CADDY_ACTION28S_TEST_MODE:-}" = 1 ]]; then
    [[ -n "${CADDY_ACTION28S_SSH_BIN:-}" ]] || exit 64
    ssh_binary=$CADDY_ACTION28S_SSH_BIN
fi
readonly ssh_binary
if [[ "${CADDY_ACTION28S_TEST_MODE:-}" = 1 &&
    "${CADDY_ACTION28S_TEST_SKIP_LOCAL_GATES:-}" = 1 ]]; then
    printf '%s_gate_test_local_gates_skipped=true\n' "$prefix"
else
    run_local_gates
fi
install -d -m 0700 "$evidence_root"
gate evidence_root_created test -d "$evidence_root"
evidence_directory=$(mktemp -d "$evidence_root/run.XXXXXX")
readonly evidence_directory
chmod 0700 "$evidence_directory"
gate evidence_directory_created test -d "$evidence_directory"
outer_root=$(mktemp -d /tmp/caddy-action28s-outer.XXXXXX)
readonly outer_root
trap 'rm -rf -- "$outer_root"' EXIT
for action28s_outer_phase in node_a_preflight node_b_preflight node_b_transaction node_a_postflight rollback; do
    install -m 0600 /dev/null "$evidence_directory/$action28s_outer_phase.stdout"
    install -m 0600 /dev/null "$evidence_directory/$action28s_outer_phase.stderr"
    install -m 0600 /dev/null "$evidence_directory/$action28s_outer_phase.status"
done
bundle=$outer_root/bundle
archive=$outer_root/payload.tar
remote_transaction=$outer_root/transaction.remote
install -d -m 0700 "$bundle"
install -m 0700 "$transaction" "$bundle/install-node-b-protocol-compatible-coupling-action28s.sh"
install -m 0600 "$source_configuration" "$bundle/keepalived-pihole00.conf"
tar -cf "$archive" -C "$bundle" install-node-b-protocol-compatible-coupling-action28s.sh keepalived-pihole00.conf
write_transaction_remote "$archive" "$remote_transaction"

run_ssh_phase node_a_preflight "$node_a_target" "$node_a_inspector"
validate_node_a "$evidence_directory/node_a_preflight.stdout" \
    "$evidence_directory/node_a_preflight.stderr" "$(<"$evidence_directory/node_a_preflight.status")" \
    "$outer_root/node-a-pre.expected" "$outer_root/node-a-pre.actual"
gate node_a_preflight true
run_ssh_phase node_b_preflight "$node_b_target" "$node_b_inspector"
validate_node_b "$evidence_directory/node_b_preflight.stdout" \
    "$evidence_directory/node_b_preflight.stderr" "$(<"$evidence_directory/node_b_preflight.status")" \
    "$outer_root/node-b-pre.expected" "$outer_root/node-b-pre.actual"
gate node_b_preflight true
run_ssh_phase node_b_transaction "$node_b_target" "$remote_transaction"
validate_transaction "$evidence_directory/node_b_transaction.stdout" \
    "$evidence_directory/node_b_transaction.stderr" "$(<"$evidence_directory/node_b_transaction.status")" \
    "$outer_root/transaction.expected" "$outer_root/transaction.actual"
gate node_b_transaction true
if ! run_ssh_phase node_a_postflight "$node_a_target" "$node_a_inspector" ||
    ! validate_node_a "$evidence_directory/node_a_postflight.stdout" \
        "$evidence_directory/node_a_postflight.stderr" "$(<"$evidence_directory/node_a_postflight.status")" \
        "$outer_root/node-a-post.expected" "$outer_root/node-a-post.actual"; then
    run_rollback || exit 125
    exit 1
fi
gate node_a_postflight true
printf '%s_evidence_directory=%s\n' "$prefix" "$evidence_directory"
printf '%s_node_a_contact_read_only=true\n' "$prefix"
printf '%s_node_b_keepalived_reload=true\n' "$prefix"
printf '%s_simultaneous_reload=false\n' "$prefix"
printf '%s_node_b_mutation=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
