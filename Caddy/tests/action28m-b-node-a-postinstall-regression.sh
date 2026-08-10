#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_28m_b_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
caddy_root=${test_directory%/tests}
readonly caddy_root
readonly inspector=$caddy_root/scripts/inspect-node-a-caddy-service-restoration-action28m-b.sh
readonly outer=$caddy_root/scripts/run-node-a-caddy-service-restoration-post-action28m-b-outer.sh
fixture_root=$(mktemp -d /tmp/caddy-action28m-b-regression.XXXXXX)
readonly fixture_root
readonly base_root=$fixture_root/base
readonly fake_ssh=$fixture_root/ssh

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }
tree_hash() {
    local action28mb_regression_tree=$1

    (
        cd "$action28mb_regression_tree"
        find . -printf '%P|%y|%m\n' | LC_ALL=C sort
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
    ) | sha256sum | awk '{ print $1 }'
}
record_check() {
    local action28mb_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action28mb_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action28mb_regression_label" >&2
    return 1
}
command_rejected() {
    if "$@" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
prepare_fixture() {
    install -d -m 0755 "$base_root/etc/keepalived/conf.d" "$base_root/state" "$base_root/run"
    install -d -m 0700 \
        "$base_root/var/backups/caddy-ha/action28m-node-a-caddy-service-restoration"
    printf 'global_defs {\n    router_id PIHOLE0\n}\n' >"$base_root/etc/keepalived/keepalived.conf"
    printf 'vrrp_instance CADDY_IPV4 {\n}\n' >"$base_root/etc/keepalived/conf.d/caddy-ha.conf"
    cp -- "$base_root/etc/keepalived/keepalived.conf" \
        "$base_root/var/backups/caddy-ha/action28m-node-a-caddy-service-restoration/keepalived.conf"
    cp -- "$base_root/etc/keepalived/conf.d/caddy-ha.conf" \
        "$base_root/var/backups/caddy-ha/action28m-node-a-caddy-service-restoration/caddy-ha.conf"
    retired_hash=$(file_hash "$base_root/etc/keepalived/keepalived.conf")
    baseline_hash=$(file_hash \
        "$base_root/var/backups/caddy-ha/action28m-node-a-caddy-service-restoration/keepalived.conf")
    fragment_hash=$(file_hash "$base_root/etc/keepalived/conf.d/caddy-ha.conf")
    readonly retired_hash baseline_hash fragment_hash
    printf 'action=28m\nbaseline_main_sha256=%s\nfragment_sha256=%s\nretired_main_sha256=%s\n' \
        "$baseline_hash" "$fragment_hash" "$retired_hash" \
        >"$base_root/var/backups/caddy-ha/action28m-node-a-caddy-service-restoration/manifest"
    chmod 0644 "$base_root/etc/keepalived/keepalived.conf" \
        "$base_root/etc/keepalived/conf.d/caddy-ha.conf"
    chmod 0600 "$base_root/var/backups/caddy-ha/action28m-node-a-caddy-service-restoration/manifest"
    printf '%s\n' 'keepalived.service=active' 'lighttpd.service=active' \
        'caddy.service=active' >"$base_root/state/services"
    printf '2: eth0 inet 10.1.0.55/22 scope global eth0\n' >"$base_root/state/ipv4"
    printf '2: eth0 inet6 fd36:5aa8:6971:1::55/128 scope global\n' >"$base_root/state/ipv6"
    printf '%s\n' \
        'localhost|127.0.0.1|/|0|204' \
        'pihole0.local.theama.co|10.1.0.53|/admin/|0|200' \
        'pihole0.local.theama.co|[fd36:5aa8:6971:1::53]|/admin/|0|200' \
        >"$base_root/state/https"
}
run_case() {
    local action28mb_regression_mode=$1
    local action28mb_regression_expected_status=$2
    local action28mb_regression_case_root
    local action28mb_regression_before_hash
    local action28mb_regression_after_hash
    local action28mb_regression_stdout
    local action28mb_regression_stderr
    local action28mb_regression_status=0
    local action28mb_regression_skip_local_gates=false

    action28mb_regression_case_root=$(mktemp -d "$fixture_root/case.XXXXXX")
    cp -a -- "$base_root/." "$action28mb_regression_case_root/"
    case "$action28mb_regression_mode" in
        main_drift) printf '# drift\n' >>"$action28mb_regression_case_root/etc/keepalived/keepalived.conf" ;;
        caddy_inactive)
            sed -i 's/caddy[.]service=active/caddy.service=inactive/' \
                "$action28mb_regression_case_root/state/services"
            ;;
        caddy_vip)
            printf '2: eth0 inet 10.1.0.56/22 scope global eth0\n' \
                >>"$action28mb_regression_case_root/state/ipv4"
            ;;
        https_failure)
            sed -i 's/localhost|127[.]0[.]0[.]1|\/|0|204/localhost|127.0.0.1|\/|28|000/' \
                "$action28mb_regression_case_root/state/https"
            ;;
        success | missing_label | duplicate_label | extra_label | stderr | nonzero) ;;
        *) return 1 ;;
    esac
    action28mb_regression_before_hash=$(tree_hash "$action28mb_regression_case_root")
    action28mb_regression_stdout=$action28mb_regression_case_root/outer.stdout
    action28mb_regression_stderr=$action28mb_regression_case_root/outer.stderr
    if [[ "$action28mb_regression_mode" != success ]]; then
        action28mb_regression_skip_local_gates=true
    fi
    if env CADDY_ACTION28MB_TEST_MODE=1 CADDY_ACTION28MB_SKIP_REGRESSION=true \
        CADDY_ACTION28MB_SKIP_LOCAL_GATES="$action28mb_regression_skip_local_gates" \
        CADDY_ACTION28MB_SSH_BIN="$fake_ssh" \
        CADDY_ACTION28MB_EVIDENCE_ROOT="$fixture_root/evidence" \
        ACTION28MB_FIXTURE_MODE="$action28mb_regression_mode" \
        ACTION28MB_FIXTURE_ROOT="$action28mb_regression_case_root" \
        ACTION28MB_FIXTURE_INSPECTOR="$inspector" \
        ACTION28MB_FIXTURE_RETIRED_SHA256="$retired_hash" \
        ACTION28MB_FIXTURE_BASELINE_SHA256="$baseline_hash" \
        ACTION28MB_FIXTURE_FRAGMENT_SHA256="$fragment_hash" \
        /bin/bash "$outer" >"$action28mb_regression_stdout" 2>"$action28mb_regression_stderr"; then
        action28mb_regression_status=0
    else
        action28mb_regression_status=$?
    fi
    if [[ "$action28mb_regression_status" -ne "$action28mb_regression_expected_status" ]]; then
        printf '%s_case_%s_observed_status=%s\n' "$prefix" \
            "$action28mb_regression_mode" "$action28mb_regression_status" >&2
        sed -n '1,260p' "$action28mb_regression_stdout" >&2
        sed -n '1,160p' "$action28mb_regression_stderr" >&2
        return 1
    fi
    if [[ "$action28mb_regression_expected_status" -eq 0 ]]; then
        grep -Fqx 'action_28m_b_outer_acceptance=true' "$action28mb_regression_stdout" || {
            sed -n '1,260p' "$action28mb_regression_stdout" >&2
            return 1
        }
        grep -Fqx 'action_28m_b_outer_node_b_contacted=false' "$action28mb_regression_stdout" || {
            printf '%s_case_%s_missing_node_b_marker=true\n' "$prefix" \
                "$action28mb_regression_mode" >&2
            return 1
        }
        [[ ! -s "$action28mb_regression_stderr" ]] || {
            sed -n '1,160p' "$action28mb_regression_stderr" >&2
            return 1
        }
        rm -f -- "$action28mb_regression_stdout" "$action28mb_regression_stderr"
        action28mb_regression_after_hash=$(tree_hash "$action28mb_regression_case_root")
        if [[ "$action28mb_regression_before_hash" != "$action28mb_regression_after_hash" ]]; then
            printf '%s_case_%s_before_hash=%s\n' "$prefix" "$action28mb_regression_mode" \
                "$action28mb_regression_before_hash" >&2
            printf '%s_case_%s_after_hash=%s\n' "$prefix" "$action28mb_regression_mode" \
                "$action28mb_regression_after_hash" >&2
            find "$action28mb_regression_case_root" -printf '%P|%y|%m|%s\n' |
                LC_ALL=C sort >&2
            return 1
        fi
    fi
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

