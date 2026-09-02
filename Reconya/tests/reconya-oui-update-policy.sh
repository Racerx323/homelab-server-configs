#!/bin/bash

set -Eeuo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
component_dir="$(cd -- "$script_dir/.." && pwd)"
readonly component_dir
readonly updater="$component_dir/scripts/update-reconya-oui.sh"
readonly deployer="$component_dir/scripts/deploy-reconya-oui-updater.sh"
readonly preparer="$component_dir/scripts/prepare-reconya-oui-deployment.sh"
readonly service_unit="$component_dir/templates/reconya-oui-update.service"
readonly timer_unit="$component_dir/templates/reconya-oui-update.timer"
readonly operation_doc="$component_dir/operations/install-oui-updater.md"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

require_fixed() {
    local needle="$1"
    local checked_file="$2"

    grep -Fq -- "$needle" "$checked_file" || fail "$checked_file missing required text: $needle"
}

for required_file in "$updater" "$deployer" "$preparer" "$service_unit" "$timer_unit" "$operation_doc"; do
    [[ -f $required_file ]] || fail "missing OUI updater artifact: $required_file"
done

require_fixed "readonly oui_url='https://standards-oui.ieee.org/oui/oui.txt'" "$updater"
require_fixed 'readonly maximum_known_duplicates=3' "$updater"
require_fixed "--proto '=https' --proto-redir '=https'" "$updater"
require_fixed 'candidate record count dropped by more than five percent' "$updater"
require_fixed 'trap rollback ERR' "$updater"
require_fixed "systemctl restart \"\$service_name\"" "$updater"
require_fixed 'ExecStart=/bin/bash /usr/local/sbin/update-reconya-oui' "$service_unit"
require_fixed 'ProtectSystem=strict' "$service_unit"
require_fixed 'ReadWritePaths=/home/pi/reconya/data/oui' "$service_unit"
require_fixed 'OnCalendar=monthly' "$timer_unit"
require_fixed 'Persistent=true' "$timer_unit"
require_fixed 'RandomizedDelaySec=6h' "$timer_unit"
require_fixed "readonly expected_seed_sha256='e2fa93fcf56ce075e9fc860d47fb7ed1dc35a6e7b2617bea011475d09b804552'" "$deployer"
require_fixed 'trap rollback ERR' "$deployer"
require_fixed 'systemctl enable --now reconya-oui-update.timer' "$deployer"
require_fixed "setting_is_false \"\$setting_name\"" "$deployer"
require_fixed 'Enabling this timer authorizes each scheduled run to:' "$operation_doc"

fixture_dir="$(mktemp -d)"
readonly fixture_dir
cleanup() {
    rm -rf -- "$fixture_dir"
}
trap cleanup EXIT

valid_fixture="$fixture_dir/valid.txt"
readonly valid_fixture
awk 'BEGIN {
    for (i = 0; i < 30000; i++) {
        printf "%02X-%02X-%02X   (hex)        TEST VENDOR %d\n", int(i / 65536), int(i / 256) % 256, i % 256, i
        print "padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding"
    }
}' >"$valid_fixture"

[[ $(/bin/bash "$updater" validate "$valid_fixture") -eq 30000 ]] || fail 'valid OUI fixture was rejected'
printf '<html>not a registry</html>\n' >"$fixture_dir/html.txt"
if /bin/bash "$updater" validate "$fixture_dir/html.txt" >/dev/null 2>&1; then
    fail 'HTML fixture was accepted'
fi
cp -- "$valid_fixture" "$fixture_dir/duplicate.txt"
printf '00-00-00   (hex)        DUPLICATE\n' >>"$fixture_dir/duplicate.txt"
if /bin/bash "$updater" validate "$fixture_dir/duplicate.txt" >/dev/null 2>&1; then
    fail 'duplicate OUI fixture was accepted'
fi

cp -- "$valid_fixture" "$fixture_dir/known-duplicates.txt"
{
    printf '08-00-30   (hex)        LEGACY ONE\n'
    printf '08-00-30   (hex)        LEGACY TWO\n'
    printf '00-01-C8   (hex)        LEGACY THREE\n'
} >>"$fixture_dir/known-duplicates.txt"
[[ $(/bin/bash "$updater" validate "$fixture_dir/known-duplicates.txt") -eq 30003 ]] ||
    fail 'reviewed IEEE legacy duplicates were rejected'

printf 'PASS: ReconYa OUI updater schedule, validation, and rollback contract\n'
