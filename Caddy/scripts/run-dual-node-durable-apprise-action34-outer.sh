#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_34_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=65536
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly repository_root=${script_directory%/Caddy/scripts}
readonly workspace_root=${repository_root%/homelab-server-configs}
readonly caddy_root=$repository_root/Caddy
readonly transaction=$script_directory/apply-durable-apprise-action34.sh
readonly regression=$caddy_root/tests/durable-apprise-queue-regression.sh
readonly artifact_manifest=$caddy_root/manifests/durable-apprise-action34.tsv
readonly runtime_baseline_manifest=$caddy_root/manifests/caddy-runtime-lifecycle-action32g.tsv
readonly action_manifest=$caddy_root/manifests/durable-apprise-action34.yaml
readonly expected_transaction_sha256=0ebc320a0dcff21764cb86b96a5a78062ea2d7f538bf4da2856724f8239ac5af
readonly expected_regression_sha256=ae45269cf71776decbcaa120a88f8e2ce35f4db4cdc226bea5a764eed56be0e9
readonly expected_artifact_manifest_sha256=6eb8b42edf4120ad60befbdbddf54cf71435a0f8ba52840c8d748cac176ae621
readonly expected_runtime_baseline_manifest_sha256=705c0e2e590e83da942048ca47c61fab545eb52c9f7b5fe866ba18524c7d1587
readonly evidence_root=/tmp/caddy-ssh-evidence/action34
readonly ssh_binary=/usr/bin/ssh
readonly scp_binary=/usr/bin/scp

work_root=
payload_archive=
payload_sha256=
run_token=
node_a_remote_payload=
node_b_remote_payload=
node_a_started=false
node_b_started=false

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

gate() {
    local action34_outer_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action34_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action34_outer_label" >&2
    return 1
}

