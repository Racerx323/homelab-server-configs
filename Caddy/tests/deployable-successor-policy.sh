#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly successor_policy_prefix=deployable_successor_policy
successor_policy_test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly successor_policy_test_directory
successor_policy_default_root=${successor_policy_test_directory%/Caddy/tests}
readonly successor_policy_default_root

if [[ -n "${CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT:-}" ]]; then
    [[ "${CADDY_DEPLOYABLE_SUCCESSOR_TEST_MODE:-}" = 1 ]] || exit 64
    [[ "$CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT" = /tmp/* ]] || exit 64
    successor_policy_repository_root=$CADDY_DEPLOYABLE_SUCCESSOR_TEST_ROOT
else
    successor_policy_repository_root=$successor_policy_default_root
fi
readonly successor_policy_repository_root
readonly successor_policy_registry=${CADDY_DEPLOYABLE_SUCCESSOR_REGISTRY:-$successor_policy_repository_root/Caddy/manifests/deployable-successor.tsv}

successor_policy_check() {
    local successor_policy_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$successor_policy_prefix" "$successor_policy_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$successor_policy_prefix" "$successor_policy_label" >&2
    return 1
}

successor_policy_regular_file() {
    local successor_policy_path=$1

    [[ -f "$successor_policy_path" && ! -L "$successor_policy_path" ]]
}

successor_policy_executable_file() {
    local successor_policy_relative=$1
    local successor_policy_path=$successor_policy_repository_root/$successor_policy_relative

    successor_policy_regular_file "$successor_policy_path" || return 1
    [[ -x "$successor_policy_path" ]] || return 1
    if [[ "$successor_policy_repository_root" = "$successor_policy_default_root" ]]; then
        [[ "$(git -C "$successor_policy_repository_root" ls-files -s -- "$successor_policy_relative" | awk '{ print $1 }')" = 100755 ]] || return 1
    fi
}

successor_policy_state_valid() {
    local successor_policy_state=$1
    local successor_policy_accepted_hash successor_policy_runtime_hash

    # conditional-validator-explicit-failures-begin
    successor_policy_regular_file "$successor_policy_state" || return 1
    [[ "$(sed -n '1p' "$successor_policy_state")" = $'schema_version\tscope\tkey\tvalue\tevidence' ]] || return 1
    awk -F '\t' '
        NR == 1 { next }
        NF != 5 || $1 != "1" { exit 1 }
        $2 !~ /^(cluster|node-a|node-b)$/ { exit 1 }
        $3 !~ /^[a-z0-9][a-z0-9-]*$/ || $4 == "" || $5 == "" { exit 1 }
        seen[$2 FS $3]++ { exit 1 }
        END { exit !(NR > 1) }
    ' "$successor_policy_state" || return 1
    for successor_policy_required in \
        cluster:accepted-live-artifacts-sha256 cluster:runtime-baseline-sha256 \
        node-a:ownership node-a:services node-a:release \
        node-a:durable-apprise-installation node-a:apprise-queue \
        node-b:ownership node-b:services node-b:release \
        node-b:durable-apprise-installation node-b:apprise-queue; do
        awk -F '\t' -v required="$successor_policy_required" '
            NR > 1 && $2 ":" $3 == required { found++ }
            END { exit(found == 1 ? 0 : 1) }
        ' "$successor_policy_state" || return 1
    done
    successor_policy_accepted_hash=$(awk -F '\t' '$2 == "cluster" && $3 == "accepted-live-artifacts-sha256" { print $4 }' "$successor_policy_state") || return 1
    successor_policy_runtime_hash=$(awk -F '\t' '$2 == "cluster" && $3 == "runtime-baseline-sha256" { print $4 }' "$successor_policy_state") || return 1
    [[ "$successor_policy_accepted_hash" = "$(sha256sum "$successor_policy_repository_root/Caddy/manifests/accepted-live-artifacts.tsv" | awk '{ print $1 }')" ]] || return 1
    [[ "$successor_policy_runtime_hash" = "$(sha256sum "$successor_policy_repository_root/Caddy/manifests/caddy-runtime-lifecycle-action32g.tsv" | awk '{ print $1 }')" ]] || return 1
    # conditional-validator-explicit-failures-end
}

successor_policy_coverage_valid() {
    local successor_policy_coverage=$1
    local successor_policy_required

    # conditional-validator-explicit-failures-begin
    successor_policy_regular_file "$successor_policy_coverage" || return 1
    [[ "$(sed -n '1p' "$successor_policy_coverage")" = $'scenario\tphase\tentrypoint\texpectation\tmarker' ]] || return 1
    awk -F '\t' '
        NR == 1 { next }
        NF != 5 { exit 1 }
        $1 !~ /^[a-z0-9][a-z0-9-]*$/ || $2 !~ /^(pre-mutation|accepted-path)$/ { exit 1 }
        $3 !~ /^(outer|transaction)$/ || $4 !~ /^(accept|reject|reach)$/ { exit 1 }
        $5 !~ /^[a-z0-9][a-z0-9_]*$/ { exit 1 }
        seen_scenario[$1]++ || seen_marker[$5]++ { exit 1 }
        END { exit !(NR > 1) }
    ' "$successor_policy_coverage" || return 1
    while IFS= read -r successor_policy_required; do
        grep -Fxq "$successor_policy_required" "$successor_policy_coverage" || return 1
    done <<'EOF'
node-b-queue-absent	pre-mutation	transaction	accept	production_path_node_b_queue_absent
node-b-exact-two-records	pre-mutation	transaction	accept	production_path_node_b_exact_two_records
node-b-one-record	pre-mutation	transaction	reject	production_path_node_b_one_record_rejected
node-b-extra-record	pre-mutation	transaction	reject	production_path_node_b_extra_record_rejected
node-b-unsafe-metadata	pre-mutation	transaction	reject	production_path_node_b_unsafe_metadata_rejected
node-b-symlink	pre-mutation	transaction	reject	production_path_node_b_symlink_rejected
node-b-malformed-record	pre-mutation	transaction	reject	production_path_node_b_malformed_record_rejected
node-a-queue-absent	pre-mutation	transaction	accept	production_path_node_a_queue_absent
outer-production-entrypoint	pre-mutation	outer	reach	production_path_outer_dispatch_entry
payload-construction	pre-mutation	outer	reach	production_path_outer_payload_constructed
remote-path-generation	pre-mutation	outer	reach	production_path_outer_remote_path_generated
upload-prepare	pre-mutation	outer	reach	production_path_outer_upload_prepare
upload-accept	pre-mutation	outer	reach	production_path_outer_upload_accept
upload-disposition	pre-mutation	outer	reach	production_path_outer_upload_disposition
remote-command-construction	pre-mutation	outer	reach	production_path_outer_remote_command_constructed
transaction-dispatch	pre-mutation	outer	reach	production_path_outer_transaction_dispatched
stdin-transaction-dispatch	pre-mutation	outer	reach	production_path_outer_stdin_transaction_dispatched
payload-validation	accepted-path	transaction	reach	production_path_payload_validation_reached
mutation-boundary	accepted-path	transaction	reach	production_path_mutation_boundary_reached
production-entrypoint	accepted-path	transaction	reach	production_path_dispatch_entry
EOF
    # conditional-validator-explicit-failures-end
}

successor_policy_outer_evidence_valid() {
    local successor_policy_evidence_root=$1
    local successor_policy_evidence_file

    [[ -d "$successor_policy_evidence_root" && ! -L "$successor_policy_evidence_root" ]] || return 1
    [[ "$(stat -c '%a' "$successor_policy_evidence_root")" = 700 ]] || return 1
    diff -u \
        <(printf '%s\n' mutation-count payload.sha256 remote-command.argv remote-path \
            transaction.status upload-events.tsv | LC_ALL=C sort) \
        <(find "$successor_policy_evidence_root" -mindepth 1 -maxdepth 1 \
            -printf '%f\n' | LC_ALL=C sort) >/dev/null || return 1
    for successor_policy_evidence_file in \
        mutation-count payload.sha256 remote-command.argv remote-path \
        transaction.status upload-events.tsv; do
        successor_policy_regular_file \
            "$successor_policy_evidence_root/$successor_policy_evidence_file" || return 1
        [[ "$(stat -c '%a' \
            "$successor_policy_evidence_root/$successor_policy_evidence_file")" = 600 ]] || return 1
    done
    grep -Eq '^[0-9a-f]{64}$' "$successor_policy_evidence_root/payload.sha256" || return 1
    grep -Eq '^/tmp/[A-Za-z0-9._/-]+$' "$successor_policy_evidence_root/remote-path" || return 1
    ! grep -Fq '..' "$successor_policy_evidence_root/remote-path" || return 1
    diff -u \
        <(printf '%s\n' $'prepare\t0' $'accept\t0' $'disposition\t0') \
        "$successor_policy_evidence_root/upload-events.tsv" >/dev/null || return 1
    grep -Fq '/bin/bash' "$successor_policy_evidence_root/remote-command.argv" || return 1
    grep -Fq "$(<"$successor_policy_evidence_root/remote-path")" \
        "$successor_policy_evidence_root/remote-command.argv" || return 1
    grep -Fxq 0 "$successor_policy_evidence_root/transaction.status" || return 1
    grep -Fxq 0 "$successor_policy_evidence_root/mutation-count" || return 1
}

successor_policy_defined_valid() {
    local successor_policy_action=$1
    local successor_policy_action_manifest=$2
    local successor_policy_transaction=$3
    local successor_policy_outer=$4
    local successor_policy_coverage=$5
    local successor_policy_regression=$6
    local successor_policy_transaction_output successor_policy_transaction_error
    local successor_policy_outer_output successor_policy_outer_error
    local successor_policy_probe_root successor_policy_marker_entrypoint
    local successor_policy_marker successor_policy_marker_output

    # conditional-validator-explicit-failures-begin
    [[ "$successor_policy_action" =~ ^[0-9]+[a-z0-9-]*$ ]] || return 1
    [[ "$successor_policy_action_manifest" =~ ^Caddy/manifests/[A-Za-z0-9._-]+\.ya?ml$ ]] || return 1
    [[ "$successor_policy_transaction" =~ ^Caddy/scripts/[A-Za-z0-9._-]+\.sh$ ]] || return 1
    [[ "$successor_policy_outer" =~ ^Caddy/scripts/[A-Za-z0-9._-]+\.sh$ ]] || return 1
    [[ "$successor_policy_coverage" =~ ^Caddy/manifests/[A-Za-z0-9._-]+\.tsv$ ]] || return 1
    [[ "$successor_policy_regression" =~ ^Caddy/tests/[A-Za-z0-9._-]+\.sh$ ]] || return 1
    [[ "${successor_policy_regression##*/}" != *action[0-9]* ]] || return 1
    successor_policy_regular_file "$successor_policy_repository_root/$successor_policy_action_manifest" || return 1
    successor_policy_executable_file "$successor_policy_transaction" || return 1
    successor_policy_executable_file "$successor_policy_outer" || return 1
    successor_policy_executable_file "$successor_policy_regression" || return 1
    successor_policy_coverage_valid "$successor_policy_repository_root/$successor_policy_coverage" || return 1
    awk -F '\t' -v path="$successor_policy_action_manifest" '
        $1 == path && $2 == "defined-unexecuted" { found++ }
        END { exit(found == 1 ? 0 : 1) }
    ' "$successor_policy_repository_root/Caddy/manifests/manifest-lifecycle.tsv" || return 1
    grep -Fq -- '--production-path-test' "$successor_policy_repository_root/$successor_policy_transaction" || return 1
    grep -Fq -- '--production-path-test' "$successor_policy_repository_root/$successor_policy_outer" || return 1
    grep -Fq -- 'deployable-successor.tsv' \
        "$successor_policy_repository_root/$successor_policy_regression" || return 1
    grep -Fq -- '--production-path-test' "$successor_policy_repository_root/$successor_policy_regression" || return 1
    awk '
        { line = $0; sub(/^ +/, "", line) }
        substr(line, 1, 1) != "#" &&
            index(line, "/bin/bash Caddy/tests/deployable-successor-policy.sh --authorization-ready") { found++ }
        END { exit(found == 1 ? 0 : 1) }
    ' "$successor_policy_repository_root/$successor_policy_outer" || return 1
    awk -v command="/bin/bash $successor_policy_regression" '
        { line = $0; sub(/^ +/, "", line) }
        substr(line, 1, 1) != "#" && index(line, command) { found++ }
        END { exit(found == 1 ? 0 : 1) }
    ' "$successor_policy_repository_root/$successor_policy_outer" || return 1
    successor_policy_transaction_output=$(mktemp /tmp/caddy-successor-transaction-output.XXXXXX) || return 1
    successor_policy_transaction_error=$(mktemp /tmp/caddy-successor-transaction-error.XXXXXX) || {
        rm -f -- "$successor_policy_transaction_output"
        return 1
    }
    successor_policy_outer_output=$(mktemp /tmp/caddy-successor-outer-output.XXXXXX) || {
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error"
        return 1
    }
    successor_policy_outer_error=$(mktemp /tmp/caddy-successor-outer-error.XXXXXX) || {
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output"
        return 1
    }
    successor_policy_probe_root=$(mktemp -d /tmp/caddy-successor-production-evidence.XXXXXX) || {
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output" "$successor_policy_outer_error"
        return 1
    }
    if ! /bin/bash "$successor_policy_repository_root/$successor_policy_transaction" \
        --production-path-test >"$successor_policy_transaction_output" \
        2>"$successor_policy_transaction_error"; then
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output" "$successor_policy_outer_error"
        rm -rf -- "$successor_policy_probe_root"
        return 1
    fi
    if [[ -s "$successor_policy_transaction_error" ]]; then
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output" "$successor_policy_outer_error"
        rm -rf -- "$successor_policy_probe_root"
        return 1
    fi
    if ! CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$successor_policy_probe_root \
        /bin/bash "$successor_policy_repository_root/$successor_policy_outer" \
        --production-path-test >"$successor_policy_outer_output" \
        2>"$successor_policy_outer_error"; then
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output" "$successor_policy_outer_error"
        rm -rf -- "$successor_policy_probe_root"
        return 1
    fi
    if [[ -s "$successor_policy_outer_error" ]]; then
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output" "$successor_policy_outer_error"
        rm -rf -- "$successor_policy_probe_root"
        return 1
    fi
    if ! successor_policy_outer_evidence_valid "$successor_policy_probe_root"; then
        rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
            "$successor_policy_outer_output" "$successor_policy_outer_error"
        rm -rf -- "$successor_policy_probe_root"
        return 1
    fi
    while IFS=$'\t' read -r _ _ successor_policy_marker_entrypoint _ successor_policy_marker; do
        case "$successor_policy_marker" in
            marker) continue ;;
        esac
        case "$successor_policy_marker_entrypoint" in
            outer) successor_policy_marker_output=$successor_policy_outer_output ;;
            transaction) successor_policy_marker_output=$successor_policy_transaction_output ;;
            *) return 1 ;;
        esac
        if [[ "$(grep -Fxc "${successor_policy_marker}=true" \
            "$successor_policy_marker_output" || true)" -ne 1 ]]; then
            rm -f -- "$successor_policy_transaction_output" \
                "$successor_policy_transaction_error" "$successor_policy_outer_output" \
                "$successor_policy_outer_error"
            rm -rf -- "$successor_policy_probe_root"
            return 1
        fi
        printf '%s_coverage_%s=true\n' "$successor_policy_prefix" "$successor_policy_marker"
    done <"$successor_policy_repository_root/$successor_policy_coverage"
    rm -f -- "$successor_policy_transaction_output" "$successor_policy_transaction_error" \
        "$successor_policy_outer_output" "$successor_policy_outer_error" || return 1
    rm -rf -- "$successor_policy_probe_root" || return 1
    /bin/bash "$successor_policy_repository_root/$successor_policy_regression" || return 1
    # conditional-validator-explicit-failures-end
}

