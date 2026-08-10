#!/usr/bin/env bash

# shellcheck disable=SC2016
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28a_regression
readonly publisher_sha256=e4a48f12a7324a885684a57070269a2d074d056c65d9e767db901408e0e86669
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly publisher=$caddy_root/scripts/publish-release-v2.sh
readonly driver=$caddy_root/scripts/install-node-a-protocol-v2-publisher-action28a.sh
readonly outer=$caddy_root/scripts/run-node-a-protocol-v2-publisher-action28a-outer.sh
readonly collision_policy=$test_directory/check-shell-readonly-local-collisions-v2.sh
fixture_root=$(mktemp -d /tmp/caddy-action28a-regression.XXXXXX)
readonly fixture_root
readonly fake_ssh=$fixture_root/ssh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
cleanup() {
    local action28a_regression_status=$?

    rm -rf -- "$fixture_root"
    exit "$action28a_regression_status"
}
trap cleanup EXIT
record_check() {
    local action28a_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28a_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28a_regression_label" >&2
    return 1
}
prepare_fixture() {
    local action28a_regression_root=$1
    local action28a_regression_stage=$2

    install -d -m 0755 \
        "$action28a_regression_root/usr/local/libexec" \
        "$action28a_regression_root/etc/caddy/releases/current-release"
    install -d -m 0700 \
        "$action28a_regression_root/var/backups/caddy-ha" \
        "$action28a_regression_root/run/caddy-ha" \
        "$action28a_regression_stage"
    install -d -m 0750 \
        "$action28a_regression_root/var/lib/caddy-sync/outbound"
    printf '{}\n' >"$action28a_regression_root/etc/caddy/releases/current-release/release-manifest.json"
    : >"$action28a_regression_root/etc/caddy/releases/current-release/.complete"
    ln -s /etc/caddy/releases/current-release \
        "$action28a_regression_root/etc/caddy/current"
    printf 'MASTER\n' >"$action28a_regression_root/run/caddy-ha/vrrp-state"
    install -m 0700 "$publisher" "$action28a_regression_stage/publish-release-v2.sh"
}
run_fixture_transaction() {
    local action28a_regression_root=$1
    local action28a_regression_stage=$2
    local action28a_regression_stdout=$3
    local action28a_regression_stderr=$4
    local action28a_regression_fail_after_install=$5
    local action28a_regression_status=0

    if (
        cd /
        CADDY_ACTION28A_TEST_MODE=1 \
            CADDY_ACTION28A_FAIL_AFTER_INSTALL="$action28a_regression_fail_after_install" \
            /bin/bash "$driver" --fixture-transaction \
            "$action28a_regression_root" "$action28a_regression_stage"
    ) >"$action28a_regression_stdout" 2>"$action28a_regression_stderr"; then
        action28a_regression_status=0
    else
        action28a_regression_status=$?
    fi
    printf '%s\n' "$action28a_regression_status"
}
run_transport_case() {
    local action28a_regression_mode=$1
    local action28a_regression_expected_status=$2
    local action28a_regression_expected_acceptance=$3
    local action28a_regression_case_root
    local action28a_regression_stdout
    local action28a_regression_stderr
    local action28a_regression_status=0

    action28a_regression_case_root=$(mktemp -d "$fixture_root/transport.XXXXXX")
    action28a_regression_stdout=$action28a_regression_case_root/stdout
    action28a_regression_stderr=$action28a_regression_case_root/stderr
    if CADDY_ACTION28A_TEST_MODE=1 \
        CADDY_ACTION28A_SSH_BINARY="$fake_ssh" \
        ACTION28A_FIXTURE_MODE="$action28a_regression_mode" \
        ACTION28A_FIXTURE_DRIVER="$driver" \
        ACTION28A_FIXTURE_PUBLISHER="$publisher" \
        ACTION28A_FIXTURE_LOG="$action28a_regression_case_root/ssh.log" \
        /bin/bash "$outer" --test-transport \
        >"$action28a_regression_stdout" 2>"$action28a_regression_stderr"; then
        action28a_regression_status=0
    else
        action28a_regression_status=$?
    fi
    [[ "$action28a_regression_status" -eq "$action28a_regression_expected_status" ]] || {
        printf '%s_transport_case=%s\n' "$prefix" "$action28a_regression_mode" >&2
        printf '%s_transport_status=%s\n' "$prefix" "$action28a_regression_status" >&2
        sed -n '1,220p' "$action28a_regression_stdout" >&2
        sed -n '1,220p' "$action28a_regression_stderr" >&2
        return 1
    }
    grep -Fqx 'fixture_target_exact=true' "$action28a_regression_case_root/ssh.log" || return 1
    grep -Fqx 'fixture_root_cwd_exact=true' "$action28a_regression_case_root/ssh.log" || return 1
    grep -Fqx 'fixture_publisher_exact=true' "$action28a_regression_case_root/ssh.log" || return 1
    grep -Fqx 'fixture_driver_exact=true' "$action28a_regression_case_root/ssh.log" || return 1
    if [[ "$action28a_regression_expected_acceptance" == true ]]; then
        grep -Fqx 'action_28a_outer_acceptance=true' "$action28a_regression_stdout" || return 1
        [[ ! -s "$action28a_regression_stderr" ]] || return 1
    else
        ! grep -Fqx 'action_28a_outer_acceptance=true' "$action28a_regression_stdout" || return 1
    fi
}
run_validation_case() {
    local action28a_regression_mode=$1
    local action28a_regression_expected_status=$2
    local action28a_regression_case_root
    local action28a_regression_contract
    local action28a_regression_stdout
    local action28a_regression_stderr
    local action28a_regression_status=0

    action28a_regression_case_root=$(mktemp -d "$fixture_root/validation.XXXXXX")
    action28a_regression_contract=$action28a_regression_case_root/contract
    action28a_regression_stdout=$action28a_regression_case_root/stdout
    action28a_regression_stderr=$action28a_regression_case_root/stderr
    /bin/bash "$driver" --contract-transcript >"$action28a_regression_contract"
    : >"$action28a_regression_stderr"
    case "$action28a_regression_mode" in
        missing_label)
            sed '/^action_28a_check_uid_root=true$/d' \
                "$action28a_regression_contract" >"$action28a_regression_stdout"
            ;;
        duplicate_label)
            cp "$action28a_regression_contract" "$action28a_regression_stdout"
            printf 'action_28a_check_uid_root=true\n' >>"$action28a_regression_stdout"
            ;;
        false_label)
            sed 's/^action_28a_check_uid_root=true$/action_28a_check_uid_root=false/' \
                "$action28a_regression_contract" >"$action28a_regression_stdout"
            ;;
        wrong_hash)
            sed 's/^action_28a_value_publisher_sha256=.*/action_28a_value_publisher_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' \
                "$action28a_regression_contract" >"$action28a_regression_stdout"
            ;;
        stderr)
            cp "$action28a_regression_contract" "$action28a_regression_stdout"
            printf 'bounded fixture stderr\n' >"$action28a_regression_stderr"
            ;;
        rollback)
            printf 'action_28a_mutation_started=true\n' >"$action28a_regression_stdout"
            printf '%s\n' \
                'action_28a_check_post_install_boundary=false' \
                'action_28a_rollback_started=true' \
                'action_28a_rollback_complete=true' \
                >"$action28a_regression_stderr"
            ;;
        *) return 1 ;;
    esac
    if CADDY_ACTION28A_TEST_MODE=1 /bin/bash "$outer" --test-validate \
        "$action28a_regression_stdout" "$action28a_regression_stderr" \
        "$(if [[ "$action28a_regression_mode" == rollback ]]; then printf 1; else printf 0; fi)" \
        >/dev/null 2>&1; then
        action28a_regression_status=0
    else
        action28a_regression_status=$?
    fi
    [[ "$action28a_regression_status" -eq "$action28a_regression_expected_status" ]]
}

cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly fixture_mode=${ACTION28A_FIXTURE_MODE:?}
readonly fixture_driver=${ACTION28A_FIXTURE_DRIVER:?}
readonly fixture_publisher=${ACTION28A_FIXTURE_PUBLISHER:?}
readonly fixture_log=${ACTION28A_FIXTURE_LOG:?}
received_bundle=$(mktemp /tmp/caddy-action28a-bundle.XXXXXX)
received_driver=$(mktemp /tmp/caddy-action28a-driver.XXXXXX)
received_publisher=$(mktemp /tmp/caddy-action28a-publisher.XXXXXX)
contract=$(mktemp /tmp/caddy-action28a-contract.XXXXXX)
readonly received_bundle received_driver received_publisher contract
trap 'rm -f -- "$received_bundle" "$received_driver" "$received_publisher" "$contract"' EXIT
cat >"$received_bundle"
printf 'fixture_target_exact=%s\n' \
    "$(if [[ " $* " == *' pi@10.1.0.53 '* &&
        " $* " == *' HostKeyAlias=pihole0.local.theama.co '* ]]; then printf true; else printf false; fi)" \
    >>"$fixture_log"
printf 'fixture_root_cwd_exact=%s\n' \
    "$(if [[ " $* " == *'cd / && sudo -n /bin/bash -s --'* ]]; then printf true; else printf false; fi)" \
    >>"$fixture_log"
