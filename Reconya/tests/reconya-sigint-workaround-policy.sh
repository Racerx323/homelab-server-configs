#!/bin/bash

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
component_dir="$(cd -- "$script_dir/.." && pwd)"
readonly component_dir
readonly unit_file="$component_dir/templates/reconya.service"
readonly checker="$component_dir/scripts/check-reconya-service.sh"
readonly deployer="$component_dir/scripts/deploy-reconya-sigint-workaround.sh"
readonly preparer="$component_dir/scripts/prepare-reconya-sigint-workaround.sh"
readonly operation_doc="$component_dir/operations/install-sigint-workaround.md"
readonly upstream_proposal="$component_dir/operations/upstream-sigterm-proposal.md"
readonly upstream_issue_body="$component_dir/operations/upstream-sigterm-issue-body.md"
readonly binary_operation="$component_dir/operations/update-v0.26.0.md"
readonly install_doc="$component_dir/reconya-installation.md"
readonly history_doc="$component_dir/HISTORY.md"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

require_fixed() {
    local needle="$1"
    local checked_file="$2"

    grep -Fq -- "$needle" "$checked_file" || fail "$checked_file missing required text: $needle"
}

for required_file in "$unit_file" "$checker" "$deployer" "$preparer" "$operation_doc" \
    "$upstream_proposal" "$upstream_issue_body" "$binary_operation" "$install_doc" \
    "$history_doc"; do
    [[ -f $required_file && ! -L $required_file ]] || fail "missing or unsafe SIGINT artifact: $required_file"
done

require_fixed 'KillSignal=SIGINT' "$unit_file"
require_fixed 'TimeoutStopSec=15s' "$unit_file"
require_fixed 'FinalKillSignal=SIGKILL' "$unit_file"
require_fixed "readonly new_unit_sha256='$(sha256sum -- "$unit_file" | awk '{print $1}')'" "$deployer"
require_fixed "readonly backup_dir='/var/backups/reconya-sigint-workaround-v1'" "$deployer"
require_fixed "grep -Fq 'Received shutdown signal: interrupt'" "$deployer"
require_fixed "grep -Fq '[SUCCESS] Services stopped'" "$deployer"
require_fixed 'restart_duration -le 10' "$deployer"
require_fixed 'trap rollback ERR' "$deployer"
require_fixed 'Each future binary update must inspect the candidate' "$binary_operation"
require_fixed "Treat \`SIGINT\` as a version-specific workaround." "$install_doc"
require_fixed 'Handle SIGTERM through the existing graceful shutdown path' "$upstream_proposal"
require_fixed 'https://github.com/Dyneteq/reconya/issues/145' "$upstream_proposal"
require_fixed 'signal.Notify(stop, os.Interrupt, syscall.SIGTERM)' "$upstream_issue_body"
require_fixed 'fbc90c10257cc44ea6acb2c53a08b7a9d03f7aa6fff26c6d902ac2bece820d51' "$history_doc"
if grep -Fq 'svmf.local.theama.co' "$upstream_issue_body"; then
    fail 'public upstream issue body contains the private hostname'
fi

if grep -Fxq 'KillSignal=SIGTERM' "$unit_file"; then
    fail 'v0.26.0 service template still sends SIGTERM'
fi

/bin/bash "$checker"
verify_output=''
if ! verify_output="$(systemd-analyze verify "$unit_file" 2>&1)"; then
    expected_verify_warning='reconya.service: Command /home/pi/reconya/reconya-linux-arm64 is not executable: No such file or directory'
    [[ $verify_output == "$expected_verify_warning" ]] || fail "systemd unit validation failed: $verify_output"
fi

printf 'PASS: ReconYa SIGINT workaround and binary-update gate\n'