successor_policy_registry_valid() {
    local successor_policy_require_defined=${1:-0}
    local successor_policy_schema successor_policy_status successor_policy_action
    local successor_policy_action_manifest successor_policy_transaction successor_policy_outer
    local successor_policy_state_relative successor_policy_state_hash successor_policy_coverage
    local successor_policy_regression successor_policy_state

    # conditional-validator-explicit-failures-begin
    successor_policy_regular_file "$successor_policy_registry" || return 1
    [[ "$(sed -n '1p' "$successor_policy_registry")" = $'schema_version\tstatus\taction\taction_manifest\ttransaction\touter_runner\tstate_contract\tstate_sha256\tcoverage\tregression' ]] || return 1
    [[ "$(wc -l <"$successor_policy_registry")" -eq 2 ]] || return 1
    IFS=$'\t' read -r successor_policy_schema successor_policy_status successor_policy_action \
        successor_policy_action_manifest successor_policy_transaction successor_policy_outer \
        successor_policy_state_relative successor_policy_state_hash successor_policy_coverage \
        successor_policy_regression < <(sed -n '2p' "$successor_policy_registry")
    [[ "$successor_policy_schema" = 1 ]] || return 1
    [[ "$successor_policy_state_relative" = Caddy/manifests/current-live-state.tsv ]] || return 1
    [[ "$successor_policy_coverage" = Caddy/manifests/deployable-successor-coverage.tsv ]] || return 1
    [[ "$successor_policy_state_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    successor_policy_state=$successor_policy_repository_root/$successor_policy_state_relative
    successor_policy_state_valid "$successor_policy_state" || return 1
    successor_policy_regular_file "$successor_policy_repository_root/$successor_policy_coverage" || return 1
    [[ "$(sed -n '1p' "$successor_policy_repository_root/$successor_policy_coverage")" = $'scenario\tphase\tentrypoint\texpectation\tmarker' ]] || return 1
    [[ "$successor_policy_state_hash" = "$(sha256sum "$successor_policy_state" | awk '{ print $1 }')" ]] || return 1
    case "$successor_policy_status" in
        none)
            [[ "$successor_policy_require_defined" = 0 ]] || return 1
            [[ "$successor_policy_action" = - && "$successor_policy_action_manifest" = - ]] || return 1
            [[ "$successor_policy_transaction" = - && "$successor_policy_outer" = - ]] || return 1
            [[ "$successor_policy_regression" = - ]] || return 1
            [[ "$(wc -l <"$successor_policy_repository_root/$successor_policy_coverage")" -eq 1 ]] || return 1
            ;;
        defined)
            successor_policy_defined_valid "$successor_policy_action" \
                "$successor_policy_action_manifest" "$successor_policy_transaction" \
                "$successor_policy_outer" "$successor_policy_coverage" \
                "$successor_policy_regression" || return 1
            ;;
        *) return 1 ;;
    esac
    # conditional-validator-explicit-failures-end
}

case "${1:-}" in
    --check)
        [[ $# -eq 1 ]] || exit 64
        successor_policy_check registry successor_policy_registry_valid 0 || exit 1
        printf '%s_complete=true\n' "$successor_policy_prefix"
        ;;
    --authorization-ready)
        [[ $# -eq 1 ]] || exit 64
        successor_policy_check authorization_ready successor_policy_registry_valid 1 || exit 1
        printf '%s_complete=true\n' "$successor_policy_prefix"
        ;;
    *)
        printf 'Usage: %s --check|--authorization-ready\n' "${0##*/}" >&2
        exit 64
        ;;
esac
