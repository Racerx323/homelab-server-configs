#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20l_regression
readonly inspector_sha256=4e3d6139778108fd5aed4cfbcd5175322e0c590404cc106e3b0dac8c66369875
readonly outer_sha256=5369e6bff8171344c75e8d31e910748b99c0fab70320e865c9437440ad5b44a7
readonly expected_check_count=49
readonly expected_remote_line_count=86
readonly fixture_state_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly inspector=$caddy_root/scripts/inspect-keepalived-dbus-readiness-action20l.sh
readonly outer=$caddy_root/scripts/run-dual-node-keepalived-dbus-readiness-action20l-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
line_count() { awk 'END { print NR }' "$1"; }
record_gate() {
    local action20l_regression_gate_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_gate_%s=true\n' "$prefix" "$action20l_regression_gate_label"
        return 0
    fi
    printf '%s_gate_%s=false\n' "$prefix" "$action20l_regression_gate_label" >&2
    return 1
}
write_capture() {
    local action20l_regression_capture_name=$1
    local action20l_regression_capture_path=$2

    printf '%s\n' \
        "action_20l_capture_${action20l_regression_capture_name}_bytes=$(wc -c <"$action20l_regression_capture_path")" \
        "action_20l_capture_${action20l_regression_capture_name}_lines=$(line_count "$action20l_regression_capture_path")" \
        "action_20l_capture_${action20l_regression_capture_name}_sha256=$(file_hash "$action20l_regression_capture_path")" \
        "action_20l_capture_${action20l_regression_capture_name}_classification=bounded_safe" \
        "action_20l_capture_${action20l_regression_capture_name}_base64=$(base64 -w 0 "$action20l_regression_capture_path")"
}
write_valid_transcript() {
    local action20l_regression_node=$1
    local action20l_regression_output=$2
    local action20l_regression_fixture_root=$3
    local action20l_regression_main_hash
    local action20l_regression_fragment_hash
    local action20l_regression_label

    case "$action20l_regression_node" in
        node-a)
            action20l_regression_main_hash=357eb09c628fa3b78efcaacf53278ab09a6574b991820632ee3ec2614265d8e2
            action20l_regression_fragment_hash=8117510587c79fa597ebd5e48da6ab4be8d8dfef6740d57b9b327037b70830be
            ;;
        node-b)
            action20l_regression_main_hash=8b260315628888c937c6f7eaf21f63e73eb52cfd9cd6e9c0d9d90fa9cf9fbd3f
            action20l_regression_fragment_hash=0dd8ec0a5410bcd3c41db0d3fed74cf8bd75978f09b01a797468dd6266b4b518
            ;;
        *) return 64 ;;
    esac
    {
        while IFS= read -r action20l_regression_label; do
            printf 'action_20l_check_%s=true\n' "$action20l_regression_label"
        done < <(/bin/bash "$inspector" --expected-checks)
        write_capture version_stdout "$action20l_regression_fixture_root/version.stdout"
        write_capture version_stderr "$action20l_regression_fixture_root/version.stderr"
        write_capture bus_stdout "$action20l_regression_fixture_root/bus.stdout"
        write_capture bus_stderr "$action20l_regression_fixture_root/bus.stderr"
        printf '%s\n' \
            "action_20l_value_node=$action20l_regression_node" \
            "action_20l_value_expected_check_count=$expected_check_count" \
            "action_20l_value_main_sha256=$action20l_regression_main_hash" \
            "action_20l_value_fragment_sha256=$action20l_regression_fragment_hash" \
            "action_20l_value_before_state_sha256=$fixture_state_sha256" \
            "action_20l_value_after_state_sha256=$fixture_state_sha256" \
            "action_20l_check_count=$expected_check_count" \
            'action_20l_failed_check_count=0' \
            'action_20l_first_failure=none' \
            'action_20l_keepalived_dbus_registration_checked=false' \
            'action_20l_config_installation=false' \
            'action_20l_keepalived_reload=false' \
            'action_20l_service_mutations=false' \
            'action_20l_vrrp_mutations=false' \
            'action_20l_vip_mutations=false' \
            'action_20l_persistent_mutations=false' \
            'action_20l_remote_complete=true'
    } >"$action20l_regression_output"
}
run_intercepted_case() {
    local action20l_regression_case_root=$1
    local action20l_regression_node_a_transcript=$2
    local action20l_regression_node_b_transcript=$3
    local action20l_regression_remote_status=$4
    local action20l_regression_expected_status=$5
    local action20l_regression_stderr_content=${6:-}
    local action20l_regression_fake_ssh=$action20l_regression_case_root/fake-ssh
    local action20l_regression_observed_status=0

    install -d -m 0700 "$action20l_regression_case_root" || return 1
    # The generated fake transport expands these variables at runtime.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'cat >"${ACTION20L_STDIN_CAPTURE:?}"' \
        'printf "%s\n" "$*" >>"${ACTION20L_ARGS_CAPTURE:?}"' \
        'case "$*" in' \
        '    *"--node node-b"*) cat "${ACTION20L_NODE_B_TRANSCRIPT:?}" ;;' \
        '    *"--node node-a"*) cat "${ACTION20L_NODE_A_TRANSCRIPT:?}" ;;' \
        '    *) exit 64 ;;' \
        'esac' \
        'if [[ -n "${ACTION20L_STDERR_CONTENT:-}" ]]; then' \
        '    printf "%s\n" "$ACTION20L_STDERR_CONTENT" >&2' \
        'fi' \
        'exit "${ACTION20L_REMOTE_STATUS:?}"' >"$action20l_regression_fake_ssh" || return 1
    chmod 0700 "$action20l_regression_fake_ssh" || return 1
    (
        cd "$repository_root" || exit 1
        CADDY_ACTION20L_TEST_MODE=1 \
            CADDY_ACTION20L_SSH_BINARY="$action20l_regression_fake_ssh" \
            ACTION20L_STDIN_CAPTURE="$action20l_regression_case_root/stdin" \
            ACTION20L_ARGS_CAPTURE="$action20l_regression_case_root/args" \
            ACTION20L_NODE_A_TRANSCRIPT="$action20l_regression_node_a_transcript" \
            ACTION20L_NODE_B_TRANSCRIPT="$action20l_regression_node_b_transcript" \
            ACTION20L_STDERR_CONTENT="$action20l_regression_stderr_content" \
            ACTION20L_REMOTE_STATUS="$action20l_regression_remote_status" \
            /bin/bash "$outer" --test-transport
    ) >"$action20l_regression_case_root/stdout" \
        2>"$action20l_regression_case_root/stderr" ||
        action20l_regression_observed_status=$?
    if [[ "$action20l_regression_observed_status" -ne "$action20l_regression_expected_status" ]]; then
        printf 'intercepted_status expected=%s observed=%s\n' \
            "$action20l_regression_expected_status" "$action20l_regression_observed_status" >&2
        printf '%s\n' 'intercepted_stdout_begin' >&2
        sed -n '1,240p' "$action20l_regression_case_root/stdout" >&2
        printf '%s\n' 'intercepted_stdout_end' 'intercepted_stderr_begin' >&2
        sed -n '1,240p' "$action20l_regression_case_root/stderr" >&2
        printf '%s\n' 'intercepted_stderr_end' >&2
        return 1
    fi
    if [[ "$(file_hash "$action20l_regression_case_root/stdin")" != "$inspector_sha256" ]]; then
        printf 'intercepted_stdin_hash=false\n' >&2
        return 1
    fi
    if [[ "$action20l_regression_expected_status" -eq 0 ]]; then
        [[ "$(wc -l <"$action20l_regression_case_root/args")" -eq 2 ]] || return 1
        sed -n '1p' "$action20l_regression_case_root/args" |
            grep -Fq -- 'pi@10.1.0.54 cd / && sudo -n /bin/bash -s -- --node node-b' || return 1
        sed -n '2p' "$action20l_regression_case_root/args" |
            grep -Fq -- 'pi@10.1.0.53 cd / && sudo -n /bin/bash -s -- --node node-a' || return 1
    fi
}
production_label_alignment() {
    local action20l_regression_root=$1

    /bin/bash "$inspector" --expected-checks >"$action20l_regression_root/expected" || return 1
    awk '$1 == "record_check" { print $2 }' "$inspector" \
        >"$action20l_regression_root/static" || return 1
    [[ "$(wc -l <"$action20l_regression_root/expected")" -eq "$expected_check_count" ]] || return 1
    [[ "$(wc -l <"$action20l_regression_root/static")" -eq "$expected_check_count" ]] || return 1
    diff -u "$action20l_regression_root/expected" \
        "$action20l_regression_root/static" >/dev/null
}

