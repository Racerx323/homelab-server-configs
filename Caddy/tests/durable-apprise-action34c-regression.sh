#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=durable_apprise_action34c_regression
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly caddy_root=${test_directory%/tests}
readonly repository_root=${caddy_root%/Caddy}
readonly transaction=$caddy_root/scripts/apply-durable-apprise-action34c.sh
readonly outer=$caddy_root/scripts/run-dual-node-durable-apprise-action34c-outer.sh
readonly artifact_manifest=$caddy_root/manifests/durable-apprise-action34c.tsv
readonly neutral_regression=$test_directory/durable-apprise-queue-regression.sh
readonly old_transaction=$caddy_root/scripts/apply-durable-apprise-action34.sh
readonly old_outer=$caddy_root/scripts/run-dual-node-durable-apprise-action34-outer.sh
readonly old_manifest=$caddy_root/manifests/durable-apprise-action34.tsv
readonly old_regression=$test_directory/durable-apprise-queue-regression.sh
readonly expected_old_transaction_sha256=0ebc320a0dcff21764cb86b96a5a78062ea2d7f538bf4da2856724f8239ac5af
readonly expected_old_outer_sha256=de580de5a11233d7d7c6611eef40adc15ac4f2dd8128686de1389e9759c3f12a
readonly expected_old_manifest_sha256=6eb8b42edf4120ad60befbdbddf54cf71435a0f8ba52840c8d748cac176ae621
readonly expected_old_regression_sha256=57e253fe4d91907ecc442fc98cac054bff83c41ab9e804c10ed16458c280cee7
readonly predecessor_transaction=$caddy_root/scripts/apply-durable-apprise-action34b.sh
readonly predecessor_outer=$caddy_root/scripts/run-dual-node-durable-apprise-action34b-outer.sh
readonly predecessor_manifest=$caddy_root/manifests/durable-apprise-action34b.tsv
readonly predecessor_action_manifest=$caddy_root/manifests/durable-apprise-action34b.yaml
readonly predecessor_regression=$test_directory/durable-apprise-action34b-regression.sh
readonly expected_predecessor_transaction_sha256=05f8abae6533ae09421621d917829abb3e68a22cbddc4be3d39084a993c10710
readonly expected_predecessor_outer_sha256=8e73e85a5f7e7495758f855cbf3bcdc8d2b2f30d2b812c992e834d6aa53df0ee
readonly expected_predecessor_manifest_sha256=93b5364241d7e1a67ba65f3358bb6e055ab57c137cc8af710f7c61830882de65
readonly expected_predecessor_action_manifest_sha256=9bcec7606e3ba0a88c1cbda8ebc24a047c620fa7ae770600f8d969852839a4a6
readonly expected_predecessor_regression_sha256=b21b13cabf31a95d81883b2c174ae1c033754c26208437d6f656c6c4f9858b36
readonly observed_notifier_sha256=0a2898c08d64e126f393bc17529e33f9e5890bebdbbfc9bccbfd0ec84a09afe6
readonly candidate_notifier_sha256=4008bb94e0d8de04295f5b9669f69efbb12340c024a944e52adb59d673dd1bdb
readonly failed_payload_sha256=15ff568ac2e0f66d6ba662d9d300470ec17ec37b6140782c8b47d2df3081dcd3

fixture_root=$(mktemp -d /tmp/caddy-action34c-regression.XXXXXX)
readonly fixture_root
trap 'rm -rf -- "$fixture_root"' EXIT

file_hash() { sha256sum -- "$1" | awk '{ print $1 }'; }

check() {
    local action34c_regression_label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '%s_check_%s=true\n' "$prefix" "$action34c_regression_label"
        return 0
    fi
    printf '%s_check_%s=false\n' "$prefix" "$action34c_regression_label" >&2
    return 1
}

