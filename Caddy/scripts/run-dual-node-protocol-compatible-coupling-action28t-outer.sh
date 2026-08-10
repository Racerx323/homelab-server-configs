#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_28t_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly transaction_sha256=3489759fec7b38fe0e3ee31f19810085bf1f8fbe363826102b6daf1a25e873db
readonly node_a_inspector_sha256=38bbc1b3fc4dc35bc3847fcbf3233d7e7822065f5c71bafb49ee999dab4c56d1
readonly node_b_inspector_sha256=9d835b805b21262b51c50749b5671223ced5f049991ffdf841054e413dec596b
readonly node_a_candidate_sha256=d8f96c4f018f90370aea38fc3ef932af649158f6edc99cc7e95dea1edff4908a
readonly node_b_candidate_sha256=034ee9c45acaca4e48e2faeda24cd371e945bdb52a117b5871403958ab36794c
readonly manifest_sha256=ed33f2c0e9a68e83a9cb4e2558e1d580df08c9468d91c6eb683bb8fd0ea8178a
readonly regression_sha256=2701659b25d3bd2cf35bb01c54a7b97991b47dc51f02b4a8a46ded09be7ddc73
readonly maximum_stream_bytes=2097152
readonly maximum_stream_lines=16384
readonly maximum_transition_seconds=45
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/scripts}
readonly workspace_root=${caddy_root%/homelab-server-configs/Caddy}
readonly transaction=$script_directory/transact-dual-node-protocol-compatible-coupling-action28t.sh
readonly node_a_inspector=$script_directory/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly node_b_inspector=$script_directory/inspect-node-b-caddy-vrrp-relinquish-action28p-a.sh
readonly node_a_candidate=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole0.conf
readonly node_b_candidate=$workspace_root/homelab-dns/Keepalived/configs/keepalived-pihole00.conf
readonly manifest=$caddy_root/manifests/caddy-sequential-dual-node-coupling-action28t.yaml
readonly regression=$caddy_root/tests/action28t-sequential-dual-node-coupling-regression.sh
evidence_root=${CADDY_ACTION28T_EVIDENCE_ROOT:-/tmp/caddy-ssh-evidence/action28t}
readonly evidence_root
ssh_binary=${CADDY_ACTION28T_SSH_BIN:-/usr/bin/ssh}
node_b_applied=false
node_a_applied=false
transaction_complete=false
rollback_running=false

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
valid_source() {
    local action28t_outer_hash=$1
    local action28t_outer_file=$2

    [[ -f "$action28t_outer_file" && ! -L "$action28t_outer_file" ]] || return 1
    [[ "$(file_hash "$action28t_outer_file")" = "$action28t_outer_hash" ]]
}
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs) [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] ;;
        *) return 1 ;;
    esac
}
gate() {
    local action28t_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action28t_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action28t_outer_label" >&2
    return 1
}
expected_local_gates() {
    printf '%s\n' \
        working_directory transaction_source node_a_inspector_source node_b_inspector_source \
        node_a_candidate_source node_b_candidate_source manifest regression_source syntax \
        transaction_self_test regression shellcheck canonical_format collision_policy \
        conditional_policy multifile_grep_policy portable_awk_policy root_cwd_policy \
        ssh_evidence_policy outer_labels accepted_live_hash_policy evidence_root_created \
        evidence_directory_created node_a_preflight node_b_preflight node_b_apply \
        transition_window_bounded node_a_apply node_a_accept node_b_accept rollback_not_invoked
}
safe_stream() {
    local action28t_outer_stream=$1

    [[ "$(wc -c <"$action28t_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action28t_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    ! LC_ALL=C grep -n '[^[:print:][:space:]]' "$action28t_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
        "$action28t_outer_stream"
}
emit_stream() {
    local action28t_outer_label=$1
    local action28t_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action28t_outer_label" "$(wc -c <"$action28t_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action28t_outer_label" "$(line_count "$action28t_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action28t_outer_label" "$(file_hash "$action28t_outer_stream")"
    if ! safe_stream "$action28t_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action28t_outer_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action28t_outer_label"
    if [[ -s "$action28t_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action28t_outer_label"
        cat "$action28t_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action28t_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action28t_outer_label"
    fi
}
require_one() {
    local action28t_outer_line=$1
    local action28t_outer_file=$2

    [[ "$(grep -Fxc "$action28t_outer_line" "$action28t_outer_file" || true)" -eq 1 ]]
}
validate_ordered_checks() {
    local action28t_outer_option=$1
    local action28t_outer_output_prefix=$2
    local action28t_outer_stdout=$3
    local action28t_outer_status=$4
    local action28t_outer_expected=$5
    local action28t_outer_actual=$6

    [[ "$action28t_outer_status" -eq 0 ]] || return 1
    "$transaction" "$action28t_outer_option" >"$action28t_outer_expected" || return 1
    sed -n "s/^${action28t_outer_output_prefix}_check_\\([a-z0-9_]*\\)=true$/\\1/p" \
        "$action28t_outer_stdout" >"$action28t_outer_actual" || return 1
    [[ -s "$action28t_outer_expected" ]] || return 1
    diff -u "$action28t_outer_expected" "$action28t_outer_actual" >/dev/null || return 1
    [[ "$(grep -Ec "^${action28t_outer_output_prefix}_check_[a-z0-9_]+=false$" "$action28t_outer_stdout" || true)" -eq 0 ]]
}
validate_inspector() {
    local action28t_outer_source=$1
    local action28t_outer_output_prefix=$2
    local action28t_outer_stdout=$3
    local action28t_outer_stderr=$4
    local action28t_outer_status=$5
    local action28t_outer_expected=$6
    local action28t_outer_actual=$7

    [[ "$action28t_outer_status" -eq 0 && ! -s "$action28t_outer_stderr" ]] || return 1
    "$action28t_outer_source" --expected-checks >"$action28t_outer_expected" || return 1
    sed -n "s/^${action28t_outer_output_prefix}_check_\\([a-z0-9_]*\\)=true$/\\1/p" \
        "$action28t_outer_stdout" >"$action28t_outer_actual" || return 1
    diff -u "$action28t_outer_expected" "$action28t_outer_actual" >/dev/null || return 1
    require_one "${action28t_outer_output_prefix}_first_failure=none" "$action28t_outer_stdout" || return 1
    require_one "${action28t_outer_output_prefix}_mutation=false" "$action28t_outer_stdout" || return 1
    require_one "${action28t_outer_output_prefix}_acceptance=true" "$action28t_outer_stdout"
}
validate_transaction() {
    local action28t_outer_mode=$1
    local action28t_outer_role=$2
    local action28t_outer_stdout=$3
    local action28t_outer_stderr=$4
    local action28t_outer_status=$5
    local action28t_outer_option

    [[ ! -s "$action28t_outer_stderr" ]] || return 1
    action28t_outer_option=--expected-${action28t_outer_mode}-checks
    validate_ordered_checks "$action28t_outer_option" \
        "action_28t_remote_${action28t_outer_mode}" "$action28t_outer_stdout" \
        "$action28t_outer_status" "$outer_root/expected" "$outer_root/actual" || return 1
    require_one "action_28t_remote_${action28t_outer_mode}_first_failure=none" \
        "$action28t_outer_stdout" || return 1
    require_one "action_28t_remote_${action28t_outer_mode}_role=$action28t_outer_role" \
        "$action28t_outer_stdout" || return 1
    require_one "action_28t_remote_${action28t_outer_mode}_acceptance=true" \
        "$action28t_outer_stdout"
}
run_local_gates() {
    gate working_directory working_directory_approved
    gate transaction_source valid_source "$transaction_sha256" "$transaction"
    gate node_a_inspector_source valid_source "$node_a_inspector_sha256" "$node_a_inspector"
    gate node_b_inspector_source valid_source "$node_b_inspector_sha256" "$node_b_inspector"
    gate node_a_candidate_source valid_source "$node_a_candidate_sha256" "$node_a_candidate"
    gate node_b_candidate_source valid_source "$node_b_candidate_sha256" "$node_b_candidate"
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
    gate outer_labels /bin/bash "$caddy_root/tests/outer-local-gate-label-policy-regression.sh" --runner "${BASH_SOURCE[0]}"
    gate accepted_live_hash_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check
}
write_apply_remote() {
    local action28t_outer_role=$1
    local action28t_outer_archive=$2
    local action28t_outer_remote=$3
    local action28t_outer_candidate_name=keepalived-${action28t_outer_role}.conf

    tar -cf "$action28t_outer_archive" -C "$bundle" \
        transact-dual-node-protocol-compatible-coupling-action28t.sh "$action28t_outer_candidate_name"
    # The single-quoted lines are the generated remote program.
    # shellcheck disable=SC2016
    {
        printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' 'set +x' 'umask 077' \
            'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
            'export PATH' 'cd /' \
            'stage=$(mktemp -d /run/caddy-action28t-bundle.XXXXXX)' \
            'cleanup_stage() { rm -rf -- "$stage"; }' 'trap cleanup_stage EXIT INT TERM' \
            'chown root:root "$stage"' 'chmod 0700 "$stage"' \
            'install -m 0600 /dev/null "$stage/payload.tar"' \
            'base64 -d >"$stage/payload.tar" <<'\''ACTION28T_ARCHIVE'\'''
        base64 "$action28t_outer_archive"
        printf '%s\n' 'ACTION28T_ARCHIVE' \
            'tar -xf "$stage/payload.tar" -C "$stage" --no-same-owner --no-same-permissions' \
            'chown root:root "$stage"/*' \
            'chmod 0700 "$stage/transact-dual-node-protocol-compatible-coupling-action28t.sh"' \
            "chmod 0600 \"\$stage/$action28t_outer_candidate_name\"" \
            "cd / && /bin/bash \"\$stage/transact-dual-node-protocol-compatible-coupling-action28t.sh\" --apply $action28t_outer_role \"\$stage/$action28t_outer_candidate_name\""
    } >"$action28t_outer_remote"
    chmod 0600 "$action28t_outer_remote"
    /bin/bash -n "$action28t_outer_remote"
}
write_mode_remote() {
    local action28t_outer_mode=$1
    local action28t_outer_role=$2
    local action28t_outer_remote=$3

    {
        printf '%s\n' '#!/usr/bin/env bash' "set -- --$action28t_outer_mode $action28t_outer_role"
        sed '1d' "$transaction"
    } >"$action28t_outer_remote"
    chmod 0600 "$action28t_outer_remote"
    /bin/bash -n "$action28t_outer_remote"
}
run_ssh_phase() {
    local action28t_outer_phase=$1
    local action28t_outer_target=$2
    local action28t_outer_input=$3
    local remote_stdout=$evidence_directory/$action28t_outer_phase.stdout
    local remote_stderr=$evidence_directory/$action28t_outer_phase.stderr
    local status_file=$evidence_directory/$action28t_outer_phase.status
    local remote_status=0

    chmod 0600 "$remote_stdout" "$remote_stderr" "$status_file"
    "$ssh_binary" -T -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
        -o StrictHostKeyChecking=yes "$action28t_outer_target" \
        'cd / && sudo -n /bin/bash -s --' <"$action28t_outer_input" \
        >"$remote_stdout" 2>"$remote_stderr" || remote_status=$?
    printf '%s\n' "$remote_status" >"$status_file"
    emit_stream remote_stdout "$remote_stdout"
    emit_stream remote_stderr "$remote_stderr"
    printf '%s_remote_phase=%s\n' "$prefix" "$action28t_outer_phase"
    printf '%s_%s_status=%s\n' "$prefix" "$action28t_outer_phase" "$remote_status"
}
rollback_phase() {
    local action28t_outer_role=$1
    local action28t_outer_target=$2
    local action28t_outer_phase=rollback_$action28t_outer_role
    local action28t_outer_remote=$outer_root/$action28t_outer_phase.remote

    write_mode_remote rollback "$action28t_outer_role" "$action28t_outer_remote"
    run_ssh_phase "$action28t_outer_phase" "$action28t_outer_target" "$action28t_outer_remote"
    validate_transaction rollback "$action28t_outer_role" \
        "$evidence_directory/$action28t_outer_phase.stdout" \
        "$evidence_directory/$action28t_outer_phase.stderr" \
        "$(<"$evidence_directory/$action28t_outer_phase.status")" || return 125
}
perform_outer_rollback() {
    local action28t_outer_rollback_status=0

    [[ "$rollback_running" = false ]] || return 125
    rollback_running=true
    if [[ "$node_a_applied" = true ]]; then
        rollback_phase node_a "$node_a_target" || action28t_outer_rollback_status=125
        node_a_applied=false
    fi
    if [[ "$node_b_applied" = true ]]; then
        rollback_phase node_b "$node_b_target" || action28t_outer_rollback_status=125
        node_b_applied=false
    fi
    printf '%s_rollback_status=%s\n' "$prefix" "$action28t_outer_rollback_status" >&2
    return "$action28t_outer_rollback_status"
}
cleanup() {
    local action28t_outer_status=$?

    trap - EXIT INT TERM
    if [[ "$transaction_complete" != true && "$rollback_running" = false &&
        ("$node_a_applied" = true || "$node_b_applied" = true) ]]; then
        perform_outer_rollback || action28t_outer_status=125
    fi
    [[ -z "${outer_root:-}" || ! -d "$outer_root" ]] || rm -rf -- "$outer_root"
    exit "$action28t_outer_status"
}
self_test() {
    [[ "$(expected_local_gates | wc -l)" -eq "$(expected_local_gates | LC_ALL=C sort -u | wc -l)" ]] || return 1
    [[ "$node_a_target" = pi@10.1.0.53 ]] || return 1
    [[ "$node_b_target" = pi@10.1.0.54 ]] || return 1
    [[ "$maximum_transition_seconds" -eq 45 ]] || return 1
    while IFS= read -r action28t_outer_gate; do
        printf '%s_gate_%s=true\n' "$prefix" "$action28t_outer_gate"
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
if [[ "${CADDY_ACTION28T_TEST_MODE:-}" = 1 ]]; then
    [[ -n "${CADDY_ACTION28T_SSH_BIN:-}" ]] || exit 64
    ssh_binary=$CADDY_ACTION28T_SSH_BIN
fi
readonly ssh_binary
if [[ "${CADDY_ACTION28T_TEST_MODE:-}" = 1 &&
    "${CADDY_ACTION28T_TEST_SKIP_LOCAL_GATES:-}" = 1 ]]; then
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
outer_root=$(mktemp -d /tmp/caddy-action28t-outer.XXXXXX)
readonly outer_root
trap cleanup EXIT INT TERM
bundle=$outer_root/bundle
install -d -m 0700 "$bundle"
install -m 0700 "$transaction" "$bundle/transact-dual-node-protocol-compatible-coupling-action28t.sh"
install -m 0600 "$node_a_candidate" "$bundle/keepalived-node_a.conf"
install -m 0600 "$node_b_candidate" "$bundle/keepalived-node_b.conf"
for action28t_outer_phase in node_a_preflight node_b_preflight node_b_apply node_a_apply \
    node_a_accept node_b_accept rollback_node_a rollback_node_b; do
    install -m 0600 /dev/null "$evidence_directory/$action28t_outer_phase.stdout"
    install -m 0600 /dev/null "$evidence_directory/$action28t_outer_phase.stderr"
    install -m 0600 /dev/null "$evidence_directory/$action28t_outer_phase.status"
done

run_ssh_phase node_a_preflight "$node_a_target" "$node_a_inspector"
validate_inspector "$node_a_inspector" action_28m_b \
    "$evidence_directory/node_a_preflight.stdout" "$evidence_directory/node_a_preflight.stderr" \
    "$(<"$evidence_directory/node_a_preflight.status")" "$outer_root/expected" "$outer_root/actual"
gate node_a_preflight true
run_ssh_phase node_b_preflight "$node_b_target" "$node_b_inspector"
validate_inspector "$node_b_inspector" action_28p_a_node_b \
    "$evidence_directory/node_b_preflight.stdout" "$evidence_directory/node_b_preflight.stderr" \
    "$(<"$evidence_directory/node_b_preflight.status")" "$outer_root/expected" "$outer_root/actual"
gate node_b_preflight true

write_apply_remote node_b "$outer_root/node-b.tar" "$outer_root/node-b-apply.remote"
run_ssh_phase node_b_apply "$node_b_target" "$outer_root/node-b-apply.remote"
if [[ "$(<"$evidence_directory/node_b_apply.status")" -eq 0 ]]; then
    node_b_applied=true
fi
validate_transaction apply node_b "$evidence_directory/node_b_apply.stdout" \
    "$evidence_directory/node_b_apply.stderr" "$(<"$evidence_directory/node_b_apply.status")"
gate node_b_apply true
transition_started_epoch=$(date +%s)
write_apply_remote node_a "$outer_root/node-a.tar" "$outer_root/node-a-apply.remote"
run_ssh_phase node_a_apply "$node_a_target" "$outer_root/node-a-apply.remote"
if [[ "$(<"$evidence_directory/node_a_apply.status")" -eq 0 ]]; then
    node_a_applied=true
fi
validate_transaction apply node_a "$evidence_directory/node_a_apply.stdout" \
    "$evidence_directory/node_a_apply.stderr" "$(<"$evidence_directory/node_a_apply.status")"
transition_completed_epoch=$(date +%s)
transition_seconds=$((transition_completed_epoch - transition_started_epoch))
printf '%s_transition_seconds=%s\n' "$prefix" "$transition_seconds"
gate transition_window_bounded test "$transition_seconds" -le "$maximum_transition_seconds"
gate node_a_apply true

write_mode_remote accept node_b "$outer_root/node-b-accept.remote"
run_ssh_phase node_b_accept "$node_b_target" "$outer_root/node-b-accept.remote"
validate_transaction accept node_b "$evidence_directory/node_b_accept.stdout" \
    "$evidence_directory/node_b_accept.stderr" "$(<"$evidence_directory/node_b_accept.status")"
gate node_b_accept true
write_mode_remote accept node_a "$outer_root/node-a-accept.remote"
run_ssh_phase node_a_accept "$node_a_target" "$outer_root/node-a-accept.remote"
validate_transaction accept node_a "$evidence_directory/node_a_accept.stdout" \
    "$evidence_directory/node_a_accept.stderr" "$(<"$evidence_directory/node_a_accept.status")"
gate node_a_accept true
gate rollback_not_invoked test "$rollback_running" = false
transaction_complete=true
printf '%s_evidence_directory=%s\n' "$prefix" "$evidence_directory"
printf '%s_node_b_reload_preceded_node_a=true\n' "$prefix"
printf '%s_simultaneous_reload=false\n' "$prefix"
printf '%s_node_a_master=true\n' "$prefix"
printf '%s_node_b_backup=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
