#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28e_regression
readonly builder_sha256=a72079d2511e0f21378571b36664c96e2627fc9e35ae869ab0780ab304b46aba
readonly predecessor_builder_sha256=5f7cf9afe81b142ecab17f4fc07570f62cf63a535c710ecf59f443d819d92f4f
readonly generated_driver_sha256=ce27b4b280e8f31ec240d53c930d4140ff3ad809f43313c7d8b8500d6cfc1405
readonly generated_inspector_sha256=56caf44ea261f997d177e9bc4cf340538e3a0de7d0fe39097a88d692d93b8e09
readonly generated_runner_sha256=1c89e740b361426f534e3ad6abf697c194b64ede40b2e4ec72f9711490d33702
readonly predecessor_driver_sha256=be998f395d430bfc537227cd5ebc45a7fe60b60a3b7653189e0ee839aeee6d58
readonly predecessor_inspector_sha256=4e4b88ab315a7ed74c6e78350745c33b788f761372a19b8f8ca5f9c5434b8482
readonly predecessor_runner_sha256=df6847bac598b8cd8453809a1fdddf6e28cabcfe45352ed6ed03ffb45aa429cc
readonly fixture_revision=action28e-fixture-release
readonly fixture_parent=action16ar-retry-node-a-default-deny
readonly fixture_manifest_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly builder=$caddy_root/scripts/build-node-a-to-node-b-release-transfer-action28e.sh
readonly predecessor_builder=$caddy_root/scripts/build-node-a-to-node-b-release-transfer-action28d.sh
readonly outer=$caddy_root/scripts/run-node-a-to-node-b-release-transfer-action28e-outer.sh
readonly collision_policy=$test_directory/check-shell-readonly-local-collisions-v2.sh
readonly conditional_policy=$test_directory/conditional-validator-errexit-policy-regression.sh
work_root=$(mktemp -d /tmp/caddy-action28e-regression.XXXXXX)
readonly work_root
readonly generated=$work_root/generated
readonly predecessor=$work_root/predecessor
readonly normalized=$work_root/normalized
readonly fixture_root=$work_root/source-fixture
readonly fake_ssh=$work_root/ssh
readonly call_log=$work_root/calls

