#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_25_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-dual-node-pihole-web-access-action25.sh
readonly outer=$caddy_root/scripts/run-dual-node-pihole-web-access-action25-outer.sh

record_check() {
    local action25_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_%s=true\n' "$prefix" "$action25_regression_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action25_regression_label" >&2
    return 1
}
expect_rejected() {
    local action25_regression_transcript=$1
    local action25_regression_stderr=$2

    ! /bin/bash "$outer" --validate-transcript node-a "$action25_regression_transcript" 0 \
        "$action25_regression_stderr" >/dev/null 2>&1
}

action25_regression_root=$(mktemp -d /tmp/caddy-action25-regression.XXXXXX)
readonly action25_regression_root
trap 'rm -rf -- "$action25_regression_root"' EXIT INT TERM

cat >"$action25_regression_root/fake-curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >"${CADDY_ACTION25_CURL_LOG:?}"
resolve=
url=
while (($#)); do
    case "$1" in
        --resolve)
            resolve=$2
            shift 2
            ;;
        http*)
            url=$1
            shift
            ;;
        *) shift ;;
    esac
done
remote=${resolve#*:*:}
remote=${remote#[}
remote=${remote%]}
printf '<html><title>Pi-hole</title></html>\n'
printf 'action25-metadata|200|%s|%s\n' "$url" "$remote"
EOF
chmod 0700 "$action25_regression_root/fake-curl"

CADDY_ACTION25_CURL_BIN="$action25_regression_root/fake-curl" \
    CADDY_ACTION25_CURL_LOG="$action25_regression_root/curl.args" \
    /bin/bash "$inspector" --probe-test node-a shared_ipv6 \
    >"$action25_regression_root/probe.stdout" 2>"$action25_regression_root/probe.stderr"
record_check probe_stderr_empty test ! -s "$action25_regression_root/probe.stderr"
record_check probe_command_status grep -Fqx 'action_25_node_a_check_shared_ipv6_command_status=true' \
    "$action25_regression_root/probe.stdout"
record_check probe_http_200 grep -Fqx 'action_25_node_a_check_shared_ipv6_http_200=true' \
    "$action25_regression_root/probe.stdout"
record_check probe_remote_ip_exact grep -Fqx \
    'action_25_node_a_value_shared_ipv6_remote_ip=fd36:5aa8:6971:1::56' \
    "$action25_regression_root/probe.stdout"
record_check production_http11_once test \
    "$(grep -Eoc '(^| )--http1[.]1( |$)' "$action25_regression_root/curl.args" || true)" -eq 1
record_check production_insecure_once test \
    "$(grep -Eoc '(^| )--insecure( |$)' "$action25_regression_root/curl.args" || true)" -eq 1
record_check production_resolve_exact grep -Fq \
    'pihole-admin.local.theama.co:443:[fd36:5aa8:6971:1::56]' \
    "$action25_regression_root/curl.args"
record_check production_admin_url_exact grep -Fq \
    'https://pihole-admin.local.theama.co/admin/' "$action25_regression_root/curl.args"

cat >"$action25_regression_root/fake-ssh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
payload=$(mktemp /tmp/caddy-action25-fake-ssh.XXXXXX)
trap 'rm -f -- "$payload"' EXIT
sed -n '1,$p' >"$payload"
chmod 0700 "$payload"
case " $* " in
    *' pi@10.1.0.53 '*'--node node-a'*) /bin/bash "$payload" --self-test-node node-a ;;
    *' pi@10.1.0.54 '*'--node node-b'*) /bin/bash "$payload" --self-test-node node-b ;;
    *) exit 91 ;;
esac
EOF
chmod 0700 "$action25_regression_root/fake-ssh"

action25_regression_outer_status=0
CADDY_ACTION25_SKIP_REGRESSION=true \
    CADDY_ACTION25_SSH_BIN="$action25_regression_root/fake-ssh" \
    /bin/bash "$outer" >"$action25_regression_root/success.stdout" \
    2>"$action25_regression_root/success.stderr" || action25_regression_outer_status=$?
