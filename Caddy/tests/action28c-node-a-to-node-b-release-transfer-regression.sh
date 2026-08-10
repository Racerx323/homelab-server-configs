#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28c_regression
readonly builder_sha256=bc17385186d282412e7f89f9bcdb150bf17eaa6427d09667b57e7d38debef86f
readonly generated_driver_sha256=175fda13c27238f891cddb79dfc067017fa4b066c7f4a8bddcbbddbac067bdf9
readonly generated_inspector_sha256=475bc8825dea697c2936760d603ef1ca4b5ad28f5214169800103e0fc7d61513
readonly generated_runner_sha256=15689ce1b521c32d10fd927a69f346f8499fff60b422a2ce375fe9aa16c23eaf
readonly fixture_revision=action28c-fixture-release
readonly fixture_parent=action16ar-retry-node-a-default-deny
readonly fixture_manifest_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly builder=$caddy_root/scripts/build-node-a-to-node-b-release-transfer-action28c.sh
readonly outer=$caddy_root/scripts/run-node-a-to-node-b-release-transfer-action28c-outer.sh
work_root=$(mktemp -d /tmp/caddy-action28c-regression.XXXXXX)
readonly work_root
readonly generated=$work_root/generated
readonly fake_ssh=$work_root/ssh
readonly call_log=$work_root/calls

cleanup() {
    local action28c_regression_status=$?

    rm -rf -- "$work_root"
    exit "$action28c_regression_status"
}
trap cleanup EXIT
file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action28c_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28c_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28c_regression_label" >&2
    return 1
}
count_matches_in_files() {
    local action28c_regression_pattern=$1
    local action28c_regression_count=0
    local action28c_regression_file
    local action28c_regression_file_count

    shift
    for action28c_regression_file in "$@"; do
        action28c_regression_file_count=$(grep -Ec "$action28c_regression_pattern" \
            "$action28c_regression_file" || true)
        action28c_regression_count=$((action28c_regression_count + action28c_regression_file_count))
    done
    printf '%s\n' "$action28c_regression_count"
}
run_validation_case() {
    local action28c_regression_mode=$1
    local action28c_regression_expected_status=$2
    local action28c_regression_case_root
    local action28c_regression_stdout
    local action28c_regression_stderr
    local action28c_regression_status=0

    action28c_regression_case_root=$(mktemp -d "$work_root/validation.XXXXXX")
    action28c_regression_stdout=$action28c_regression_case_root/stdout
    action28c_regression_stderr=$action28c_regression_case_root/stderr
    cp -- "$successful_stdout" "$action28c_regression_stdout"
    : >"$action28c_regression_stderr"
    case "$action28c_regression_mode" in
        missing_acceptance) sed -i '/^action_28c_acceptance=true$/d' "$action28c_regression_stdout" ;;
        duplicate_revision) printf 'action_28c_value_revision=%s\n' "$fixture_revision" >>"$action28c_regression_stdout" ;;
        malformed_manifest) sed -i 's/^action_28c_value_manifest_sha256=.*/action_28c_value_manifest_sha256=not-a-hash/' "$action28c_regression_stdout" ;;
        mutation_true) sed -i 's/^action_28c_service_mutations=false$/action_28c_service_mutations=true/' "$action28c_regression_stdout" ;;
        stderr) printf 'bounded regression stderr\n' >"$action28c_regression_stderr" ;;
        nonzero) ;;
        *) return 1 ;;
    esac
    if CADDY_ACTION28C_TEST_MODE=1 /bin/bash "$outer" --test-validate \
        "$action28c_regression_stdout" "$action28c_regression_stderr" \
        "$(if [[ "$action28c_regression_mode" = nonzero ]]; then printf 23; else printf 0; fi)" \
        >/dev/null 2>&1; then
        action28c_regression_status=0
    else
        action28c_regression_status=$?
    fi
    [[ "$action28c_regression_status" -eq "$action28c_regression_expected_status" ]]
}

