#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/go/bin:/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_26_retry_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly adapter=$caddy_root/scripts/run-workstation-caddy-protocols-action26-retry.sh
readonly outer=$caddy_root/scripts/run-workstation-caddy-protocols-action26-retry-outer.sh
regression_root=

fail() {
    printf '%s_failure=%s\n' "$prefix" "$1" >&2
    return 1
}
cleanup() {
    local action26_retry_regression_status=$?

    trap - EXIT INT TERM
    [[ -z "$regression_root" ]] || rm -rf -- "$regression_root"
    exit "$action26_retry_regression_status"
}
run_adapter() {
    local action26_retry_run_status=0

    CADDY_ACTION26_CURL_BIN="$regression_root/fake-curl" \
        CADDY_ACTION26_HTTP3_BIN="$regression_root/fake-http3" \
        CADDY_ACTION26_CURL_LOG="$regression_root/curl.args" \
        CADDY_ACTION26_HTTP3_LOG="$regression_root/http3.args" \
        /bin/bash "$adapter" >"$regression_root/adapter.stdout" \
        2>"$regression_root/adapter.stderr" || action26_retry_run_status=$?
    printf '%s\n' "$action26_retry_run_status" >"$regression_root/adapter.status"
}
expect_rejected() {
    local action26_retry_case=$1
    local action26_retry_status=0

    /bin/bash "$outer" --validate-transcript "$action26_retry_case" 0 \
        "$regression_root/empty.stderr" >/dev/null 2>&1 || action26_retry_status=$?
    test "$action26_retry_status" -ne 0
}

regression_root=$(mktemp -d /tmp/caddy-action26-retry-regression.XXXXXX)
trap cleanup EXIT INT TERM
cat >"$regression_root/fake-curl" <<'EOF'
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
printf 'protocol=%s\nstatus=204\nremote_ip=%s\nbody_bytes=0\nredirects=0\n' "$protocol" "$remote"
EOF
cat >"$regression_root/fake-http3" <<'EOF'
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
printf 'protocol=HTTP/3.0\nstatus=204\nremote_ip=%s\nbody_bytes=0\nredirects=0\n' "$remote"
EOF
chmod 0755 "$regression_root/fake-curl" "$regression_root/fake-http3"
: >"$regression_root/curl.args"
: >"$regression_root/http3.args"
: >"$regression_root/empty.stderr"

run_adapter
if [[ "$(<"$regression_root/adapter.status")" -ne 0 ]]; then
    sed -n '1,240p' "$regression_root/adapter.stdout" >&2
    sed -n '1,120p' "$regression_root/adapter.stderr" >&2
    fail production_status
fi
[[ ! -s "$regression_root/adapter.stderr" ]] || fail production_stderr
/bin/bash "$outer" --validate-transcript "$regression_root/adapter.stdout" 0 \
    "$regression_root/adapter.stderr" >/dev/null || fail production_transcript
[[ "$(grep -Ec '^action_26_retry_check_.*=true$' "$regression_root/adapter.stdout")" -eq 59 ]] ||
    fail production_core_check_count
[[ "$(grep -Ec '^action_26_retry_adapter_check_.*=true$' "$regression_root/adapter.stdout")" -eq 7 ]] ||
    fail production_adapter_check_count
[[ "$(sed -n '/^action_26_/ { /^action_26_retry_/!p }' "$regression_root/adapter.stdout" | wc -l)" -eq 0 ]] ||
    fail historical_prefix_absent
[[ "$(grep -Ec '^--http(1[.]1|2)( |$)' "$regression_root/curl.args" || true)" -eq 4 ]] || fail curl_count
[[ "$(wc -l <"$regression_root/http3.args")" -eq 2 ]] || fail http3_count

sed '/action_26_retry_adapter_check_generated_hash=true/d' "$regression_root/adapter.stdout" \
    >"$regression_root/missing"
expect_rejected "$regression_root/missing" || fail missing_adapter_rejected
sed 's/action_26_retry_check_h2_ipv6_protocol_exact=true/action_26_retry_check_h2_ipv6_protocol_exact=false/' \
    "$regression_root/adapter.stdout" >"$regression_root/false"
expect_rejected "$regression_root/false" || fail false_core_rejected
sed 's/^action_26_retry_/action_26_/' "$regression_root/adapter.stdout" >"$regression_root/historical"
expect_rejected "$regression_root/historical" || fail historical_prefix_rejected

printf '%s_live_protocol_probe=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
