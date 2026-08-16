#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

# ssh-local-evidence-contract-v1
readonly prefix=action_34l_outer
readonly node_a_target=pi@10.1.0.53
readonly node_b_target=pi@10.1.0.54
readonly maximum_stream_bytes=8388608
readonly maximum_stream_lines=65536
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly repository_root=${script_directory%/Caddy/scripts}
readonly workspace_root=${repository_root%/homelab-server-configs}
readonly caddy_root=$repository_root/Caddy
readonly upload_transaction=$script_directory/apply-durable-apprise-action34i.sh
readonly action_transaction=$script_directory/apply-durable-apprise-action34l.sh
readonly regression=$caddy_root/tests/durable-apprise-deployment-regression.sh
readonly artifact_manifest=$caddy_root/manifests/durable-apprise-action34l.tsv
readonly runtime_baseline_manifest=$caddy_root/manifests/caddy-runtime-lifecycle-action32g.tsv
readonly action_manifest=$caddy_root/manifests/durable-apprise-action34l.yaml
readonly expected_upload_transaction_sha256=34d43af6e72bcb40826eb8510cfe0a2d11369f8b7ec94529772e47217505675f
readonly expected_action_transaction_sha256=7bd7b3860b6983765ec99afb4ade0e177c4e60c0369e2731f088b605cdb8f95e
readonly expected_regression_sha256=c3fa0b29389b510f60010c93879a83aa28f68b15f08aed7ad90f8fe04eebb13f
readonly expected_artifact_manifest_sha256=cde29cecd1d2bd39fa17add94fdb9d003c833cff1cb85ad356cf1ef14ba6e881
readonly expected_runtime_baseline_manifest_sha256=705c0e2e590e83da942048ca47c61fab545eb52c9f7b5fe866ba18524c7d1587
readonly evidence_root=/tmp/caddy-ssh-evidence/action34l
readonly ssh_binary=/usr/bin/ssh
readonly scp_binary=/usr/bin/scp

work_root=
payload_archive=
payload_sha256=
payload_size=
run_token=
node_a_remote_payload=
node_b_remote_payload=
node_a_started=false
node_b_started=false

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }

gate() {
    local action34i_outer_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_gate_%s=true\n' "$prefix" "$action34i_outer_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action34i_outer_label" >&2
    return 1
}

safe_stream() {
    local action34i_outer_stream=$1
    [[ "$(wc -c <"$action34i_outer_stream")" -le "$maximum_stream_bytes" ]] || return 1
    [[ "$(line_count "$action34i_outer_stream")" -le "$maximum_stream_lines" ]] || return 1
    iconv -f UTF-8 -t UTF-8 "$action34i_outer_stream" >/dev/null 2>&1 || return 1
    ! LC_ALL=C.UTF-8 grep -n '[^[:print:][:space:]]' "$action34i_outer_stream" >/dev/null || return 1
    ! grep -Eqi 'BEGIN [A-Z ]*PRIVATE KEY|Authorization:[[:space:]]*Bearer|WEBPASSWORD' "$action34i_outer_stream"
}

emit_stream() {
    local action34i_outer_label=$1
    local action34i_outer_stream=$2
    printf '%s_%s_bytes=%s\n' "$prefix" "$action34i_outer_label" "$(wc -c <"$action34i_outer_stream")"
    printf '%s_%s_lines=%s\n' "$prefix" "$action34i_outer_label" "$(line_count "$action34i_outer_stream")"
    printf '%s_%s_sha256=%s\n' "$prefix" "$action34i_outer_label" "$(file_hash "$action34i_outer_stream")"
    if ! safe_stream "$action34i_outer_stream"; then
        printf '%s_%s_classification=unsafe_retained\n' "$prefix" "$action34i_outer_label" >&2
        return 97
    fi
    printf '%s_%s_classification=bounded_safe\n' "$prefix" "$action34i_outer_label"
    if [[ -s "$action34i_outer_stream" ]]; then
        printf '%s_%s_begin\n' "$prefix" "$action34i_outer_label"
        cat "$action34i_outer_stream"
        printf '%s_%s_end\n' "$prefix" "$action34i_outer_label"
    else
        printf '%s_%s_content=empty\n' "$prefix" "$action34i_outer_label"
    fi
}

prepare_capture() {
    local action34i_outer_capture
    for action34i_outer_capture in "$@"; do
        install -m 0600 /dev/null "$action34i_outer_capture" || return 1
    done
}

