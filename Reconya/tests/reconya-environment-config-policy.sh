#!/bin/bash

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
component_dir="$(cd -- "$script_dir/.." && pwd)"
readonly component_dir
readonly env_template="$component_dir/configs/svmf.env.example"
readonly config_doc="$component_dir/configs/README.md"
readonly install_doc="$component_dir/reconya-installation.md"
readonly deployment_doc="$component_dir/operations/reconcile-environment-config.md"
readonly deploy_script="$component_dir/scripts/deploy-reconya-environment-config.sh"
readonly prepare_script="$component_dir/scripts/prepare-reconya-environment-config-deployment.sh"
repository_root="$(cd -- "$component_dir/.." && pwd)"
readonly repository_root

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

require_fixed() {
    local needle="$1"
    local checked_file="$2"

    grep -Fq -- "$needle" "$checked_file" || fail "$checked_file missing required text: $needle"
}

for required_file in "$env_template" "$config_doc" "$install_doc" "$deployment_doc" "$deploy_script" "$prepare_script"; do
    [[ -f $required_file && ! -L $required_file ]] || fail "missing or unsafe configuration artifact: $required_file"
done

mapfile -t actual_keys < <(
    awk -F= '/^[A-Z][A-Z0-9_]*=/{print $1}' "$env_template" | LC_ALL=C sort
)
readonly -a expected_keys=(
    ALERT_OFFLINE_THRESHOLD_HOURS
    DATABASE_NAME
    GEOLOCATION_ENABLED
    LOGIN_PASSWORD
    LOGIN_USERNAME
    OUI_DOWNLOAD_ENABLED
    PORT
    PUBLIC_IP_LOOKUP_ENABLED
    SQLITE_PATH
    VENDOR_LOOKUP_ONLINE_ENABLED
)

[[ ${#actual_keys[@]} -eq ${#expected_keys[@]} ]] || fail 'configuration key count drifted'
for index in "${!expected_keys[@]}"; do
    [[ ${actual_keys[index]} == "${expected_keys[index]}" ]] || fail 'configuration key set drifted'
done

require_fixed 'LOGIN_USERNAME=REPLACE_WITH_LOGIN_USERNAME' "$env_template"
require_fixed 'LOGIN_PASSWORD=REPLACE_WITH_STRONG_PASSWORD' "$env_template"
require_fixed 'PUBLIC_IP_LOOKUP_ENABLED=false' "$env_template"
require_fixed 'GEOLOCATION_ENABLED=false' "$env_template"
require_fixed 'VENDOR_LOOKUP_ONLINE_ENABLED=false' "$env_template"
require_fixed 'OUI_DOWNLOAD_ENABLED=false' "$env_template"
require_fixed 'ALERT_OFFLINE_THRESHOLD_HOURS=6' "$env_template"
require_fixed 'Reconya/configs/svmf.env.example' "$install_doc"
require_fixed 'JWT_SECRET_KEY' "$config_doc"
require_fixed "readonly expected_template_sha256='$(sha256sum -- "$env_template" | awk '{print $1}')'" "$deploy_script"
require_fixed "readonly backup_dir='/var/backups/reconya-env-v0.26.0-desired-state-v1'" "$deploy_script"
require_fixed "credential_lines_match \"\$backup_dir/env.original\" \"\$env_file\"" "$deploy_script"
require_fixed 'trap rollback ERR' "$deploy_script"
require_fixed 'Public-IP lookup would contact' "$deployment_doc"
require_fixed 'This operation does not alter SQLite or OUI data' "$deployment_doc"

git -C "$repository_root" check-ignore -q Reconya/configs/svmf.env ||
    fail 'a copied ReconYa credential file would not be ignored'
if git -C "$repository_root" check-ignore -q Reconya/configs/svmf.env.example; then
    fail 'the sanitized ReconYa environment template is ignored'
fi

if grep -Eq '^(JWT_SECRET_KEY|DATABASE_TYPE|IPV6_[A-Z0-9_]+)=' "$env_template"; then
    fail 'v0.26.0 template contains an inert legacy key'
fi
if grep -Eq '^(LOGIN_USERNAME|LOGIN_PASSWORD)=(admin|password|strong_password_here|your_)' "$env_template"; then
    fail 'configuration template contains a deployable default credential'
fi

fixture_dir="$(mktemp -d)"
readonly fixture_dir
cleanup() {
    rm -rf -- "$fixture_dir"
}
trap cleanup EXIT

sed \
    -e 's/^LOGIN_USERNAME=.*/LOGIN_USERNAME=test_operator/' \
    -e 's/^LOGIN_PASSWORD=.*/LOGIN_PASSWORD=test_password/' \
    "$env_template" >"$fixture_dir/desired.env"
/bin/bash "$deploy_script" validate-desired "$fixture_dir/desired.env" ||
    fail 'desired-state fixture failed deployment validation'

{
    printf 'DATABASE_TYPE=sqlite\n'
    printf 'SQLITE_PATH=data/reconya.db\n'
    printf 'DATABASE_NAME="reconya-dev"\n'
    printf 'PORT=3008\n'
    printf 'LOGIN_USERNAME=test_operator\n'
    printf 'LOGIN_PASSWORD=test_password\n'
    printf 'JWT_SECRET_KEY=legacy_test_secret\n'
    printf 'IPV6_MONITORING_ENABLED=true\n'
    printf 'IPV6_MONITOR_INTERFACES=\n'
    printf 'IPV6_MONITOR_INTERVAL=30\n'
    printf 'IPV6_LINK_LOCAL_MONITORING=true\n'
    printf 'IPV6_MULTICAST_MONITORING=false\n'
    printf 'OUI_DOWNLOAD_ENABLED=false\n'
    printf 'VENDOR_LOOKUP_ONLINE_ENABLED=false\n'
} >"$fixture_dir/pre-reconciliation.env"
/bin/bash "$deploy_script" validate-pre-reconciliation "$fixture_dir/pre-reconciliation.env" ||
    fail 'legacy production fixture failed deployment validation'

printf 'UNREVIEWED_SETTING=true\n' >>"$fixture_dir/desired.env"
if /bin/bash "$deploy_script" validate-desired "$fixture_dir/desired.env"; then
    fail 'desired-state validator accepted an extra key'
fi

printf 'PASS: ReconYa environment template is complete and sanitized\n'
