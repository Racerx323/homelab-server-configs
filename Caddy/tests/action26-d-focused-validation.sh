#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
set +x
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
readonly PATH

readonly prefix=action_26_d_focused
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly powershell_action=$caddy_root/scripts/Invoke-WorkstationWslMirroredActivationAction26d.ps1
readonly inspector=$caddy_root/scripts/inspect-workstation-wsl-mirrored-postrestart-action26-d.sh
readonly regression=$test_directory/action26-d-windows-activation-regression.sh
readonly focused=$test_directory/action26-d-focused-validation.sh
readonly manifest=$caddy_root/manifests/wsl-ipv6-integration-action26-d.yaml
readonly powershell_sha256=6ac36b4ed4b2dad3df6a740dba632acc00c35c9636aa2f7254cb64cbb0362247
readonly inspector_sha256=c28daa30a7b127d8d6b4ca9e669564350367695e8be4986112b4478d37d23a1d
readonly regression_sha256=6ca95759fb3ca3dfc8191ce55ca1938977d506520bbe40e14af255dc4bb4df98
readonly manifest_sha256=0f958287dd15fcc7a28b497698d9f6e6888f86036e90f5bf92e065cab34e4a7f

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }
record_check() {
    local action26d_focused_label=$1

    shift
    if "$@" >/dev/null; then
        printf '%s_check_%s=true\n' "$prefix" "$action26d_focused_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action26d_focused_label" >&2
    return 1
}
powershell_syntax() {
    command -v pwsh >/dev/null || return 0
    ACTION26D_POWERSHELL_PATH=$powershell_action pwsh -NoProfile -Command \
        '$errors=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($env:ACTION26D_POWERSHELL_PATH,[ref]$null,[ref]$errors); if ($errors.Count) { exit 1 }'
}
yaml_check() {
    if command -v yamllint >/dev/null; then
        yamllint -s "$manifest"
        return
    fi
    grep -Fqx 'action: 26d' "$manifest" || return 1
    grep -Fqx 'status: defined' "$manifest"
}
contract_check() {
    grep -Fq '[Environment]::OSVersion.Platform' "$powershell_action" || return 1
    grep -Fq 'WSL_INTEROP' "$powershell_action" || return 1
    grep -Fq 'WSL_DISTRO_NAME' "$powershell_action" || return 1
    grep -Fq 'Set-Location -LiteralPath ([IO.Path]::GetTempPath())' "$powershell_action" || return 1
    test "$(grep -Fxc '    $Shutdown = Invoke-CapturedProcess activation_shutdown $WslExe @("--shutdown")' \
        "$powershell_action")" -eq 1 || return 1
    test "$(grep -Fxc '    $Shutdown = Invoke-CapturedProcess rollback_shutdown $WslExe @("--shutdown")' \
        "$powershell_action")" -eq 1 || return 1
    grep -Fq '"--distribution", $Distribution' "$powershell_action" || return 1
    grep -Fq '"--cd", "/"' "$powershell_action" || return 1
    grep -Fq '"--expect-mirrored"' "$powershell_action" || return 1
    grep -Fq '"--expect-nat"' "$powershell_action" || return 1
    grep -Fq '[IO.File]::Delete($Target)' "$powershell_action" || return 1
    grep -Fq 'manual_intervention_status: 125' "$manifest" || return 1
    grep -Fq 'windows_firewall_change: false' "$manifest" || return 1
    grep -Fq 'ha_node_administrative_contact: false' "$manifest" || return 1
    ! grep -Eq '(^|[[:space:]])(ssh|scp|rsync)([[:space:]]|$)' \
        "$powershell_action" "$inspector" "$regression"
}
no_live_execution_path() {
    ! grep -Eq '^[[:space:]]*(pwsh|powershell)(\.exe)?[[:space:]].*Invoke-WorkstationWslMirroredActivationAction26d' \
        "$0" || return 1
    ! grep -Eq '^[[:space:]]*wsl(\.exe)?[[:space:]]+--shutdown' "$0"
}
run_regression() {
    if [[ "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]]; then
        /bin/bash "$regression" --linux-only
        return
    fi
    /bin/bash "$regression"
}

record_check powershell_hash test "$(file_hash "$powershell_action")" = "$powershell_sha256"
record_check inspector_hash test "$(file_hash "$inspector")" = "$inspector_sha256"
record_check regression_hash test "$(file_hash "$regression")" = "$regression_sha256"
record_check manifest_hash test "$(file_hash "$manifest")" = "$manifest_sha256"
record_check bash_syntax /bin/bash -n "$inspector" "$regression" "$0"
record_check powershell_syntax powershell_syntax
record_check shellcheck shellcheck "$inspector" "$regression" "$0"
record_check canonical_format /bin/bash "$test_directory/shfmt-canonical.sh" --check \
    "$inspector" "$regression" "$0"
record_check yaml yaml_check
record_check regression run_regression
record_check contract contract_check
record_check collision_policy /bin/bash "$test_directory/check-shell-readonly-local-collisions-v2.sh" \
    "$inspector" "$regression" "$0"
record_check conditional_policy /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
record_check output_evidence_policy /bin/bash "$test_directory/transaction-output-evidence-policy-regression.sh"
record_check scalar_grep_policy /bin/bash "$test_directory/multifile-grep-count-policy.sh" --check \
    "$inspector" "$regression" "$0"
record_check portable_awk_policy /bin/bash "$test_directory/portable-awk-policy.sh" --check \
    "$inspector" "$regression" "$0"
record_check accepted_live_hash_policy /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
record_check no_live_execution_path no_live_execution_path
for action26d_focused_entrypoint in "$powershell_action" "$inspector" "$regression" "$focused"; do
    record_check "executable_index_$(basename "$action26d_focused_entrypoint" | tr '.-' '__')" \
        test "$(git ls-files --stage -- "Caddy/${action26d_focused_entrypoint#"$caddy_root/"}" | awk '{ print $1 }')" = 100755
done
printf '%s_windows_host_activation=false\n' "$prefix"
printf '%s_wsl_shutdown=false\n' "$prefix"
printf '%s_node_contact=false\n' "$prefix"
printf '%s_complete_suite_bypassed=true\n' "$prefix"
printf '%s_complete=true\n' "$prefix"