build_payload() {
    local action34i_outer_payload_root=$work_root/payload
    local action34i_outer_source action34i_outer_target action34i_outer_mode
    local action34i_outer_baseline action34i_outer_candidate action34i_outer_source_path
    install -d -m 0700 "$action34i_outer_payload_root/Caddy/manifests" || return 1
    install -m 0600 "$artifact_manifest" \
        "$action34i_outer_payload_root/Caddy/manifests/durable-apprise-action34l.tsv" || return 1
    install -m 0600 "$runtime_baseline_manifest" \
        "$action34i_outer_payload_root/Caddy/manifests/${runtime_baseline_manifest##*/}" || return 1
    while IFS=$'\t' read -r action34i_outer_source action34i_outer_target \
        action34i_outer_mode action34i_outer_baseline action34i_outer_candidate; do
        [[ -n "$action34i_outer_source" && "$action34i_outer_source" != \#* ]] || continue
        : "$action34i_outer_target" "$action34i_outer_mode" "$action34i_outer_baseline"
        [[ "$action34i_outer_source" != /* && "$action34i_outer_source" != *..* ]] || return 1
        case "$action34i_outer_source" in
            Caddy/*) action34i_outer_source_path=$repository_root/$action34i_outer_source ;;
            homelab-dns/*) action34i_outer_source_path=$workspace_root/$action34i_outer_source ;;
            *) return 1 ;;
        esac
        [[ -f "$action34i_outer_source_path" && ! -L "$action34i_outer_source_path" ]] || return 1
        [[ "$(file_hash "$action34i_outer_source_path")" = "$action34i_outer_candidate" ]] || return 1
        install -d -m 0700 "$action34i_outer_payload_root/${action34i_outer_source%/*}" || return 1
        install -m 0600 "$action34i_outer_source_path" \
            "$action34i_outer_payload_root/$action34i_outer_source" || return 1
    done <"$artifact_manifest"
    payload_archive=$work_root/caddy-action34l-payload.tar
    tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
        --format=ustar -cf "$payload_archive" -C "$action34i_outer_payload_root" . || return 1
    chmod 0600 "$payload_archive" || return 1
    payload_sha256=$(file_hash "$payload_archive") || return 1
    payload_size=$(stat -c '%s' -- "$payload_archive") || return 1
    printf '%s_payload_sha256=%s\n' "$prefix" "$payload_sha256"
    printf '%s_payload_size=%s\n' "$prefix" "$payload_size"
}

run_local_gates() {
    gate working_directory test "$PWD" = /home/aaron/code/homelab-server-configs || return 1
    gate upload_transaction_hash test "$(file_hash "$upload_transaction")" = "$expected_upload_transaction_sha256" || return 1
    gate action_transaction_hash test "$(file_hash "$action_transaction")" = "$expected_action_transaction_sha256" || return 1
    gate regression_hash test "$(file_hash "$regression")" = "$expected_regression_sha256" || return 1
    gate artifact_manifest_hash test "$(file_hash "$artifact_manifest")" = "$expected_artifact_manifest_sha256" || return 1
    gate runtime_baseline_manifest_hash test "$(file_hash "$runtime_baseline_manifest")" = \
        "$expected_runtime_baseline_manifest_sha256" || return 1
    gate syntax /bin/bash -n "$upload_transaction" "$action_transaction" "$regression" "${BASH_SOURCE[0]}" || return 1
    gate regression /bin/bash "$regression" || return 1
    gate deployable_successor_policy \
        /bin/bash Caddy/tests/deployable-successor-policy.sh --authorization-ready || return 1
    gate neutral_production_regression \
        /bin/bash Caddy/tests/durable-apprise-deployment-regression.sh || return 1
    gate shellcheck shellcheck "$upload_transaction" "$action_transaction" \
        "$regression" "${BASH_SOURCE[0]}" || return 1
    gate canonical_format /bin/bash "$caddy_root/tests/shfmt-canonical.sh" --check \
        "$upload_transaction" "$action_transaction" "$regression" \
        "${BASH_SOURCE[0]}" || return 1
    gate collision_policy /bin/bash "$caddy_root/tests/check-shell-readonly-local-collisions-v2.sh" \
        "$upload_transaction" "$action_transaction" "$regression" \
        "${BASH_SOURCE[0]}" || return 1
    gate multifile_grep_policy /bin/bash "$caddy_root/tests/multifile-grep-count-policy.sh" --check \
        "$upload_transaction" "$action_transaction" "$regression" \
        "${BASH_SOURCE[0]}" || return 1
    gate remote_cwd_policy /bin/bash "$caddy_root/tests/remote-streamed-bash-cwd-policy.sh" --check \
        "${BASH_SOURCE[0]}" || return 1
    gate ssh_evidence_policy /bin/bash "$caddy_root/tests/ssh-stream-local-evidence-policy.sh" --check \
        "${BASH_SOURCE[0]}" || return 1
    gate lifecycle_policy /bin/bash "$caddy_root/tests/deployment-lifecycle-policy.sh" --check || return 1
    gate manifest yamllint -s "$action_manifest" || return 1
}

retain_remote_path() {
    local action34i_outer_role=$1
    local action34i_outer_path=$2
    local action34i_outer_path_file=$work_root/$action34i_outer_role.remote-path
    printf '%s\n' "$action34i_outer_path" >"$action34i_outer_path_file" || return 1
    chmod 0600 "$action34i_outer_path_file" || return 1
    printf '%s_%s_remote_path=%s\n' "$prefix" "${action34i_outer_role//-/_}" "$action34i_outer_path"
    printf '%s_%s_remote_path_sha256=%s\n' "$prefix" "${action34i_outer_role//-/_}" \
        "$(file_hash "$action34i_outer_path_file")"
}

run_streamed() {
    local action34i_outer_label=$1 target=$2 alias=$3 program=$4
    shift 4
    local action34i_outer_stdout=$work_root/$action34i_outer_label.stdout
    local action34i_outer_stderr=$work_root/$action34i_outer_label.stderr
    local action34i_outer_status_file=$work_root/$action34i_outer_label.status
    local action34i_outer_status=0 action34i_outer_command action34i_outer_argument
    prepare_capture "$action34i_outer_stdout" "$action34i_outer_stderr" "$action34i_outer_status_file" || return 1
    action34i_outer_command="cd / && sudo -n /bin/bash -s --"
    for action34i_outer_argument in "$@"; do
        printf -v action34i_outer_command '%s %q' "$action34i_outer_command" "$action34i_outer_argument"
    done
    "$ssh_binary" -T -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes \
        -o "HostKeyAlias=$alias" -o ConnectTimeout=10 -o ConnectionAttempts=1 \
        -o LogLevel=ERROR "$target" "$action34i_outer_command" \
        <"$program" >"$action34i_outer_stdout" 2>"$action34i_outer_stderr" || action34i_outer_status=$?
    printf '%s\n' "$action34i_outer_status" >"$action34i_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action34i_outer_label" "$action34i_outer_status"
    emit_stream "remote_stdout_$action34i_outer_label" "$action34i_outer_stdout" || return $?
    emit_stream "remote_stderr_$action34i_outer_label" "$action34i_outer_stderr" || return $?
    [[ "$action34i_outer_status" -eq 0 && ! -s "$action34i_outer_stderr" ]]
}

run_upload() {
    local action34i_outer_label=$1 target=$2 alias=$3 remote=$4
    local action34i_outer_stdout=$work_root/$action34i_outer_label.stdout
    local action34i_outer_stderr=$work_root/$action34i_outer_label.stderr
    local action34i_outer_status_file=$work_root/$action34i_outer_label.status
    local action34i_outer_status=0
    prepare_capture "$action34i_outer_stdout" "$action34i_outer_stderr" "$action34i_outer_status_file" || return 1
    "$scp_binary" -q -o BatchMode=yes -o IdentitiesOnly=no -o StrictHostKeyChecking=yes \
        -o "HostKeyAlias=$alias" -o ConnectTimeout=10 -o ConnectionAttempts=1 \
        "$payload_archive" "$target:$remote" >"$action34i_outer_stdout" \
        2>"$action34i_outer_stderr" || action34i_outer_status=$?
    printf '%s\n' "$action34i_outer_status" >"$action34i_outer_status_file"
    printf '%s_%s_status=%s\n' "$prefix" "$action34i_outer_label" "$action34i_outer_status"
    emit_stream "remote_stdout_$action34i_outer_label" "$action34i_outer_stdout" || return $?
    emit_stream "remote_stderr_$action34i_outer_label" "$action34i_outer_stderr" || return $?
    [[ "$action34i_outer_status" -eq 0 && ! -s "$action34i_outer_stderr" ]]
}

dispose_attempt() {
    local role=$1 target=$2 alias=$3 remote=$4
    run_streamed "$role-upload-disposition" "$target" "$alias" "$upload_transaction" \
        --dispose-upload "$role" "$remote" "$payload_sha256" "$payload_size" "$run_token"
}

recover() {
    local action34i_outer_failed=false
    if [[ "$node_a_started" = true ]]; then
        run_streamed node-a-recovery "$node_a_target" pihole0.local.theama.co "$action_transaction" \
            --recover node-a "$node_a_remote_payload" "$payload_sha256" "$run_token" || action34i_outer_failed=true
    fi
    if [[ "$node_b_started" = true ]]; then
        run_streamed node-b-recovery "$node_b_target" pihole00.local.theama.co "$action_transaction" \
            --recover node-b "$node_b_remote_payload" "$payload_sha256" "$run_token" || action34i_outer_failed=true
    fi
    if [[ "$action34i_outer_failed" = true ]]; then
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
    node_b_remote_payload=/tmp/caddy-action34h-payload-node-b-$run_token.tar
    node_a_remote_payload=/tmp/caddy-action34h-payload-node-a-$run_token.tar
    retain_remote_path node-b "$node_b_remote_payload" || return 1
    retain_remote_path node-a "$node_a_remote_payload" || return 1
    run_streamed node-b-action34h-residue "$node_b_target" pihole00.local.theama.co "$upload_transaction" \
        --dispose-action34h-node-b-residue node-b "$node_b_remote_payload" \
        524a1083b78a7d4862cd03d8e0affecc4e9de3cce7ae51bcab0cb6691755a5fb 40960 "$run_token" || return 1
    run_streamed node-b-upload-prepare "$node_b_target" pihole00.local.theama.co "$upload_transaction" \
        --prepare-upload node-b "$node_b_remote_payload" "$payload_sha256" "$payload_size" "$run_token" || return 1
    if ! run_upload node-b-upload "$node_b_target" pihole00.local.theama.co "$node_b_remote_payload"; then
        dispose_attempt node-b "$node_b_target" pihole00.local.theama.co "$node_b_remote_payload" || return 125
        return 1
    fi
    run_streamed node-b-upload-accept "$node_b_target" pihole00.local.theama.co "$upload_transaction" \
        --accept-upload node-b "$node_b_remote_payload" "$payload_sha256" "$payload_size" "$run_token" || return 125
    node_b_started=true
    run_streamed node-b-apply "$node_b_target" pihole00.local.theama.co "$action_transaction" \
        --apply node-b "$node_b_remote_payload" "$payload_sha256" "$run_token" || recover || return $?
    run_streamed node-a-upload-prepare "$node_a_target" pihole0.local.theama.co "$upload_transaction" \
        --prepare-upload node-a "$node_a_remote_payload" "$payload_sha256" "$payload_size" "$run_token" || recover || return $?
    if ! run_upload node-a-upload "$node_a_target" pihole0.local.theama.co "$node_a_remote_payload"; then
        dispose_attempt node-a "$node_a_target" pihole0.local.theama.co "$node_a_remote_payload" || return 125
        recover || return $?
    fi
    run_streamed node-a-upload-accept "$node_a_target" pihole0.local.theama.co "$upload_transaction" \
        --accept-upload node-a "$node_a_remote_payload" "$payload_sha256" "$payload_size" "$run_token" || recover || return $?
    node_a_started=true
    run_streamed node-a-apply "$node_a_target" pihole0.local.theama.co "$action_transaction" \
        --apply node-a "$node_a_remote_payload" "$payload_sha256" "$run_token" || recover || return $?
    run_streamed node-b-final "$node_b_target" pihole00.local.theama.co "$action_transaction" \
        --verify-current node-b none "$payload_sha256" "$run_token" || recover || return $?
    run_streamed node-a-final "$node_a_target" pihole0.local.theama.co "$action_transaction" \
        --verify-current node-a none "$payload_sha256" "$run_token" || recover || return $?
    printf '%s_evidence_directory=%s\n' "$prefix" "$work_root"
    printf '%s_standby_first=true\n' "$prefix"
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

production_path_helper_call() {
    local action34l_outer_helper_role=$1
    local action34l_outer_helper_path=$2
    local action34l_outer_helper_operation=$3
    local action34l_outer_helper_function

    case "$action34l_outer_helper_operation" in
        prepare) action34l_outer_helper_function=prepare_upload ;;
        accept) action34l_outer_helper_function=accept_upload ;;
        disposition) action34l_outer_helper_function=dispose_upload ;;
        *) return 64 ;;
    esac
    CADDY_ACTION34I_TEST_TMP=/tmp \
        CADDY_ACTION34I_TEST_RUN=$work_root/helper-run \
        /bin/bash -c '
            action34l_helper_source=$6
            action34l_helper_function=$7
            set -- --library-test "$1" "$2" "$3" "$4" "$5"
            source "$action34l_helper_source"
            "$action34l_helper_function"
        ' _ "$action34l_outer_helper_role" "$action34l_outer_helper_path" \
        "$payload_sha256" "$payload_size" "$run_token" \
        "$upload_transaction" "$action34l_outer_helper_function"
}

production_path_test() {
    local action34l_outer_evidence_root=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:-}
    local action34l_outer_transaction_stdout action34l_outer_transaction_stderr
    local action34l_outer_transaction_status=0
    local action34l_outer_node_a_path action34l_outer_node_b_path

    [[ "$action34l_outer_evidence_root" = /tmp/* ]] || return 64
    [[ -d "$action34l_outer_evidence_root" && ! -L "$action34l_outer_evidence_root" ]] || return 64
    [[ "$(stat -c '%a' "$action34l_outer_evidence_root")" = 700 ]] || return 64
    [[ -z "$(find "$action34l_outer_evidence_root" -mindepth 1 -maxdepth 1 -print -quit)" ]] || return 64

    work_root=$(mktemp -d /tmp/caddy-action34l-outer-production.XXXXXX) || return 1
    chmod 0700 "$work_root" || return 1
    run_token=$(date +%s)-$$ || return 1
    action34l_outer_node_b_path=/tmp/caddy-action34h-payload-node-b-$run_token.tar
    action34l_outer_node_a_path=/tmp/caddy-action34h-payload-node-a-$run_token.tar
    action34l_outer_transaction_stdout=$work_root/transaction.stdout
    action34l_outer_transaction_stderr=$work_root/transaction.stderr
    trap 'rm -f -- "$action34l_outer_node_a_path" "$action34l_outer_node_b_path"; rm -rf -- "/tmp/caddy-action34i/$run_token-node-a" "/tmp/caddy-action34i/$run_token-node-b" "$work_root"' EXIT

    printf 'production_path_outer_dispatch_entry=true\n'
    build_payload || return 1
    printf 'production_path_outer_payload_constructed=true\n'
    printf 'production_path_outer_remote_path_generated=true\n'

    production_path_helper_call node-b "$action34l_outer_node_b_path" prepare || return 1
    printf 'production_path_outer_upload_prepare=true\n'
    install -m 0600 "$payload_archive" "$action34l_outer_node_b_path" || return 1
    production_path_helper_call node-b "$action34l_outer_node_b_path" accept || return 1
    printf 'production_path_outer_upload_accept=true\n'

    production_path_helper_call node-a "$action34l_outer_node_a_path" prepare || return 1
    install -m 0600 "$payload_archive" "$action34l_outer_node_a_path" || return 1
    production_path_helper_call node-a "$action34l_outer_node_a_path" disposition || return 1
    printf 'production_path_outer_upload_disposition=true\n'

    printf '%s\n' \
        "cd / && sudo -n /bin/bash -s -- --apply node-b $action34l_outer_node_b_path $payload_sha256 $run_token" \
        >"$action34l_outer_evidence_root/remote-command.argv" || return 1
    printf '%s\n' "$action34l_outer_node_b_path" \
        >"$action34l_outer_evidence_root/remote-path" || return 1
    printf 'production_path_outer_remote_command_constructed=true\n'

    /bin/bash "$action_transaction" --production-path-test \
        >"$action34l_outer_transaction_stdout" \
        2>"$action34l_outer_transaction_stderr" || action34l_outer_transaction_status=$?
    [[ "$action34l_outer_transaction_status" -eq 0 ]] || return 1
    [[ ! -s "$action34l_outer_transaction_stderr" ]] || return 1
    printf 'production_path_outer_transaction_dispatched=true\n'

    printf '%s\n' "$payload_sha256" \
        >"$action34l_outer_evidence_root/payload.sha256" || return 1
    printf '%s\n' "$action34l_outer_transaction_status" \
        >"$action34l_outer_evidence_root/transaction.status" || return 1
    printf '0\n' >"$action34l_outer_evidence_root/mutation-count" || return 1
    printf 'prepare\t0\naccept\t0\ndisposition\t0\n' \
        >"$action34l_outer_evidence_root/upload-events.tsv" || return 1
    chmod 0600 "$action34l_outer_evidence_root"/* || return 1

    rm -f -- "$action34l_outer_node_a_path" "$action34l_outer_node_b_path" || return 1
    rm -rf -- "/tmp/caddy-action34i/$run_token-node-a" \
        "/tmp/caddy-action34i/$run_token-node-b" "$work_root" || return 1
    trap - EXIT
}

case "${1:-}" in
    --self-test) self_test ;;
    --production-path-test) production_path_test ;;
    '') run_action ;;
    *) exit 64 ;;
esac
