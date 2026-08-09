#!/usr/bin/env bash

set -Eeuo pipefail
set +x
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
readonly caddy_root=${script_directory%/tests}
readonly inspector=$caddy_root/scripts/inspect-node-b-keepalived-dbus-postrollback-action20o-a-retry.sh
readonly outer=$caddy_root/scripts/run-node-b-keepalived-dbus-postrollback-action20o-a-retry-outer.sh
readonly regression=$script_directory/action20o-a-retry-node-b-postrollback-regression.sh
readonly shfmt_canonical=$script_directory/shfmt-canonical.sh

for action20oa_focused_file in "$inspector" "$outer" "$regression" "$0"; do
    [[ -f "$action20oa_focused_file" && -x "$action20oa_focused_file" ]] || exit 1
done
/bin/bash -n "$inspector" "$outer" "$regression" "$0"
shellcheck "$inspector" "$outer" "$regression" "$0"
/bin/bash "$shfmt_canonical" --check "$inspector" "$outer" "$regression" "$0"
/bin/bash "$script_directory/check-shell-readonly-local-collisions-v2.sh" "$inspector" "$outer" "$regression" "$0"
/bin/bash "$script_directory/multifile-grep-count-policy.sh" --check "$inspector" "$outer" "$regression" "$0"
/bin/bash "$script_directory/portable-awk-policy.sh" --check "$inspector" "$outer" "$regression" "$0"
/bin/bash "$inspector" --self-test
/bin/bash "$regression"
grep -Fq 'ip -o -4 address show dev ' "$inspector"
grep -Fq 'ip -o -6 address show dev ' "$inspector"
if grep -Eq 'ip -o[[:space:]]+"?\$[^ ]*family|ip -o[[:space:]]+"?[46]"?' "$inspector"; then
    exit 1
fi
grep -Fq ' -eq 0 ]] || return 1' "$inspector"
if grep -Eq 'systemctl[[:space:]]+(reload|restart)|busctl[^\n]*tree|(^|[[:space:]])(install|mv|cp|rm)[[:space:]]' "$inspector"; then
    exit 1
fi
grep -Fq 'normalize_dbus_list_for_snapshot' "$inspector"
grep -Fq 'normalized_dbus_hash' "$inspector"
grep -Fq "\$3 != \"busctl\"" "$inspector"
grep -Fq 'org.keepalived.Vrrp1' "$inspector"
grep -Fq '/org/keepalived/Vrrp1/Instance/eth0/110/IPv4' "$inspector"
grep -Fq "'cd / && sudo -n /bin/bash -s --'" "$outer"
printf '%s\n' \
    action_20o_a_retry_focused_node_b_contacted=false \
    action_20o_a_retry_focused_node_a_contacted=false \
    action_20o_a_retry_focused_reload=false \
    action_20o_a_retry_focused_correction=false \
    action_20o_a_retry_focused_complete=true
