#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_27_retry3
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly immutable_retry2=$script_directory/run-workstation-caddy-tls-action27-retry2.sh
readonly executed_retry2_outer=$script_directory/run-workstation-caddy-tls-action27-retry2-outer.sh
readonly immutable_retry2_sha256=039dedbde868d795132b5b2ad538f7be2720ddf3c4dd53c2ea909e90f45b05e1
readonly executed_retry2_outer_sha256=2f183a44de5ccca561cacc1e274f8609d2b1e69187410b3fbab033ce5b54cb01
readonly raw_curl_bin=${CADDY_ACTION27_RETRY3_RAW_CURL_BIN:-/usr/bin/curl}
action27_retry3_root=

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action27_retry3_check_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action27_retry3_check_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action27_retry3_check_label" >&2
    return 1
}
expected_checks() {
    printf '%s\n' immutable_retry2_hash executed_retry2_outer_hash raw_curl_executable \
        adapter_regular adapter_executable adapter_path_contract adapter_argument_contract
}
create_adapter() {
    local action27_retry3_adapter=$1

    cat >"$action27_retry3_adapter" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH
readonly raw_curl_bin=${CADDY_ACTION27_RETRY3_RAW_CURL_BIN:-/usr/bin/curl}
readonly inherited_url=https://proxy.local.theama.co/healthz
readonly corrected_url=https://proxy.local.theama.co/
rewritten_count=0
corrected_arguments=()
for supplied_argument in "$@"; do
    if [[ "$supplied_argument" = "$inherited_url" ]]; then
        corrected_arguments+=("$corrected_url")
        rewritten_count=$((rewritten_count + 1))
    else
        corrected_arguments+=("$supplied_argument")
    fi
done
[[ "$rewritten_count" -eq 1 ]] || exit 65
exec "$raw_curl_bin" "${corrected_arguments[@]}"
EOF
    chmod 0700 "$action27_retry3_adapter"
}
adapter_path_contract() {
    grep -Fq 'readonly inherited_url=https://proxy.local.theama.co/healthz' "$0" || return 1
    grep -Fq 'readonly corrected_url=https://proxy.local.theama.co/' "$0"
}
adapter_argument_contract() {
    # These patterns intentionally match literal adapter source.
    # shellcheck disable=SC2016
    grep -Fq '[[ "$rewritten_count" -eq 1 ]] || exit 65' "$0" || return 1
    # shellcheck disable=SC2016
    grep -Fq 'exec "$raw_curl_bin" "${corrected_arguments[@]}"' "$0"
}
cleanup() {
    local action27_retry3_status=$?

    trap - EXIT INT TERM
    [[ -z "$action27_retry3_root" ]] || rm -rf -- "$action27_retry3_root"
    exit "$action27_retry3_status"
}
run_action() {
    local action27_retry3_adapter

    action27_retry3_root=$(mktemp -d /tmp/caddy-action27-retry3.XXXXXX)
    trap cleanup EXIT INT TERM
    action27_retry3_adapter=$action27_retry3_root/curl-path-adapter
    check immutable_retry2_hash test "$(file_hash "$immutable_retry2")" = \
        "$immutable_retry2_sha256" || return 1
    check executed_retry2_outer_hash test "$(file_hash "$executed_retry2_outer")" = \
        "$executed_retry2_outer_sha256" || return 1
    check raw_curl_executable test -x "$raw_curl_bin" || return 1
    create_adapter "$action27_retry3_adapter" || return 1
    check adapter_regular test -f "$action27_retry3_adapter" || return 1
    check adapter_executable test -x "$action27_retry3_adapter" || return 1
    check adapter_path_contract adapter_path_contract || return 1
    check adapter_argument_contract adapter_argument_contract || return 1
    printf '%s_curl_path_scope=/healthz_to_root_only\n' "$prefix"
    CADDY_ACTION27_CURL_BIN=$action27_retry3_adapter \
        /bin/bash "$immutable_retry2"
}

case "${1:-}" in
    --expected-checks) expected_checks ;;
    --expected-retry2-checks) /bin/bash "$immutable_retry2" --expected-checks ;;
    --expected-core-checks) /bin/bash "$immutable_retry2" --expected-core-checks ;;
    "") run_action ;;
    *) exit 64 ;;
esac
