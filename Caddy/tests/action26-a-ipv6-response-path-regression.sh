#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_a_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly core=$caddy_root/scripts/run-workstation-caddy-ipv6-response-path-action26-a.sh
readonly outer=$caddy_root/scripts/run-workstation-caddy-ipv6-response-path-action26-a-outer.sh

record_check() {
    local action26a_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_%s=true\n' "$prefix" "$action26a_regression_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action26a_regression_label" >&2
    return 1
}
expect_rejected() {
    local action26a_regression_transcript=$1
    local action26a_regression_stderr=$2

    ! /bin/bash "$outer" --validate-transcript "$action26a_regression_transcript" 0 \
        "$action26a_regression_stderr" >/dev/null 2>&1
}
run_fixture() {
    local action26a_regression_name=$1
    shift

    : >"$action26a_regression_root/${action26a_regression_name}.ip.args"
    : >"$action26a_regression_root/${action26a_regression_name}.curl.args"
    env "$@" \
        CADDY_ACTION26A_IP_BIN="$action26a_regression_root/fake-ip" \
        CADDY_ACTION26A_CURL_BIN="$action26a_regression_root/fake-curl" \
        CADDY_ACTION26A_IP_LOG="$action26a_regression_root/${action26a_regression_name}.ip.args" \
        CADDY_ACTION26A_CURL_LOG="$action26a_regression_root/${action26a_regression_name}.curl.args" \
        /bin/bash "$core" >"$action26a_regression_root/${action26a_regression_name}.stdout" \
        2>"$action26a_regression_root/${action26a_regression_name}.stderr"
}

action26a_regression_root=$(mktemp -d /tmp/caddy-action26-a-regression.XXXXXX)
readonly action26a_regression_root
trap 'rm -rf -- "$action26a_regression_root"' EXIT INT TERM

cat >"$action26a_regression_root/fake-ip" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION26A_IP_LOG:?}"
target=${*: -1}
if [[ "$*" == *" route get "* ]]; then
    if [[ "${CADDY_ACTION26A_FAKE_ROUTE_MISSING:-false}" = true && "$target" == *"::56" ]]; then
        printf 'RTNETLINK answers: Network is unreachable\n' >&2
        exit 2
    fi
    printf '%s dev eth0 src fd36:5aa8:6971:1::100 metric 1024\n' "$target"
    exit 0
fi
if [[ "$*" == *" neigh show to "* ]]; then
    printf '%s dev eth0 lladdr 00:11:22:33:44:55 REACHABLE\n' "$target"
    exit 0
fi
exit 64
EOF
chmod 0700 "$action26a_regression_root/fake-ip"

