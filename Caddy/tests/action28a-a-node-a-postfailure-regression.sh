#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28a_a_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly inspector=$caddy_root/scripts/inspect-node-a-publisher-postfailure-action28a-a.sh
readonly outer=$caddy_root/scripts/run-node-a-publisher-postfailure-action28a-a-outer.sh
fixture_root=$(mktemp -d /tmp/caddy-action28a-a-regression.XXXXXX)
readonly fixture_root
readonly node_root=$fixture_root/node
readonly fake_ssh=$fixture_root/ssh

cleanup() {
    local action28a_a_regression_status=$?

    rm -rf -- "$fixture_root"
    exit "$action28a_a_regression_status"
}
trap cleanup EXIT
record_check() {
    local action28a_a_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28a_a_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28a_a_regression_label" >&2
    return 1
}
prepare_fixture() {
    install -d -m 0755 \
        "$node_root/usr/local/libexec" \
        "$node_root/etc/caddy/releases/release-one"
    install -d -m 0750 \
        "$node_root/var/lib/caddy-sync/outbound/release-one"
    install -d -m 0700 \
        "$node_root/var/backups/caddy-ha" \
        "$node_root/run/caddy-ha"
    printf '{}\n' >"$node_root/etc/caddy/releases/release-one/release-manifest.json"
    printf 'fixture\n' >"$node_root/etc/caddy/releases/release-one/Caddyfile"
    : >"$node_root/etc/caddy/releases/release-one/.complete"
    ln -s /etc/caddy/releases/release-one "$node_root/etc/caddy/current"
    printf '{}\n' >"$node_root/var/lib/caddy-sync/outbound/release-one/release-manifest.json"
    printf 'fixture\n' >"$node_root/var/lib/caddy-sync/outbound/release-one/Caddyfile"
    : >"$node_root/var/lib/caddy-sync/outbound/release-one/.finalize-request"
    printf 'MASTER\n' >"$node_root/run/caddy-ha/vrrp-state"
}
run_inspector_fixture() {
    (
        cd /
        CADDY_ACTION28A_A_TEST_MODE=1 /bin/bash "$inspector" --fixture-root "$node_root"
    )
}
run_case() {
    local action28a_a_regression_mode=$1
    local action28a_a_regression_expected_status=$2
    local action28a_a_regression_expect_acceptance=$3
    local action28a_a_regression_case_root
    local action28a_a_regression_stdout
    local action28a_a_regression_stderr
    local action28a_a_regression_status=0

    action28a_a_regression_case_root=$(mktemp -d "$fixture_root/case.XXXXXX")
    action28a_a_regression_stdout=$action28a_a_regression_case_root/stdout
    action28a_a_regression_stderr=$action28a_a_regression_case_root/stderr
    if CADDY_ACTION28A_A_TEST_MODE=1 \
        CADDY_ACTION28A_A_SSH_BINARY="$fake_ssh" \
        ACTION28A_A_FIXTURE_MODE="$action28a_a_regression_mode" \
        ACTION28A_A_FIXTURE_ROOT="$node_root" \
        ACTION28A_A_FIXTURE_INSPECTOR="$inspector" \
        ACTION28A_A_FIXTURE_LOG="$action28a_a_regression_case_root/ssh.log" \
        /bin/bash "$outer" --test-transport \
        >"$action28a_a_regression_stdout" 2>"$action28a_a_regression_stderr"; then
        action28a_a_regression_status=0
    else
        action28a_a_regression_status=$?
    fi
    [[ "$action28a_a_regression_status" -eq "$action28a_a_regression_expected_status" ]] || return 1
    grep -Fqx 'fixture_target_exact=true' "$action28a_a_regression_case_root/ssh.log" || return 1
    grep -Fqx 'fixture_root_cwd_exact=true' "$action28a_a_regression_case_root/ssh.log" || return 1
    grep -Fqx 'fixture_inspector_exact=true' "$action28a_a_regression_case_root/ssh.log" || return 1
    if [[ "$action28a_a_regression_expect_acceptance" == true ]]; then
        grep -Fqx 'action_28a_a_outer_acceptance=true' "$action28a_a_regression_stdout" || return 1
        grep -Fqx 'action_28a_a_outer_node_a_contacted=false' "$action28a_a_regression_stdout" || return 1
        [[ ! -s "$action28a_a_regression_stderr" ]] || return 1
    else
        ! grep -Fqx 'action_28a_a_outer_acceptance=true' "$action28a_a_regression_stdout" || return 1
    fi
}
run_validation_case() {
    local action28a_a_regression_mode=$1
    local action28a_a_regression_expected_status=$2
    local action28a_a_regression_case_root
    local action28a_a_regression_stdout
    local action28a_a_regression_stderr
    local action28a_a_regression_status=0

    action28a_a_regression_case_root=$(mktemp -d "$fixture_root/validation.XXXXXX")
    action28a_a_regression_stdout=$action28a_a_regression_case_root/stdout
    action28a_a_regression_stderr=$action28a_a_regression_case_root/stderr
    cp "$fixture_transcript" "$action28a_a_regression_stdout"
    : >"$action28a_a_regression_stderr"
    case "$action28a_a_regression_mode" in
        missing_check) sed -i '/^action_28a_a_check_publisher_absent=true$/d' "$action28a_a_regression_stdout" ;;
        false_check) sed -i 's/^action_28a_a_check_publisher_absent=true$/action_28a_a_check_publisher_absent=false/' "$action28a_a_regression_stdout" ;;
        duplicate_check) printf 'action_28a_a_check_publisher_absent=true\n' >>"$action28a_a_regression_stdout" ;;
        missing_child) sed -i '/^action_28a_a_value_outbound_child_0001_b64=/d' "$action28a_a_regression_stdout" ;;
        altered_inventory_hash) sed -i 's/^action_28a_a_value_outbound_inventory_sha256=.*/action_28a_a_value_outbound_inventory_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' "$action28a_a_regression_stdout" ;;
        malformed_child) sed -i 's/^action_28a_a_value_outbound_child_0001_b64=.*/action_28a_a_value_outbound_child_0001_b64=not-base64!/' "$action28a_a_regression_stdout" ;;
        mutation_true) sed -i 's/^action_28a_a_filesystem_mutations=false$/action_28a_a_filesystem_mutations=true/' "$action28a_a_regression_stdout" ;;
        stderr) printf 'bounded fixture stderr\n' >"$action28a_a_regression_stderr" ;;
        nonzero) ;;
        *) return 1 ;;
    esac
    if CADDY_ACTION28A_A_TEST_MODE=1 /bin/bash "$outer" --test-validate \
        "$action28a_a_regression_stdout" "$action28a_a_regression_stderr" \
        "$(if [[ "$action28a_a_regression_mode" == nonzero ]]; then printf 23; else printf 0; fi)" \
        >/dev/null 2>&1; then
        action28a_a_regression_status=0
    else
        action28a_a_regression_status=$?
    fi
    [[ "$action28a_a_regression_status" -eq "$action28a_a_regression_expected_status" ]]
}