mkdir -m 0700 "$generated"
/bin/bash "$builder" "$generated"
cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly call_log=${ACTION28C_FIXTURE_CALL_LOG:?}
readonly driver_sha256=${ACTION28C_FIXTURE_DRIVER_SHA256:?}
readonly inspector_sha256=${ACTION28C_FIXTURE_INSPECTOR_SHA256:?}
readonly fixture_revision=${ACTION28C_FIXTURE_REVISION:?}
readonly fixture_parent=${ACTION28C_FIXTURE_PARENT:?}
readonly fixture_manifest_sha256=${ACTION28C_FIXTURE_MANIFEST_SHA256:?}
payload=$(mktemp /tmp/action28c-fake-ssh.XXXXXX)
readonly payload
trap 'rm -f -- "$payload"' EXIT
cat >"$payload"
payload_sha256=$(sha256sum "$payload" | awk '{ print $1 }')
readonly payload_sha256
arguments=" $* "
emit_transcript() {
    local action28c_fixture_prefix=$1
    local action28c_fixture_phase=$2
    local action28c_fixture_revision_value=$3
    local action28c_fixture_parent_value=$4
    local action28c_fixture_manifest_value=$5

    printf '%s\n' \
        "${action28c_fixture_prefix}_check_fixture=true" \
        "${action28c_fixture_prefix}_value_phase=$action28c_fixture_phase" \
        "${action28c_fixture_prefix}_value_revision=$action28c_fixture_revision_value" \
        "${action28c_fixture_prefix}_value_parent_revision=$action28c_fixture_parent_value" \
        "${action28c_fixture_prefix}_value_manifest_sha256=$action28c_fixture_manifest_value" \
        "${action28c_fixture_prefix}_checks_total=1" \
        "${action28c_fixture_prefix}_checks_passed=1" \
        "${action28c_fixture_prefix}_checks_failed=0" \
        "${action28c_fixture_prefix}_first_failure=none" \
        "${action28c_fixture_prefix}_acceptance=true"
}
if [[ "$arguments" == *' pi@10.1.0.54 '* && "$arguments" == *' --preflight '* ]]; then
    [[ "$payload_sha256" = "$inspector_sha256" ]]
    printf 'node_b_preflight\n' >>"$call_log"
    emit_transcript action_28c_node_b preflight unavailable unavailable unavailable
elif [[ "$arguments" == *' pi@10.1.0.53 '* && "$arguments" == *' --preflight '* ]]; then
    [[ "$payload_sha256" = "$driver_sha256" ]]
    printf 'node_a_preflight\n' >>"$call_log"
    emit_transcript action_28c_node_a preflight unavailable unavailable unavailable
elif [[ "$arguments" == *' pi@10.1.0.53 '* && "$arguments" == *' --transfer '* ]]; then
    [[ "$payload_sha256" = "$driver_sha256" ]]
    printf 'node_a_transfer\n' >>"$call_log"
    emit_transcript action_28c_node_a transfer \
        "$fixture_revision" "$fixture_parent" "$fixture_manifest_sha256"
elif [[ "$arguments" == *' pi@10.1.0.54 '* && "$arguments" == *' --complete '* ]]; then
    [[ "$payload_sha256" = "$inspector_sha256" ]]
    [[ "$arguments" == *" --complete $fixture_revision $fixture_parent $fixture_manifest_sha256 "* ]]
    printf 'node_b_complete\n' >>"$call_log"
    emit_transcript action_28c_node_b complete \
        "$fixture_revision" "$fixture_parent" "$fixture_manifest_sha256"
else
    exit 98
fi
FAKE_SSH
chmod 0700 "$fake_ssh"

record_check builder_hash test "$(file_hash "$builder")" = "$builder_sha256"
record_check driver_hash test \
    "$(file_hash "$generated/transfer-node-a-release-to-node-b-action28c.sh")" = \
    "$generated_driver_sha256"