cat >"$action26a_regression_root/fake-curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
logged_args=$*
logged_args=${logged_args//$'\n'/\\n}
printf '%s\n' "$logged_args" >>"${CADDY_ACTION26A_CURL_LOG:?}"
remote=
while (($#)); do
    case "$1" in
        --resolve)
            remote=${2#*:*:}
            remote=${remote#[}
            remote=${remote%]}
            shift 2
            ;;
        *) shift ;;
    esac
done
if [[ "${CADDY_ACTION26A_FAKE_ALL_FAIL:-false}" = true ]] ||
    { [[ "$remote" == *"::56" ]] && [[ "${CADDY_ACTION26A_FAKE_VIP_HEALTHY:-false}" != true ]]; }; then
    printf 'protocol=0\nstatus=000\nremote_ip=\nbody_bytes=0\nredirects=0\n'
    printf 'curl: (7) bounded connection failure\n' >&2
    exit 7
fi
printf 'protocol=1.1\nstatus=204\nremote_ip=%s\nbody_bytes=0\nredirects=0\n' "$remote"
EOF
chmod 0700 "$action26a_regression_root/fake-curl"

run_fixture vip-specific
record_check vip_specific_stderr_empty test ! -s "$action26a_regression_root/vip-specific.stderr"
record_check vip_specific_classification grep -Fqx \
    'action_26_a_observed_classification=vip_specific_https_failure' \
    "$action26a_regression_root/vip-specific.stdout"
record_check vip_specific_transcript_accepted /bin/bash "$outer" --validate-transcript \
    "$action26a_regression_root/vip-specific.stdout" 0 \
    "$action26a_regression_root/vip-specific.stderr"
printf '%s_observed_route_invocation_count=%s\n' "$prefix" \
    "$(grep -Ec '^-6 route get ' "$action26a_regression_root/vip-specific.ip.args" || true)"
printf '%s_observed_neighbor_invocation_count=%s\n' "$prefix" \
    "$(grep -Ec '^-6 neigh show to ' "$action26a_regression_root/vip-specific.ip.args" || true)"
printf '%s_observed_curl_invocation_count=%s\n' "$prefix" \
    "$(wc -l <"$action26a_regression_root/vip-specific.curl.args")"
record_check route_invocation_count test \
    "$(grep -Ec '^-6 route get ' "$action26a_regression_root/vip-specific.ip.args" || true)" -eq 3
record_check neighbor_invocation_count test \
    "$(grep -Ec '^-6 neigh show to ' "$action26a_regression_root/vip-specific.ip.args" || true)" -eq 6
record_check curl_invocation_count test \
    "$(wc -l <"$action26a_regression_root/vip-specific.curl.args")" -eq 3
record_check node_a_control_exact grep -Fq \
    'proxy.local.theama.co:443:[fd36:5aa8:6971:1::53]' \
    "$action26a_regression_root/vip-specific.curl.args"
record_check node_b_control_exact grep -Fq \
    'proxy.local.theama.co:443:[fd36:5aa8:6971:1::54]' \
    "$action26a_regression_root/vip-specific.curl.args"
record_check caddy_vip_exact grep -Fq \
    'proxy.local.theama.co:443:[fd36:5aa8:6971:1::56]' \
    "$action26a_regression_root/vip-specific.curl.args"
record_check all_curl_http11 test \
    "$(grep -Ec '(^| )--http1[.]1( |$)' "$action26a_regression_root/vip-specific.curl.args" || true)" -eq 3
record_check all_curl_health_path test \
    "$(grep -Ec '(^| )https://proxy[.]local[.]theama[.]co/( |$)' \
        "$action26a_regression_root/vip-specific.curl.args" || true)" -eq 3

run_fixture workstation-failure CADDY_ACTION26A_FAKE_ALL_FAIL=true
record_check workstation_failure_classification grep -Fqx \
    'action_26_a_observed_classification=workstation_ipv6_https_path_failure' \
    "$action26a_regression_root/workstation-failure.stdout"
record_check workstation_failure_transcript_accepted /bin/bash "$outer" --validate-transcript \
    "$action26a_regression_root/workstation-failure.stdout" 0 \
    "$action26a_regression_root/workstation-failure.stderr"

run_fixture vip-healthy CADDY_ACTION26A_FAKE_VIP_HEALTHY=true
record_check vip_healthy_classification grep -Fqx \
    'action_26_a_observed_classification=vip_https_healthy' \
    "$action26a_regression_root/vip-healthy.stdout"
record_check vip_healthy_transcript_accepted /bin/bash "$outer" --validate-transcript \
    "$action26a_regression_root/vip-healthy.stdout" 0 \
    "$action26a_regression_root/vip-healthy.stderr"

run_fixture route-missing CADDY_ACTION26A_FAKE_ROUTE_MISSING=true
record_check route_missing_classification grep -Fqx \
    'action_26_a_observed_classification=vip_route_missing' \
    "$action26a_regression_root/route-missing.stdout"
record_check route_missing_transcript_accepted /bin/bash "$outer" --validate-transcript \
    "$action26a_regression_root/route-missing.stdout" 0 \
    "$action26a_regression_root/route-missing.stderr"

: >"$action26a_regression_root/empty.stderr"
sed '/action_26_a_check_accepted_action26_outer_hash=true/d' \
    "$action26a_regression_root/vip-specific.stdout" >"$action26a_regression_root/missing"
record_check missing_check_rejected expect_rejected "$action26a_regression_root/missing" \
    "$action26a_regression_root/empty.stderr"
sed 's/action_26_a_check_accepted_action26_outer_hash=true/action_26_a_check_accepted_action26_outer_hash=false/' \
    "$action26a_regression_root/vip-specific.stdout" >"$action26a_regression_root/false"
record_check false_check_rejected expect_rejected "$action26a_regression_root/false" \
    "$action26a_regression_root/empty.stderr"
cp "$action26a_regression_root/vip-specific.stdout" "$action26a_regression_root/duplicate"
grep -F 'action_26_a_check_accepted_action26_outer_hash=true' \
    "$action26a_regression_root/vip-specific.stdout" >>"$action26a_regression_root/duplicate"
record_check duplicate_check_rejected expect_rejected "$action26a_regression_root/duplicate" \
    "$action26a_regression_root/empty.stderr"
sed 's/action_26_a_observed_classification=vip_specific_https_failure/action_26_a_observed_classification=unknown/' \
    "$action26a_regression_root/vip-specific.stdout" >"$action26a_regression_root/unknown"
record_check unknown_classification_rejected expect_rejected "$action26a_regression_root/unknown" \
    "$action26a_regression_root/empty.stderr"
printf 'bounded stderr\n' >"$action26a_regression_root/nonempty.stderr"
record_check stderr_rejected expect_rejected "$action26a_regression_root/vip-specific.stdout" \
    "$action26a_regression_root/nonempty.stderr"
if /bin/bash "$outer" --validate-transcript "$action26a_regression_root/vip-specific.stdout" 1 \
    "$action26a_regression_root/empty.stderr" >/dev/null 2>&1; then
    printf '%s_nonzero_status_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_nonzero_status_rejected=true\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_probe=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
