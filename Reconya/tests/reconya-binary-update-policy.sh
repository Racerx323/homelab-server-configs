#!/bin/bash

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
component_dir="$(cd -- "$script_dir/.." && pwd)"
readonly component_dir
readonly prepare_script="$component_dir/scripts/prepare-reconya-update.sh"
readonly deploy_script="$component_dir/scripts/deploy-reconya-update.sh"
readonly operation_doc="$component_dir/operations/update-v0.26.0.md"
readonly release_manifest="$component_dir/manifests/reconya-v0.26.0.sha256"
readonly install_doc="$component_dir/reconya-installation.md"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

require_fixed() {
    local needle="$1"
    local checked_file="$2"

    grep -Fq -- "$needle" "$checked_file" || fail "$checked_file missing required text: $needle"
}

for required_file in "$prepare_script" "$deploy_script" "$operation_doc" "$release_manifest" "$install_doc"; do
    [[ -f $required_file ]] || fail "missing ReconYa update artifact: $required_file"
done

require_fixed "readonly release_version='v0.26.0'" "$prepare_script"
require_fixed "readonly archive_sha256='31e6ee19536e90c24d676446a950feee3d5e8e53fb6ef429e50568eb916be812'" "$prepare_script"
require_fixed "readonly binary_sha256='0f5bdd5c2198f190316595b235f7c2c2fe828632baf320f773bcb5c2f990c4c3'" "$prepare_script"
require_fixed "readonly old_binary_sha256='75101e776500539b5827ba0300fb3435cc4991cd75fcaa9123cf6206fc68f9d3'" "$deploy_script"
require_fixed "readonly backup_dir='/var/backups/reconya/v0.24.1-to-v0.26.0'" "$deploy_script"
require_fixed 'trap rollback ERR' "$deploy_script"
require_fixed 'cp -a -- "'\$'data_path" "'\$'backup_dir/data.snapshot"' "$deploy_script"
require_fixed 'mv -- "'\$'data_path" "'\$'backup_dir/failed-v0.26.0-data"' "$deploy_script"
require_fixed 'No reboot is part of this operation.' "$operation_doc"
require_fixed 'Each future binary update must inspect the candidate' "$operation_doc"
require_fixed 'perform a controlled stop test' "$operation_doc"
require_fixed "Treat \`SIGINT\` as a version-specific workaround." "$install_doc"
require_fixed '/bin/bash Reconya/scripts/prepare-reconya-update.sh' "$install_doc"

if grep -Eq 'releases/(latest|download/latest)|releases/latest/download' "$prepare_script" "$deploy_script"; then
    fail 'update scripts must not resolve a moving latest release'
fi
if grep -Eq 'curl[^|]*\|[[:space:]]*(sh|bash|tar)' "$install_doc" "$prepare_script" "$deploy_script"; then
    fail 'ReconYa update path contains an unverified curl pipeline'
fi

printf 'PASS: ReconYa binary update provenance and rollback contract\n'