prepare_fixture
cat >"$fake_ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly fixture_mode=${ACTION28A_A_FIXTURE_MODE:?}
readonly fixture_root=${ACTION28A_A_FIXTURE_ROOT:?}
readonly fixture_inspector=${ACTION28A_A_FIXTURE_INSPECTOR:?}
readonly fixture_log=${ACTION28A_A_FIXTURE_LOG:?}
received_inspector=$(mktemp /tmp/caddy-action28a-a-received.XXXXXX)
transcript=$(mktemp /tmp/caddy-action28a-a-transcript.XXXXXX)
readonly received_inspector transcript
trap 'rm -f -- "$received_inspector" "$transcript"' EXIT
cat >"$received_inspector"
printf 'fixture_target_exact=%s\n' \
    "$(if [[ " $* " == *' pi@10.1.0.53 '* && " $* " == *' HostKeyAlias=pihole0.local.theama.co '* ]]; then printf true; else printf false; fi)" \
    >>"$fixture_log"
printf 'fixture_root_cwd_exact=%s\n' \
    "$(if [[ " $* " == *'cd / && sudo -n /bin/bash -s --'* ]]; then printf true; else printf false; fi)" \
    >>"$fixture_log"
printf 'fixture_inspector_exact=%s\n' \
    "$(if [[ "$(sha256sum "$received_inspector" | awk '{ print $1 }')" == "$(sha256sum "$fixture_inspector" | awk '{ print $1 }')" ]]; then printf true; else printf false; fi)" \
    >>"$fixture_log"
