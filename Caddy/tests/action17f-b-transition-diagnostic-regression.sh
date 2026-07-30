#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
caddy_root=$(cd -- "$script_dir/.." && pwd)
readonly caddy_root
readonly diagnostic="$caddy_root/scripts/diagnose-node-b-unbound-action17f-transition.sh"
readonly driver="$caddy_root/scripts/stage-node-b-unbound-local-zone-action17f.sh"

bash -n "$diagnostic"
"$diagnostic" --self-test >/dev/null

for function_name in file_hash live_state validate_primary_stage validate_baseline; do
    diff -u \
        <(sed -n "/^${function_name}()/,/^}/p" "$driver") \
        <(sed -n "/^${function_name}()/,/^}/p" "$diagnostic")
done

grep -Fq 'transition_validate_baseline_status=' "$diagnostic"
grep -Fq 'transition_live_state_assignment_status=' "$diagnostic"
grep -Fq 'transition_snapshot_readonly_status=' "$diagnostic"
grep -Fq 'transition_snapshot_hash_status=' "$diagnostic"
grep -Fq 'transition_snapshot_hash_readonly_status=' "$diagnostic"
grep -Fq 'transition_exact_failure_step=' "$diagnostic"
grep -Fq 'transition_exact_block_status=' "$diagnostic"
grep -Fq 'action_17f_b_transition_diagnostic_complete=true' "$diagnostic"

if grep -Eq \
    '^[[:space:]]*(rm|install|cp|mv|touch|chmod|chown|tee|truncate|mkdir|mktemp)([[:space:]]|$)' \
    "$diagnostic"; then
    printf 'Action 17f-b diagnostic contains a filesystem mutation.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' \
    "$diagnostic"; then
    printf 'Action 17f-b diagnostic contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(ssh|rsync|scp|sftp)([[:space:]]|$)' \
    "$diagnostic"; then
    printf 'Action 17f-b diagnostic must not make a peer connection.\n' >&2
    exit 1
fi

for pinned_value in \
    8808b474175ff8eeebecbf407f9091fd73f65c4a43a6ee212e8ae2d9f80778f8 \
    017aa2556346c93a64a3571dcb49046fb858edd358937339bc5f7e60d145fac7 \
    3a05c0487101f3b44f8e5ba41a4a74713d07cddc369542f04d4a8b1f417cb824 \
    cef0349528f87e97362c5917f1d0f77baca92eebf04790ed96997dfe3a0dd2e8; do
    grep -Fq "$pinned_value" "$diagnostic"
    grep -Fq "$pinned_value" "$driver"
done

printf 'action_17f_b_transition_diagnostic_regression_complete=true\n'
