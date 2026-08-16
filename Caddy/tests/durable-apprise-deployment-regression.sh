#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=durable_apprise_deployment_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly registry=${CADDY_DEPLOYABLE_SUCCESSOR_REGISTRY:-$repository_root/Caddy/manifests/deployable-successor.tsv}
readonly coverage=${CADDY_DEPLOYABLE_SUCCESSOR_COVERAGE:-$repository_root/Caddy/manifests/deployable-successor-coverage.tsv}

check() {
    local durable_apprise_label=$1

    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$durable_apprise_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$durable_apprise_label" >&2
    return 1
}

regular_file() {
    local durable_apprise_path=$1

    [[ -f "$durable_apprise_path" && ! -L "$durable_apprise_path" ]]
}

IFS=$'\t' read -r _ successor_status _ _ successor_transaction \
    successor_outer _ _ _ _ < <(sed -n '2p' "$registry")
[[ "$successor_status" = defined ]] || exit 64
readonly successor_transaction successor_outer
readonly transaction=$repository_root/$successor_transaction
readonly outer=$repository_root/$successor_outer

check registry_regular regular_file "$registry" || exit 1
check coverage_regular regular_file "$coverage" || exit 1
check transaction_regular regular_file "$transaction" || exit 1
check outer_regular regular_file "$outer" || exit 1

work_root=$(mktemp -d /tmp/caddy-durable-apprise-current.XXXXXX)
readonly work_root
cleanup() { rm -rf -- "$work_root"; }
trap cleanup EXIT INT TERM
evidence_root=$work_root/evidence
install -d -m 0700 "$evidence_root"

/bin/bash "$transaction" --production-path-test \
    >"$work_root/transaction.stdout" 2>"$work_root/transaction.stderr"
[[ ! -s "$work_root/transaction.stderr" ]]
CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$evidence_root \
    /bin/bash "$outer" --production-path-test \
    >"$work_root/outer.stdout" 2>"$work_root/outer.stderr"
[[ ! -s "$work_root/outer.stderr" ]]

while IFS=$'\t' read -r _ _ durable_apprise_entrypoint _ durable_apprise_marker; do
    [[ "$durable_apprise_marker" != marker ]] || continue
    case "$durable_apprise_entrypoint" in
        outer) durable_apprise_output=$work_root/outer.stdout ;;
        transaction) durable_apprise_output=$work_root/transaction.stdout ;;
        *) exit 1 ;;
    esac
    [[ "$(grep -Fxc "${durable_apprise_marker}=true" \
        "$durable_apprise_output" || true)" -eq 1 ]]
done <"$coverage"

check payload_observed grep -Eq '^[0-9a-f]{64}$' "$evidence_root/payload.sha256" || exit 1
check remote_path_observed grep -Eq '^/tmp/[A-Za-z0-9._/-]+$' \
    "$evidence_root/remote-path" || exit 1
check upload_sequence diff -u \
    <(printf '%s\n' $'prepare\t0' $'accept\t0' $'disposition\t0') \
    "$evidence_root/upload-events.tsv" || exit 1
check remote_command_uses_payload grep -Fq "$(<"$evidence_root/remote-path")" \
    "$evidence_root/remote-command.argv" || exit 1
check remote_command_streams_stdin grep -Fq '/bin/bash -s --' \
    "$evidence_root/remote-command.argv" || exit 1
check transaction_status grep -Fxq 0 "$evidence_root/transaction.status" || exit 1
check no_mutation grep -Fxq 0 "$evidence_root/mutation-count" || exit 1
printf '%s_complete=true\n' "$prefix"
