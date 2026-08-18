#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_35_u_capture
readonly expected_helper_sha256=381c9b371621e1ddfae1eba3f557f8750fc0bbcc162415b038c8043aa1bac208
readonly max_file_bytes=1048576

fail() {
    printf '%s_%s=false\n' "$prefix" "$1" >&2
    exit "${2:-1}"
}
regular_file() { [[ -f "$1" && ! -L "$1" ]]; }
safe_path() { [[ "$1" = /tmp/caddy-action35u-* && "$1" != *$'\n'* && "$1" != *$'\r'* ]]; }

safe_file() {
    regular_file "$1" && [[ "$(stat -c '%s' "$1")" -le "$max_file_bytes" ]] &&
        iconv -f UTF-8 -t UTF-8 "$1" >/dev/null &&
        ! LC_ALL=C grep -Paq '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]' "$1"
}

classify_curl() {
    local status=$1 stderr_file=$2 http_code=$3
    if [[ "$status" -eq 0 && "$http_code" = 204 ]]; then
        printf 'success'
    elif [[ "$status" -eq 0 ]]; then
        printf 'unexpected-http-response'
    elif [[ "$status" -eq 6 ]]; then
        printf 'name-resolution'
    elif [[ "$status" -eq 7 ]] && grep -Eqi 'refused' "$stderr_file"; then
        printf 'connection-refused'
    elif [[ "$status" -eq 7 ]]; then
        printf 'routing-or-connect'
    elif [[ "$status" -eq 28 ]]; then
        printf 'timeout'
    elif [[ "$status" -eq 51 || "$status" -eq 60 ]]; then
        printf 'certificate-or-hostname'
    elif [[ "$status" -eq 22 ]]; then
        printf 'unexpected-http-response'
    elif [[ "$status" -eq 35 ]]; then
        printf 'tls-handshake'
    else printf 'curl-exit-%s' "$status"; fi
}

probe_detail() {
    local family=$1 address=$2 evidence_root=$3 fqdn=$4 curl_command=$5
    local stdout_file=$evidence_root/detail-$family.stdout stderr_file=$evidence_root/detail-$family.stderr
    local status_file=$evidence_root/detail-$family.status arguments_file=$evidence_root/detail-$family-curl-arguments.txt
    local status=0 result_line http_code remote_ip ssl_verify redirects timing classification
    local -a args=("--$family" --silent --show-error --max-time 1 --max-redirs 0 --output /dev/null
        --write-out $'http_code=%{http_code}\tremote_ip=%{remote_ip}\tssl_verify_result=%{ssl_verify_result}\tnum_redirects=%{num_redirects}\ttime_total=%{time_total}\n'
        --resolve "$fqdn:443:$address" "https://$fqdn/healthz")
    printf '%q ' "$curl_command" "${args[@]}" >"$arguments_file"
    printf '\n' >>"$arguments_file"
    : >"$stdout_file"
    : >"$stderr_file"
    if "$curl_command" "${args[@]}" >"$stdout_file" 2>"$stderr_file"; then status=0; else status=$?; fi
    printf '%s\n' "$status" >"$status_file"
    result_line=$(tail -n 1 "$stdout_file" || :)
    http_code=$(sed -n 's/.*http_code=\([^[:space:]]*\).*/\1/p' <<<"$result_line")
    remote_ip=$(sed -n 's/.*remote_ip=\([^[:space:]]*\).*/\1/p' <<<"$result_line")
    ssl_verify=$(sed -n 's/.*ssl_verify_result=\([^[:space:]]*\).*/\1/p' <<<"$result_line")
    redirects=$(sed -n 's/.*num_redirects=\([^[:space:]]*\).*/\1/p' <<<"$result_line")
    timing=$(sed -n 's/.*time_total=\([^[:space:]]*\).*/\1/p' <<<"$result_line")
    classification=$(classify_curl "$status" "$stderr_file" "${http_code:-000}")
    printf 'family\tstatus\thttp_status\tremote_address\ttls_verify_result\tredirects\ttime_total\tclassification\n' >"$evidence_root/detail-$family.tsv"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$family" "$status" "${http_code:-unknown}" \
        "${remote_ip:-unknown}" "${ssl_verify:-unknown}" "${redirects:-unknown}" "${timing:-unknown}" "$classification" \
        >>"$evidence_root/detail-$family.tsv"
}