regression_root=$(mktemp -d /tmp/caddy-action20l-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT
install -m 0600 /dev/null "$regression_root/version.stderr"
install -m 0600 /dev/null "$regression_root/bus.stderr"
printf '%s\n' \
    'Keepalived v2.2.7 (01/16,2022)' \
    'Config options: NFTABLES LVS VRRP DBUS' >"$regression_root/version.stdout"
printf '%s\n' \
    'org.freedesktop.DBus 1 dbus root :1.0 system - -' >"$regression_root/bus.stdout"
readonly valid_node_a=$regression_root/node-a.valid
readonly valid_node_b=$regression_root/node-b.valid
write_valid_transcript node-a "$valid_node_a" "$regression_root"
write_valid_transcript node-b "$valid_node_b" "$regression_root"

record_gate inspector_hash_exact test "$(file_hash "$inspector")" = "$inspector_sha256"
record_gate outer_hash_exact test "$(file_hash "$outer")" = "$outer_sha256"
record_gate syntax /bin/bash -n "$0" "$inspector" "$outer"
record_gate inspector_self_test /bin/bash "$inspector" --self-test
record_gate production_label_alignment production_label_alignment "$regression_root"
record_gate valid_node_a_line_count test "$(line_count "$valid_node_a")" -eq "$expected_remote_line_count"
record_gate valid_node_b_line_count test "$(line_count "$valid_node_b")" -eq "$expected_remote_line_count"
# The child Bash expands its positional parameters.
# shellcheck disable=SC2016
record_gate read_only_source_contract bash -c \
    '! grep -Eq "systemctl[[:space:]]+(start|stop|restart|reload)|ip[[:space:]]+(-[46][[:space:]]+)?(address|addr)[[:space:]]+(add|delete|del)" "$1" "$2"' \
    _ "$inspector" "$outer"
record_gate valid_production_path run_intercepted_case \
    "$regression_root/valid" "$valid_node_a" "$valid_node_b" 0 0

cp -- "$valid_node_b" "$regression_root/node-b.false"
sed -i 's/action_20l_check_keepalived_dbus_build_feature_present=true/action_20l_check_keepalived_dbus_build_feature_present=false/' \
    "$regression_root/node-b.false"
record_gate false_assertion_rejected run_intercepted_case \
    "$regression_root/false" "$valid_node_a" "$regression_root/node-b.false" 0 97

grep -Fv 'action_20l_check_keepalived_dbus_build_feature_present=true' \
    "$valid_node_b" >"$regression_root/node-b.missing"
record_gate missing_assertion_rejected run_intercepted_case \
    "$regression_root/missing" "$valid_node_a" "$regression_root/node-b.missing" 0 97

cp -- "$valid_node_b" "$regression_root/node-b.duplicate"
printf '%s\n' 'action_20l_check_keepalived_dbus_build_feature_present=true' \
    >>"$regression_root/node-b.duplicate"
record_gate duplicate_assertion_rejected run_intercepted_case \
    "$regression_root/duplicate" "$valid_node_a" "$regression_root/node-b.duplicate" 0 97

awk 'NR == 1 { first=$0; next } NR == 2 { print; print first; next } { print }' \
    "$valid_node_b" >"$regression_root/node-b.reordered"
record_gate reordered_assertion_rejected run_intercepted_case \
    "$regression_root/reordered" "$valid_node_a" "$regression_root/node-b.reordered" 0 97

printf '%s\n' 'Keepalived v2.2.7' 'Config options: NFTABLES LVS VRRP' \
    >"$regression_root/version.stdout"
write_valid_transcript node-b "$regression_root/node-b.no-dbus" "$regression_root"
record_gate missing_dbus_evidence_rejected run_intercepted_case \
    "$regression_root/no-dbus" "$valid_node_a" "$regression_root/node-b.no-dbus" 0 97

printf '%s\n' 'Keepalived v2.2.7' 'Config options: NFTABLES LVS VRRP DBUS' \
    >"$regression_root/version.stdout"
printf '%s\n' 'org.example.Other 2 other root :1.1 system - -' \
    >"$regression_root/bus.stdout"
write_valid_transcript node-b "$regression_root/node-b.no-system-bus" "$regression_root"
record_gate missing_system_bus_name_rejected run_intercepted_case \
    "$regression_root/no-system-bus" "$valid_node_a" "$regression_root/node-b.no-system-bus" 0 97

record_gate stderr_rejected run_intercepted_case \
    "$regression_root/stderr" "$valid_node_a" "$valid_node_b" 0 97 bounded-safe-error
record_gate nonzero_status_preserved run_intercepted_case \
    "$regression_root/status" "$valid_node_a" "$valid_node_b" 7 7

printf '%s_false_negative_valid_production_transcript_accepted=true\n' "$prefix"
printf '%s_false_positive_false_assertion_rejected=true\n' "$prefix"
printf '%s_false_positive_missing_assertion_rejected=true\n' "$prefix"
printf '%s_false_positive_duplicate_assertion_rejected=true\n' "$prefix"
printf '%s_false_positive_reordered_assertion_rejected=true\n' "$prefix"
printf '%s_false_positive_missing_dbus_evidence_rejected=true\n' "$prefix"
printf '%s_false_positive_missing_system_bus_name_rejected=true\n' "$prefix"
printf '%s_false_positive_stderr_rejected=true\n' "$prefix"
printf '%s_false_negative_nonzero_status_preserved=true\n' "$prefix"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_action_executed=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
