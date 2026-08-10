#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28d_regression
readonly builder_sha256=5f7cf9afe81b142ecab17f4fc07570f62cf63a535c710ecf59f443d819d92f4f
readonly predecessor_builder_sha256=bc17385186d282412e7f89f9bcdb150bf17eaa6427d09667b57e7d38debef86f
readonly generated_driver_sha256=be998f395d430bfc537227cd5ebc45a7fe60b60a3b7653189e0ee839aeee6d58
readonly generated_inspector_sha256=4e4b88ab315a7ed74c6e78350745c33b788f761372a19b8f8ca5f9c5434b8482
readonly generated_runner_sha256=df6847bac598b8cd8453809a1fdddf6e28cabcfe45352ed6ed03ffb45aa429cc
readonly fixture_revision=action28d-fixture-release
readonly fixture_parent=action16ar-retry-node-a-default-deny
readonly fixture_manifest_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly builder=$caddy_root/scripts/build-node-a-to-node-b-release-transfer-action28d.sh
readonly predecessor_builder=$caddy_root/scripts/build-node-a-to-node-b-release-transfer-action28c.sh
readonly outer=$caddy_root/scripts/run-node-a-to-node-b-release-transfer-action28d-outer.sh
work_root=$(mktemp -d /tmp/caddy-action28d-regression.XXXXXX)
readonly work_root
readonly generated=$work_root/generated
readonly predecessor=$work_root/predecessor
readonly normalized=$work_root/normalized
readonly fake_ssh=$work_root/ssh
readonly call_log=$work_root/calls

cleanup() {
    local action28d_regression_status=$?

    rm -rf -- "$work_root"
    exit "$action28d_regression_status"
}
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28d_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28d_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28d_regression_label" >&2
    return 1
}
production_command_contract() {
    local action28d_regression_runner=$1

    # The pattern intentionally matches literal generated shell source.
    # shellcheck disable=SC2016
    [[ "$(grep -Fc \
        '"cd / && sudo -n /bin/bash -s -- $remote_argument"' \
        "$action28d_regression_runner" || true)" -eq 1 ]] || return 1
    ! grep -Fq '/bin/bash -s/' "$action28d_regression_runner"
}
malformed_contract_rejected() {
    ! production_command_contract "$1"
}
normalize_successor() {
    local action28d_regression_source=$1
    local action28d_regression_output=$2

    # The expression intentionally rewrites literal generated shell source.
    # shellcheck disable=SC2016
    sed -e 's/action_28d/action_28c/g' \
        -e 's/action28d/action28c/g' \
        -e 's/ACTION28D/ACTION28C/g' \
        -e 's/be998f395d430bfc537227cd5ebc45a7fe60b60a3b7653189e0ee839aeee6d58/175fda13c27238f891cddb79dfc067017fa4b066c7f4a8bddcbbddbac067bdf9/' \
        -e 's/4e4b88ab315a7ed74c6e78350745c33b788f761372a19b8f8ca5f9c5434b8482/475bc8825dea697c2936760d603ef1ca4b5ad28f5214169800103e0fc7d61513/' \
        -e 's|sudo -n /bin/bash -s -- $remote_argument|sudo -n /bin/bash -s/ -- $remote_argument|' \
        "$action28d_regression_source" >"$action28d_regression_output"
}
run_validation_case() {
    local action28d_regression_mode=$1
    local action28d_regression_expected_status=$2
    local action28d_regression_case_root
    local action28d_regression_stdout
    local action28d_regression_stderr
    local action28d_regression_status=0

    action28d_regression_case_root=$(mktemp -d "$work_root/validation.XXXXXX")
    action28d_regression_stdout=$action28d_regression_case_root/stdout
    action28d_regression_stderr=$action28d_regression_case_root/stderr
    cp -- "$successful_stdout" "$action28d_regression_stdout"
    : >"$action28d_regression_stderr"
    case "$action28d_regression_mode" in
        missing_acceptance) sed -i '/^action_28d_acceptance=true$/d' "$action28d_regression_stdout" ;;
        duplicate_revision) printf 'action_28d_value_revision=%s\n' "$fixture_revision" >>"$action28d_regression_stdout" ;;
        malformed_manifest) sed -i 's/^action_28d_value_manifest_sha256=.*/action_28d_value_manifest_sha256=not-a-hash/' "$action28d_regression_stdout" ;;
        mutation_true) sed -i 's/^action_28d_service_mutations=false$/action_28d_service_mutations=true/' "$action28d_regression_stdout" ;;
        stderr) printf 'bounded regression stderr\n' >"$action28d_regression_stderr" ;;
        nonzero) ;;
        *) return 1 ;;
    esac
    if CADDY_ACTION28D_TEST_MODE=1 /bin/bash "$outer" --test-validate \
        "$action28d_regression_stdout" "$action28d_regression_stderr" \
        "$(if [[ "$action28d_regression_mode" = nonzero ]]; then printf 23; else printf 0; fi)" \
        >/dev/null 2>&1; then
        action28d_regression_status=0
    else
        action28d_regression_status=$?
    fi
    [[ "$action28d_regression_status" -eq "$action28d_regression_expected_status" ]]
}

