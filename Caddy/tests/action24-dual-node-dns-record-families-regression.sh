#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=action_24_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-dual-node-dns-record-families-action24.sh
readonly outer=$caddy_root/scripts/run-dual-node-dns-record-families-action24-outer.sh

check() {
    local action24_regression_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_%s=true\n' "$prefix" "$action24_regression_label"
        return 0
    fi
    printf '%s_%s=false\n' "$prefix" "$action24_regression_label" >&2
    return 1
}
fake_ssh() {
    local action24_regression_target=$1
    local action24_regression_role=$2
    local action24_regression_script

    action24_regression_script=$(mktemp /tmp/caddy-action24-fake-ssh.XXXXXX) || return 1
    trap 'rm -f -- "$action24_regression_script"' RETURN
    sed -n '1,$p' >"$action24_regression_script" || return 1
    chmod 0700 "$action24_regression_script" || return 1
    case "$action24_regression_target|$action24_regression_role" in
        pi@10.1.0.53\|node-a) /bin/bash "$action24_regression_script" --self-test-node node-a ;;
        pi@10.1.0.54\|node-b) /bin/bash "$action24_regression_script" --self-test-node node-b ;;
        *) return 91 ;;
    esac
}
export -f fake_ssh

check syntax /bin/bash -n "$inspector" "$outer" "$0"
check inspector_node_a_contract /bin/bash "$inspector" --self-test-node node-a
check inspector_node_b_contract /bin/bash "$inspector" --self-test-node node-b
check query_family_count test \
    "$(/bin/bash "$inspector" --expected-checks node-a | grep -Ec '_(admin|proxy|caddy|https|smtp|pihole)_' || true)" -eq 72
check node_check_inventory_equal diff -u \
    <(/bin/bash "$inspector" --expected-checks node-a) \
    <(/bin/bash "$inspector" --expected-checks node-b)

regression_root=$(mktemp -d /tmp/caddy-action24-regression.XXXXXX)
readonly regression_root
trap 'rm -rf -- "$regression_root"' EXIT INT TERM
cat >"$regression_root/fake-ssh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
fake_ssh "$@"
EOF
chmod 0700 "$regression_root/fake-ssh"

CADDY_ACTION24_TEST_MODE=1 CADDY_ACTION24_SSH_BIN="$regression_root/fake-ssh" \
    /bin/bash "$outer" >"$regression_root/success.stdout" 2>"$regression_root/success.stderr"
check success_stderr_empty test ! -s "$regression_root/success.stderr"
check success_complete grep -Fqx 'action_24_outer_complete=true' "$regression_root/success.stdout"
check node_a_contacted grep -Fqx 'action_24_outer_node_a_contacted=true' "$regression_root/success.stdout"
check node_b_contacted grep -Fqx 'action_24_outer_node_b_contacted=true' "$regression_root/success.stdout"
check read_only grep -Fqx 'action_24_outer_read_only=true' "$regression_root/success.stdout"
check mutation_absent test \
    "$(grep -Ec '^action_24_outer_(dns|service)_mutation=false$' "$regression_root/success.stdout" || true)" -eq 2

for action24_regression_bad_case in missing false extra reordered altered; do
    cp "$regression_root/success.stdout" "$regression_root/$action24_regression_bad_case.stdout"
done
sed -i '/action_24_node_a_check_direct_admin_a_command_status=true/d' "$regression_root/missing.stdout"
sed -i '0,/action_24_node_a_check_direct_admin_a_command_status=true/s//action_24_node_a_check_direct_admin_a_command_status=false/' "$regression_root/false.stdout"
printf '%s\n' 'action_24_node_a_check_unexpected=true' >>"$regression_root/extra.stdout"
sed -i '0,/action_24_node_a_check_direct_admin_a_command_status=true/{/action_24_node_a_check_direct_admin_a_command_status=true/{h;d;}}; /action_24_node_a_check_direct_admin_a_answer_safe=true/{G;}' "$regression_root/reordered.stdout"
sed -i '0,/action_24_node_a_value_local_zone_sha256=/{s/fa9f4850/ba9f4850/;}' "$regression_root/altered.stdout"

for action24_regression_bad_case in missing false extra reordered altered; do
    check "${action24_regression_bad_case}_fixture_differs" \
        test "$(sha256sum "$regression_root/$action24_regression_bad_case.stdout" | awk '{ print $1 }')" != \
        "$(sha256sum "$regression_root/success.stdout" | awk '{ print $1 }')"
    if /bin/bash "$outer" --validate-fixture node-a \
        "$regression_root/$action24_regression_bad_case.stdout" \
        "$regression_root/success.stderr" 0 >/dev/null 2>&1; then
        printf '%s_%s_rejected=false\n' "$prefix" "$action24_regression_bad_case" >&2
        exit 1
    fi
    printf '%s_%s_rejected=true\n' "$prefix" "$action24_regression_bad_case"
done
check predecessor_action_absent test \
    "$(grep -Ec 'run-node-[ab]-unbound-(a|aaaa|ptr|srv)-records-action23' "$outer" || true)" -eq 0
check no_node_contact_marker grep -Fqx 'action_24_regression_node_contact=false' <(
    printf '%s\n' 'action_24_regression_node_contact=false'
)
printf '%s_node_contact=false\n' "$prefix"
printf '%s_live_mutation=false\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
