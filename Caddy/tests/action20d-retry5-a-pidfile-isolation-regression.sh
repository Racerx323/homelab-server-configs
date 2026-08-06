#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_20d_retry5_a_regression
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly outer=$caddy_root/scripts/run-node-a-keepalived-pidfile-isolation-action20d-retry5-a-outer.sh
readonly diagnostic=$caddy_root/scripts/diagnose-node-a-keepalived-pidfile-isolation-action20d-retry5-a.sh

check_regression() {
    local regression_label=$1

    shift
    if "$@"; then
        printf '%s_check_%s=true\n' "$prefix" "$regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$regression_label" >&2
    return 1
}
write_fixture() {
    local fixture_classification=$1
    local fixture_status=$2
    local assertion_name
    local snapshot_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    while IFS= read -r assertion_name; do
        printf 'action_20d_retry5_a_probe_assertion_%s=true\n' "$assertion_name"
    done < <(/bin/bash "$diagnostic" --expected-assertions)
    printf '%s\n' \
        "action_20d_retry5_a_probe_value_probe_status=$fixture_status" \
        'action_20d_retry5_a_probe_value_probe_duration_ms=511' \
        "action_20d_retry5_a_probe_value_probe_classification=$fixture_classification" \
        "action_20d_retry5_a_probe_value_before_snapshot_sha256=$snapshot_hash" \
        "action_20d_retry5_a_probe_value_after_snapshot_sha256=$snapshot_hash" \
        'action_20d_retry5_a_probe_value_assertion_count=37' \
        'action_20d_retry5_a_probe_value_failure_count=0' \
        'action_20d_retry5_a_probe_value_first_failure=none' \
        'action_20d_retry5_a_probe_notification_invoked=false' \
        'action_20d_retry5_a_probe_service_mutations=false' \
        'action_20d_retry5_a_probe_keepalived_mutations=false' \
        'action_20d_retry5_a_probe_vrrp_mutations=false' \
        'action_20d_retry5_a_probe_vip_mutations=false' \
        'action_20d_retry5_a_probe_persistent_mutations=false' \
        'action_20d_retry5_a_probe_cleanup_complete=true' \
        'action_20d_retry5_a_probe_diagnostic_complete=true'
}
make_fake_ssh() {
    local fake_path=$1
    local fixture_path=$2
    local fake_mode=$3

    cp "$fixture_path" "$fake_path.fixture"
    # Dollar-prefixed text is expanded by the generated fake SSH process.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        'captured=$(mktemp)' \
        'trap '\''rm -f -- "$captured"'\'' EXIT' \
        'cat >"$captured"' \
        '[[ "$*" = *"HostKeyAlias=pihole0.local.theama.co"* ]]' \
        '[[ "$*" = *"pi@10.1.0.53"* ]]' \
        '[[ "$*" = *"cd / && sudo -n /bin/bash -s -- node-a"* ]]' \
        'grep -Fq -- '\''--pid="$diagnostic_root/parent.pid"'\'' "$captured"' \
        'grep -Fq -- '\''--vrrp_pid="$diagnostic_root/vrrp.pid"'\'' "$captured"' \
        'grep -Fq -- '\''--checkers_pid="$diagnostic_root/checkers.pid"'\'' "$captured"' \
        "case '$fake_mode' in" \
        '  valid) cat "${0}.fixture" ;;' \
        '  missing) sed '\''/assertion_candidate_hash_exact=true/d'\'' "${0}.fixture" ;;' \
        '  duplicate) cat "${0}.fixture"; grep -F '\''assertion_candidate_hash_exact=true'\'' "${0}.fixture" ;;' \
        '  mismatch) sed '\''s/value_probe_classification=.*/value_probe_classification=pidfile_isolation_timeout_term/'\'' "${0}.fixture" ;;' \
        '  *) exit 64 ;;' \
        'esac' >"$fake_path"
    chmod 0755 "$fake_path"
}
run_case() {
    local case_name=$1
    local expected_status=$2
    local fixture_classification=$3
    local fixture_status=$4
    local fake_mode=$5
    local case_root
    local case_status=0

    case_root=$(mktemp -d /tmp/caddy-action20d-retry5-a-regression-case.XXXXXX)
    write_fixture "$fixture_classification" "$fixture_status" >"$case_root/fixture"
    make_fake_ssh "$case_root/fake-ssh" "$case_root/fixture" "$fake_mode"
    /bin/bash "$outer" --production-path-test "$case_root/fake-ssh" \
        >"$case_root/stdout" 2>"$case_root/stderr" || case_status=$?
    check_regression "${case_name}_status" test "$case_status" -eq "$expected_status"
    if [[ "$expected_status" -eq 0 ]]; then
        check_regression "${case_name}_accepted" \
            grep -Fqx 'action_20d_retry5_a_outer_diagnostic_accepted=true' \
            "$case_root/stdout"
        check_regression "${case_name}_stderr_empty" test ! -s "$case_root/stderr"
    else
        check_regression "${case_name}_rejected" \
            grep -Fqx 'action_20d_retry5_a_transcript_accepted=false' \
            "$case_root/stderr"
    fi
    rm -rf -- "$case_root"
}

run_case resolved 0 pidfile_isolation_resolved_sigterm 0 valid
run_case persistent_sigterm 0 pidfile_isolation_did_not_resolve_sigterm 143 valid
run_case missing_assertion 1 pidfile_isolation_resolved_sigterm 0 missing
run_case duplicate_assertion 1 pidfile_isolation_resolved_sigterm 0 duplicate
run_case mismatched_classification 1 pidfile_isolation_resolved_sigterm 0 mismatch
printf '%s_false_positive_and_false_negative_controls=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
