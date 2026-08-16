#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=durable_apprise_action34a_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly transaction=$caddy_root/scripts/apply-durable-apprise-action34a.sh
readonly outer=$caddy_root/scripts/run-dual-node-durable-apprise-action34a-outer.sh
readonly artifact_manifest=$caddy_root/manifests/durable-apprise-action34a.tsv
readonly neutral_regression=$test_directory/durable-apprise-queue-regression.sh
readonly old_transaction=$caddy_root/scripts/apply-durable-apprise-action34.sh
readonly old_outer=$caddy_root/scripts/run-dual-node-durable-apprise-action34-outer.sh
readonly old_manifest=$caddy_root/manifests/durable-apprise-action34.tsv
readonly old_regression=$test_directory/durable-apprise-queue-regression.sh
readonly expected_old_transaction_sha256=0ebc320a0dcff21764cb86b96a5a78062ea2d7f538bf4da2856724f8239ac5af
readonly expected_old_outer_sha256=de580de5a11233d7d7c6611eef40adc15ac4f2dd8128686de1389e9759c3f12a
readonly expected_old_manifest_sha256=6eb8b42edf4120ad60befbdbddf54cf71435a0f8ba52840c8d748cac176ae621
readonly expected_old_regression_sha256=ae45269cf71776decbcaa120a88f8e2ce35f4db4cdc226bea5a764eed56be0e9
readonly failed_payload_sha256=15ff568ac2e0f66d6ba662d9d300470ec17ec37b6140782c8b47d2df3081dcd3

fixture_root=$(mktemp -d /tmp/caddy-action34a-regression.XXXXXX)
readonly fixture_root
trap 'rm -rf -- "$fixture_root"' EXIT

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

check() {
    local action34a_regression_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action34a_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action34a_regression_label" >&2
    return 1
}