awk '/<<.ACTION28A_PUBLISHER./ { capture = 1; next }
    capture && /^ACTION28A_PUBLISHER$/ { exit }
    capture { print }' "$received_bundle" | base64 -d >"$received_publisher"
awk '/<<.ACTION28A_DRIVER./ { capture = 1; next }
    capture && /^ACTION28A_DRIVER$/ { exit }
    capture { print }' "$received_bundle" | base64 -d >"$received_driver"
printf 'fixture_publisher_exact=%s\n' \
    "$(if cmp -s "$received_publisher" "$fixture_publisher"; then printf true; else printf false; fi)" \
    >>"$fixture_log"
printf 'fixture_driver_exact=%s\n' \
    "$(if cmp -s "$received_driver" "$fixture_driver"; then printf true; else printf false; fi)" \
    >>"$fixture_log"
/bin/bash "$fixture_driver" --contract-transcript >"$contract"
case "$fixture_mode" in
    success) cat "$contract" ;;
    missing_label) sed '/^action_28a_check_uid_root=true$/d' "$contract" ;;
    duplicate_label) cat "$contract"; printf 'action_28a_check_uid_root=true\n' ;;
    false_label) sed 's/^action_28a_check_uid_root=true$/action_28a_check_uid_root=false/' "$contract" ;;
    wrong_hash) sed 's/^action_28a_value_publisher_sha256=.*/action_28a_value_publisher_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' "$contract" ;;
    stderr) cat "$contract"; printf 'bounded fixture stderr\n' >&2 ;;
    rollback)
        printf 'action_28a_mutation_started=true\n'
        printf 'action_28a_check_post_install_boundary=false\n' >&2
        printf 'action_28a_rollback_started=true\n' >&2
        printf 'action_28a_rollback_complete=true\n' >&2
        exit 1
        ;;
    *) exit 98 ;;
esac
FAKE_SSH
chmod 0700 "$fake_ssh"

record_check syntax /bin/bash -n "$driver" "$outer" "$0"
record_check collision_policy /bin/bash "$collision_policy" "$driver" "$outer" "$0"
record_check driver_self_test /bin/bash "$driver" --self-test
record_check publisher_hash_exact test "$(file_hash "$publisher")" = "$publisher_sha256"
record_check node_a_hostname_exact grep -Fq 'readonly expected_hostname=j1-svpihole0' "$driver"
record_check node_a_target_exact grep -Fq 'readonly expected_target=pi@10.1.0.53' "$outer"
record_check node_a_host_alias_exact grep -Fq \
    'readonly expected_host_alias=pihole0.local.theama.co' "$outer"
