#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly exception_manifest="$test_directory/fixtures/transcript-contract-historical-exceptions.tsv"

file_hash() { sha256sum "$1" | awk '{ print $1 }'; }

collect_violations() {
    local scan_root=$1
    local candidate

    while IFS= read -r -d '' candidate; do
        # This is a literal source-policy expression.
        # shellcheck disable=SC2016
        if grep -Eq '\[\[ "\$check_count" -ge [0-9]+ \]\]' "$candidate"; then
            printf 'arbitrary-minimum\t%s\t%s\n' \
                "$(file_hash "$candidate")" "${candidate#"$scan_root/"}"
        fi
    done < <(find "$scan_root/Caddy/scripts" -maxdepth 1 -type f -name '*.sh' \
        -print0 | LC_ALL=C sort -z)

    while IFS= read -r -d '' candidate; do
        if [[ "$candidate" == "$scan_root/Caddy/tests/transcript-contract-ratchet-policy-regression.sh" ]]; then
            continue
        fi
        if grep -Eq 'seq 1 [0-9]+' "$candidate" &&
            grep -Fq 'check_fixture_' "$candidate"; then
            printf 'synthetic-check-fixture\t%s\t%s\n' \
                "$(file_hash "$candidate")" "${candidate#"$scan_root/"}"
        fi
    done < <(find "$scan_root/Caddy/tests" -maxdepth 1 -type f -name '*.sh' \
        -print0 | LC_ALL=C sort -z)
}

normalize_manifest() {
    local manifest_path=$1

    awk -F '\t' '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        NF != 3 { exit 42 }
        $1 !~ /^(arbitrary-minimum|synthetic-check-fixture)$/ { exit 43 }
        length($2) != 64 || $2 !~ /^[0-9a-f]+$/ { exit 44 }
        $3 !~ /^Caddy\/(scripts|tests)\/[A-Za-z0-9_.\/-]+$/ { exit 45 }
        { print }
    ' "$manifest_path" | LC_ALL=C sort
}

policy_valid() {
    local scan_root=$1
    local manifest_path=$2
    local observed
    local expected
    local policy_root

    policy_root=$(mktemp -d /tmp/caddy-transcript-policy.XXXXXX)
    observed=$policy_root/observed
    expected=$policy_root/expected
    if ! collect_violations "$scan_root" | LC_ALL=C sort >"$observed" ||
        ! normalize_manifest "$manifest_path" >"$expected"; then
        rm -rf -- "$policy_root"
        return 1
    fi
    if ! cmp -s "$expected" "$observed"; then
        printf 'transcript_contract_policy_expected_begin\n' >&2
        cat "$expected" >&2
        printf 'transcript_contract_policy_expected_end\n' >&2
        printf 'transcript_contract_policy_observed_begin\n' >&2
        cat "$observed" >&2
        printf 'transcript_contract_policy_observed_end\n' >&2
        rm -rf -- "$policy_root"
        return 1
    fi
    rm -rf -- "$policy_root"
}

[[ -f "$exception_manifest" && ! -L "$exception_manifest" ]]
policy_valid "$repository_root" "$exception_manifest"
printf 'transcript_contract_ratchet_current_baseline_exact=true\n'

fixture_root=$(mktemp -d /tmp/caddy-transcript-policy-fixture.XXXXXX)
readonly fixture_root
cleanup() { rm -rf -- "$fixture_root"; }
trap cleanup EXIT
install -d -m 0700 "$fixture_root/Caddy/scripts" "$fixture_root/Caddy/tests"
cp -- "$exception_manifest" "$fixture_root/exceptions.tsv"

cat >"$fixture_root/Caddy/scripts/new-unsafe-runner.sh" <<'FIXTURE'
#!/usr/bin/env bash
check_count=100
[[ "$check_count" -ge 90 ]]
FIXTURE
if policy_valid "$fixture_root" "$fixture_root/exceptions.tsv" 2>/dev/null; then
    printf 'transcript_contract_ratchet_new_arbitrary_minimum_rejected=false\n' >&2
    exit 1
fi
printf 'transcript_contract_ratchet_new_arbitrary_minimum_rejected=true\n'

rm -f -- "$fixture_root/Caddy/scripts/new-unsafe-runner.sh"
cat >"$fixture_root/Caddy/tests/new-synthetic-regression.sh" <<'FIXTURE'
#!/usr/bin/env bash
for fixture_index in $(seq 1 90); do
    printf 'new_check_fixture_%03d=true\n' "$fixture_index"
done
FIXTURE
if policy_valid "$fixture_root" "$fixture_root/exceptions.tsv" 2>/dev/null; then
    printf 'transcript_contract_ratchet_new_synthetic_fixture_rejected=false\n' >&2
    exit 1
fi
printf 'transcript_contract_ratchet_new_synthetic_fixture_rejected=true\n'

rm -f -- "$fixture_root/Caddy/tests/new-synthetic-regression.sh"
: >"$fixture_root/exceptions.tsv"
policy_valid "$fixture_root" "$fixture_root/exceptions.tsv"
printf 'transcript_contract_ratchet_clean_fixture_accepted=true\n'
printf 'transcript_contract_ratchet_policy_regression_complete=true\n'