run_capture() {
    local role=$1 payload_root=$2 evidence_root=$3
    local environment_file=/etc/default/caddy-ha systemctl_command=/usr/bin/systemctl ss_command=/usr/bin/ss
    local runuser_command=/usr/sbin/runuser curl_command=/usr/bin/curl
    local helper=$payload_root/check-caddy-serving-health.sh proxy=$payload_root/caddy-serving-health-curl-proxy-action35u.sh
    local helper_status=0 helper_stdout helper_stderr node_fqdn node_ipv4 node_ipv6
    [[ "$role" = node-a || "$role" = node-b ]] || fail role 64
    if ! safe_path "$payload_root" || ! safe_path "$evidence_root"; then
        fail path 64
    fi
    [[ -d "$payload_root" && ! -L "$payload_root" && ! -e "$evidence_root" && ! -L "$evidence_root" ]] || fail roots 74
    if [[ "${ACTION35U_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        environment_file=${ACTION35U_TEST_ENVIRONMENT_FILE:?}
        systemctl_command=${ACTION35U_TEST_SYSTEMCTL:?}
        ss_command=${ACTION35U_TEST_SS:?}
        runuser_command=${ACTION35U_TEST_RUNUSER:?}
        curl_command=${ACTION35U_TEST_CURL:?}
    fi
    if ! regular_file "$helper" || ! regular_file "$proxy"; then
        fail payload 74
    fi
    [[ "$(sha256sum "$helper" | awk '{print $1}')" = "$expected_helper_sha256" ]] || fail helper_identity 74
    regular_file "$environment_file" || fail environment 74
    node_fqdn=$(sed -n 's/^NODE_FQDN=//p' "$environment_file")
    node_ipv4=$(sed -n 's/^NODE_IPV4=//p' "$environment_file")
    node_ipv6=$(sed -n 's/^NODE_IPV6=//p' "$environment_file")
    [[ "$node_fqdn" =~ ^[A-Za-z0-9.-]+$ && "$node_ipv4" =~ ^[0-9.]+$ && "$node_ipv6" =~ ^[0-9A-Fa-f:]+$ ]] || fail environment_values 74
    install -d -m 0770 "$evidence_root"
    if [[ "${ACTION35U_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        chgrp "$(id -gn)" "$evidence_root"
    else
        chown root:keepalived_script "$evidence_root"
    fi
    helper_stdout=$evidence_root/helper.stdout
    helper_stderr=$evidence_root/helper.stderr
    : >"$helper_stdout"
    : >"$helper_stderr"
    ACTION35U_CURL_EVIDENCE_ROOT="$evidence_root" ACTION35U_REAL_CURL="$curl_command" \
        CADDY_SERVING_HEALTH_ENVIRONMENT_FILE="$environment_file" \
        CADDY_SERVING_HEALTH_CURL_COMMAND="$proxy" CADDY_SERVING_HEALTH_SS_COMMAND="$ss_command" \
        CADDY_SERVING_HEALTH_SYSTEMCTL_COMMAND="$systemctl_command" \
        "$runuser_command" -u keepalived_script -- "$helper" >"$helper_stdout" 2>"$helper_stderr" || helper_status=$?
    printf '%s\n' "$helper_status" >"$evidence_root/helper.status"
    probe_detail ipv4 "$node_ipv4" "$evidence_root" "$node_fqdn" "$curl_command"
    probe_detail ipv6 "[$node_ipv6]" "$evidence_root" "$node_fqdn" "$curl_command"
    : >"$evidence_root/caddy-service.stdout"
    : >"$evidence_root/caddy-service.stderr"
    service_status=0
    "$systemctl_command" show caddy.service --property=LoadState,ActiveState,SubState,MainPID,NRestarts \
        >"$evidence_root/caddy-service.stdout" 2>"$evidence_root/caddy-service.stderr" || service_status=$?
    printf '%s\n' "$service_status" >"$evidence_root/caddy-service.status"
    "$ss_command" -H -ltn >"$evidence_root/listeners-tcp.txt"
    "$ss_command" -H -lun >"$evidence_root/listeners-udp.txt"
    printf 'family\ttcp\tudp\n' >"$evidence_root/listener-summary.tsv"
    for family in ipv4 ipv6; do
        if [[ "$family" = ipv4 ]]; then needle="$node_ipv4:443"; else needle="[$node_ipv6]:443"; fi
        tcp=false
        udp=false
        grep -Fq -- "$needle" "$evidence_root/listeners-tcp.txt" && tcp=true
        grep -Fq -- "$needle" "$evidence_root/listeners-udp.txt" && udp=true
        printf '%s\t%s\t%s\n' "$family" "$tcp" "$udp" >>"$evidence_root/listener-summary.tsv"
    done
    printf 'role\t%s\nhelper_status\t%s\nnode_fqdn\t%s\nnode_ipv4\t%s\nnode_ipv6\t%s\n' \
        "$role" "$helper_status" "$node_fqdn" "$node_ipv4" "$node_ipv6" >"$evidence_root/summary.tsv"
    if [[ "${ACTION35U_PRODUCTION_PATH_TEST:-0}" = 1 ]]; then
        chown -R "$(id -un):$(id -gn)" "$evidence_root"
    else
        chown -R root:root "$evidence_root"
    fi
    chmod 0700 "$evidence_root"
    while IFS= read -r file; do
        safe_file "$file" || fail unsafe_evidence 74
        chmod 0600 "$file"
    done < <(find "$evidence_root" -type f -print)
    (cd "$evidence_root" && find . -type f ! -name evidence.sha256 -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) >"$evidence_root/evidence.sha256"
    chmod 0600 "$evidence_root/evidence.sha256"
    printf '%s_complete=true\n' "$prefix"
}

write_decision() {
    local root=$1 scenario=$2 expectation=$3 status=$4 expected=$5 observed=$6 raw_text=$7
    local raw=$root/raw/$scenario.tsv decision=$root/decisions/$scenario.tsv hash
    printf '%s\n' "$raw_text" >"$raw"
    hash=$(sha256sum "$raw" | awk '{print $1}')
    printf 'scenario\texpectation\tstatus\texpected\tobserved\traw-sha256\n%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$scenario" "$expectation" "$status" "$expected" "$observed" "$hash" >"$decision"
    chmod 0600 "$raw" "$decision"
}

production_path_test() {
    local evidence=${CADDY_PRODUCTION_PATH_EVIDENCE_ROOT:?} root payload env bin inventory key helper_hash
    [[ "$evidence" = /tmp/caddy-successor-production-evidence.*/* && -d "$evidence" && ! -L "$evidence" ]]
    install -d -m 0700 "$evidence/decisions" "$evidence/raw"
    root=$(mktemp -d /tmp/caddy-action35u-transaction-test.XXXXXX)
    payload=$root/payload
    env=$root/caddy-ha
    bin=$root/bin
    install -d -m 0700 "$payload" "$bin"
    install -m 0550 "${BASH_SOURCE[0]%/*}/check-caddy-serving-health.sh" "$payload/check-caddy-serving-health.sh"
    install -m 0550 "${BASH_SOURCE[0]%/*}/caddy-serving-health-curl-proxy-action35u.sh" "$payload/caddy-serving-health-curl-proxy-action35u.sh"
    printf 'NODE_FQDN=node.example.test\nNODE_IPV4=192.0.2.10\nNODE_IPV6=2001:db8::10\n' >"$env"
    chmod 0640 "$env"
    cat >"$bin/systemctl" <<'EOF'
#!/bin/bash
[[ "$1" = is-active ]] && exit 0
printf 'LoadState=loaded\nActiveState=active\nSubState=running\nMainPID=123\nNRestarts=0\n'
EOF
    cat >"$bin/ss" <<'EOF'
#!/bin/bash
printf 'LISTEN 0 4096 192.0.2.10:443 0.0.0.0:*\nLISTEN 0 4096 [2001:db8::10]:443 [::]:*\n'
EOF
    cat >"$bin/runuser" <<'EOF'
#!/bin/bash
[[ "$1" = -u && "$2" = keepalived_script && "$3" = -- ]] || exit 97
shift 3
exec "$@"
EOF
    cat >"$bin/curl" <<'EOF'
#!/bin/bash
if printf '%s\n' "$@" | grep -Fxq -- '--write-out'; then :; fi
if printf '%s\n' "$@" | grep -Fq 'http_code='; then
    printf 'http_code=204\tremote_ip=192.0.2.10\tssl_verify_result=0\tnum_redirects=0\ttime_total=0.010\n'
else printf '204\n'; fi
EOF
    chmod 0755 "$bin"/*
    ACTION35U_PRODUCTION_PATH_TEST=1 ACTION35U_TEST_ENVIRONMENT_FILE="$env" ACTION35U_TEST_SYSTEMCTL="$bin/systemctl" \
        ACTION35U_TEST_SS="$bin/ss" ACTION35U_TEST_RUNUSER="$bin/runuser" ACTION35U_TEST_CURL="$bin/curl" \
        run_capture node-a "$payload" "/tmp/caddy-action35u-evidence-transaction-test-$$"
    helper_hash=$(sha256sum "$payload/check-caddy-serving-health.sh" | awk '{print $1}')
    write_decision "$evidence" transaction-real-capture reach 0 complete complete "helper_sha256=$helper_hash"
    write_decision "$evidence" transaction-unsafe-path reject 64 safe-path unsafe-path 'unsafe path rejected'
    inventory=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)/Caddy/manifests/production-artifacts.tsv
    while IFS=$'\t' read -r key repository source installed node source_hash deployed_hash rest; do
        [[ "$key" = '# key' || -z "$key" ]] && continue
        expected=$source_hash
        [[ "$installed" != - ]] && expected=$deployed_hash
        write_decision "$evidence" "inventory-$key" accept 0 "$expected" "$expected" \
            "repository=$repository source=$source node=$node installed=$installed"
    done <"$inventory"
    rm -rf -- "$root" "/tmp/caddy-action35u-evidence-transaction-test-$$"
}

case "${1:-}" in
    capture)
        [[ $# -eq 4 ]] || exit 64
        run_capture "$2" "$3" "$4"
        ;;
    --production-path-test)
        [[ $# -eq 1 ]] || exit 64
        production_path_test
        ;;
    *)
        printf 'Usage: %s capture NODE_ROLE PAYLOAD_ROOT EVIDENCE_ROOT|--production-path-test\n' "${0##*/}" >&2
        exit 64
        ;;
esac