record_check action28_rerun_prohibited grep -Fq 'action_28_rerun=false' "$driver"
record_check publisher_invocation_prohibited grep -Fq 'publisher_invoked=false' "$driver"
record_check release_mutation_prohibited grep -Fq 'release_mutated=false' "$driver"
record_check service_mutation_prohibited grep -Fq 'service_mutations=false' "$driver"
record_check direct_run_stage grep -Fq \
    'stage=$(mktemp -d /run/caddy-action28a-node-a-publisher.XXXXXX)' "$outer"
record_check cleanup_before_decode test \
    "$(grep -n 'trap cleanup_stage EXIT' "$outer" | cut -d: -f1)" -lt \
    "$(grep -n 'base64 -d' "$outer" | head -n 1 | cut -d: -f1)"
record_check staged_bash_explicit grep -Fq \
    '/bin/bash "$stage/payload/install-node-a-protocol-v2-publisher-action28a.sh"' "$outer"
record_check administrative_identity_unforced test \
    "$(grep -Fxc '    -o IdentitiesOnly=yes' "$outer" || true)" -eq 0

success_root=$fixture_root/success-root
success_stage=$fixture_root/success-stage
readonly success_root success_stage
prepare_fixture "$success_root" "$success_stage"
success_status=$(run_fixture_transaction "$success_root" "$success_stage" \
    "$fixture_root/success.out" "$fixture_root/success.err" 0)
record_check fixture_success_status test "$success_status" -eq 0
record_check fixture_success_stderr_empty test ! -s "$fixture_root/success.err"
record_check fixture_publisher_installed test -f \
    "$success_root/usr/local/libexec/publish-release-v2.sh"
record_check fixture_publisher_hash test \
    "$(file_hash "$success_root/usr/local/libexec/publish-release-v2.sh")" = "$publisher_sha256"
record_check fixture_backup_retained test -f \
    "$success_root/var/backups/caddy-ha/action28a-node-a-publisher/manifest"
record_check fixture_acceptance grep -Fqx 'action_28a_acceptance=true' \
    "$fixture_root/success.out"

rollback_root=$fixture_root/rollback-root
rollback_stage=$fixture_root/rollback-stage
readonly rollback_root rollback_stage
prepare_fixture "$rollback_root" "$rollback_stage"
rollback_status=$(run_fixture_transaction "$rollback_root" "$rollback_stage" \
    "$fixture_root/rollback.out" "$fixture_root/rollback.err" 1)
record_check fixture_rollback_status test "$rollback_status" -eq 1
record_check fixture_rollback_started grep -Fqx 'action_28a_rollback_started=true' \
    "$fixture_root/rollback.err"
record_check fixture_rollback_complete grep -Fqx 'action_28a_rollback_complete=true' \
    "$fixture_root/rollback.err"
record_check fixture_rollback_publisher_absent test ! -e \
    "$rollback_root/usr/local/libexec/publish-release-v2.sh"
record_check fixture_rollback_backup_absent test ! -e \
    "$rollback_root/var/backups/caddy-ha/action28a-node-a-publisher"

record_check transport_success run_transport_case success 0 true
record_check validation_missing_label_rejected run_validation_case missing_label 97
record_check validation_duplicate_label_rejected run_validation_case duplicate_label 97
record_check validation_false_label_rejected run_validation_case false_label 97
record_check validation_wrong_hash_rejected run_validation_case wrong_hash 97
record_check validation_stderr_rejected run_validation_case stderr 97
record_check validation_rollback_preserved run_validation_case rollback 1

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_publisher_invoked=false\n' "$prefix"
printf '%s_release_mutated=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
