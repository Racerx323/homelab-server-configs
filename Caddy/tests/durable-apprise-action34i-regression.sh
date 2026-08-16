#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=durable_apprise_action34i_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly upload_transaction=$caddy_root/scripts/apply-durable-apprise-action34i.sh
readonly outer=$caddy_root/scripts/run-dual-node-durable-apprise-action34i-outer.sh
readonly artifact_manifest=$caddy_root/manifests/durable-apprise-action34i.tsv
readonly predecessor_outer=$caddy_root/scripts/run-dual-node-durable-apprise-action34h-outer.sh
readonly predecessor_transaction=$caddy_root/scripts/apply-durable-apprise-action34h.sh
readonly predecessor_regression=$test_directory/durable-apprise-action34h-regression.sh
readonly predecessor_manifest=$caddy_root/manifests/durable-apprise-action34h.tsv
readonly predecessor_action_manifest=$caddy_root/manifests/durable-apprise-action34h.yaml
readonly expected_predecessor_outer_sha256=7e8824a4314908cc9e8802307e01693bc52dc316f0e9a8360b96460b072aee34
readonly expected_predecessor_transaction_sha256=a909614f5d806e9c0da1d283090e5c8aa332ba9bf00a558707439899c5dac55c
readonly expected_predecessor_regression_sha256=66e3cc0fb6ffa8edc9c83da34e622a6e31143e93d8905d3d70d26a2a2b160765
readonly expected_predecessor_manifest_sha256=cde29cecd1d2bd39fa17add94fdb9d003c833cff1cb85ad356cf1ef14ba6e881
readonly expected_predecessor_action_manifest_sha256=d5b2d55cf0c7f29c105b3d600f15433d3d8b96e92b4690e8e6b23f3ac61958b6

fixture_root=$(mktemp -d /tmp/caddy-action34i-regression.XXXXXX)
readonly fixture_root
trap 'rm -rf -- "$fixture_root"' EXIT

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

check() {
    local action34i_regression_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action34i_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action34i_regression_label" >&2
    return 1
}