safe_stream() {
    local action34_outer_stream=$1
    [[ "$(wc -c <"$action34_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action34_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action34_outer_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action34_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action34_outer_stream"
}

emit_stream() {
    local action34_outer_label=$1
    local action34_outer_stream=$2
    printf '%s_%s_bytes=%s\n' "$prefix" "$action34_outer_label" "$(wc -c <"$action34_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action34_outer_label" "$(line_count "$action34_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action34_outer_label" "$(file_hash "$action34_outer_stream")"
    if ! safe_stream "$action34_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action34_outer_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action34_outer_label"
    if [[ -s "$action34_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action34_outer_label"
        cat "$action34_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action34_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action34_outer_label"
    fi
}

prepare_capture() {
    local action34_outer_capture
    for action34_outer_capture in "$@"; do
        install -m 0600 /dev/null "$action34_outer_capture" || return 1
    done
}

build_payload() {
    local action34_outer_payload_root=$work_root/payload
    local action34_outer_source action34_outer_target action34_outer_mode
    local action34_outer_baseline action34_outer_candidate
    local action34_outer_source_path
    install -d -m 0700 "$action34_outer_payload_root/Caddy/manifests" || return 1
    install -m 0600 "$artifact_manifest" \
        "$action34_outer_payload_root/Caddy/manifests/${artifact_manifest##*/}" || return 1
    install -m 0600 "$runtime_baseline_manifest" \
        "$action34_outer_payload_root/Caddy/manifests/${runtime_baseline_manifest##*/}" || return 1
    while IFS=$'\t' read -r action34_outer_source action34_outer_target \
        action34_outer_mode action34_outer_baseline action34_outer_candidate; do
        [[ -n "$action34_outer_source" && "$action34_outer_source" != \#* ]] || continue
        : "$action34_outer_target" "$action34_outer_mode" "$action34_outer_baseline"
        [[ "$action34_outer_source" != /* && "$action34_outer_source" != *..* ]] || return 1
        case "$action34_outer_source" in
            Caddy/*) action34_outer_source_path=$repository_root/$action34_outer_source ;;
            homelab-dns/*) action34_outer_source_path=$workspace_root/$action34_outer_source ;;
            *) return 1 ;;
        esac
        [[ -f "$action34_outer_source_path" && ! -L "$action34_outer_source_path" ]] || return 1
        [[ "$(file_hash "$action34_outer_source_path")" = "$action34_outer_candidate" ]] || return 1
        install -d -m 0700 "$action34_outer_payload_root/${action34_outer_source%/*}" || return 1
        install -m 0600 "$action34_outer_source_path" \
            "$action34_outer_payload_root/$action34_outer_source" || return 1
    done <"$artifact_manifest"
    payload_archive=$work_root/caddy-action34-payload.tar
    tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
        --format=ustar -cf "$payload_archive" -C "$action34_outer_payload_root" . || return 1
    chmod 0600 "$payload_archive" || return 1
    payload_sha256=$(file_hash "$payload_archive") || return 1
    printf '%s_payload_sha256=%s\n' "$prefix" "$payload_sha256"
}

run_local_gates() {
    gate working_directory test "$PWD" = /home/aaron/code/homelab-server-configs || return 1
    gate transaction_hash test "$(file_hash "$transaction")" = "$expected_transaction_sha256" || return 1
    gate regression_hash test "$(file_hash "$regression")" = "$expected_regression_sha256" || return 1
    gate artifact_manifest_hash test "$(file_hash "$artifact_manifest")" = "$expected_artifact_manifest_sha256" || return 1
    gate runtime_baseline_manifest_hash test "$(file_hash "$runtime_baseline_manifest")" = \
        "$expected_runtime_baseline_manifest_sha256" || return 1
    gate syntax /bin/bash -n "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate regression /bin/bash "$regression" || return 1
    gate shellcheck shellcheck "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate remote_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" --check \
        "${BASH_SOURCE[0]}" || return 1
    gate ssh_evidence_policy /bin/bash "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" --check \
        "${BASH_SOURCE[0]}" || return 1
    gate lifecycle_policy /bin/bash "$caddy_root/tests/deployment-lifecycle-policy.sh" --check || return 1
    gate manifest yamllint -s "$action_manifest" || return 1
}

run_upload() {
    local action34_outer_label=$1
    local action34_outer_target=$2
    local action34_outer_alias=$3
    local action34_outer_remote=$4
    local action34_outer_stdout=$work_root/$action34_outer_label.stdout
    local action34_outer_stderr=$work_root/$action34_outer_label.stderr
    local action34_outer_status_file=$work_root/$action34_outer_label.status
    local action34_outer_status=0
    prepare_capture "$action34_outer_stdout" "$action34_outer_stderr" "$action34_outer_status_file" || return 1
    "$scp_binary" -q -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes \
        -o "HostKeyAlias=$action34_outer_alias" -o ConnectTimeout=10 -o ConnectionAttempts=1 \
        "$payload_archive" "$action34_outer_target:$action34_outer_remote" \
        >"$action34_outer_stdout" 2>"$action34_outer_stderr" || action34_outer_status=$?
    printf '%s\n' "$action34_outer_status" >"$action34_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action34_outer_label" "$action34_outer_status"
    emit_stream "remote_stdout_$action34_outer_label" "$action34_outer_stdout" || return $?
    emit_stream "remote_stderr_$action34_outer_label" "$action34_outer_stderr" || return $?
    [[ "$action34_outer_status" -eq 0 && ! -s "$action34_outer_stderr" ]]
}

run_remote() {
    local action34_outer_label=$1
    local action34_outer_target=$2
    local action34_outer_alias=$3
    local action34_outer_role=$4
    local action34_outer_mode=$5
    local action34_outer_remote_payload=${6:-none}
    local action34_outer_stdout=$work_root/$action34_outer_label.stdout
    local action34_outer_stderr=$work_root/$action34_outer_label.stderr
    local action34_outer_status_file=$work_root/$action34_outer_label.status
    local action34_outer_status=0
    local action34_outer_command
    prepare_capture "$action34_outer_stdout" "$action34_outer_stderr" "$action34_outer_status_file" || return 1
    action34_outer_command="cd / && sudo -n /bin/bash -s -- $action34_outer_mode $action34_outer_role $action34_outer_remote_payload $payload_sha256 $run_token"
    "$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes \
        -o "HostKeyAlias=$action34_outer_alias" -o ConnectTimeout=10 -o ConnectionAttempts=1 \
        -o LogLevel=ERROR "$action34_outer_target" "$action34_outer_command" \
        <"$transaction" >"$action34_outer_stdout" 2>"$action34_outer_stderr" || action34_outer_status=$?
    printf '%s\n' "$action34_outer_status" >"$action34_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action34_outer_label" "$action34_outer_status"
    emit_stream "remote_stdout_$action34_outer_label" "$action34_outer_stdout" || return $?
    emit_stream "remote_stderr_$action34_outer_label" "$action34_outer_stderr" || return $?
    [[ "$action34_outer_status" -eq 0 ]] || return "$action34_outer_status"
    [[ ! -s "$action34_outer_stderr" ]] || return 1
    ! grep -Eq '^action_34_remote_.*_check_.*=false$' "$action34_outer_stdout"
}

recover() {
    local action34_outer_failed=false
    if [[ "$node_a_started" = true ]]; then
        run_remote node-a-rollback "$node_a_target" pihole0.local.theama.co node-a --rollback || action34_outer_failed=true
    fi
    if [[ "$node_b_started" = true ]]; then
        run_remote node-b-rollback "$node_b_target" pihole00.local.theama.co node-b --rollback || action34_outer_failed=true
    fi
    if [[ "$action34_outer_failed" = true ]]; then
        printf '%s_manual_intervention_required=true\n' "$prefix" >&2
        return 125
    fi
    printf '%s_recovery_proven=true\n' "$prefix"
    return 1
}

run_action() {
    run_local_gates || return 1
    install -d -m 0700 "$evidence_root" || return 1
    work_root=$(mktemp -d "$evidence_root/run.XXXXXX") || return 1
    chmod 0700 "$work_root" || return 1
    build_payload || return 1
    run_token=$(date +%s)-$$ || return 1
    node_a_remote_payload=/tmp/caddy-action34-payload-node-a-$run_token.tar
    node_b_remote_payload=/tmp/caddy-action34-payload-node-b-$run_token.tar
    run_upload node-b-upload "$node_b_target" pihole00.local.theama.co "$node_b_remote_payload" || return 1
    node_b_started=true
    run_remote node-b-apply "$node_b_target" pihole00.local.theama.co node-b --apply "$node_b_remote_payload" || recover || return $?
    run_upload node-a-upload "$node_a_target" pihole0.local.theama.co "$node_a_remote_payload" || recover || return $?
    node_a_started=true
    run_remote node-a-apply "$node_a_target" pihole0.local.theama.co node-a --apply "$node_a_remote_payload" || recover || return $?
    run_remote node-b-final "$node_b_target" pihole00.local.theama.co node-b --verify-current || recover || return $?
    run_remote node-a-final "$node_a_target" pihole0.local.theama.co node-a --verify-current || recover || return $?
    printf '%s_evidence_directory=%s\n' "$prefix" "$work_root"
    printf '%s_standby_first=true\n' "$prefix"
    printf '%s_keepalived_reload_performed=false\n' "$prefix"
    printf '%s_vrrp_transition_performed=false\n' "$prefix"
    printf '%s_manual_intervention_required=false\n' "$prefix"
    printf '%s_complete=true\n' "$prefix"
}

self_test() {
    run_local_gates || return 1
    install -d -m 0700 "$evidence_root" || return 1
    work_root=$(mktemp -d "$evidence_root/self-test.XXXXXX") || return 1
    chmod 0700 "$work_root" || return 1
    build_payload || return 1
    printf '%s_node_contact=false\n' "$prefix"
    printf '%s_self_test_complete=true\n' "$prefix"
}

case "${1:-}" in
    --self-test) self_test ;;
    '') run_action ;;
    *) exit 64 ;;
esac