(
    cd /
    CADDY_ACTION28A_A_TEST_MODE=1 /bin/bash "$fixture_inspector" --fixture-root "$fixture_root"
) >"$transcript"
case "$fixture_mode" in
    success) cat "$transcript" ;;
    missing_check) sed '/^action_28a_a_check_publisher_absent=true$/d' "$transcript" ;;
    false_check) sed 's/^action_28a_a_check_publisher_absent=true$/action_28a_a_check_publisher_absent=false/' "$transcript" ;;
    duplicate_check) cat "$transcript"; printf 'action_28a_a_check_publisher_absent=true\n' ;;
    missing_child) sed '/^action_28a_a_value_outbound_child_0001_b64=/d' "$transcript" ;;
    altered_inventory_hash) sed 's/^action_28a_a_value_outbound_inventory_sha256=.*/action_28a_a_value_outbound_inventory_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' "$transcript" ;;
    malformed_child) sed 's/^action_28a_a_value_outbound_child_0001_b64=.*/action_28a_a_value_outbound_child_0001_b64=not-base64!/' "$transcript" ;;
    mutation_true) sed 's/^action_28a_a_filesystem_mutations=false$/action_28a_a_filesystem_mutations=true/' "$transcript" ;;
    stderr) cat "$transcript"; printf 'bounded fixture stderr\n' >&2 ;;
    nonzero) cat "$transcript"; exit 23 ;;
    *) exit 98 ;;
esac
FAKE_SSH
chmod 0700 "$fake_ssh"

fixture_transcript=$fixture_root/fixture.transcript
readonly fixture_transcript
run_inspector_fixture >"$fixture_transcript"
child_record=$(sed -n 's/^action_28a_a_value_outbound_child_0001_b64=//p' "$fixture_transcript")
readonly child_record
record_check inspector_syntax /bin/bash -n "$inspector"
record_check outer_syntax /bin/bash -n "$outer"
record_check inspector_self_test /bin/bash "$inspector" --self-test
record_check fixture_acceptance grep -Fqx 'action_28a_a_acceptance=true' "$fixture_transcript"
record_check fixture_child_count grep -Fqx 'action_28a_a_value_outbound_child_count=1' "$fixture_transcript"
record_check fixture_child_record_once test \
    "$(grep -Ec '^action_28a_a_value_outbound_child_[0-9][0-9][0-9][0-9]_b64=' "$fixture_transcript" || true)" -eq 1
record_check fixture_child_record_decodes test \
    "$(printf '%s' "$child_record" | base64 -d | awk -F '|' '{ print NF }')" -eq 8
record_check actions_not_invoked test \
    "$(grep -Ec 'run-node-a-to-node-b-protocol-v2-action28-outer|run-node-a-protocol-v2-publisher-action28a-outer|install-node-a-protocol-v2-publisher-action28a' "$inspector" || true)" -eq 0
record_check success_case run_case success 0 true
record_check missing_check_rejected run_validation_case missing_check 97
record_check false_check_rejected run_validation_case false_check 97
record_check duplicate_check_rejected run_validation_case duplicate_check 97
record_check missing_child_rejected run_validation_case missing_child 97
record_check altered_inventory_hash_rejected run_validation_case altered_inventory_hash 97
record_check malformed_child_rejected run_validation_case malformed_child 97
record_check mutation_true_rejected run_validation_case mutation_true 97
record_check stderr_rejected run_validation_case stderr 97
record_check nonzero_rejected run_validation_case nonzero 23

printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_28_rerun=false\n' "$prefix"
printf '%s_action_28a_rerun=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
