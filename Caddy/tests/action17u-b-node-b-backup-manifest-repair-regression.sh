#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
caddy_root=$(cd -- "$script_directory/.." && pwd)
readonly caddy_root
readonly repair="$caddy_root/scripts/repair-node-b-action17u-backup-manifest-action17u-b.sh"
readonly runner="$caddy_root/scripts/run-node-b-action17u-backup-manifest-repair-action17u-b.sh"
readonly collision_checker="$script_directory/check-shell-readonly-local-collisions.sh"
readonly expected_repair_sha256=c47653c285e7e3db98ed22b163c7f741d781f9d27f6c8feb1293bb70706eb0de
readonly expected_old_manifest_sha256=8b7ee379963bec0932dece5b11dd602efba33fe5d76a6e281c4db0c93b60dfbf
readonly expected_new_manifest_sha256=a992c2ff9bdfde76770ddae910dedfc2a8bbdf6ad25de909ec5cbeacda31d70b

file_hash() {
    sha256sum "$1" | awk '{ print $1 }'
}

require_absent() {
    if grep "$@"; then
        return 1
    fi
}

[[ -f "$repair" && ! -L "$repair" ]]
[[ -f "$runner" && ! -L "$runner" ]]
[[ "$(stat -c '%a' "$repair")" == 755 ]]
[[ "$(stat -c '%a' "$runner")" == 755 ]]
[[ "$(file_hash "$repair")" == "$expected_repair_sha256" ]]
grep -Fqx "readonly repair_sha256=$expected_repair_sha256" "$runner"
grep -Fqx "readonly old_manifest_sha256=$expected_old_manifest_sha256" "$repair"
grep -Fqx "readonly new_manifest_sha256=$expected_new_manifest_sha256" "$repair"
grep -Fqx "readonly old_manifest_sha256=$expected_old_manifest_sha256" "$runner"
grep -Fqx "readonly new_manifest_sha256=$expected_new_manifest_sha256" "$runner"

bash -n "$repair" "$runner"
"$collision_checker" "$repair" "$runner" >/dev/null
"$repair" --self-test >/dev/null
"$runner" --self-test >/dev/null
"$runner" --contract-test >/dev/null

[[ "$("$repair" --expected-checks | wc -l)" -eq 54 ]]
[[ "$("$repair" --expected-checks | LC_ALL=C sort | uniq -d | wc -l)" -eq 0 ]]
grep -Fqx backup_manifest_old_hash < <("$repair" --expected-checks)
grep -Fqx candidate_hash < <("$repair" --expected-checks)
grep -Fqx repaired_manifest_hash < <("$repair" --expected-checks)
grep -Fqx continuity_unchanged < <("$repair" --expected-checks)
grep -Fqx work_directory_removed < <("$repair" --expected-checks)

# Exact mutation and rollback boundaries.
# shellcheck disable=SC2016
[[ "$(grep -Fxc '        install -o root -g root -m 0600 -- "$rollback_manifest" "$backup_manifest"' "$repair")" -eq 1 ]]
# shellcheck disable=SC1003,SC2016
[[ "$(grep -Fxc 'if ! install -o root -g root -m 0600 -- "$candidate_manifest" "$backup_manifest" \' "$repair")" -eq 1 ]]
[[ "$(grep -Fxc "    printf 'action=17u\\n'" "$repair")" -eq 0 ]]
grep -Fq "printf 'action=17u\\nold_finalizer_sha256=%s\\nnew_finalizer_sha256=%s\\n'" "$repair"
# shellcheck disable=SC2016
grep -Fq 'manifest_contract 17t "$old_manifest_sha256" "$backup_manifest"' "$repair"
# shellcheck disable=SC2016
grep -Fq 'manifest_contract 17u "$new_manifest_sha256" "$backup_manifest"' "$repair"

# No finalizer, release, synchronization, or service mutation is permitted.
require_absent -Eq 'systemctl[[:space:]]+(start|stop|restart|reload|enable|disable|mask|unmask)' "$repair"
require_absent -Eq '(^|[[:space:]])(rsync|lsyncd|caddy[[:space:]]+reload|keepalived)([[:space:]]|$)' "$repair"
# shellcheck disable=SC2016
require_absent -Fq '"$live_finalizer" ' "$repair"
require_absent -Fq 'touch ' "$repair"
require_absent -Fq 'ln -s' "$repair"
# shellcheck disable=SC2016
require_absent -Fq 'chmod '"'"' "$release"'"'"'' "$repair"

# The runner must detach the administrative SSH pseudo-terminal, enter /, and
# supply only the pinned repair through stdin.
# shellcheck disable=SC1003
grep -Fq '    -T \' "$runner"
grep -Fq "    'cd / && sudo -n /bin/bash -s --' \\" "$runner"
# shellcheck disable=SC2016
grep -Fq '    <"$repair" >"$remote_stdout" 2>"$remote_stderr"' "$runner"
require_absent -Fq 'IdentitiesOnly=yes' "$runner"
grep -Fq 'remote_%s_safe_content_begin=true' "$runner"
grep -Fq 'remote_%s_content_secured=protected_retention' "$runner"

# The contract test must prove both directions: an early false assertion is
# rejected even when later assertions are true, and duplicate evidence is not
# accepted as either success or a trustworthy failure transcript.
grep -Fq 'assertion_candidate_hash=false' "$runner"
# shellcheck disable=SC2016
grep -Fq 'if validate_success_transcript "$contract_transcript"; then' "$runner"
# shellcheck disable=SC2016
grep -Fq 'if validate_failure_transcript "$contract_transcript"; then' "$runner"

printf 'Action 17u-b backup-manifest repair regression passed.\n'
