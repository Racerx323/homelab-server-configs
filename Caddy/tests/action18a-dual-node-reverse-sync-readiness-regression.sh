#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root="${test_directory%/tests}"
readonly inspector="$caddy_root/scripts/inspect-reverse-sync-readiness-action18a.sh"
readonly runner="$caddy_root/scripts/run-dual-node-reverse-sync-readiness-action18a.sh"

bash -n "$inspector" "$runner"
"$inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null

[[ "$(grep -Ec '^record_command [a-z0-9_]+ ' "$inspector")" -ge 50 ]]
grep -Fq 'publisher_requires_emergency' "$inspector"
grep -Fq 'publisher_requires_master' "$inspector"
grep -Fq 'authorization_v2_exact' "$inspector"
grep -Fq 'receiver_v2_hash_exact' "$inspector"
grep -Fq 'release_parent_exact' "$inspector"
grep -Fq 'ipv4_bind_address_exact' "$inspector"
grep -Fq 'ipv6_bind_address_exact' "$inspector"
grep -Fq 'IdentitiesOnly=yes' "$inspector"
# Literal source contract; expansion is intentionally suppressed.
# shellcheck disable=SC2016
grep -Fq 'identityfile "$private_key"' "$inspector"
grep -Fq 'prerequisites_required_before_action18' "$runner"
# Literal source contracts; expansion is intentionally suppressed.
# shellcheck disable=SC2016
grep -Fq "printf '%s_cross_node_%s_exact=true" "$runner"
grep -Fq 'revision parent_revision payload_sha256 manifest_sha256' "$runner"

if grep -Eq 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)' "$inspector"; then
    printf 'Action 18a inspector contains a service mutation.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(rsync|scp|sftp)([[:space:]]|$)' "$inspector"; then
    printf 'Action 18a inspector contains a peer-transfer command.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*ssh[[:space:]]+(-[46][[:space:]]+)?[^-G]' "$inspector"; then
    printf 'Action 18a inspector contains a connecting SSH command.\n' >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*(install|cp|mv|touch|chmod|chown|tee|truncate)([[:space:]]|$)' "$inspector"; then
    printf 'Action 18a inspector contains a persistent write command.\n' >&2
    exit 1
fi

printf 'action_18a_dual_node_reverse_sync_readiness_regression_complete=true\n'