record_check inspector_hash test \
    "$(file_hash "$generated/inspect-node-b-incoming-release-action28c.sh")" = \
    "$generated_inspector_sha256"
record_check runner_hash test \
    "$(file_hash "$generated/run-node-a-to-node-b-release-transfer-action28c.sh")" = \
    "$generated_runner_sha256"
record_check generated_syntax /bin/bash -n "$generated"/*.sh
record_check source_context_executable test -x \
    "$caddy_root/tests/run-source-test-in-context.sh"
record_check generated_runner_self_test env \
    CADDY_ACTION28C_CADDY_ROOT="$caddy_root" \
    /bin/bash "$generated/run-node-a-to-node-b-release-transfer-action28c.sh" \
    --self-test

successful_stdout=$work_root/success.stdout
successful_stderr=$work_root/success.stderr
readonly successful_stdout successful_stderr
: >"$call_log"
runner_status=0
ACTION28C_FIXTURE_CALL_LOG="$call_log" \
    ACTION28C_FIXTURE_DRIVER_SHA256="$generated_driver_sha256" \
    ACTION28C_FIXTURE_INSPECTOR_SHA256="$generated_inspector_sha256" \
    ACTION28C_FIXTURE_REVISION="$fixture_revision" \
    ACTION28C_FIXTURE_PARENT="$fixture_parent" \
    ACTION28C_FIXTURE_MANIFEST_SHA256="$fixture_manifest_sha256" \
    CADDY_ACTION28C_SSH_BINARY="$fake_ssh" \
    CADDY_ACTION28C_CADDY_ROOT="$caddy_root" \
    /bin/bash "$generated/run-node-a-to-node-b-release-transfer-action28c.sh" \
    >"$successful_stdout" 2>"$successful_stderr" || runner_status=$?
readonly runner_status
if [[ "$runner_status" -ne 0 ]]; then
    printf '%s_fixture_runner_status=%s\n' "$prefix" "$runner_status" >&2
    sed -n '1,260p' "$successful_stdout" >&2
    sed -n '1,160p' "$successful_stderr" >&2
    exit 1
fi

record_check successful_stderr_empty test ! -s "$successful_stderr"
record_check successful_acceptance grep -Fqx 'action_28c_acceptance=true' "$successful_stdout"
record_check exact_phase_order diff -u \
    <(printf '%s\n' node_b_preflight node_a_preflight node_a_transfer node_b_complete) \
    "$call_log"
record_check historical_prefix_absent test \
    "$(grep -Ec '^action_28_' "$successful_stdout" || true)" -eq 0
record_check service_mutation_absent test \
    "$(count_matches_in_files \
        'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)' \
        "$generated"/*.sh)" -eq 0
record_check remote_delete_absent test \
    "$(count_matches_in_files '(^|[[:space:]])--delete([[:space:]]|$)' \
        "$generated"/*.sh)" -eq 0
record_check accepted_action28b_baseline_present grep -Fq \
    'record_command action28b_manifest_exact' \
    "$generated/transfer-node-a-release-to-node-b-action28c.sh"
record_check retained_tree_gate_present grep -Fq \
    'record_command retained_release_tree_exact' \
    "$generated/transfer-node-a-release-to-node-b-action28c.sh"
record_check receiver_finalization_required grep -Fq \
    'record_command release_complete_regular' \
    "$generated/inspect-node-b-incoming-release-action28c.sh"
record_check missing_acceptance_rejected run_validation_case missing_acceptance 97
record_check duplicate_revision_rejected run_validation_case duplicate_revision 97
record_check malformed_manifest_rejected run_validation_case malformed_manifest 97
record_check mutation_true_rejected run_validation_case mutation_true 97
record_check stderr_rejected run_validation_case stderr 97
record_check nonzero_rejected run_validation_case nonzero 97

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28_rerun=false\n' "$prefix"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_release_transferred=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
