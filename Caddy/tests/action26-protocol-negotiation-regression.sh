#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_26_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly core=$caddy_root/scripts/run-workstation-caddy-protocols-action26.sh
readonly outer=$caddy_root/scripts/run-workstation-caddy-protocols-action26-outer.sh

record_check() {
    local action26_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_%s=true\n' "$prefix" "$action26_regression_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action26_regression_label" >&2
    return 1
}
expect_rejected() {
    local action26_regression_transcript=$1
    local action26_regression_stderr=$2

    ! /bin/bash "$outer" --validate-transcript "$action26_regression_transcript" 0 \
        "$action26_regression_stderr" >/dev/null 2>&1
}

action26_regression_root=$(mktemp -d /tmp/caddy-action26-regression.XXXXXX)
readonly action26_regression_root
trap 'rm -rf -- "$action26_regression_root"' EXIT INT TERM

cat >"$action26_regression_root/fake-curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == --version ]]; then
    printf 'curl test\nProtocols: http https\nFeatures: HTTP2 SSL IPv6\n'
    exit 0
fi
printf '%s\n' "$*" >>"${CADDY_ACTION26_CURL_LOG:?}"
protocol=
remote=
while (($#)); do
    case "$1" in
        --http1.1) protocol=1.1; shift ;;
        --http2) protocol=2; shift ;;
        --resolve)
            remote=${2#*:*:}
            remote=${remote#[}
            remote=${remote%]}
            shift 2
            ;;
        *) shift ;;
    esac
done
printf 'protocol=%s\nstatus=204\nremote_ip=%s\nbody_bytes=0\nredirects=0\n' \
    "${CADDY_ACTION26_FAKE_CURL_PROTOCOL:-$protocol}" "$remote"
EOF
chmod 0700 "$action26_regression_root/fake-curl"

cat >"$action26_regression_root/fake-http3" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION26_HTTP3_LOG:?}"
remote=
while (($#)); do
    case "$1" in
        -ip) remote=$2; shift 2 ;;
        *) shift ;;
    esac
done
printf 'protocol=%s\nstatus=204\nremote_ip=%s\nbody_bytes=0\nredirects=0\n' \
    "${CADDY_ACTION26_FAKE_HTTP3_PROTOCOL:-HTTP/3.0}" "$remote"
EOF
chmod 0700 "$action26_regression_root/fake-http3"

: >"$action26_regression_root/curl.args"
: >"$action26_regression_root/http3.args"
action26_regression_core_status=0
CADDY_ACTION26_CURL_BIN="$action26_regression_root/fake-curl" \
    CADDY_ACTION26_HTTP3_BIN="$action26_regression_root/fake-http3" \
    CADDY_ACTION26_CURL_LOG="$action26_regression_root/curl.args" \
    CADDY_ACTION26_HTTP3_LOG="$action26_regression_root/http3.args" \
    /bin/bash "$core" >"$action26_regression_root/core.stdout" \
    2>"$action26_regression_root/core.stderr" || action26_regression_core_status=$?
if [[ "$action26_regression_core_status" -ne 0 ]]; then
    printf '%s_core_status=%s\n' "$prefix" "$action26_regression_core_status" >&2
    sed -n '1,400p' "$action26_regression_root/core.stdout" >&2
    sed -n '1,200p' "$action26_regression_root/core.stderr" >&2
    exit "$action26_regression_core_status"
fi
record_check core_status_zero test "$action26_regression_core_status" -eq 0
record_check core_stderr_empty test ! -s "$action26_regression_root/core.stderr"
record_check exact_transcript_accepted /bin/bash "$outer" --validate-transcript \
    "$action26_regression_root/core.stdout" 0 "$action26_regression_root/core.stderr"
printf '%s_observed_curl_log_line_count=%s\n' "$prefix" \
    "$(wc -l <"$action26_regression_root/curl.args")"
printf '%s_observed_http3_invocation_count=%s\n' "$prefix" \
    "$(wc -l <"$action26_regression_root/http3.args")"
printf '%s_observed_curl_args_begin\n' "$prefix"
cat "$action26_regression_root/curl.args"
printf '%s_observed_curl_args_end\n' "$prefix"
record_check curl_invocation_count test \
    "$(grep -Ec '^--http(1[.]1|2)( |$)' "$action26_regression_root/curl.args" || true)" -eq 4
record_check http3_invocation_count test "$(wc -l <"$action26_regression_root/http3.args")" -eq 2
record_check http11_count test \
    "$(grep -Ec '(^| )--http1[.]1( |$)' "$action26_regression_root/curl.args" || true)" -eq 2
record_check http2_count test \
    "$(grep -Ec '(^| )--http2( |$)' "$action26_regression_root/curl.args" || true)" -eq 2
record_check curl_ipv4_resolve grep -Fq \
    'proxy.local.theama.co:443:10.1.0.56' "$action26_regression_root/curl.args"