candidate_sources_match() {
    local source_path installed_path mode baseline candidate source
    # conditional-validator-explicit-failures-begin
    while IFS=$'\t' read -r source_path installed_path mode baseline candidate; do
        [[ -n "$source_path" && "$source_path" != \#* ]] || continue
        : "$installed_path" "$mode" "$baseline"
        case "$source_path" in
            Caddy/*) source=$repository_root/$source_path ;;
            homelab-dns/*) source=$repository_root/../$source_path ;;
            *) return 1 ;;
        esac
        [[ -f "$source" && ! -L "$source" ]] || return 1
        [[ "$(file_hash "$source")" = "$candidate" ]] || return 1
    done <"$artifact_manifest"
    # conditional-validator-explicit-failures-end
}

outer_order_is_safe() {
    local retain_b prepare_b upload_b dispose_b accept_b apply_b
    local retain_a prepare_a upload_a dispose_a accept_a apply_a
    # conditional-validator-explicit-failures-begin
    retain_b=$(grep -nF 'retain_remote_path node-b' "$outer" | cut -d: -f1) || return 1
    prepare_b=$(grep -nF 'run_streamed node-b-upload-prepare' "$outer" | cut -d: -f1) || return 1
    upload_b=$(grep -nF 'run_upload node-b-upload ' "$outer" | cut -d: -f1) || return 1
    dispose_b=$(grep -nF 'dispose_attempt node-b' "$outer" | cut -d: -f1) || return 1
    accept_b=$(grep -nF 'run_streamed node-b-upload-accept' "$outer" | cut -d: -f1) || return 1
    apply_b=$(grep -nF 'run_streamed node-b-apply' "$outer" | cut -d: -f1) || return 1
    retain_a=$(grep -nF 'retain_remote_path node-a' "$outer" | cut -d: -f1) || return 1
    prepare_a=$(grep -nF 'run_streamed node-a-upload-prepare' "$outer" | cut -d: -f1) || return 1
    upload_a=$(grep -nF 'run_upload node-a-upload ' "$outer" | cut -d: -f1) || return 1
    dispose_a=$(grep -nF 'dispose_attempt node-a' "$outer" | cut -d: -f1) || return 1
    accept_a=$(grep -nF 'run_streamed node-a-upload-accept' "$outer" | cut -d: -f1) || return 1
    apply_a=$(grep -nF 'run_streamed node-a-apply' "$outer" | cut -d: -f1) || return 1
    [[ "$retain_b" -lt "$prepare_b" && "$prepare_b" -lt "$upload_b" ]] || return 1
    [[ "$upload_b" -lt "$dispose_b" && "$dispose_b" -lt "$accept_b" && "$accept_b" -lt "$apply_b" ]] || return 1
    [[ "$retain_a" -lt "$prepare_a" && "$prepare_a" -lt "$upload_a" ]] || return 1
    [[ "$upload_a" -lt "$dispose_a" && "$dispose_a" -lt "$accept_a" && "$accept_a" -lt "$apply_a" ]] || return 1
    [[ "$apply_b" -lt "$prepare_a" ]] || return 1
    # conditional-validator-explicit-failures-end
}

outer_contract_is_complete() {
    # conditional-validator-explicit-failures-begin
    # shellcheck disable=SC2016
    grep -Fq 'local action34i_outer_path_file=$work_root/$action34i_outer_role.remote-path' "$outer" || return 1
    grep -Fq -- '--dispose-action34h-node-b-residue' "$outer" || return 1
    grep -Fq -- '--prepare-upload' "$outer" || return 1
    grep -Fq -- '--dispose-upload' "$outer" || return 1
    grep -Fq -- '--accept-upload' "$outer" || return 1
    grep -Fq 'Caddy/manifests/durable-apprise-action34h.tsv' "$outer" || return 1
    # shellcheck disable=SC2016
    grep -Fq 'node_b_remote_payload=/tmp/caddy-action34h-payload-node-b-$run_token.tar' "$outer" || return 1
    # shellcheck disable=SC2016
    grep -Fq 'node_a_remote_payload=/tmp/caddy-action34h-payload-node-a-$run_token.tar' "$outer" || return 1
    grep -Fq 'return 125' "$outer" || return 1
    ! grep -Fq 'run-dual-node-durable-apprise-action34h-outer.sh' "$outer" || return 1
    # conditional-validator-explicit-failures-end
}

run_upload_boundary_production_path() {
    local test_tmp=$fixture_root/tmp
    local test_run=$fixture_root/run
    local token=1700000000-1
    local path=$test_tmp/caddy-action34h-payload-node-b-$token.tar
    local payload=$fixture_root/payload
    local payload_hash payload_size
    install -d -m 0700 "$test_tmp" "$test_run"
    printf 'bounded payload bytes\n' >"$payload"
    payload_hash=$(file_hash "$payload")
    payload_size=$(stat -c '%s' -- "$payload")
    CADDY_ACTION34I_TEST_TMP=$test_tmp CADDY_ACTION34I_TEST_RUN=$test_run \
        /bin/bash -c '
            source "$1" --library-test node-b "$2" "$3" "$4" "$5"
            prepare_upload
            printf partial >"$2"
            chmod 0600 "$2"
            dispose_upload
            [[ ! -e "$2" ]]
            [[ -f "$evidence_root/attempted-upload.tsv" ]]
            prepare_upload
            install -m 0600 "$6" "$2"
            accept_upload
            [[ -f "$2" ]]
            [[ ! -e "$marker" ]]
        ' bash "$upload_transaction" "$path" "$payload_hash" "$payload_size" "$token" "$payload" \
        >"$fixture_root/production-path.out"
    grep -Fq '_attempted_upload_size=7' "$fixture_root/production-path.out"
    grep -Fq '_disposition_complete=true' "$fixture_root/production-path.out"
    grep -Fq '_upload_hash_exact=true' "$fixture_root/production-path.out"
}

run_action34h_residue_path() {
    local test_tmp=$fixture_root/residue-tmp
    local test_run=$fixture_root/residue-run
    local token=1700000001-2
    local current=$test_tmp/caddy-action34h-payload-node-b-$token.tar
    local residue=$test_tmp/caddy-action34h-payload-node-b-1700000000-99.tar
    install -d -m 0700 "$test_tmp" "$test_run"
    printf partial-action34h >"$residue"
    chmod 0600 "$residue"
    CADDY_ACTION34I_TEST_TMP=$test_tmp CADDY_ACTION34I_TEST_RUN=$test_run \
        /bin/bash -c '
            source "$1" --library-test node-b "$2" "$3" 40960 "$4"
            dispose_action34h_node_b_residue
            [[ ! -e "$5" ]]
            [[ -f "$evidence_root/action34h-residue.tsv" ]]
        ' bash "$upload_transaction" "$current" \
        524a1083b78a7d4862cd03d8e0affecc4e9de3cce7ae51bcab0cb6691755a5fb \
        "$token" "$residue" >"$fixture_root/residue.out"
    grep -Fq '_action34h_residue_count=1' "$fixture_root/residue.out"
    grep -Fq '_action34h_residue_removed=true' "$fixture_root/residue.out"
}

check predecessor_outer_immutable test "$(file_hash "$predecessor_outer")" = "$expected_predecessor_outer_sha256"
check predecessor_transaction_immutable test "$(file_hash "$predecessor_transaction")" = "$expected_predecessor_transaction_sha256"
check predecessor_regression_immutable test "$(file_hash "$predecessor_regression")" = "$expected_predecessor_regression_sha256"
check predecessor_manifest_immutable test "$(file_hash "$predecessor_manifest")" = "$expected_predecessor_manifest_sha256"
check predecessor_action_manifest_immutable test "$(file_hash "$predecessor_action_manifest")" = "$expected_predecessor_action_manifest_sha256"
check candidate_sources_match candidate_sources_match
check upload_boundary_production_path run_upload_boundary_production_path
check action34h_residue_path run_action34h_residue_path
check outer_contract_complete outer_contract_is_complete
check outer_order_safe outer_order_is_safe
printf '%s_complete=true\n' "$prefix"
