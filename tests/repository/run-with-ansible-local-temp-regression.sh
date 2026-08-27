#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

regression_directory=$(mktemp -d \
    /tmp/ansible-local-temp-regression.XXXXXX)
readonly regression_directory
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_directory
wrapper_file="${script_directory}/run-with-ansible-local-temp.sh"
readonly wrapper_file

cleanup_regression_directory() {
    case "$regression_directory" in
        /tmp/ansible-local-temp-regression.??????) ;;
        *) return 70 ;;
    esac
    rm -rf -- "$regression_directory"
}
trap cleanup_regression_directory EXIT

fixture_file="${regression_directory}/capture.sh"
readonly fixture_file
cat >"$fixture_file" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$ANSIBLE_LOCAL_TEMP" >"$1"
stat --format='%a' "$ANSIBLE_LOCAL_TEMP" >"$2"
exit "${3:-0}"
EOF
chmod 0700 "$fixture_file"

first_path_file="${regression_directory}/first-path"
first_mode_file="${regression_directory}/first-mode"
second_path_file="${regression_directory}/second-path"
second_mode_file="${regression_directory}/second-mode"
failure_path_file="${regression_directory}/failure-path"
failure_mode_file="${regression_directory}/failure-mode"

/bin/bash "$wrapper_file" /bin/bash "$fixture_file" \
    "$first_path_file" "$first_mode_file"
/bin/bash "$wrapper_file" /bin/bash "$fixture_file" \
    "$second_path_file" "$second_mode_file"

first_path=$(<"$first_path_file")
readonly first_path
second_path=$(<"$second_path_file")
readonly second_path

[[ "$first_path" == /tmp/homelab-server-configs-ansible.?????? ]]
[[ "$second_path" == /tmp/homelab-server-configs-ansible.?????? ]]
[[ "$first_path" != "$second_path" ]]
[[ $(<"$first_mode_file") == 700 ]]
[[ $(<"$second_mode_file") == 700 ]]
[[ ! -e "$first_path" ]]
[[ ! -e "$second_path" ]]

set +e
/bin/bash "$wrapper_file" /bin/bash "$fixture_file" \
    "$failure_path_file" "$failure_mode_file" 23
preserved_status=$?
set -e
[[ "$preserved_status" -eq 23 ]]
failure_path=$(<"$failure_path_file")
readonly failure_path
[[ "$failure_path" == /tmp/homelab-server-configs-ansible.?????? ]]
[[ $(<"$failure_mode_file") == 700 ]]
[[ ! -e "$failure_path" ]]

printf 'ansible_local_temp_wrapper_regression_complete=true\n'