if [[ "$action25_regression_outer_status" -ne 0 ]]; then
    printf '%s_outer_status=%s\n' "$prefix" "$action25_regression_outer_status" >&2
    printf '%s_outer_stdout_begin\n' "$prefix" >&2
    sed -n '1,500p' "$action25_regression_root/success.stdout" >&2
    printf '%s_outer_stdout_end\n' "$prefix" >&2
    printf '%s_outer_stderr_begin\n' "$prefix" >&2
    sed -n '1,500p' "$action25_regression_root/success.stderr" >&2
    printf '%s_outer_stderr_end\n' "$prefix" >&2
    exit "$action25_regression_outer_status"
fi
record_check success_status_zero test "$action25_regression_outer_status" -eq 0
record_check success_stderr_empty test ! -s "$action25_regression_root/success.stderr"
record_check success_complete grep -Fqx 'action_25_outer_complete=true' \
    "$action25_regression_root/success.stdout"
record_check node_a_contacted grep -Fqx 'action_25_outer_node_a_contacted=true' \
    "$action25_regression_root/success.stdout"
record_check node_b_contacted grep -Fqx 'action_25_outer_node_b_contacted=true' \
    "$action25_regression_root/success.stdout"
record_check read_only grep -Fqx 'action_25_outer_read_only=true' \
    "$action25_regression_root/success.stdout"

/bin/bash "$inspector" --self-test-node node-a >"$action25_regression_root/transcript"
: >"$action25_regression_root/empty.stderr"
record_check exact_transcript_accepted /bin/bash "$outer" --validate-transcript node-a \
    "$action25_regression_root/transcript" 0 "$action25_regression_root/empty.stderr"

sed '/action_25_node_a_check_uid_root=true/d' "$action25_regression_root/transcript" \
    >"$action25_regression_root/missing"
record_check missing_check_rejected expect_rejected "$action25_regression_root/missing" \
    "$action25_regression_root/empty.stderr"
sed 's/action_25_node_a_check_uid_root=true/action_25_node_a_check_uid_root=false/' \
    "$action25_regression_root/transcript" >"$action25_regression_root/false"
record_check false_check_rejected expect_rejected "$action25_regression_root/false" \
    "$action25_regression_root/empty.stderr"
cp "$action25_regression_root/transcript" "$action25_regression_root/duplicate"
grep -F 'action_25_node_a_check_uid_root=true' "$action25_regression_root/transcript" \
    >>"$action25_regression_root/duplicate"
record_check duplicate_check_rejected expect_rejected "$action25_regression_root/duplicate" \
    "$action25_regression_root/empty.stderr"
awk 'NR == 1 { first=$0; next } NR == 2 { print; print first; next } { print }' \
    "$action25_regression_root/transcript" >"$action25_regression_root/reordered"
record_check reordered_check_rejected expect_rejected "$action25_regression_root/reordered" \
    "$action25_regression_root/empty.stderr"
cp "$action25_regression_root/transcript" "$action25_regression_root/extra"
printf 'action_25_node_a_check_unexpected=true\n' >>"$action25_regression_root/extra"
record_check extra_check_rejected expect_rejected "$action25_regression_root/extra" \
    "$action25_regression_root/empty.stderr"
printf 'bounded failure\n' >"$action25_regression_root/nonempty.stderr"
record_check stderr_rejected expect_rejected "$action25_regression_root/transcript" \
    "$action25_regression_root/nonempty.stderr"
if /bin/bash "$outer" --validate-transcript node-a "$action25_regression_root/transcript" 1 \
    "$action25_regression_root/empty.stderr" >/dev/null 2>&1; then
    printf '%s_nonzero_status_rejected=false\n' "$prefix" >&2
    exit 1
fi
printf '%s_nonzero_status_rejected=true\n' "$prefix"

record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$inspector" "$outer" "$0"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
