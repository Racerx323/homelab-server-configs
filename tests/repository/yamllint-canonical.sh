#!/usr/bin/env bash
set -euo pipefail

# Preserve hash-bound operation bytes, including PyYAML's valid indentless
# sequences. All other YAML retains the repository's default indentation rule.
yaml_regular=()
yaml_operation=()
for yaml_file in "$@"; do
    case "$yaml_file" in
        Caddy/manifests/serving-health-operation.yaml | \
            Nautobot/manifests/operation.yaml | \
            Nautobot/terminal/workload/terminal-operation.yaml | \
            Nautobot/terminal/workload/controller-start-failure/sources/Nautobot/manifests/operation.yaml | \
            Nautobot/terminal/workload/executed/sources/Nautobot/manifests/operation.yaml)
            yaml_operation+=("$yaml_file")
            ;;
        *)
            yaml_regular+=("$yaml_file")
            ;;
    esac
done
if ((${#yaml_regular[@]})); then
    yamllint --strict "${yaml_regular[@]}"
fi
if ((${#yaml_operation[@]})); then
    yamllint --strict -d \
        '{extends: .yamllint.yml, rules: {indentation: {indent-sequences: consistent}}}' \
        "${yaml_operation[@]}"
fi