candidate_sources_match() {
    local action34c_regression_source action34c_regression_target action34c_regression_mode
    local action34c_regression_baseline action34c_regression_candidate action34c_regression_source_path
    # conditional-validator-explicit-failures-begin
    while IFS=$'\t' read -r action34c_regression_source action34c_regression_target \
        action34c_regression_mode action34c_regression_baseline action34c_regression_candidate; do
        if [[ -z "$action34c_regression_source" || "$action34c_regression_source" = \#* ]]; then
            continue
        fi
        : "$action34c_regression_target" "$action34c_regression_mode" "$action34c_regression_baseline"
        case "$action34c_regression_source" in
            Caddy/*) action34c_regression_source_path=$repository_root/$action34c_regression_source ;;
            homelab-dns/*) action34c_regression_source_path=$repository_root/../$action34c_regression_source ;;
            *) return 1 ;;
        esac
        [[ -f "$action34c_regression_source_path" && ! -L "$action34c_regression_source_path" ]] || return 1
        [[ "$(file_hash "$action34c_regression_source_path")" = "$action34c_regression_candidate" ]] || return 1
    done <"$artifact_manifest"
    # conditional-validator-explicit-failures-end
}

function_order_is_safe() {
    local action34c_regression_backup_line action34c_regression_install_line
    local action34c_regression_marker_line action34c_regression_mutation_line
    # conditional-validator-explicit-failures-begin
    action34c_regression_backup_line=$(grep -nF "backup_artifacts \"\$action34c_stage\"" "$transaction" | cut -d: -f1) || return 1
    action34c_regression_install_line=$(grep -nF "install_artifacts \"\$action34c_stage\"" "$transaction" | cut -d: -f1) || return 1
    action34c_regression_marker_line=$(grep -nF "install -m 0600 /dev/null \"\$backup_root/mutation-started\"" "$transaction" | cut -d: -f1) || return 1
    action34c_regression_mutation_line=$(grep -nF 'mutation_started=true' "$transaction" | tail -n 1 | cut -d: -f1) || return 1
    [[ "$action34c_regression_backup_line" -lt "$action34c_regression_install_line" ]] || return 1
    [[ "$action34c_regression_marker_line" -lt "$action34c_regression_mutation_line" ]] || return 1
    # conditional-validator-explicit-failures-end
}

outer_has_no_rollback_mode() {
    ! grep -Fq -- 'node-b --rollback' "$outer"
}

successor_does_not_rerun_predecessors() {
    ! grep -Eq 'apply-durable-apprise-action34(a|b)?\.sh|run-dual-node-durable-apprise-action34(a|b)?-outer\.sh' \
        "$transaction" "$outer"
}

notifier_prerequisite_is_exact() {
    local action34c_regression_source action34c_regression_target action34c_regression_mode
    local action34c_regression_baseline action34c_regression_candidate
    local action34c_regression_matches=0
    # conditional-validator-explicit-failures-begin
    while IFS=$'\t' read -r action34c_regression_source action34c_regression_target \
        action34c_regression_mode action34c_regression_baseline action34c_regression_candidate; do
        [[ "$action34c_regression_target" = /usr/local/bin/keepalived-notify.sh ]] || continue
        [[ "$action34c_regression_source" = homelab-dns/Keepalived/scripts/keepalived-notify.sh ]] || return 1
        [[ "$action34c_regression_mode" = 0755 ]] || return 1
        [[ "$action34c_regression_baseline" = "$observed_notifier_sha256" ]] || return 1
        [[ "$action34c_regression_candidate" = "$candidate_notifier_sha256" ]] || return 1
        action34c_regression_matches=$((action34c_regression_matches + 1))
    done <"$artifact_manifest"
    [[ "$action34c_regression_matches" -eq 1 ]] || return 1
    # conditional-validator-explicit-failures-end
}

cat >"$fixture_root/library-test.sh" <<'LIBRARY_TEST'
#!/usr/bin/env bash
set -Eeuo pipefail
transaction=$1
fixture_root=$2
production_manifest=$3
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

labels=$fixture_root/production-labels.tsv
: >"$labels"
while IFS=$'\t' read -r source_path installed_path row_mode baseline candidate; do
    if [[ -z "$source_path" || "$source_path" = \#* ]]; then
        continue
    fi
    : "$row_mode" "$baseline" "$candidate"
    encoded_label=$(artifact_label "$installed_path")
    [[ "$encoded_label" =~ ^path_[0-9a-f]+$ ]]
    printf '%s\t%s\n' "$installed_path" "$encoded_label" >>"$labels"
done <"$production_manifest"
expected_count=$(awk -F '\t' '!/^[[:space:]]*(#|$)/ { count++ } END { print count + 0 }' "$production_manifest")
[[ "$(wc -l <"$labels")" -eq "$expected_count" ]]
[[ -z "$(cut -f2 "$labels" | LC_ALL=C sort | uniq -d)" ]]
grep -Fq $'/etc/systemd/system/caddy-sync-failure@.service\tpath_' "$labels"
! cut -f2 "$labels" | grep -Fq '@'
[[ "$(artifact_label /tmp/a-b)" != "$(artifact_label /tmp/a_b)" ]]
LIBRARY_TEST
chmod 0700 "$fixture_root/library-test.sh"

check old_transaction_immutable test "$(file_hash "$old_transaction")" = "$expected_old_transaction_sha256"
check old_outer_immutable test "$(file_hash "$old_outer")" = "$expected_old_outer_sha256"
check old_manifest_immutable test "$(file_hash "$old_manifest")" = "$expected_old_manifest_sha256"
check old_regression_immutable test "$(file_hash "$old_regression")" = "$expected_old_regression_sha256"
check predecessor_transaction_immutable test "$(file_hash "$predecessor_transaction")" = "$expected_predecessor_transaction_sha256"
check predecessor_outer_immutable test "$(file_hash "$predecessor_outer")" = "$expected_predecessor_outer_sha256"
check predecessor_manifest_immutable test "$(file_hash "$predecessor_manifest")" = "$expected_predecessor_manifest_sha256"
check predecessor_action_manifest_immutable test "$(file_hash "$predecessor_action_manifest")" = "$expected_predecessor_action_manifest_sha256"
check predecessor_regression_immutable test "$(file_hash "$predecessor_regression")" = "$expected_predecessor_regression_sha256"
check notifier_prerequisite_exact notifier_prerequisite_is_exact
check failed_payload_identity grep -Fq "readonly failed_action34_payload_sha256=$failed_payload_sha256" "$transaction"
check candidate_sources_match candidate_sources_match
check baseline_and_production_label_functions /bin/bash "$fixture_root/library-test.sh" \
    "$transaction" "$fixture_root" "$artifact_manifest"
check safe_mutation_order function_order_is_safe
check recovery_mode grep -Fq -- '--recover) recover_action' "$transaction"
check outer_recovery_mode grep -Fq -- 'node-b --recover' "$outer"
check outer_no_rollback_mode outer_has_no_rollback_mode
check no_predecessor_rerun successor_does_not_rerun_predecessors
check neutral_queue_contract /bin/bash "$neutral_regression"
printf '%s_complete=true\n' "$prefix"