received=$(mktemp /tmp/caddy-action28m-b-received.XXXXXX)
transcript=$(mktemp /tmp/caddy-action28m-b-transcript.XXXXXX)
stderr_file=$(mktemp /tmp/caddy-action28m-b-stderr.XXXXXX)
readonly received transcript stderr_file
trap 'rm -f -- "$received" "$transcript" "$stderr_file"' EXIT
cat >"$received"
[[ " $* " == *' pi@10.1.0.53 '* ]] || exit 90
[[ " $* " == *' HostKeyAlias=pihole0.local.theama.co '* ]] || exit 91
[[ " $* " == *'cd / && sudo -n /bin/bash -s --'* ]] || exit 92
[[ "$(sha256sum "$received" | awk '{ print $1 }')" = \
    "$(sha256sum "$ACTION28MB_FIXTURE_INSPECTOR" | awk '{ print $1 }')" ]] || exit 93
producer_status=0
(
    cd /
    CADDY_ACTION28MB_TEST_MODE=1 \
        CADDY_ACTION28MB_RETIRED_MAIN_SHA256="$ACTION28MB_FIXTURE_RETIRED_SHA256" \
        CADDY_ACTION28MB_BASELINE_MAIN_SHA256="$ACTION28MB_FIXTURE_BASELINE_SHA256" \
        CADDY_ACTION28MB_FRAGMENT_SHA256="$ACTION28MB_FIXTURE_FRAGMENT_SHA256" \
        /bin/bash "$received" --fixture-root "$ACTION28MB_FIXTURE_ROOT"
) >"$transcript" 2>"$stderr_file" || producer_status=$?
case "$ACTION28MB_FIXTURE_MODE" in
    missing_label) sed -i '/^action_28m_b_check_caddy_active_after=true$/d' "$transcript" ;;
    duplicate_label) printf 'action_28m_b_check_caddy_active_after=true\n' >>"$transcript" ;;
    extra_label) printf 'action_28m_b_check_unexpected=true\n' >>"$transcript" ;;
    stderr) printf 'bounded fixture stderr\n' >>"$stderr_file" ;;
    nonzero) producer_status=23 ;;
esac
cat "$transcript"
cat "$stderr_file" >&2
exit "$producer_status"
FAKE_SSH
chmod 0700 "$fake_ssh"

record_check inspector_self_test /bin/bash "$inspector" --self-test
record_check production_success run_case success 0
record_check rejects_main_drift run_case main_drift 1
record_check rejects_inactive_caddy run_case caddy_inactive 1
record_check rejects_caddy_vip run_case caddy_vip 1
record_check rejects_https_failure run_case https_failure 1
record_check rejects_missing_label run_case missing_label 1
record_check rejects_duplicate_label run_case duplicate_label 1
record_check rejects_extra_label run_case extra_label 1
record_check rejects_stderr run_case stderr 1
record_check rejects_nonzero run_case nonzero 1
record_check predecessor_transaction_not_invoked command_rejected \
    grep -Fq 'run-node-a-caddy-service-restoration-action28m-outer.sh' "$fake_ssh"
record_check predecessor_acceptance_not_invoked command_rejected \
    grep -Fq 'run-node-a-caddy-service-restoration-post-action28m-a-outer.sh' "$fake_ssh"
printf '%s_node_a_contacted=false\n' "$prefix"
printf '%s_node_b_contacted=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
