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
readonly diagnostic="$caddy_root/scripts/inspect-node-a-unbound-semantic-diff-action17h-a.sh"
readonly prior_inspector="$caddy_root/scripts/inspect-node-a-two-file-unbound-preflight-action17h.sh"
readonly runner="$caddy_root/scripts/run-node-a-unbound-semantic-diff-action17h-a.sh"
readonly collision_checker="$script_dir/check-shell-readonly-local-collisions.sh"

bash -n "$diagnostic" "$prior_inspector" "$runner"
"$diagnostic" --self-test >/dev/null
"$prior_inspector" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null
"$collision_checker" "$diagnostic" "$prior_inspector" "$runner" >/dev/null

grep -Fq 'expected_assertion_count=29' "$diagnostic"
grep -Fq 'expected_difference_count=24' "$diagnostic"
grep -Fq 'expected_difference_count=24' "$runner"
grep -Fq 'prior_false_labels' "$diagnostic"
grep -Fq 'live_only_directive_count,normalized_sha256' "$diagnostic"
grep -Fq 'action_17h_a_%s_%03d_b64=%s' "$diagnostic"
grep -Fq 'emit_difference_records live_only' "$diagnostic"
grep -Fq 'emit_difference_records candidate_only' "$diagnostic"
grep -Fq 'action_17h_a_%s_directive_%03d=%s' "$runner"
grep -Fq 'cd /' "$runner"
grep -Fq 'action_17h_a_remote_stage_cleanup_complete=true' "$runner"
grep -Fq 'service_mutations=false' "$diagnostic"
grep -Fq 'persistent_mutations=false' "$diagnostic"

if grep -Eq \
    '(rm|install|cp|mv|chmod|chown|touch|truncate)[^\n]*(/etc/unbound|/var/lib/unbound|/etc/pihole)' \
    "$diagnostic"; then
    printf 'Action 17h-a writes to a persistent DNS path.\n' >&2
    exit 1
fi
if grep -Eq \
    'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|reset-failed)|unbound-control|(^|[[:space:]])dig([[:space:]]|$)' \
    "$diagnostic"; then
    printf 'Action 17h-a contains a DNS query or service mutation.\n' >&2
    exit 1
fi

printf 'action_17h_a_node_a_semantic_diff_regression_complete=true\n'
