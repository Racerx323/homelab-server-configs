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
readonly core=$caddy_root/scripts/run-workstation-caddy-http3-action26-h3.sh
readonly outer=$caddy_root/scripts/run-workstation-caddy-http3-action26-h3-outer.sh
regression_root=

cleanup() {
    local action26_h3_regression_status=$?

    trap - EXIT INT TERM
    [[ -z "$regression_root" ]] || rm -rf -- "$regression_root"
    exit "$action26_h3_regression_status"
}
run_core() {
    local action26_h3_mode=$1
    local action26_h3_status=0

    CADDY_ACTION26_H3_MODE=$action26_h3_mode CADDY_ACTION26_H3_BIN="$regression_root/fake-http3" \
        CADDY_ACTION26_H3_LOG="$regression_root/$action26_h3_mode.log" \
        /bin/bash "$core" >"$regression_root/$action26_h3_mode.stdout" \
        2>"$regression_root/$action26_h3_mode.stderr" || action26_h3_status=$?
    printf '%s\n' "$action26_h3_status" >"$regression_root/$action26_h3_mode.status"
}

regression_root=$(mktemp -d /tmp/caddy-action26-h3-regression.XXXXXX)
trap cleanup EXIT INT TERM
cat >"$regression_root/fake-http3" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${CADDY_ACTION26_H3_LOG:?}"
if [[ "${CADDY_ACTION26_H3_MODE:-success}" == failure ]]; then
    i=0
    while ((i < 34)); do
        printf 'bounded safe HTTP3 failure evidence line %02d xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' "$i" >&2
        ((i += 1))
    done
    exit 2
fi
remote=
while (($#)); do
    case "$1" in
        -ip) remote=$2; shift 2 ;;
        *) shift ;;
    esac
done
printf 'protocol=HTTP/3.0\nstatus=204\nremote_ip=%s\nbody_bytes=0\nredirects=0\n' "$remote"
EOF
chmod 0755 "$regression_root/fake-http3"

run_core success
[[ "$(<"$regression_root/success.status")" -eq 0 ]]
[[ ! -s "$regression_root/success.stderr" ]]
/bin/bash "$outer" --validate-transcript "$regression_root/success.stdout" 0 \
    "$regression_root/success.stderr" >/dev/null
[[ "$(wc -l <"$regression_root/success.log")" -eq 2 ]]
grep -Fqx -- '-hostname proxy.local.theama.co -ip 10.1.0.56 -path / -timeout 8s -insecure' \
    "$regression_root/success.log"
grep -Fqx -- '-hostname proxy.local.theama.co -ip fd36:5aa8:6971:1::56 -path / -timeout 8s -insecure' \
    "$regression_root/success.log"

run_core failure
[[ "$(<"$regression_root/failure.status")" -ne 0 ]]
grep -Fqx 'action_26_h3_observed_h3_ipv4_command_status=2' "$regression_root/failure.stdout"
grep -Fqx 'action_26_h3_observed_h3_ipv4_stderr_classification=bounded_safe' "$regression_root/failure.stdout"
grep -Fqx 'action_26_h3_observed_h3_ipv4_stderr_begin' "$regression_root/failure.stdout"
grep -Fq 'bounded safe HTTP3 failure evidence line 33' "$regression_root/failure.stdout"
grep -Fqx 'action_26_h3_observed_h3_ipv4_stderr_end' "$regression_root/failure.stdout"
grep -Fqx 'action_26_h3_check_h3_ipv4_command_status=false' "$regression_root/failure.stderr"
action26_h3_observed_failure_bytes=$(sed -n \
    's/^action_26_h3_observed_h3_ipv4_stderr_bytes=//p' "$regression_root/failure.stdout")
readonly action26_h3_observed_failure_bytes
[[ "$action26_h3_observed_failure_bytes" -gt 2533 ]]
[[ "$action26_h3_observed_failure_bytes" -le 8192 ]]
awk '
    /action_26_h3_observed_h3_ipv4_stderr_end/ { emitted=NR }
    END { exit !(emitted > 0) }
' "$regression_root/failure.stdout"

printf 'action_26_h3_regression_live_probe=false\n'
printf 'action_26_h3_regression_complete=true\n'
