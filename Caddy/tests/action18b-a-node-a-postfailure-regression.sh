#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector="$caddy_root/scripts/inspect-node-a-action18b-postfailure-action18b-a.sh"
readonly runner="$caddy_root/scripts/run-node-a-action18b-postfailure-action18b-a.sh"
readonly collision_checker="$test_directory/check-shell-readonly-local-collisions-v2.sh"
readonly inspector_sha256=f893c433739b0b7c115b7d46c9e13dfd38338f2edbe7259ab3fae52a68545c0a

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_hash() {
    local hash_label=$1
    local hash_path=$2
    local expected_hash=$3

    [[ "$(file_hash "$hash_path")" == "$expected_hash" ]] || return 1
    printf 'action_18b_a_regression_assertion_%s=true\n' "$hash_label"
}

regression_root=$(mktemp -d /tmp/caddy-action18b-a-regression.XXXXXX)
readonly regression_root
cleanup() {
    # shellcheck disable=SC2317
    rm -rf -- "$regression_root"
}
trap cleanup EXIT

require_hash inspector_hash_exact "$inspector" "$inspector_sha256"
bash -n "$inspector" "$runner"
shellcheck "$inspector" "$runner"
"$collision_checker" "$inspector" "$runner" >/dev/null
"$inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --source-test >/dev/null
"$runner" --contract-test >/dev/null

if grep -Eq 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$inspector" "$runner"; then
    printf 'Action 18b-a contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '(^|[[:space:]])(rsync|scp|sftp)([[:space:]]|$)' \
    "$inspector" "$runner"; then
    printf 'Action 18b-a contains a transfer command.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' \
    "$inspector"; then
    printf 'Action 18b-a inspector contains a persistent write command.\n' >&2
    exit 1
fi
grep -Fq 'marker_classification=sender_build_complete' "$inspector"
grep -Fq 'action18b_backup_count_zero' "$inspector"
grep -Fq 'action18b_stage_count_zero' "$inspector"
# shellcheck disable=SC2016
grep -Fq 'if [[ "$unit" == *.service ]]; then' "$inspector"
grep -Fq 'conditional-validator-explicit-failures-begin' "$runner"
grep -Fq 'conditional-validator-explicit-failures-end' "$runner"

stage="$regression_root/Caddy"
install -d -m 0700 "$stage/scripts" "$stage/tests" "$regression_root/bin"
install -m 0755 "$inspector" "$stage/scripts/"
install -m 0755 "$runner" "$stage/scripts/"
install -m 0755 "$collision_checker" "$stage/tests/"
case_runner="$stage/scripts/${runner##*/}"
sed -i "s|^PATH=/usr/bin:/bin$|PATH=$regression_root/bin:/usr/bin:/bin|" "$case_runner"

# Variables expand only in the intercepted subprocess.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'cat >"$ACTION18BA_CAPTURED_INSPECTOR"' \
    'printf "%s\n" "$*" >"$ACTION18BA_SSH_ARGUMENTS"' \
    'cat "$ACTION18BA_FIXTURE"' \
    'cat "$ACTION18BA_ERROR" >&2' \
    'exit "$ACTION18BA_STATUS"' >"$regression_root/bin/ssh"
chmod 0755 "$regression_root/bin/ssh"

write_fixture() {
    local fixture_path=$1
    local fixture_label

    {
        while IFS= read -r fixture_label; do
            printf 'action_18b_a_assertion_%s=true\n' "$fixture_label"
        done < <(sed -n 's/^record_command \([a-z0-9_]*\).*/\1/p' "$inspector")
        printf '%s\n' \
            action_18b_a_value_marker_classification=sender_build_complete \
            action_18b_a_value_marker_owner=caddy-sync \
            action_18b_a_value_marker_group=caddy-sync \
            action_18b_a_value_marker_mode=440 \
            action_18b_a_value_marker_bytes=0 \
            action_18b_a_value_marker_lines=0 \
            action_18b_a_value_marker_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 \
            action_18b_a_value_action18b_backup_count=0 \
            action_18b_a_value_action18b_stage_count=0 \
            action_18b_a_value_before_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
            action_18b_a_value_after_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
            action_18b_a_assertion_count=59 \
            action_18b_a_failed_assertion_count=0 \
            action_18b_a_first_failure=none \
            action_18b_a_receiver_invoked=false \
            action_18b_a_finalizer_invoked=false \
            action_18b_a_release_mutated=false \
            action_18b_a_authorization_mutated=false \
            action_18b_a_service_mutations=false \
            action_18b_a_synchronization_mutations=false \
            action_18b_a_persistent_mutations=false \
            action_18b_a_remote_complete=true
    } >"$fixture_path"
}

write_fixture "$regression_root/success.fixture"

: >"$regression_root/empty.error"
run_case() {
    local case_name=$1
    local case_fixture=$2
    local case_status=$3
    local expected_status=$4

    actual_status=0
    ACTION18BA_CAPTURED_INSPECTOR="$regression_root/$case_name.inspector" \
        ACTION18BA_SSH_ARGUMENTS="$regression_root/$case_name.arguments" \
        ACTION18BA_FIXTURE="$case_fixture" \
        ACTION18BA_ERROR="$regression_root/empty.error" \
        ACTION18BA_STATUS="$case_status" \
        "$case_runner" >"$regression_root/$case_name.out" \
        2>"$regression_root/$case_name.err" || actual_status=$?
    [[ "$actual_status" -eq "$expected_status" ]]
}

run_case success "$regression_root/success.fixture" 0 0
grep -Fxq action_18b_a_runner_classification=state_verified \
    "$regression_root/success.out"
grep -Fq 'pi@10.1.0.53' "$regression_root/success.arguments"
grep -Fq 'HostKeyAlias=pihole0.local.theama.co' "$regression_root/success.arguments"
cmp -s "$inspector" "$regression_root/success.inspector"

cp "$regression_root/success.fixture" "$regression_root/semantic.fixture"
sed -i 's/assertion_receiver_v2_absent=true/assertion_receiver_v2_absent=false/; s/failed_assertion_count=0/failed_assertion_count=1/; s/first_failure=none/first_failure=receiver_v2_absent/' \
    "$regression_root/semantic.fixture"
run_case semantic "$regression_root/semantic.fixture" 1 1
grep -Fxq action_18b_a_runner_classification=semantic_mismatch \
    "$regression_root/semantic.out"

cp "$regression_root/success.fixture" "$regression_root/duplicate.fixture"
printf 'action_18b_a_assertion_identity_root=true\n' \
    >>"$regression_root/duplicate.fixture"
run_case duplicate "$regression_root/duplicate.fixture" 0 97
grep -Fxq action_18b_a_runner_classification=evidence_failure \
    "$regression_root/duplicate.out"

printf 'action_18b_a_false_negative_valid_success_accepted=true\n'
printf 'action_18b_a_false_negative_semantic_mismatch_preserved=true\n'
printf 'action_18b_a_false_positive_duplicate_rejected=true\n'
printf 'action_18b_a_production_path_network_contact=false\n'
printf 'action_18b_a_node_a_postfailure_regression_complete=true\n'