cleanup() {
    local action28e_regression_status=$?

    rm -rf -- "$work_root"
    exit "$action28e_regression_status"
}
trap cleanup EXIT

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
tree_digest() {
    local action28e_regression_tree_root=$1

    (
        cd "$action28e_regression_tree_root" || exit
        find . -printf '%P|%y|%U:%G:%m:%s\n' | LC_ALL=C sort
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}
record_check() {
    local action28e_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28e_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28e_regression_label" >&2
    return 1
}
source_contract_status() {
    local action28e_regression_source=$1
    local action28e_regression_release_root=$2
    local action28e_regression_expected_tree=$3
    local action28e_regression_expected_status=$4
    local action28e_regression_status=0

    /bin/bash "$generated/transfer-node-a-release-to-node-b-action28e.sh" \
        --source-contract-test "$action28e_regression_source" \
        "$action28e_regression_release_root" "$action28e_regression_expected_tree" \
        >/dev/null 2>&1 || action28e_regression_status=$?
    [[ "$action28e_regression_status" -eq "$action28e_regression_expected_status" ]]
}
run_validation_case() {
    local action28e_regression_mode=$1
    local action28e_regression_expected_status=$2
    local action28e_regression_case_root
    local action28e_regression_stdout
    local action28e_regression_stderr
    local action28e_regression_status=0

    action28e_regression_case_root=$(mktemp -d "$work_root/validation.XXXXXX")
    action28e_regression_stdout=$action28e_regression_case_root/stdout
    action28e_regression_stderr=$action28e_regression_case_root/stderr
    cp -- "$successful_stdout" "$action28e_regression_stdout"
    : >"$action28e_regression_stderr"
    case "$action28e_regression_mode" in
        missing_acceptance) sed -i '/^action_28e_acceptance=true$/d' "$action28e_regression_stdout" ;;
        duplicate_revision) printf 'action_28e_value_revision=%s\n' "$fixture_revision" >>"$action28e_regression_stdout" ;;
        malformed_manifest) sed -i 's/^action_28e_value_manifest_sha256=.*/action_28e_value_manifest_sha256=not-a-hash/' "$action28e_regression_stdout" ;;
        mutation_true) sed -i 's/^action_28e_service_mutations=false$/action_28e_service_mutations=true/' "$action28e_regression_stdout" ;;
        stderr) printf 'bounded regression stderr\n' >"$action28e_regression_stderr" ;;
        nonzero) ;;
        *) return 1 ;;
    esac
    if CADDY_ACTION28E_TEST_MODE=1 /bin/bash "$outer" --test-validate \
        "$action28e_regression_stdout" "$action28e_regression_stderr" \
        "$(if [[ "$action28e_regression_mode" = nonzero ]]; then printf 23; else printf 0; fi)" \
        >/dev/null 2>&1; then
        action28e_regression_status=0
    else
        action28e_regression_status=$?
    fi
    [[ "$action28e_regression_status" -eq "$action28e_regression_expected_status" ]]
}
normalize_component() {
    local action28e_regression_source=$1
    local action28e_regression_output=$2

    sed -e 's/action_28e/action_28d/g' \
        -e 's/action28e/action28d/g' \
        -e 's/ACTION28E/ACTION28D/g' \
        -e 's/ce27b4b280e8f31ec240d53c930d4140ff3ad809f43313c7d8b8500d6cfc1405/be998f395d430bfc537227cd5ebc45a7fe60b60a3b7653189e0ee839aeee6d58/' \
        -e 's/56caf44ea261f997d177e9bc4cf340538e3a0de7d0fe39097a88d692d93b8e09/4e4b88ab315a7ed74c6e78350745c33b788f761372a19b8f8ca5f9c5434b8482/' \
        "$action28e_regression_source" >"$action28e_regression_output"
}
normalize_driver() {
    local action28e_regression_source=$1
    local action28e_regression_output=$2
    local action28e_regression_intermediate=$work_root/normalized-driver.intermediate

    awk '
        /# action28e-source-contract-(state|functions|assertions|test-mode)-begin/ {
            skipped = 1
            next
        }
        /# action28e-source-contract-(state|functions|assertions|test-mode)-end/ {
            skipped = 0
            next
        }
        /# action28e-source-contract-invocation-begin/ {
            print "    \"$publisher\" --source \"$source_release\" --node-role node-a \\"
            skipped = 1
            next
        }
        /# action28e-source-contract-invocation-end/ {
            skipped = 0
            next
        }
        !skipped { print }
    ' "$action28e_regression_source" >"$action28e_regression_intermediate"
    normalize_component "$action28e_regression_intermediate" "$action28e_regression_output"
}
production_source_contract() {
    local action28e_regression_driver=$1

    grep -Fq 'readonly release_root=/etc/caddy/releases' "$action28e_regression_driver" || return 1
    # The patterns intentionally match literal generated shell source.
    # shellcheck disable=SC2016
    grep -Fq 'record_command source_target_resolved resolve_source_release "$source_release"' \
        "$action28e_regression_driver" || return 1
    grep -Fq 'record_command source_target_direct_child source_target_direct_child' \
        "$action28e_regression_driver" || return 1
    grep -Fq 'record_command source_target_tree_exact test' \
        "$action28e_regression_driver" || return 1
    # shellcheck disable=SC2016
    grep -Fq '"$publisher" --source "$resolved_source_release" --node-role node-a' \
        "$action28e_regression_driver" || return 1
    # shellcheck disable=SC2016
    ! grep -Fq '"$publisher" --source "$source_release" --node-role node-a' \
        "$action28e_regression_driver"
}

mkdir -m 0700 "$generated" "$predecessor" "$normalized" "$fixture_root"
/bin/bash "$builder" "$generated"
/bin/bash "$predecessor_builder" "$predecessor"

readonly collision_fixture=$work_root/readonly-local-collision.sh
# The fixture text intentionally contains a literal shell variable reference.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'readonly '"duplicate_name=global" \
    'collision_function() {' \
    '    local '"duplicate_name=local" \
    '    printf '\''%s\n'\'' "$duplicate_name"' \
    '}' >"$collision_fixture"
