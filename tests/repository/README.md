# Repository validation helpers

This directory owns shared formatting and shell-safety checks. Component behavior
stays in component tests. These helpers do not stage deployments, contact targets
or establish production acceptance.

| Helper | Purpose and limits |
| --- | --- |
| `shfmt-canonical.sh` | Explicit-file formatting/checking with repository flags; rejects symlinks and paths outside this repository and the approved Munin source. Never run bare `shfmt -w`. |
| `yamllint-canonical.sh` | Strict YAML checks. Two exact current operation files allow consistent indentless sequences to preserve approved bytes. Archived workload path exceptions have been retired from main. |
| `run-with-ansible-local-temp.sh` | Creates one mode-0700 controller temporary directory, preserves command status and removes it on exit. It adds no inventory, privilege or transport behavior. |
| `run-with-ansible-local-temp-regression.sh` | Checks unique directories, permissions, cleanup and failure-status preservation using local commands. It does not qualify Ansible itself. |
| `portable-awk-policy.sh` | Detects unsupported interval expressions in the shell AWK forms it recognizes. Static scan, not a complete shell parser. |
| `multifile-grep-count-policy.sh` | Uses the shfmt AST to reject ambiguous multi-operand grep counts. Conservative argument-shape check, not semantic proof of every possible grep invocation. |
| `remote-streamed-bash-policy.sh` | Checks recognized SSH/streamed Bash forms in `scripts/*.sh`. It does not inspect Python-built SSH commands or authorize execution. |
| `run-policy-self-tests.sh` | Runs the three shell-policy self-tests and temporary-directory regression. Formatter checks remain separate. |

Run shared regressions and scoped formatting checks from the repository root:

```bash
/bin/bash tests/repository/run-policy-self-tests.sh
/bin/bash tests/repository/shfmt-canonical.sh --check PATH_TO_CHANGED_SCRIPT
/bin/bash tests/repository/yamllint-canonical.sh PATH_TO_CHANGED_YAML
```

`portable-awk-policy.sh --check` without file arguments scans tracked shell files;
with explicit paths it checks only those paths. Other policy hooks receive file
arguments from pre-commit. Use `/bin/bash` for shell entrypoints.

Pre-commit selects checks for changed inputs. Nautobot behavioral checks retain
conservative executable/schema/shared-helper coverage, but roadmap edits and
unrelated test files no longer select all behavioral suites. Documentation/link
checks still run. CI's `Nautobot/tests/run-validation.py` runs the complete offline
suite with `--all-files`; opt-in native runtime tests remain explicit. Neither
local nor CI success establishes target capacity.

Keep Caddy lifecycle checks scoped to Caddy. The readonly/local name-collision
check currently resides under `Caddy/tests/` but is a shared shell-language safety
check; its location does not make it a Nautobot deployment prerequisite.
