#!/usr/bin/env bash

set -Eeuo pipefail
set +x
umask 077
PATH=/usr/bin:/bin
export PATH
readonly PATH

readonly prefix=focused_validation_runner
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly test_directory
readonly repository_root=${test_directory%/Caddy/tests}
readonly manifest=${CADDY_FOCUSED_VALIDATION_MANIFEST:-$test_directory/focused-validation.yaml}

selection_mode=
selection_profiles_csv=
changed_base=HEAD
container_mode=auto
execution_phase=all
explain=false
list_only=false

usage() {
    printf 'Usage: %s (--profile NAME [...] | --profiles CSV | --changed [--base REF] | --list) [--explain] [--container auto|always|never] [--phase all|host|container]\n' "${0##*/}" >&2
}

append_profile() {
    local focused_runner_new_profile=$1

    [[ "$focused_runner_new_profile" =~ ^[a-z0-9-]+$ ]] || return 64
    if [[ -z "$selection_profiles_csv" ]]; then
        selection_profiles_csv=$focused_runner_new_profile
    else
        selection_profiles_csv=$selection_profiles_csv,$focused_runner_new_profile
    fi
}

while (($#)); do
    case "$1" in
        --profile)
            [[ $# -ge 2 && (-z "$selection_mode" || "$selection_mode" = profiles) ]] || {
                usage
                exit 64
            }
            selection_mode=profiles
            append_profile "$2" || exit $?
            shift 2
            ;;
        --profiles)
            [[ $# -ge 2 && -z "$selection_mode" ]] || {
                usage
                exit 64
            }
            selection_mode=profiles
            selection_profiles_csv=$2
            shift 2
            ;;
        --changed)
            [[ -z "$selection_mode" ]] || {
                usage
                exit 64
            }
            selection_mode=changed
            shift
            ;;
        --base)
            [[ $# -ge 2 ]] || exit 64
            changed_base=$2
            shift 2
            ;;
        --container)
            [[ $# -ge 2 ]] || exit 64
            container_mode=$2
            shift 2
            ;;
        --phase)
            [[ $# -ge 2 ]] || exit 64
            execution_phase=$2
            shift 2
            ;;
        --explain)
            explain=true
            shift
            ;;
        --list)
            [[ -z "$selection_mode" ]] || exit 64
            selection_mode=list
            list_only=true
            shift
            ;;
        *)
            usage
            exit 64
            ;;
    esac
done

[[ "$container_mode" =~ ^(auto|always|never)$ ]] || exit 64
[[ "$execution_phase" =~ ^(all|host|container)$ ]] || exit 64
[[ -n "$selection_mode" ]] || {
    usage
    exit 64
}
[[ "$execution_phase" != container || "${CADDY_VALIDATION_CONTAINER:-}" = 1 ]] || exit 64

if [[ -n "${CADDY_FOCUSED_EVIDENCE_ROOT:-}" ]]; then
    evidence_root=$CADDY_FOCUSED_EVIDENCE_ROOT
    [[ "$evidence_root" = /* && -d "$evidence_root" && ! -L "$evidence_root" ]] || exit 64
else
    evidence_root=$(mktemp -d /tmp/caddy-focused-validation.XXXXXX)
fi
readonly evidence_root
chmod 0700 "$evidence_root"
# The override belongs to this runner instance. Nested runner regressions must
# create their own evidence roots and cannot overwrite the parent summary.
unset CADDY_FOCUSED_EVIDENCE_ROOT
summary_path=$evidence_root/summary.tsv
readonly summary_path
: >"$summary_path"
chmod 0600 "$summary_path"

record_summary() {
    local focused_runner_kind=$1
    local focused_runner_name=$2
    local focused_runner_status=$3

    printf '%s\t%s\t%s\n' "$focused_runner_kind" "$focused_runner_name" "$focused_runner_status" >>"$summary_path"
}

stable_unique() {
    awk 'NF && !seen[$0]++'
}

nonproduction_inventory_path() {
    local focused_runner_changed_path=$1
    local focused_runner_registry=
    local focused_runner_lifecycle=

    case "$focused_runner_changed_path" in
        Caddy/tests/*) focused_runner_registry=$test_directory/test-lifecycle.tsv ;;
        Caddy/scripts/*) focused_runner_registry=$repository_root/Caddy/manifests/script-lifecycle.tsv ;;
        Caddy/manifests/*) focused_runner_registry=$repository_root/Caddy/manifests/manifest-lifecycle.tsv ;;
        Caddy/systemd/*) focused_runner_registry=$repository_root/Caddy/manifests/systemd-lifecycle.tsv ;;
        Caddy/templates/*) focused_runner_registry=$repository_root/Caddy/manifests/template-lifecycle.tsv ;;
        *) return 1 ;;
    esac
    focused_runner_lifecycle=$(awk -F '\t' -v path="$focused_runner_changed_path" \
        '$1 == path { print $2; found++ } END { if (found != 1) exit 1 }' \
        "$focused_runner_registry") || return 1
    [[ "$focused_runner_lifecycle" != production-current ]]
}

/bin/bash "$test_directory/focused-validation-manifest-policy.sh" --check >/dev/null

if [[ "$list_only" = true ]]; then
    jq -r '.profiles | keys[] | "profile\t\(.)"' "$manifest"
    printf '%s_evidence_path=%s\n' "$prefix" "$evidence_root"
    exit 0
fi

profiles_raw=$evidence_root/profiles.raw
host_raw=$evidence_root/host.raw
debian_raw=$evidence_root/debian.raw
policies_raw=$evidence_root/policies.raw
shell_raw=$evidence_root/shell.raw
readonly profiles_raw host_raw debian_raw policies_raw shell_raw
: >"$profiles_raw"
: >"$host_raw"
: >"$debian_raw"
: >"$policies_raw"
: >"$shell_raw"

load_profile() {
    local focused_runner_profile=$1
    local focused_runner_include_debian=$2

    jq -e --arg profile "$focused_runner_profile" '.profiles | has($profile)' "$manifest" >/dev/null || return 64
    printf '%s\n' "$focused_runner_profile" >>"$profiles_raw"
    jq -r --arg profile "$focused_runner_profile" '.profiles[$profile].host_tests[]' "$manifest" >>"$host_raw"
    if [[ "$focused_runner_include_debian" = true ]]; then
        jq -r --arg profile "$focused_runner_profile" '.profiles[$profile].debian_tests[]' "$manifest" >>"$debian_raw"
    fi
    jq -r --arg profile "$focused_runner_profile" '.profiles[$profile].policies[]' "$manifest" >>"$policies_raw"
    jq -r --arg profile "$focused_runner_profile" '.profiles[$profile].shell_files[]' "$manifest" >>"$shell_raw"
}

case "$selection_mode" in
    profiles)
        [[ "$selection_profiles_csv" =~ ^[a-z0-9-]+(,[a-z0-9-]+)*$ ]] || exit 64
        IFS=, read -r -a focused_runner_requested_profiles <<<"$selection_profiles_csv"
        for focused_runner_profile in "${focused_runner_requested_profiles[@]}"; do
            load_profile "$focused_runner_profile" true || exit $?
        done
        ;;
    changed)
        git -C "$repository_root" rev-parse --verify "$changed_base^{commit}" >/dev/null || exit 64
        changed_raw=$evidence_root/changed.raw
        {
            git -C "$repository_root" diff --name-only "$changed_base"...HEAD
            git -C "$repository_root" diff --name-only HEAD
            git -C "$repository_root" diff --cached --name-only
            git -C "$repository_root" ls-files --others --exclude-standard
        } | stable_unique >"$changed_raw"
        [[ -s "$changed_raw" ]] || {
            printf '%s_changed_file_count=0\n' "$prefix"
            printf '%s_evidence_path=%s\n' "$prefix" "$evidence_root"
            exit 0
        }
        while IFS= read -r focused_runner_profile; do
            focused_runner_profile_match=false
            focused_runner_profile_debian=false
            while IFS= read -r focused_runner_pattern; do
                while IFS= read -r focused_runner_changed_path; do
                    # The manifest value is intentionally a validated glob pattern.
                    # shellcheck disable=SC2053
                    if [[ "$focused_runner_changed_path" == $focused_runner_pattern ]]; then
                        focused_runner_profile_match=true
                        break 2
                    fi
                done <"$changed_raw"
            done < <(jq -r --arg profile "$focused_runner_profile" '.profiles[$profile].path_patterns[]' "$manifest")
            if [[ "$focused_runner_profile_match" = true ]]; then
                while IFS= read -r focused_runner_pattern; do
                    while IFS= read -r focused_runner_changed_path; do
                        # The manifest value is intentionally a validated glob pattern.
                        # shellcheck disable=SC2053
                        if [[ "$focused_runner_changed_path" == $focused_runner_pattern ]]; then
                            focused_runner_profile_debian=true
                            break 2
                        fi
                    done <"$changed_raw"
                done < <(jq -r --arg profile "$focused_runner_profile" \
                    '.profiles[$profile].debian_path_patterns[]' "$manifest")
                load_profile "$focused_runner_profile" "$focused_runner_profile_debian" || exit $?
            fi
        done < <(jq -r '.profiles | keys[]' "$manifest")
        while IFS= read -r focused_runner_changed_path; do
            if nonproduction_inventory_path "$focused_runner_changed_path"; then
                continue
            fi
            case "$focused_runner_changed_path" in
                Caddy/* | AGENTS.md | .pre-commit-config.yaml)
                    focused_runner_path_covered=false
                    while IFS= read -r focused_runner_profile; do
                        while IFS= read -r focused_runner_pattern; do
                            # The manifest value is intentionally a validated glob pattern.
                            # shellcheck disable=SC2053
                            if [[ "$focused_runner_changed_path" == $focused_runner_pattern ]]; then
                                focused_runner_path_covered=true
                                break 2
                            fi
                        done < <(jq -r --arg profile "$focused_runner_profile" '.profiles[$profile].path_patterns[]' "$manifest")
                    done < <(jq -r '.profiles | keys[]' "$manifest")
                    if [[ "$focused_runner_path_covered" != true ]]; then
                        printf '%s_unmapped_changed_path=%s\n' "$prefix" "$focused_runner_changed_path" >&2
                        exit 1
                    fi
                    ;;
            esac
        done <"$changed_raw"
        [[ -s "$profiles_raw" ]] || exit 1
        ;;
esac

profiles_path=$evidence_root/profiles
host_path=$evidence_root/host
debian_path=$evidence_root/debian
policies_path=$evidence_root/policies
shell_path=$evidence_root/shell
readonly profiles_path host_path debian_path policies_path shell_path
stable_unique <"$profiles_raw" >"$profiles_path"
stable_unique <"$host_raw" >"$host_path"
stable_unique <"$debian_raw" >"$debian_path"
stable_unique <"$policies_raw" >"$policies_path"
stable_unique <"$shell_raw" >"$shell_path"

validate_selected_test() {
    local focused_runner_relative=$1
    local focused_runner_path=$repository_root/$focused_runner_relative

    [[ "$focused_runner_relative" =~ ^Caddy/tests/[A-Za-z0-9._/-]+\.sh$ ]] || return 1
    [[ "$focused_runner_relative" != *..* ]] || return 1
    [[ -f "$focused_runner_path" && ! -L "$focused_runner_path" && -x "$focused_runner_path" ]]
}

while IFS= read -r focused_runner_test; do
    validate_selected_test "$focused_runner_test" || exit 1
done < <(stable_unique < <(printf '%s\n' "$(<"$host_path")" "$(<"$debian_path")"))

printf '%s_selection_mode=%s\n' "$prefix" "$selection_mode"
printf '%s_profiles=%s\n' "$prefix" "$(paste -sd, "$profiles_path")"
printf '%s_host_test_count=%s\n' "$prefix" "$(wc -l <"$host_path")"
printf '%s_debian_test_count=%s\n' "$prefix" "$(wc -l <"$debian_path")"
printf '%s_policy_count=%s\n' "$prefix" "$(wc -l <"$policies_path")"

if [[ "$explain" = true ]]; then
    sed 's/^/host_test\t/' "$host_path"
    sed 's/^/debian_test\t/' "$debian_path"
    sed 's/^/policy\t/' "$policies_path"
    sed 's/^/shell_file\t/' "$shell_path"
    printf '%s_evidence_path=%s\n' "$prefix" "$evidence_root"
    exit 0
fi

run_policy() {
    local focused_runner_policy=$1

    case "$focused_runner_policy" in
        selected-shell)
            [[ -s "$shell_path" ]] || return 1
            mapfile -t focused_runner_shell_files <"$shell_path"
            /bin/bash "$test_directory/focused-validation-selected-shell.sh" --check \
                "${focused_runner_shell_files[@]}"
            ;;
        accepted-live-hashes)
            /bin/bash "$test_directory/accepted-live-hash-policy.sh" --check
            ;;
        conditional-validator)
            /bin/bash "$test_directory/conditional-validator-errexit-policy-regression.sh"
            ;;
        executable-modes)
            /bin/bash "$test_directory/executable-wrapper-policy-regression.sh"
            ;;
        remote-cwd)
            [[ -s "$shell_path" ]] || return 1
            mapfile -t focused_runner_shell_files <"$shell_path"
            /bin/bash "$test_directory/remote-streamed-bash-cwd-policy.sh" --check \
                "${focused_runner_shell_files[@]}"
            ;;
        ssh-evidence)
            [[ -s "$shell_path" ]] || return 1
            mapfile -t focused_runner_shell_files <"$shell_path"
            /bin/bash "$test_directory/ssh-stream-local-evidence-policy.sh" --check \
                "${focused_runner_shell_files[@]}"
            ;;
        systemd-boot)
            /bin/bash "$test_directory/systemd-boot-persistence-policy.sh" --check
            ;;
        template-lifecycle)
            /bin/bash "$test_directory/template-lifecycle-policy.sh" --check
            ;;
        deployment-lifecycle)
            /bin/bash "$test_directory/deployment-lifecycle-policy.sh" --check
            ;;
        deployable-successor)
            /bin/bash "$test_directory/deployable-successor-policy.sh" --check
            ;;
        environment-v2)
            /bin/bash "$test_directory/caddy-environment-v2-policy.sh" --check
            ;;
        test-lifecycle)
            /bin/bash "$test_directory/test-lifecycle-policy.sh" --check
            ;;
        *) return 64 ;;
    esac
}

run_test_file() {
    local focused_runner_phase=$1
    local focused_runner_relative=$2
    local focused_runner_status=0

    printf '%s_test_begin=%s:%s\n' "$prefix" "$focused_runner_phase" "$focused_runner_relative"
    /bin/bash "$repository_root/$focused_runner_relative" || focused_runner_status=$?
    record_summary "$focused_runner_phase" "$focused_runner_relative" "$focused_runner_status"
    printf '%s_test_status=%s:%s:%s\n' "$prefix" "$focused_runner_phase" "$focused_runner_relative" "$focused_runner_status"
    [[ "$focused_runner_status" -eq 0 ]]
}

if [[ "$execution_phase" = all || "$execution_phase" = host ]]; then
    while IFS= read -r focused_runner_policy; do
        [[ -n "$focused_runner_policy" ]] || continue
        focused_runner_policy_status=0
        run_policy "$focused_runner_policy" || focused_runner_policy_status=$?
        record_summary policy "$focused_runner_policy" "$focused_runner_policy_status"
        [[ "$focused_runner_policy_status" -eq 0 ]] || exit "$focused_runner_policy_status"
    done <"$policies_path"
    while IFS= read -r focused_runner_test; do
        [[ -n "$focused_runner_test" ]] || continue
        run_test_file host "$focused_runner_test" || exit $?
    done <"$host_path"
fi

if [[ "$execution_phase" = container ]]; then
    while IFS= read -r focused_runner_test; do
        [[ -n "$focused_runner_test" ]] || continue
        run_test_file debian "$focused_runner_test" || exit $?
    done <"$debian_path"
elif [[ "$execution_phase" = all && "$container_mode" != never && -s "$debian_path" ]]; then
    focused_runner_container_args=()
    focused_runner_container_args=(--profiles "$(paste -sd, "$profiles_path")")
    container_evidence_root=$evidence_root/debian-evidence
    focused_runner_container_status=0
    CADDY_FOCUSED_HOST_EVIDENCE_DIR=$container_evidence_root \
        /bin/bash "$test_directory/run-focused-container.sh" \
        "${focused_runner_container_args[@]}" || focused_runner_container_status=$?
    if [[ -f "$container_evidence_root/summary.tsv" && ! -L "$container_evidence_root/summary.tsv" ]]; then
        cat -- "$container_evidence_root/summary.tsv" >>"$summary_path"
    elif [[ "$focused_runner_container_status" -eq 0 ]]; then
        printf '%s_container_summary_missing=true\n' "$prefix" >&2
        exit 1
    fi
    [[ "$focused_runner_container_status" -eq 0 ]] || exit "$focused_runner_container_status"
elif [[ "$container_mode" = always && ! -s "$debian_path" ]]; then
    printf '%s_container_required_but_empty=true\n' "$prefix" >&2
    exit 1
fi

printf '%s_evidence_path=%s\n' "$prefix" "$evidence_root"
printf '%s_complete=true\n' "$prefix"