record_check curl_ipv6_resolve grep -Fq \
    'proxy.local.theama.co:443:[fd36:5aa8:6971:1::56]' "$action26_regression_root/curl.args"
record_check curl_url_exact test \
    "$(grep -Ec '(^| )https://proxy[.]local[.]theama[.]co/( |$)' \
        "$action26_regression_root/curl.args" || true)" -eq 4
record_check http3_hostname_exact test \
    "$(grep -Ec '(^| )-hostname proxy[.]local[.]theama[.]co( |$)' \
        "$action26_regression_root/http3.args" || true)" -eq 2
record_check http3_ipv4_exact grep -Fq -- '-ip 10.1.0.56' "$action26_regression_root/http3.args"
record_check http3_ipv6_exact grep -Fq -- '-ip fd36:5aa8:6971:1::56' "$action26_regression_root/http3.args"
record_check http3_path_exact test \
    "$(grep -Ec '(^| )-path /( |$)' "$action26_regression_root/http3.args" || true)" -eq 2
record_check observed_before_evaluation awk '
    /action_26_observed_h3_ipv4_protocol=HTTP\/3.0/ { observed=NR }
    /action_26_check_h3_ipv4_protocol_exact=true/ { evaluated=NR }
    END { exit !(observed > 0 && evaluated > observed) }
' "$action26_regression_root/core.stdout"

action26_regression_bad_status=0
CADDY_ACTION26_FAKE_HTTP3_PROTOCOL=2 \
    CADDY_ACTION26_CURL_BIN="$action26_regression_root/fake-curl" \
    CADDY_ACTION26_HTTP3_BIN="$action26_regression_root/fake-http3" \
    CADDY_ACTION26_CURL_LOG="$action26_regression_root/bad-curl.args" \
    CADDY_ACTION26_HTTP3_LOG="$action26_regression_root/bad-http3.args" \
    /bin/bash "$core" >"$action26_regression_root/bad.stdout" \
    2>"$action26_regression_root/bad.stderr" || action26_regression_bad_status=$?
record_check wrong_h3_rejected test "$action26_regression_bad_status" -ne 0
record_check wrong_h3_observed grep -Fqx 'action_26_observed_h3_ipv4_protocol=2' \
    "$action26_regression_root/bad.stdout"
record_check wrong_h3_failure_labeled grep -Fqx 'action_26_check_h3_ipv4_protocol_exact=false' \
    "$action26_regression_root/bad.stderr"

: >"$action26_regression_root/empty.stderr"
sed '/action_26_check_accepted_action25_outer_hash=true/d' "$action26_regression_root/core.stdout" \
    >"$action26_regression_root/missing"
record_check missing_check_rejected expect_rejected "$action26_regression_root/missing" \
    "$action26_regression_root/empty.stderr"
sed 's/action_26_check_accepted_action25_outer_hash=true/action_26_check_accepted_action25_outer_hash=false/' \
    "$action26_regression_root/core.stdout" >"$action26_regression_root/false"
record_check false_check_rejected expect_rejected "$action26_regression_root/false" \
    "$action26_regression_root/empty.stderr"
cp "$action26_regression_root/core.stdout" "$action26_regression_root/duplicate"
grep -F 'action_26_check_accepted_action25_outer_hash=true' "$action26_regression_root/core.stdout" \
    >>"$action26_regression_root/duplicate"
record_check duplicate_check_rejected expect_rejected "$action26_regression_root/duplicate" \
    "$action26_regression_root/empty.stderr"
awk 'NR == 1 { first=$0; next } NR == 2 { print; print first; next } { print }' \
    "$action26_regression_root/core.stdout" >"$action26_regression_root/reordered"
record_check reordered_check_rejected expect_rejected "$action26_regression_root/reordered" \
    "$action26_regression_root/empty.stderr"
cp "$action26_regression_root/core.stdout" "$action26_regression_root/extra"
printf 'action_26_check_unexpected=true\n' >>"$action26_regression_root/extra"
record_check extra_check_rejected expect_rejected "$action26_regression_root/extra" \
    "$action26_regression_root/empty.stderr"
sed 's/action_26_observed_h3_ipv4_protocol=HTTP\/3.0/action_26_observed_h3_ipv4_protocol=2/' \
    "$action26_regression_root/core.stdout" >"$action26_regression_root/altered-observation"
record_check altered_observation_rejected expect_rejected "$action26_regression_root/altered-observation" \
    "$action26_regression_root/empty.stderr"
printf 'bounded failure\n' >"$action26_regression_root/nonempty.stderr"
record_check stderr_rejected expect_rejected "$action26_regression_root/core.stdout" \
    "$action26_regression_root/nonempty.stderr"
if /bin/bash "$outer" --validate-transcript "$action26_regression_root/core.stdout" 1 \
    "$action26_regression_root/empty.stderr" >/dev/null 2>&1; then
    printf '%s_nonzero_status_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_nonzero_status_rejected=true\n' "$prefix"

record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$core" "$outer" "$0"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_protocol_probe=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
