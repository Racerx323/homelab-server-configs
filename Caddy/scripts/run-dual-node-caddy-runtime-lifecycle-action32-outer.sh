#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_32_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly maximum_stream_bytes=16777216
readonly maximum_stream_lines=131072
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly repository_root=${script_directory%/Caddy/scripts}
readonly caddy_root=$repository_root/Caddy
readonly transaction=$script_directory/apply-caddy-runtime-lifecycle-action32.sh
readonly regression=$caddy_root/tests/action32-caddy-runtime-lifecycle-regression.sh
readonly artifact_manifest=$caddy_root/manifests/caddy-runtime-lifecycle-action32.tsv
readonly action_manifest=$caddy_root/manifests/caddy-runtime-lifecycle-action32.yaml
readonly expected_transaction_sha256=0505afa283c500f965ac578b3a65535eaa483fac67c00d734ed227db5c94f53a
readonly expected_regression_sha256=6693afacb9ce789671d948f3f6d0d89649671d14cfdf742fbd9386df85c5856d
readonly expected_artifact_manifest_sha256=5c381af6311e0a8ef1827d7519f5d297c67e4ca298f068e9818a0d9eb1c60f7c
evidence_root=${CADDY_ACTION32_EVIDENCE_ROOT:-/tmp/caddy-ssh-evidence/action32}
readonly evidence_root
ssh_binary=${CADDY_ACTION32_SSH_BIN:-/usr/bin/ssh}
readonly ssh_binary
scp_binary=${CADDY_ACTION32_SCP_BIN:-/usr/bin/scp}
readonly scp_binary
work_root=
payload_archive=
payload_sha256=
run_token=
node_a_remote_payload=
node_b_remote_payload=
node_a_mutated=false
node_b_mutated=false

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
working_directory_approved() {
    case "$PWD" in
        /home/aaron/code/homelab-server-configs) return 0 ;;
        /workspace/homelab-server-configs) [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] ;;
        *) return 1 ;;
    esac
}
manifest_valid_local() {
    if command -v yamllint >/dev/null 2>&1; then
        yamllint -s "$action_manifest"
        return
    fi
    [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]
}
gate() {
    local action32_outer_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action32_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action32_outer_label" >&2
    return 1
}
safe_stream() {
    local action32_outer_stream=$1

    [[ "$(wc -c <"$action32_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action32_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action32_outer_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action32_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' \
        "$action32_outer_stream"
}
emit_stream() {
    local action32_outer_label=$1
    local action32_outer_stream=$2

    printf '%s_%s_bytes=%s\n' "$prefix" "$action32_outer_label" \
        "$(wc -c <"$action32_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action32_outer_label" \
        "$(line_count "$action32_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action32_outer_label" \
        "$(file_hash "$action32_outer_stream")"
    if ! safe_stream "$action32_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action32_outer_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action32_outer_label"
    if [[ -s "$action32_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action32_outer_label"
        cat "$action32_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action32_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action32_outer_label"
    fi
}
prepare_capture() {
    local action32_outer_capture

    for action32_outer_capture in "$@"; do
        install -m 0600 /dev/null "$action32_outer_capture" || return 1
    done
}
build_payload() {
    local action32_outer_payload_root=$work_root/payload
    local action32_outer_source
    local action32_outer_target
    local action32_outer_mode
    local action32_outer_baseline
    local action32_outer_candidate

    install -d -m 0700 "$action32_outer_payload_root/Caddy/manifests" || return 1
    install -m 0600 "$artifact_manifest" \
        "$action32_outer_payload_root/Caddy/manifests/${artifact_manifest##*/}" || return 1
    while IFS=$'\t' read -r action32_outer_source action32_outer_target \
        action32_outer_mode action32_outer_baseline action32_outer_candidate; do
        [[ -n "$action32_outer_source" && "$action32_outer_source" != \#* ]] || continue
        : "$action32_outer_target" "$action32_outer_mode" "$action32_outer_baseline"
        [[ -f "$repository_root/$action32_outer_source" &&
            ! -L "$repository_root/$action32_outer_source" ]] || return 1
        [[ "$(file_hash "$repository_root/$action32_outer_source")" = "$action32_outer_candidate" ]] || return 1
        install -d -m 0700 \
            "$action32_outer_payload_root/${action32_outer_source%/*}" || return 1
        install -m 0600 "$repository_root/$action32_outer_source" \
            "$action32_outer_payload_root/$action32_outer_source" || return 1
    done <"$artifact_manifest"
    payload_archive=$work_root/caddy-action32-payload.tar
    tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
        --format=ustar -cf "$payload_archive" -C "$action32_outer_payload_root" . || return 1
    chmod 0600 "$payload_archive" || return 1
    payload_sha256=$(file_hash "$payload_archive") || return 1
    printf '%s_payload_sha256=%s\n' "$prefix" "$payload_sha256"
}
validate_payload_local() {
    /bin/bash "$transaction" --validate-payload node-a \
        "$payload_archive" "$payload_sha256" >/dev/null || return 1
    /bin/bash "$transaction" --validate-payload node-b \
        "$payload_archive" "$payload_sha256" >/dev/null
}
run_local_gates() {
    gate working_directory working_directory_approved || return 1
    gate transaction_hash test "$(file_hash "$transaction")" = \
        "$expected_transaction_sha256" || return 1
    gate regression_hash test "$(file_hash "$regression")" = \
        "$expected_regression_sha256" || return 1
    gate artifact_manifest_hash test "$(file_hash "$artifact_manifest")" = \
        "$expected_artifact_manifest_sha256" || return 1
    gate syntax /bin/bash -n "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate regression /bin/bash "$regression" || return 1
    gate shellcheck shellcheck "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate conditional_policy /bin/bash "$caddy_root/tests/conditional-validator-errexit-policy-regression.sh" || return 1
    gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate portable_awk_policy /bin/bash "$caddy_root/tests/portable-awk-policy.sh" --check \
        "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate remote_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-precommit.sh" \
        "${BASH_SOURCE[0]}" || return 1
    gate ssh_evidence_policy /bin/bash "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" \
        --check "${BASH_SOURCE[0]}" || return 1
    gate accepted_live_policy /bin/bash "$caddy_root/tests/accepted-live-hash-policy.sh" --check || return 1
    gate manifest manifest_valid_local || return 1
}
run_upload() {
    local action32_outer_label=$1
    local action32_outer_target=$2
    local action32_outer_alias=$3
    local action32_outer_remote=$4
    local action32_outer_stdout=$work_root/$action32_outer_label.stdout
    local action32_outer_stderr=$work_root/$action32_outer_label.stderr
    local action32_outer_status_file=$work_root/$action32_outer_label.status
    local action32_outer_status=0

    prepare_capture "$action32_outer_stdout" "$action32_outer_stderr" \
        "$action32_outer_status_file" || return 1
    "$scp_binary" -q -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o "HostKeyAlias=$action32_outer_alias" \
        -o ConnectTimeout=10 -o ConnectionAttempts=1 \
        "$payload_archive" "$action32_outer_target:$action32_outer_remote" \
        >"$action32_outer_stdout" 2>"$action32_outer_stderr" || action32_outer_status=$?
    printf '%s\n' "$action32_outer_status" >"$action32_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action32_outer_label" "$action32_outer_status"
    emit_stream "${action32_outer_label}_stdout" "$action32_outer_stdout" || return $?
    emit_stream "${action32_outer_label}_stderr" "$action32_outer_stderr" || return $?
    [[ "$action32_outer_status" -eq 0 && ! -s "$action32_outer_stderr" ]]
}
completion_marker() {
    local action32_outer_mode=$1
    local action32_outer_token=$2

    case "$action32_outer_mode" in
        --apply) printf 'action_32_remote_%s_apply_complete=true\n' "$action32_outer_token" ;;
        --rollback) printf 'action_32_remote_%s_rollback_complete=true\n' "$action32_outer_token" ;;
        --verify-current) printf 'action_32_remote_%s_verify_current_complete=true\n' "$action32_outer_token" ;;
        *) return 64 ;;
    esac
}
run_remote() {
    local action32_outer_label=$1
    local action32_outer_target=$2
    local action32_outer_alias=$3
    local action32_outer_role=$4
    local action32_outer_mode=$5
    local action32_outer_remote_payload=${6:-}
    local action32_outer_token=${action32_outer_role//-/_}
    local action32_outer_stdout=$work_root/$action32_outer_label.stdout
    local action32_outer_stderr=$work_root/$action32_outer_label.stderr
    local action32_outer_status_file=$work_root/$action32_outer_label.status
    local action32_outer_status=0
    local action32_outer_marker
    local action32_outer_command

    prepare_capture "$action32_outer_stdout" "$action32_outer_stderr" \
        "$action32_outer_status_file" || return 1
    case "$action32_outer_mode" in
        --apply) action32_outer_command="cd / && sudo -n /bin/bash -s -- $action32_outer_mode $action32_outer_role $action32_outer_remote_payload $payload_sha256" ;;
        --rollback) action32_outer_command="cd / && sudo -n /bin/bash -s -- $action32_outer_mode $action32_outer_role $action32_outer_remote_payload" ;;
        --verify-current) action32_outer_command="cd / && sudo -n /bin/bash -s -- $action32_outer_mode $action32_outer_role" ;;
        *) return 64 ;;
    esac
    "$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no \
        -o StrictHostKeyChecking=yes -o "HostKeyAlias=$action32_outer_alias" \
        -o ConnectTimeout=10 -o ConnectionAttempts=1 -o LogLevel=ERROR \
        "$action32_outer_target" "$action32_outer_command" \
        <"$transaction" >"$action32_outer_stdout" \
        2>"$action32_outer_stderr" || action32_outer_status=$?
    printf '%s\n' "$action32_outer_status" >"$action32_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action32_outer_label" "$action32_outer_status"
    emit_stream "remote_stdout_$action32_outer_label" "$action32_outer_stdout" || return $?
    emit_stream "remote_stderr_$action32_outer_label" "$action32_outer_stderr" || return $?
    [[ "$action32_outer_status" -eq 0 ]] || return 1
    [[ ! -s "$action32_outer_stderr" ]] || return 1
    ! grep -Eq '^action_32_remote_.*_check_.*=false$' "$action32_outer_stdout" || return 1
    action32_outer_marker=$(completion_marker "$action32_outer_mode" "$action32_outer_token") || return 1
    [[ "$(grep -Fxc "$action32_outer_marker" "$action32_outer_stdout")" -eq 1 ]]
}
recover() {
    local action32_outer_recovery_failed=false

    if [[ "$node_a_mutated" = true ]]; then
        run_remote node-a-rollback "$node_a_target" pihole0.local.theama.co \
            node-a --rollback "$node_a_remote_payload" || action32_outer_recovery_failed=true
    fi
    if [[ "$node_b_mutated" = true ]]; then
        run_remote node-b-rollback "$node_b_target" pihole00.local.theama.co \
            node-b --rollback "$node_b_remote_payload" || action32_outer_recovery_failed=true
    fi
    if [[ "$action32_outer_recovery_failed" = true ]]; then
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        return 125
    fi
    printf '%s_recovery_proven=true\n' "$prefix"
    return 1
}
run_action() {
    local action32_outer_started_ns
    local action32_outer_finished_ns

    run_local_gates || return 1
    install -d -m 0700 "$evidence_root" || return 1
    work_root=$(mktemp -d "$evidence_root/run.XXXXXX") || return 1
    chmod 0700 "$work_root" || return 1
    build_payload || return 1
    validate_payload_local || return 1
    run_token=$(date +%s%N)-$$ || return 1
    node_a_remote_payload=/tmp/caddy-action32-payload-node-a-$run_token.tar
    node_b_remote_payload=/tmp/caddy-action32-payload-node-b-$run_token.tar
    action32_outer_started_ns=$(date +%s%N) || return 1

    node_b_mutated=true
    run_upload node-b-upload "$node_b_target" pihole00.local.theama.co \
        "$node_b_remote_payload" || recover || return $?
    run_remote node-b-apply "$node_b_target" pihole00.local.theama.co \
        node-b --apply "$node_b_remote_payload" || recover || return $?
    node_a_mutated=true
    run_upload node-a-upload "$node_a_target" pihole0.local.theama.co \
        "$node_a_remote_payload" || recover || return $?
    run_remote node-a-apply "$node_a_target" pihole0.local.theama.co \
        node-a --apply "$node_a_remote_payload" || recover || return $?
    run_remote node-b-final "$node_b_target" pihole00.local.theama.co \
        node-b --verify-current || recover || return $?
    run_remote node-a-final "$node_a_target" pihole0.local.theama.co \
        node-a --verify-current || recover || return $?

    action32_outer_finished_ns=$(date +%s%N) || return 1
    printf '%s_evidence_directory=%s\n' "$prefix" "$work_root"
    printf '%s_elapsed_ms=%s\n' "$prefix" \
        "$(((action32_outer_finished_ns - action32_outer_started_ns) / 1000000))"
    printf '%s_standby_first=true\n' "$prefix"
    printf '%s_caddy_reload_performed=false\n' "$prefix"
    printf '%s_keepalived_reload_performed=false\n' "$prefix"
    printf '%s_recovery_invoked=false\n' "$prefix"
    printf '%s_manual_intervention_required=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}
self_test() {
    run_local_gates || return 1
    install -d -m 0700 "$evidence_root" || return 1
    work_root=$(mktemp -d "$evidence_root/self-test.XXXXXX") || return 1
    chmod 0700 "$work_root" || return 1
    build_payload || return 1
    validate_payload_local || return 1
    printf '%s_node_contact=false\n' "$prefix"
    printf '%s_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --self-test) self_test ;;
    '') run_action ;;
    *) exit 64 ;;
esac