chmod 0600 "$collision_fixture"
record_check collision_policy_current /bin/bash "$collision_policy" \
    "$0" "$builder" "$outer" "$generated"/*.sh
if /bin/bash "$collision_policy" "$collision_fixture" >/dev/null 2>&1; then
    record_check collision_negative_rejected false
else
    record_check collision_negative_rejected true
fi
record_check conditional_policy /bin/bash "$conditional_policy"

record_check builder_hash test "$(file_hash "$builder")" = "$builder_sha256"
record_check predecessor_builder_hash test \
    "$(file_hash "$predecessor_builder")" = "$predecessor_builder_sha256"
record_check driver_hash test \
    "$(file_hash "$generated/transfer-node-a-release-to-node-b-action28e.sh")" = \
    "$generated_driver_sha256"
record_check inspector_hash test \
    "$(file_hash "$generated/inspect-node-b-incoming-release-action28e.sh")" = \
    "$generated_inspector_sha256"
record_check runner_hash test \
    "$(file_hash "$generated/run-node-a-to-node-b-release-transfer-action28e.sh")" = \
    "$generated_runner_sha256"
record_check predecessor_driver_hash test \
    "$(file_hash "$predecessor/transfer-node-a-release-to-node-b-action28d.sh")" = \
    "$predecessor_driver_sha256"
record_check predecessor_inspector_hash test \
    "$(file_hash "$predecessor/inspect-node-b-incoming-release-action28d.sh")" = \
    "$predecessor_inspector_sha256"
record_check predecessor_runner_hash test \
    "$(file_hash "$predecessor/run-node-a-to-node-b-release-transfer-action28d.sh")" = \
    "$predecessor_runner_sha256"
record_check generated_syntax /bin/bash -n "$generated"/*.sh
record_check production_source_contract production_source_contract \
    "$generated/transfer-node-a-release-to-node-b-action28e.sh"

normalize_driver "$generated/transfer-node-a-release-to-node-b-action28e.sh" \
    "$normalized/transfer-node-a-release-to-node-b-action28d.sh"
normalize_component "$generated/inspect-node-b-incoming-release-action28e.sh" \
    "$normalized/inspect-node-b-incoming-release-action28d.sh"
normalize_component "$generated/run-node-a-to-node-b-release-transfer-action28e.sh" \
    "$normalized/run-node-a-to-node-b-release-transfer-action28d.sh"
record_check driver_only_source_contract_and_provenance_changed cmp -s \
    "$normalized/transfer-node-a-release-to-node-b-action28d.sh" \
    "$predecessor/transfer-node-a-release-to-node-b-action28d.sh"
record_check inspector_only_provenance_changed cmp -s \
    "$normalized/inspect-node-b-incoming-release-action28d.sh" \
    "$predecessor/inspect-node-b-incoming-release-action28d.sh"
record_check runner_only_provenance_changed cmp -s \
    "$normalized/run-node-a-to-node-b-release-transfer-action28d.sh" \
    "$predecessor/run-node-a-to-node-b-release-transfer-action28d.sh"

readonly releases=$fixture_root/releases
readonly release=$releases/release-a
readonly current=$fixture_root/current
mkdir -m 0750 "$releases" "$release"
printf 'fixture\n' >"$release/Caddyfile"
ln -s -- "$release" "$current"
fixture_tree_sha256=$(tree_digest "$release")
readonly fixture_tree_sha256
record_check source_contract_valid source_contract_status \
    "$current" "$releases" "$fixture_tree_sha256" 0
record_check direct_directory_rejected source_contract_status \
    "$release" "$releases" "$fixture_tree_sha256" 97
ln -s -- "$releases/missing" "$fixture_root/dangling"
record_check dangling_target_rejected source_contract_status \
    "$fixture_root/dangling" "$releases" "$fixture_tree_sha256" 97
mkdir -m 0750 "$fixture_root/outside"
ln -s -- "$fixture_root/outside" "$fixture_root/outside-current"
record_check outside_root_rejected source_contract_status \
    "$fixture_root/outside-current" "$releases" \
    "$(tree_digest "$fixture_root/outside")" 97
mkdir -m 0750 "$releases/group" "$releases/group/release-b"
ln -s -- "$releases/group/release-b" "$fixture_root/nested-current"
record_check nested_target_rejected source_contract_status \
    "$fixture_root/nested-current" "$releases" \
    "$(tree_digest "$releases/group/release-b")" 97
ln -s -- "$releases" "$fixture_root/releases-link"
record_check symlink_root_rejected source_contract_status \
    "$current" "$fixture_root/releases-link" "$fixture_tree_sha256" 97
record_check tree_drift_rejected source_contract_status \
    "$current" "$releases" \
    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 97

cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly call_log=${ACTION28E_FIXTURE_CALL_LOG:?}
readonly driver_sha256=${ACTION28E_FIXTURE_DRIVER_SHA256:?}
readonly inspector_sha256=${ACTION28E_FIXTURE_INSPECTOR_SHA256:?}
readonly fixture_revision=${ACTION28E_FIXTURE_REVISION:?}
readonly fixture_parent=${ACTION28E_FIXTURE_PARENT:?}
readonly fixture_manifest_sha256=${ACTION28E_FIXTURE_MANIFEST_SHA256:?}
payload=$(mktemp /tmp/action28e-fake-ssh.XXXXXX)
readonly payload
trap 'rm -f -- "$payload"' EXIT
cat >"$payload"
payload_sha256=$(sha256sum "$payload" | awk '{ print $1 }')
readonly payload_sha256
arguments=" $* "
remote_command=${!#}
readonly remote_command
emit_transcript() {
    local action28e_fixture_prefix=$1
    local action28e_fixture_phase=$2
    local action28e_fixture_revision_value=$3
    local action28e_fixture_parent_value=$4
    local action28e_fixture_manifest_value=$5

    printf '%s\n' \
        "${action28e_fixture_prefix}_check_fixture=true" \
        "${action28e_fixture_prefix}_value_phase=$action28e_fixture_phase" \
        "${action28e_fixture_prefix}_value_revision=$action28e_fixture_revision_value" \
        "${action28e_fixture_prefix}_value_parent_revision=$action28e_fixture_parent_value" \
        "${action28e_fixture_prefix}_value_manifest_sha256=$action28e_fixture_manifest_value" \
        "${action28e_fixture_prefix}_checks_total=1" \
        "${action28e_fixture_prefix}_checks_passed=1" \
        "${action28e_fixture_prefix}_checks_failed=0" \
        "${action28e_fixture_prefix}_first_failure=none" \
        "${action28e_fixture_prefix}_acceptance=true"
}
if [[ "$arguments" == *' pi@10.1.0.54 '* &&
    "$remote_command" = 'cd / && sudo -n /bin/bash -s -- --preflight' ]]; then
    [[ "$payload_sha256" = "$inspector_sha256" ]]
    printf 'node_b_preflight\n' >>"$call_log"
    emit_transcript action_28e_node_b preflight unavailable unavailable unavailable
elif [[ "$arguments" == *' pi@10.1.0.53 '* &&
    "$remote_command" = 'cd / && sudo -n /bin/bash -s -- --preflight' ]]; then
    [[ "$payload_sha256" = "$driver_sha256" ]]
    printf 'node_a_preflight\n' >>"$call_log"
    emit_transcript action_28e_node_a preflight unavailable unavailable unavailable
elif [[ "$arguments" == *' pi@10.1.0.53 '* &&
    "$remote_command" = 'cd / && sudo -n /bin/bash -s -- --transfer' ]]; then
    [[ "$payload_sha256" = "$driver_sha256" ]]
    printf 'node_a_transfer\n' >>"$call_log"
    emit_transcript action_28e_node_a transfer \
        "$fixture_revision" "$fixture_parent" "$fixture_manifest_sha256"
elif [[ "$arguments" == *' pi@10.1.0.54 '* &&
    "$remote_command" = "cd / && sudo -n /bin/bash -s -- --complete $fixture_revision $fixture_parent $fixture_manifest_sha256" ]]; then
    [[ "$payload_sha256" = "$inspector_sha256" ]]
    printf 'node_b_complete\n' >>"$call_log"
    emit_transcript action_28e_node_b complete \
        "$fixture_revision" "$fixture_parent" "$fixture_manifest_sha256"
else
    exit 98
fi
FAKE_SSH
chmod 0700 "$fake_ssh"

readonly successful_stdout=$work_root/success.stdout
readonly successful_stderr=$work_root/success.stderr
: >"$call_log"
runner_status=0
ACTION28E_FIXTURE_CALL_LOG="$call_log" \
    ACTION28E_FIXTURE_DRIVER_SHA256="$generated_driver_sha256" \
    ACTION28E_FIXTURE_INSPECTOR_SHA256="$generated_inspector_sha256" \
    ACTION28E_FIXTURE_REVISION="$fixture_revision" \
    ACTION28E_FIXTURE_PARENT="$fixture_parent" \
    ACTION28E_FIXTURE_MANIFEST_SHA256="$fixture_manifest_sha256" \
    CADDY_ACTION28E_SSH_BINARY="$fake_ssh" \
    CADDY_ACTION28E_CADDY_ROOT="$caddy_root" \
    /bin/bash "$generated/run-node-a-to-node-b-release-transfer-action28e.sh" \
    >"$successful_stdout" 2>"$successful_stderr" || runner_status=$?
readonly runner_status
if [[ "$runner_status" -ne 0 ]]; then
    printf '%s_fixture_runner_status=%s\n' "$prefix" "$runner_status" >&2
    sed -n '1,280p' "$successful_stdout" >&2
    sed -n '1,180p' "$successful_stderr" >&2
    exit 1
fi
record_check production_runner_status_zero test "$runner_status" -eq 0
record_check successful_stderr_empty test ! -s "$successful_stderr"
record_check successful_acceptance grep -Fqx 'action_28e_acceptance=true' \
    "$successful_stdout"
record_check exact_phase_order diff -u \
    <(printf '%s\n' node_b_preflight node_a_preflight node_a_transfer node_b_complete) \
    "$call_log"
record_check predecessor_prefix_absent test \
    "$(grep -Ec '^action_28d' "$successful_stdout" || true)" -eq 0
record_check missing_acceptance_rejected run_validation_case missing_acceptance 97
record_check duplicate_revision_rejected run_validation_case duplicate_revision 97
record_check malformed_manifest_rejected run_validation_case malformed_manifest 97
record_check mutation_true_rejected run_validation_case mutation_true 97
record_check stderr_rejected run_validation_case stderr 97
record_check nonzero_rejected run_validation_case nonzero 97

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28d_rerun=false\n' "$prefix"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_release_transferred=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
