#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
wrapper="$script_dir/shfmt-canonical.sh"
precommit_config="$repo_root/.pre-commit-config.yaml"
test_runner="$script_dir/run.sh"

grep -Fq 'entry: Caddy/tests/shfmt-canonical.sh --check' "$precommit_config"
grep -Fq '"$script_dir/shfmt-canonical.sh" --check "${shell_files[@]}"' \
    "$test_runner"
grep -Fq 'exec shfmt "$shfmt_mode" -i 4 -ci' "$wrapper"

fixture_directory=$(mktemp -d /tmp/caddy-shfmt-policy.XXXXXX)
trap 'rm -rf -- "$fixture_directory"' EXIT
fixture="$fixture_directory/fixture.sh"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'example() {' \
    'echo example' \
    '}' >"$fixture"

if "$wrapper" --write "$fixture_directory" >/dev/null 2>&1; then
    printf 'Canonical shfmt wrapper accepted a directory.\n' >&2
    exit 1
fi
if "$wrapper" --write >/dev/null 2>&1; then
    printf 'Canonical shfmt wrapper accepted an empty file set.\n' >&2
    exit 1
fi
if "$wrapper" --write "$fixture" >/dev/null 2>&1; then
    printf 'Canonical shfmt wrapper accepted a file outside the repository.\n' >&2
    exit 1
fi

repository_fixture=$(mktemp "$script_dir/.shfmt-policy-fixture.XXXXXX.sh")
repository_fixture_link="${repository_fixture%.sh}.link.sh"
cleanup_repository_fixture() {
    rm -f -- "$repository_fixture" "$repository_fixture_link"
}
trap 'cleanup_repository_fixture; rm -rf -- "$fixture_directory"' EXIT
cp -- "$fixture" "$repository_fixture"
ln -s -- "$repository_fixture" "$repository_fixture_link"
if "$wrapper" --write "$repository_fixture_link" >/dev/null 2>&1; then
    printf 'Canonical shfmt wrapper accepted a symbolic link.\n' >&2
    exit 1
fi
"$wrapper" --write "$repository_fixture"
"$wrapper" --check "$repository_fixture"
grep -Fxq '    echo example' "$repository_fixture"
cleanup_repository_fixture

printf 'canonical_shfmt_policy_regression_complete=true\n'