candidate_sources_match() {
    local action34a_regression_source action34a_regression_target action34a_regression_mode
    local action34a_regression_baseline action34a_regression_candidate action34a_regression_source_path
    # conditional-validator-explicit-failures-begin
    while IFS=$'\t' read -r action34a_regression_source action34a_regression_target \
        action34a_regression_mode action34a_regression_baseline action34a_regression_candidate; do
        if [[ -z "$action34a_regression_source" || "$action34a_regression_source" = \#* ]]; then
            continue
        fi
        : "$action34a_regression_target" "$action34a_regression_mode" "$action34a_regression_baseline"
        case "$action34a_regression_source" in
            Caddy/*) action34a_regression_source_path=$repository_root/$action34a_regression_source ;;
            homelab-dns/*) action34a_regression_source_path=$repository_root/../$action34a_regression_source ;;
            *) return 1 ;;
        esac
        [[ -f "$action34a_regression_source_path" && ! -L "$action34a_regression_source_path" ]] || return 1
        [[ "$(file_hash "$action34a_regression_source_path")" = "$action34a_regression_candidate" ]] || return 1
    done <"$artifact_manifest"
    # conditional-validator-explicit-failures-end
}

function_order_is_safe() {
    local action34a_regression_backup_line action34a_regression_install_line
    local action34a_regression_marker_line action34a_regression_mutation_line
    # conditional-validator-explicit-failures-begin
    action34a_regression_backup_line=$(grep -nF "backup_artifacts \"\$action34a_stage\"" "$transaction" | cut -d: -f1) || return 1
    action34a_regression_install_line=$(grep -nF "install_artifacts \"\$action34a_stage\"" "$transaction" | cut -d: -f1) || return 1
    action34a_regression_marker_line=$(grep -nF "install -m 0600 /dev/null \"\$backup_root/mutation-started\"" "$transaction" | cut -d: -f1) || return 1
    action34a_regression_mutation_line=$(grep -nF 'mutation_started=true' "$transaction" | tail -n 1 | cut -d: -f1) || return 1
    [[ "$action34a_regression_backup_line" -lt "$action34a_regression_install_line" ]] || return 1
    [[ "$action34a_regression_marker_line" -lt "$action34a_regression_mutation_line" ]] || return 1
    # conditional-validator-explicit-failures-end
}

outer_has_no_rollback_mode() {
    ! grep -Fq -- 'node-b --rollback' "$outer"
}

successor_does_not_rerun_action34() {
    ! grep -Eq 'apply-durable-apprise-action34\.sh|run-dual-node-durable-apprise-action34-outer\.sh' \
        "$transaction" "$outer"
}

cat >"$fixture_root/library-test.sh" <<'LIBRARY_TEST'
#!/usr/bin/env bash
set -Eeuo pipefail
transaction=$1
fixture_root=$2
source "$transaction" --library-test node-a none none 1700000000-1

legacy_file=$fixture_root/legacy
candidate_file=$fixture_root/candidate
target=$fixture_root/target
manifest=$fixture_root/resume.tsv
rm -f -- "$target"
rm -rf -- "$fixture_root/cleanup"
printf 'legacy\n' >"$legacy_file"
printf 'candidate\n' >"$candidate_file"
legacy_hash=$(file_hash "$legacy_file")
candidate_hash=$(file_hash "$candidate_file")
printf 'fixture\t%s\t0644\t%s\t%s\n' "$target" "$legacy_hash" "$candidate_hash" >"$manifest"

printf 'candidate\n' >"$target"
if ! verify_resume_baseline "$manifest" >"$fixture_root/candidate.out"; then
    cat "$fixture_root/candidate.out" >&2
    exit 1
fi
grep -Fq "_observed=$candidate_hash" "$fixture_root/candidate.out"
grep -Fq '_identity=true' "$fixture_root/candidate.out"

printf 'legacy\n' >"$target"
verify_resume_baseline "$manifest" >"$fixture_root/legacy.out"
grep -Fq "_observed=$legacy_hash" "$fixture_root/legacy.out"
grep -Fq "_expected=legacy:$legacy_hash|candidate:$candidate_hash" "$fixture_root/legacy.out"

rm -f -- "$target"
printf 'fixture\t%s\t0644\tabsent\t%s\n' "$target" "$candidate_hash" >"$manifest"
verify_resume_baseline "$manifest" >"$fixture_root/absent.out"
grep -Fq '_observed=absent' "$fixture_root/absent.out"

printf 'unknown\n' >"$target"
if verify_resume_baseline "$manifest" >"$fixture_root/unknown.out" 2>"$fixture_root/unknown.err"; then
    exit 1
fi
grep -Fq '_identity=false' "$fixture_root/unknown.err"

rm -f -- "$target"
ln -s -- "$candidate_file" "$target"
if verify_resume_baseline "$manifest" >"$fixture_root/symlink.out" 2>"$fixture_root/symlink.err"; then
    exit 1
fi
grep -Fq '_observed=invalid-symlink' "$fixture_root/symlink.out"

cleanup_root=$fixture_root/cleanup
mkdir -m 0700 "$cleanup_root"
retained=$cleanup_root/caddy-action34-payload-node-b-1700000000-1.tar
unrelated=$cleanup_root/caddy-action34-payload-node-a-1700000001-2.tar
printf 'known failed payload\n' >"$retained"
printf 'preserve unrelated payload\n' >"$unrelated"
retained_hash=$(file_hash "$retained")
if ! cleanup_failed_action34_payload_at "$cleanup_root" "$retained_hash" >"$fixture_root/cleanup.out"; then
    cat "$fixture_root/cleanup.out" >&2
    exit 1
fi
[[ ! -e "$retained" && -f "$unrelated" ]]
grep -Fq '_failed_action34_payload_match_count=1' "$fixture_root/cleanup.out"
grep -Fq '_check_failed_action34_payload_match_bounded=true' "$fixture_root/cleanup.out"
LIBRARY_TEST
chmod 0700 "$fixture_root/library-test.sh"

check old_transaction_immutable test "$(file_hash "$old_transaction")" = "$expected_old_transaction_sha256"
check old_outer_immutable test "$(file_hash "$old_outer")" = "$expected_old_outer_sha256"
check old_manifest_immutable test "$(file_hash "$old_manifest")" = "$expected_old_manifest_sha256"
check old_regression_immutable test "$(file_hash "$old_regression")" = "$expected_old_regression_sha256"
check failed_payload_identity grep -Fq "readonly failed_action34_payload_sha256=$failed_payload_sha256" "$transaction"
check candidate_sources_match candidate_sources_match
check baseline_functions /bin/bash "$fixture_root/library-test.sh" "$transaction" "$fixture_root"
check safe_mutation_order function_order_is_safe
check recovery_mode grep -Fq -- '--recover) recover_action' "$transaction"
check outer_recovery_mode grep -Fq -- 'node-b --recover' "$outer"
check outer_no_rollback_mode outer_has_no_rollback_mode
check no_action34_rerun successor_does_not_rerun_action34
check neutral_queue_contract /bin/bash "$neutral_regression"
printf '%s_complete=true\n' "$prefix"