mkdir -m 0700 "$generated" "$predecessor" "$normalized"
/bin/bash "$builder" "$generated"
/bin/bash "$predecessor_builder" "$predecessor"

cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly call_log=${ACTION28D_FIXTURE_CALL_LOG:?}
readonly driver_sha256=${ACTION28D_FIXTURE_DRIVER_SHA256:?}
readonly inspector_sha256=${ACTION28D_FIXTURE_INSPECTOR_SHA256:?}
readonly fixture_revision=${ACTION28D_FIXTURE_REVISION:?}
readonly fixture_parent=${ACTION28D_FIXTURE_PARENT:?}
readonly fixture_manifest_sha256=${ACTION28D_FIXTURE_MANIFEST_SHA256:?}
payload=$(mktemp /tmp/action28d-fake-ssh.XXXXXX)
readonly payload
trap 'rm -f -- "$payload"' EXIT
cat >"$payload"
payload_sha256=$(sha256sum "$payload" | awk '{ print $1 }')
readonly payload_sha256
arguments=" $* "
remote_command=${!#}
readonly remote_command
emit_transcript() {
    local action28d_fixture_prefix=$1
    local action28d_fixture_phase=$2
    local action28d_fixture_revision_value=$3
    local action28d_fixture_parent_value=$4
    local action28d_fixture_manifest_value=$5

    printf '%s\n' \
        "${action28d_fixture_prefix}_check_fixture=true" \
        "${action28d_fixture_prefix}_value_phase=$action28d_fixture_phase" \
        "${action28d_fixture_prefix}_value_revision=$action28d_fixture_revision_value" \
        "${action28d_fixture_prefix}_value_parent_revision=$action28d_fixture_parent_value" \
        "${action28d_fixture_prefix}_value_manifest_sha256=$action28d_fixture_manifest_value" \
        "${action28d_fixture_prefix}_checks_total=1" \
        "${action28d_fixture_prefix}_checks_passed=1" \
        "${action28d_fixture_prefix}_checks_failed=0" \
        "${action28d_fixture_prefix}_first_failure=none" \
        "${action28d_fixture_prefix}_acceptance=true"
}
if [[ "$arguments" == *' pi@10.1.0.54 '* &&
    "$remote_command" = 'cd / && sudo -n /bin/bash -s -- --preflight' ]]; then
    [[ "$payload_sha256" = "$inspector_sha256" ]]
    printf 'node_b_preflight|%s\n' "$remote_command" >>"$call_log"
    emit_transcript action_28d_node_b preflight unavailable unavailable unavailable
elif [[ "$arguments" == *' pi@10.1.0.53 '* &&
    "$remote_command" = 'cd / && sudo -n /bin/bash -s -- --preflight' ]]; then
    [[ "$payload_sha256" = "$driver_sha256" ]]
    printf 'node_a_preflight|%s\n' "$remote_command" >>"$call_log"
    emit_transcript action_28d_node_a preflight unavailable unavailable unavailable
elif [[ "$arguments" == *' pi@10.1.0.53 '* &&
    "$remote_command" = 'cd / && sudo -n /bin/bash -s -- --transfer' ]]; then
    [[ "$payload_sha256" = "$driver_sha256" ]]
    printf 'node_a_transfer|%s\n' "$remote_command" >>"$call_log"
    emit_transcript action_28d_node_a transfer \
        "$fixture_revision" "$fixture_parent" "$fixture_manifest_sha256"
elif [[ "$arguments" == *' pi@10.1.0.54 '* &&
    "$remote_command" = "cd / && sudo -n /bin/bash -s -- --complete $fixture_revision $fixture_parent $fixture_manifest_sha256" ]]; then
    [[ "$payload_sha256" = "$inspector_sha256" ]]
    printf 'node_b_complete|%s\n' "$remote_command" >>"$call_log"
    emit_transcript action_28d_node_b complete \
        "$fixture_revision" "$fixture_parent" "$fixture_manifest_sha256"
else
    exit 98
fi
FAKE_SSH
chmod 0700 "$fake_ssh"

record_check builder_hash test "$(file_hash "$builder")" = "$builder_sha256"
record_check predecessor_builder_hash test \
    "$(file_hash "$predecessor_builder")" = "$predecessor_builder_sha256"
record_check driver_hash test \
    "$(file_hash "$generated/transfer-node-a-release-to-node-b-action28d.sh")" = \
    "$generated_driver_sha256"
record_check inspector_hash test \
    "$(file_hash "$generated/inspect-node-b-incoming-release-action28d.sh")" = \
    "$generated_inspector_sha256"
record_check runner_hash test \
    "$(file_hash "$generated/run-node-a-to-node-b-release-transfer-action28d.sh")" = \
    "$generated_runner_sha256"
record_check generated_syntax /bin/bash -n "$generated"/*.sh
record_check corrected_command_exact production_command_contract \
    "$generated/run-node-a-to-node-b-release-transfer-action28d.sh"

malformed_runner=$work_root/malformed-runner.sh
readonly malformed_runner
# The expression intentionally rewrites literal generated shell source.
# shellcheck disable=SC2016
sed 's|sudo -n /bin/bash -s -- $remote_argument|sudo -n /bin/bash -s/ -- $remote_argument|' \
    "$generated/run-node-a-to-node-b-release-transfer-action28d.sh" >"$malformed_runner"
record_check malformed_command_rejected malformed_contract_rejected \
    "$malformed_runner"

normalize_successor "$generated/transfer-node-a-release-to-node-b-action28d.sh" \
    "$normalized/transfer-node-a-release-to-node-b-action28c.sh"
normalize_successor "$generated/inspect-node-b-incoming-release-action28d.sh" \
    "$normalized/inspect-node-b-incoming-release-action28c.sh"
normalize_successor "$generated/run-node-a-to-node-b-release-transfer-action28d.sh" \
    "$normalized/run-node-a-to-node-b-release-transfer-action28c.sh"
record_check driver_only_provenance_changed cmp -s \
    "$normalized/transfer-node-a-release-to-node-b-action28c.sh" \
    "$predecessor/transfer-node-a-release-to-node-b-action28c.sh"
record_check inspector_only_provenance_changed cmp -s \
    "$normalized/inspect-node-b-incoming-release-action28c.sh" \
    "$predecessor/inspect-node-b-incoming-release-action28c.sh"
record_check runner_only_command_and_provenance_changed cmp -s \
    "$normalized/run-node-a-to-node-b-release-transfer-action28c.sh" \
    "$predecessor/run-node-a-to-node-b-release-transfer-action28c.sh"

successful_stdout=$work_root/success.stdout
successful_stderr=$work_root/success.stderr
readonly successful_stdout successful_stderr
: >"$call_log"
runner_status=0
ACTION28D_FIXTURE_CALL_LOG="$call_log" \
    ACTION28D_FIXTURE_DRIVER_SHA256="$generated_driver_sha256" \
    ACTION28D_FIXTURE_INSPECTOR_SHA256="$generated_inspector_sha256" \
    ACTION28D_FIXTURE_REVISION="$fixture_revision" \
    ACTION28D_FIXTURE_PARENT="$fixture_parent" \
    ACTION28D_FIXTURE_MANIFEST_SHA256="$fixture_manifest_sha256" \
    CADDY_ACTION28D_SSH_BINARY="$fake_ssh" \
    CADDY_ACTION28D_CADDY_ROOT="$caddy_root" \
    /bin/bash "$generated/run-node-a-to-node-b-release-transfer-action28d.sh" \
    >"$successful_stdout" 2>"$successful_stderr" || runner_status=$?
readonly runner_status
if [[ "$runner_status" -ne 0 ]]; then
    printf '%s_fixture_runner_status=%s\n' "$prefix" "$runner_status" >&2
    sed -n '1,260p' "$successful_stdout" >&2
    sed -n '1,160p' "$successful_stderr" >&2
    exit 1
fi
record_check production_runner_status_zero test "$runner_status" -eq 0
record_check successful_stderr_empty test ! -s "$successful_stderr"
record_check successful_acceptance grep -Fqx 'action_28d_acceptance=true' "$successful_stdout"
record_check exact_phase_and_command_order diff -u \
    <(printf '%s\n' \
        'node_b_preflight|cd / && sudo -n /bin/bash -s -- --preflight' \
        'node_a_preflight|cd / && sudo -n /bin/bash -s -- --preflight' \
        'node_a_transfer|cd / && sudo -n /bin/bash -s -- --transfer' \
        "node_b_complete|cd / && sudo -n /bin/bash -s -- --complete $fixture_revision $fixture_parent $fixture_manifest_sha256") \
    "$call_log"
record_check action_28c_prefix_absent test \
    "$(grep -Ec '^action_28c' "$successful_stdout" || true)" -eq 0
record_check missing_acceptance_rejected run_validation_case missing_acceptance 97
record_check duplicate_revision_rejected run_validation_case duplicate_revision 97
record_check malformed_manifest_rejected run_validation_case malformed_manifest 97
record_check mutation_true_rejected run_validation_case mutation_true 97
record_check stderr_rejected run_validation_case stderr 97
record_check nonzero_rejected run_validation_case nonzero 97

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28c_rerun=false\n' "$prefix"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_release_transferred=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
