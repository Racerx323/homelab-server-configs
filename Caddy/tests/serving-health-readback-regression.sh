#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
trap 'printf "serving_health_readback_regression_error_line=%s\n" "$LINENO" >&2' ERR
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly transaction=$repository_root/Caddy/scripts/capture-caddy-serving-health-action35u.sh
readonly outer=$repository_root/Caddy/scripts/run-caddy-serving-health-readback-action35u-outer.sh
root=$(mktemp -d /tmp/caddy-successor-production-evidence.XXXXXX)
readonly root
payload=/tmp/caddy-action35u-regression-payload-$$
readonly payload
trap 'rm -rf -- "$root" "$payload" /tmp/caddy-action35u-evidence-regression-*' EXIT

install -d -m 0700 "$root/transaction" "$root/outer" "$payload" "$root/bin"
CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$root/transaction /bin/bash "$transaction" --production-path-test
CADDY_PRODUCTION_PATH_EVIDENCE_ROOT=$root/outer /bin/bash "$outer" --production-path-test

install -m 0550 "$repository_root/Caddy/scripts/check-caddy-serving-health.sh" "$payload/check-caddy-serving-health.sh"
install -m 0550 "$repository_root/Caddy/scripts/caddy-serving-health-curl-proxy-action35u.sh" "$payload/caddy-serving-health-curl-proxy-action35u.sh"
printf 'NODE_FQDN=node-a.example.test\nNODE_IPV4=192.0.2.10\nNODE_IPV6=2001:db8::10\n' >"$root/environment"
cat >"$root/bin/systemctl" <<'EOF'
#!/bin/bash
[[ "$1" = is-active ]] && exit 0
printf 'LoadState=loaded\nActiveState=active\nSubState=running\nMainPID=123\nNRestarts=0\n'
EOF
cat >"$root/bin/ss" <<'EOF'
#!/bin/bash
printf 'LISTEN 0 4096 192.0.2.10:443 0.0.0.0:*\nLISTEN 0 4096 [2001:db8::10]:443 [::]:*\n'
EOF
cat >"$root/bin/runuser" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>'$root/runuser.calls'
[[ "\$1" = -u && "\$2" = keepalived_script && "\$3" = -- ]] || exit 97
shift 3
exec "\$@"
EOF
cat >"$root/bin/curl" <<'EOF'
#!/bin/bash
if printf '%s\n' "$@" | grep -Fxq -- '--ipv4'; then
    printf 'curl: (7) Failed to connect: Connection refused\n' >&2
    exit 7
fi
if printf '%s\n' "$@" | grep -Fq 'http_code='; then
    printf 'http_code=204\tremote_ip=2001:db8::10\tssl_verify_result=0\tnum_redirects=0\ttime_total=0.010\n'
else
    printf '204\n'
fi
EOF
chmod 0755 "$root/bin"/*
evidence=/tmp/caddy-action35u-evidence-regression-$$
ACTION35U_PRODUCTION_PATH_TEST=1 ACTION35U_TEST_ENVIRONMENT_FILE=$root/environment \
    ACTION35U_TEST_SYSTEMCTL=$root/bin/systemctl ACTION35U_TEST_SS=$root/bin/ss \
    ACTION35U_TEST_RUNUSER=$root/bin/runuser ACTION35U_TEST_CURL=$root/bin/curl \
    /bin/bash "$transaction" capture node-a "$payload" "$evidence"

grep -Fxq $'ipv4\t7\tunknown\tunknown\tunknown\tunknown\tunknown\tconnection-refused' "$evidence/detail-ipv4.tsv"
grep -Fxq $'ipv6\t0\t204\t2001:db8::10\t0\t0\t0.010\tsuccess' "$evidence/detail-ipv6.tsv"
grep -Fxq '1' "$evidence/helper.status"
grep -Fq -- '--ipv4' "$evidence/helper-ipv4-curl-arguments.txt"
grep -Fq -- '--ipv6' "$evidence/helper-ipv6-curl-arguments.txt"
grep -Fxq -- '-u keepalived_script --' <(awk '{print $1, $2, $3}' "$root/runuser.calls")
grep -Fq 'ActiveState=active' "$evidence/caddy-service.stdout"
[[ "$(stat -c '%U:%G:%a' "$evidence")" = "$(id -un):$(id -gn):700" ]]
grep -Fxq $'ipv4\ttrue\ttrue' "$evidence/listener-summary.tsv"
grep -Fxq $'ipv6\ttrue\ttrue' "$evidence/listener-summary.tsv"

printf 'serving_health_readback_regression_complete=true\n'
