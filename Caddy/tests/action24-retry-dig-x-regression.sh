#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_24_retry_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly retry_outer=$caddy_root/scripts/run-dual-node-dns-record-families-action24-retry-outer.sh

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
check() {
    local action24_retry_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_%s=true\n' "$prefix" "$action24_retry_regression_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action24_retry_regression_label" >&2
    return 1
}

regression_root=$(mktemp -d /tmp/caddy-action24-retry-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT INT TERM
/bin/bash "$retry_outer" --render-hashes >"$regression_root/hashes"
rendered_inspector_hash=$(sed -n 's/^rendered_inspector_sha256=//p' "$regression_root/hashes")
readonly rendered_inspector_hash
rendered_core_hash=$(sed -n 's/^rendered_core_sha256=//p' "$regression_root/hashes")
readonly rendered_core_hash

check rendered_inspector_hash_valid test "${#rendered_inspector_hash}" -eq 64
check rendered_core_hash_valid test "${#rendered_core_hash}" -eq 64

cat >"$regression_root/fake-dig" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >"${CADDY_ACTION24_RETRY_DIG_LOG:?}"
printf '%s\n' 'proxy.local.theama.co.'
EOF
chmod 0700 "$regression_root/fake-dig"

# The retry outer renders into a protected temporary root. Reproduce only its
# deterministic render interface for the production-function command test.
awk '/^render_inspector\(\)/,/^}/ { print }' "$retry_outer" >"$regression_root/render-function.txt"
check render_function_present test -s "$regression_root/render-function.txt"

source_inspector=$caddy_root/scripts/inspect-dual-node-dns-record-families-action24.sh
readonly source_inspector
{
    sed -n '1p' "$source_inspector"
    sed -n "/^        cat <<'SHIM'$/,/^SHIM$/p" "$retry_outer" | sed '1d;$d'
    sed -n '2,$p' "$source_inspector"
} >"$regression_root/rendered-inspector"
chmod 0700 "$regression_root/rendered-inspector"
check rendered_inspector_exact_hash test "$(file_hash "$regression_root/rendered-inspector")" = "$rendered_inspector_hash"

CADDY_ACTION24_RETRY_DIG_BIN="$regression_root/fake-dig" \
    CADDY_ACTION24_RETRY_DIG_LOG="$regression_root/dig.log" \
    /bin/bash "$regression_root/rendered-inspector" --retry-ptr-command-test \
    >"$regression_root/ptr.stdout" 2>"$regression_root/ptr.stderr"
check ptr_command_stderr_empty test ! -s "$regression_root/ptr.stderr"
check ptr_command_answer_exact grep -Fqx 'proxy.local.theama.co.' "$regression_root/ptr.stdout"
check ptr_command_reverse_flag_exact test "$(grep -Eoc '(^| )-x( |$)' "$regression_root/dig.log" || true)" -eq 1
check ptr_command_address_exact test "$(grep -Eoc '(^| )10[.]1[.]0[.]56( |$)' "$regression_root/dig.log" || true)" -eq 1
check ptr_command_literal_type_absent test "$(grep -Eoc '(^| )PTR( |$)' "$regression_root/dig.log" || true)" -eq 0

cat >"$regression_root/fake-ssh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
target=$1
role=$2
payload=$(mktemp /tmp/caddy-action24-retry-fake-ssh.XXXXXX)
trap 'rm -f -- "$payload"' EXIT
sed -n '1,$p' >"$payload"
chmod 0700 "$payload"
case "$target|$role" in
    pi@10.1.0.53\|node-a) /bin/bash "$payload" --self-test-node node-a ;;
    pi@10.1.0.54\|node-b) /bin/bash "$payload" --self-test-node node-b ;;
    *) exit 91 ;;
esac
EOF
chmod 0700 "$regression_root/fake-ssh"

action24_retry_regression_outer_status=0
CADDY_ACTION24_RETRY_TEST_MODE=1 \
    CADDY_ACTION24_RETRY_SSH_BIN="$regression_root/fake-ssh" \
    /bin/bash "$retry_outer" >"$regression_root/success.stdout" 2>"$regression_root/success.stderr" ||
    action24_retry_regression_outer_status=$?
if [[ "$action24_retry_regression_outer_status" -ne 0 ]]; then
    printf '%s_outer_status=%s\n' "$prefix" "$action24_retry_regression_outer_status" >&2
    printf '%s_outer_stdout_begin\n' "$prefix" >&2
    sed -n '1,400p' "$regression_root/success.stdout" >&2
    printf '%s_outer_stdout_end\n' "$prefix" >&2
    printf '%s_outer_stderr_begin\n' "$prefix" >&2
    sed -n '1,400p' "$regression_root/success.stderr" >&2
    printf '%s_outer_stderr_end\n' "$prefix" >&2
    exit "$action24_retry_regression_outer_status"
fi
check success_status_zero test "$action24_retry_regression_outer_status" -eq 0
check success_stderr_empty test ! -s "$regression_root/success.stderr"
check success_complete grep -Fqx 'action_24_retry_outer_complete=true' "$regression_root/success.stdout"
check observed_count grep -Fqx 'action_24_retry_outer_observed_ptr_count=16' "$regression_root/success.stdout"
check node_a_contacted grep -Fqx 'action_24_retry_outer_node_a_contacted=true' "$regression_root/success.stdout"
check node_b_contacted grep -Fqx 'action_24_retry_outer_node_b_contacted=true' "$regression_root/success.stdout"
check read_only grep -Fqx 'action_24_retry_outer_read_only=true' "$regression_root/success.stdout"
check predecessor_outer_not_invoked test \
    "$(grep -Ec '/bin/bash.*run-dual-node-dns-record-families-action24-outer[.]sh' "$retry_outer" || true)" -eq 0
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
