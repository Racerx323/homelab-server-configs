#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_27_retry
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly immutable_core=$script_directory/run-workstation-caddy-tls-action27.sh
readonly immutable_core_sha256=b39eeff2a60beefd4b9e0528a54dda63e6a0f150881b01183a2fc0066efdbfad
readonly raw_openssl_bin=${CADDY_ACTION27_RETRY_RAW_OPENSSL_BIN:-/usr/bin/openssl}
action27_retry_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action27_retry_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action27_retry_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action27_retry_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' immutable_core_hash raw_openssl_executable adapter_regular \
        adapter_executable adapter_contract_exact
}
adapter_contract_exact() {
    grep -Fqx "readonly raw_openssl_bin=\${CADDY_ACTION27_RETRY_RAW_OPENSSL_BIN:-/usr/bin/openssl}" \
        "$0" || return 1
    grep -Fqx "            -e 's/^[[:space:]]*Verify[[:space:]]+return[[:space:]]+code:[[:space:]]*0[[:space:]]+\\(ok\\)[[:space:]]*$/Verify return code: 0 (ok)/'" \
        "$0" || return 1
}
create_adapter() {
    local action27_retry_adapter=$1

    cat >"$action27_retry_adapter" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH
readonly raw_openssl_bin=${CADDY_ACTION27_RETRY_RAW_OPENSSL_BIN:-/usr/bin/openssl}
if [[ "${1:-}" = s_client ]]; then
    "$raw_openssl_bin" "$@" 2>&1 |
        /usr/bin/sed -E \
            -e 's/^[[:space:]]*Verify[[:space:]]+return[[:space:]]+code:[[:space:]]*0[[:space:]]+\(ok\)[[:space:]]*$/Verify return code: 0 (ok)/'
    exit "${PIPESTATUS[0]}"
fi
exec "$raw_openssl_bin" "$@"
EOF
    chmod 0700 "$action27_retry_adapter"
}
cleanup() {
    local action27_retry_status=$?

    trap - EXIT INT TERM
    [[ -z "$action27_retry_root" ]] || rm -rf -- "$action27_retry_root"
    exit "$action27_retry_status"
}
run_action() {
    local action27_retry_adapter

    action27_retry_root=$(mktemp -d /tmp/caddy-action27-retry.XXXXXX)
    trap cleanup EXIT INT TERM
    action27_retry_adapter=$action27_retry_root/openssl-normalizer
    check immutable_core_hash test "$(file_hash "$immutable_core")" = \
        "$immutable_core_sha256" || return 1
    check raw_openssl_executable test -x "$raw_openssl_bin" || return 1
    create_adapter "$action27_retry_adapter" || return 1
    check adapter_regular test -f "$action27_retry_adapter" || return 1
    check adapter_executable test -x "$action27_retry_adapter" || return 1
    check adapter_contract_exact adapter_contract_exact || return 1
    printf '%s_normalization_scope=exact_success_verification_line_whitespace_only\n' "$prefix"
    CADDY_ACTION27_OPENSSL_BIN=$action27_retry_adapter /bin/bash "$immutable_core"
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    --expected-core-checks) /bin/bash "$immutable_core" --expected-checks ;;
    "") run_action ;;
    *) exit 64 ;;
esac
