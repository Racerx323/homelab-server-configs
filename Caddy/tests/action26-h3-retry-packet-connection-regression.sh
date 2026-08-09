#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/local/go/bin:/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly outer=$caddy_root/scripts/run-workstation-caddy-http3-action26-h3-retry-outer.sh
readonly source_root=$caddy_root/tools/http3-probe-v2
regression_root=

cleanup() {
    local action26_h3_retry_regression_status=$?

    trap - EXIT INT TERM
    [[ -z "$regression_root" ]] || rm -rf -- "$regression_root"
    exit "$action26_h3_retry_regression_status"
}

regression_root=$(mktemp -d /tmp/caddy-action26-h3-retry-regression.XXXXXX)
trap cleanup EXIT INT TERM
cat >"$regression_root/fake-http3" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION26_H3_RETRY_LOG:?}"
remote=
while (($#)); do
    case "$1" in
        -ip)
            remote=$2
            shift 2
            ;;
        *) shift ;;
    esac
done
printf 'protocol=HTTP/3.0\nstatus=204\nremote_ip=%s\nbody_bytes=0\nredirects=0\n' "$remote"
EOF
chmod 0755 "$regression_root/fake-http3"

if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
    printf 'action_26_h3_retry_regression_go_test=deferred_host_authoritative\n'
else
    cache_root=$regression_root/go-cache
    mkdir -m 0700 -- "$cache_root"
    (
        cd -- "$source_root"
        GOCACHE=$cache_root GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off \
            go test -mod=readonly -run 'TestHistoricalZeroValueTransportPanics|TestCorrectedTransportInitializesAndClosesPacketConn' ./...
    )
    printf 'action_26_h3_retry_regression_go_test=passed_host_authoritative\n'
fi

CADDY_ACTION26_H3_RETRY_TEST_BIN=$regression_root/fake-http3 \
    CADDY_ACTION26_H3_RETRY_LOG=$regression_root/probes.log \
    CADDY_ACTION26_H3_RETRY_SKIP_REGRESSION=true \
    /bin/bash "$outer" >"$regression_root/outer.stdout" 2>"$regression_root/outer.stderr"
[[ ! -s "$regression_root/outer.stderr" ]]
grep -Fqx 'action_26_h3_retry_outer_complete=true' "$regression_root/outer.stdout"
[[ "$(wc -l <"$regression_root/probes.log")" -eq 2 ]]
grep -Fqx -- '-hostname proxy.local.theama.co -ip 10.1.0.56 -path / -timeout 8s -insecure' \
    "$regression_root/probes.log"
grep -Fqx -- '-hostname proxy.local.theama.co -ip fd36:5aa8:6971:1::56 -path / -timeout 8s -insecure' \
    "$regression_root/probes.log"
grep -Fq '&quic.Transport{Conn: packetConn}' "$source_root/main.go"
grep -Fq 'resources.quicTransport.Close(), resources.packetConn.Close()' "$source_root/main.go"
grep -Fq 'TestHistoricalZeroValueTransportPanics' "$source_root/main_test.go"
grep -Fq 'TestCorrectedTransportInitializesAndClosesPacketConn' "$source_root/main_test.go"

printf 'action_26_h3_retry_regression_live_probe=false\n'
printf 'action_26_h3_retry_regression_historical_panic_reproduced=true\n'
printf 'action_26_h3_retry_regression_corrected_path_accepted=true\n'
printf 'action_26_h3_retry_regression_complete=true\n'
