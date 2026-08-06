# Repository Agents

This document outlines the various automated agents and services that have access to and interact with this repository. Understanding their roles is key to maintaining a secure and efficient workflow.

---

## GitHub Actions

- **Purpose**: Automates workflows such as testing, building, and deploying code based on triggers like pushes, pull requests, or scheduled events.
- **Configuration**: Workflows are defined in YAML files located in the `.github/workflows` directory.
- **Permissions**: Permissions are granted on a per-workflow basis and are scoped to be as restrictive as possible. See each workflow file for its specific permissions.

---

## Dependabot

- **Purpose**: Automatically keeps dependencies up-to-date by scanning for outdated packages and opening pull requests to update them. This helps to patch vulnerabilities and use the latest features.
- **Configuration**: The configuration for Dependabot is located in the `.github/dependabot.yml` file.
- **Scope**: Currently configured to monitor:
  - GitHub Actions (`.github/workflows/*.yml`)

---

## Code Style Linter

- **Purpose**: To automatically check the codebase against a set of style rules to ensure consistency and readability. This repository adheres to the **Google Style Guides**.
- **Configuration**: This is typically configured as a step within a GitHub Actions workflow (e.g., `.github/workflows/lint.yml`) that runs on pull requests or pushes. It can use tools like `Super-Linter`.
- **Permissions**: Requires read-only permissions to check out and analyze the repository's code.

---

## Codecov

- **Purpose**: To upload code coverage reports to Codecov to track the percentage of the codebase that is tested.
- **Configuration**: This is typically configured within a GitHub Actions workflow (e.g., in a file within `.github/workflows/`) to run after tests and upload the results.
- **Permissions**: It generally requires permissions to read repository contents and, in some configurations, to post comments on pull requests with coverage information.

---

## CodeRabbit reviews

CodeRabbit requires external network access. Run all `coderabbit review` commands with network escalation (`sandbox_permissions: "require_escalated"`). Request the reusable approval prefix `["coderabbit", "review"]`.

Do not wait for a sandboxed review to time out. If it stalls while connecting, rerun it immediately with network escalation.

---

## Security Considerations

- **Least Privilege**: Each automated agent should operate with the minimum permissions necessary to perform its tasks. Review and adjust permissions regularly.
- **Secrets Management**: Sensitive information such as API keys and tokens should be stored securely using GitHub Secrets and not hard-coded in workflows.
- **Dependency Updates**: Regularly review and merge Dependabot pull requests to keep dependencies up-to-date and reduce the risk of vulnerabilities.
- **Monitoring and Alerts**: Set up monitoring for automated workflows to detect and respond to any unusual activity or failures.

---

## Testing instructions

- Fix any test or type errors until the whole suite is green.
- `Caddy/tests/run.sh` is a Podman wrapper, not a host-only test command. Run it
  outside the filesystem sandbox on its first attempt with the narrowest
  applicable scoped escalation because its final integration phase requires
  the rootless runtime under `/run/user`.
- Run focused Debian validation only through
  `Caddy/tests/run-focused-container.sh Caddy/tests/TEST_SCRIPT`. The wrapper
  owns the validation image's existing Bash entrypoint, passes `-lc` directly
  instead of supplying a second `/bin/bash`, exports the required
  `CADDY_VALIDATION_CONTAINER=1` marker, disables networking, and mounts the
  workspace read-only. Treat this wrapper as a Podman command and run it
  outside the filesystem sandbox on its first attempt. Do not construct ad hoc
  focused `podman run` invocations.
- The repository `.vscode` directory contains shared configuration and must
  remain trackable. Preserve the root-anchored `!/.vscode/` and
  `!/.vscode/**` rules in `.gitignore`, and run
  `Caddy/tests/vscode-tracking-policy-regression.sh` after ignore-policy
  changes.
- After moving files or changing imports, check that all files or imports adhere to the project's coding standards.
- Add or update tests for the code you change, even if nobody asked.
- Run linters and formatters to ensure code quality. For shell files, never run
  bare `shfmt -w`; use
  `Caddy/tests/shfmt-canonical.sh --write FILE [FILE ...]`. Use `--check` for
  validation. The wrapper pins the repository's `-i 4 -ci` policy and rejects
  empty, broad, symbolic-link, and unapproved-repository targets.
- Every tracked `Caddy/scripts/*.sh` and `Caddy/tests/*.sh` Bash entry point
  must be executable in both the working tree and Git index (`100755`). Local
  `core.fileMode=false` can conceal an index-mode defect, so never accept
  `test -x` alone. Run
  `Caddy/tests/executable-wrapper-policy-regression.sh`; it enumerates the
  tracked set and rejects both working-tree and index mode `0644`, including
  explicit negative controls.
- Keep workstation source ownership checks out of container integration
  commands. Regressions that need a runner's `--source-test` must invoke
  `Caddy/tests/run-source-test-in-context.sh --runner RUNNER`. The policy
  executes the source test only with `aaron:aaron:755` ownership on the
  workstation. In the validation container it accepts only the explicit
  `CADDY_VALIDATION_CONTAINER=1`, `/workspace/...`, `root:root:755`
  read-only bind-mount projection. Do not add ad hoc ownership exceptions.
- Every fail-closed infrastructure validator must emit one uniquely labeled
  assertion per observable condition. Never combine multiple commands,
  queries, comparisons, or mutation results under one assertion label.
  Every new transactional outer wrapper must expose its canonical local-gate
  inventory through `--expected-local-gates`; host and Podman suites must run
  `Caddy/tests/outer-local-gate-label-policy-regression.sh --runner WRAPPER`.
  The policy must reject missing, duplicate, false, and unexpected gate labels.
  A silent aggregate `run_local_gates` boundary is prohibited.
  DNS readiness blocks must record each server, port, name, type, command
  status, and safe observed answer independently before deriving an overall
  decision. Enforce marked DNS readiness blocks with
  `Caddy/tests/labeled-dns-readiness-policy-regression.sh`.
- Cross-script transcript consumers must validate the actual producer grammar
  and label inventory, not a hand-authored approximation. A synthetic-only
  success fixture is insufficient. The producer must expose its expected labels
  or a canonical transcript fixture, and the consumer regression must accept
  that exact contract while rejecting a wrong record prefix or kind, a missing
  label, and a duplicate label. Never copy a producer record name into a
  consumer without exercising the real producer contract in regression tests.
  When a suite wires an entry point whose self-test or contract-test requires
  arguments, its production regression must also verify the suite's exact
  invocation signature in both `Caddy/tests/run.sh` and
  `Caddy/tests/integration.sh`; a directly passing test is not sufficient.
- Enforce the cross-script transcript rule with
  `Caddy/tests/transcript-contract-ratchet-policy-regression.sh`. Its historical
  exception manifest is an immutable-hash ratchet, not permission to reuse a
  deficient runner for a new live action. Before reusing any historical runner,
  run the ratchet and audit that runner against the current producer contract.
  A runner listed for an arbitrary assertion minimum or a regression listed for
  synthetic check fixtures must be replaced by an append-only corrected action
  before another live invocation. New exceptions are prohibited. Consumers
  must reconcile the producer's exact exported label inventory; `-ge`/`-gt`
  assertion-count acceptance and hand-authored numbered success labels are not
  valid contracts.
- Treat temporary deployment staging filesystems such as `/run` and `/tmp` as
  potentially mounted `noexec`. Invoke every staged Bash artifact explicitly
  with `/bin/bash`; never execute it directly by pathname. A regression for a
  staged runner must exercise a non-executable-but-readable script fixture and
  prove that the production path still reaches it through `/bin/bash`.
- A generated validator is not accepted through syntax, static text, or a
  synthetic transcript alone. Its regression must execute every newly inserted
  production assertion from the rendered artifact, including both true and
  false fixtures, and must consume the real upstream producer output. Never
  fabricate producer summary markers in a fixture; derive or capture them from
  the producer's canonical contract.
- Never rely on `set -e` or `set -E` to propagate a failure from a validator
  function. Bash disables errexit semantics when a function is evaluated by
  `if`, `!`, `&&`, or `||`, so a later successful command can overwrite an
  earlier failure. Every predicate, comparison, parser, and nested validator in
  a conditional validator must use an explicit `|| return`, a guarded `if`, or
  an equivalent explicit status return. Mark straight-line validator regions
  with `conditional-validator-explicit-failures-begin` and
  `conditional-validator-explicit-failures-end`, and enforce them with
  `Caddy/tests/conditional-validator-errexit-policy-regression.sh`. Every new
  validator regression must include an early-invalid/later-valid transcript and
  prove rejection, covering both false-positive and false-negative behavior.
  Any custom predicate or policy helper passed through `require_gate`, `if`,
  `!`, `&&`, or `||` must mark its assertion body even when it appears small;
  an unmarked helper is not an accepted validation boundary. When a fallible
  command and its explicit return span separate physical lines, mark the
  return line with `conditional-validator-requires-return` so the policy
  verifies the boundary instead of relying on visual review.
- Every new shell regression must pass itself and every generated or invoked
  shell artifact through
  `Caddy/tests/check-shell-readonly-local-collisions-v2.sh` before invoking
  those artifacts. It must include a negative dynamic-scope collision fixture
  and an early-invalid/later-valid production-helper fixture, require both to
  be rejected, and require the regression's own stderr to remain empty. A
  later successful assertion never converts an earlier shell diagnostic into
  a passing regression. Run the repository-wide collision and conditional
  validator policies before focused action tests; do not wait for the complete
  suite to discover these defects.
- A live transactional command whose stdout or stderr affects acceptance must
  capture both streams during that same execution. Before testing emptiness or
  content, emit independently labeled, bounded byte count, line count,
  SHA-256, and safe classification records. Metadata alone is not sufficient:
  after classification, emit bounded safe content between explicit begin/end
  labels, or retain it at a reported protected path with exact ownership, mode,
  and hash. Record empty streams explicitly. Suppress unsafe content and retain
  it only in a protected evidence path for separately authorized inspection.
  Never defer stream capture to a follow-on action, delete the only useful
  capture before its evidence outcome is secured, or print unclassified raw
  output. Preserve historical deficient actions only behind an exact immutable
  hash exception, and require corrected or new actions to pass
  `Caddy/tests/transaction-output-evidence-policy-regression.sh`.
- During the active Caddy deployment, validate an ordinary action definition or
  correction with its focused host tests, the equivalent focused Debian 12
  Podman slice, and every policy that governs the changed boundary. Run the
  complete preserved historical host/Podman suite only when an action changes
  deployment category, immediately before Caddy VRRP activation, and at final
  deployment acceptance. A focused slice must exercise the real production
  functions and both false-positive and false-negative controls; it is not a
  synthetic-fixture shortcut. A failure outside the focused action remains
  recorded but does not invalidate a passing focused gate unless it exposes a
  shared policy or dependency failure. Do not remove, consolidate, or rewrite
  historical action tests during deployment. A manifest-driven focused runner
  and historical-suite streamlining remain post-deployment work.
- Make sure to test edge cases and error handling.
- Document any new features or changes to existing functionality.
- Ensure all changes are backward compatible.
- Update any relevant documentation or comments in the code.

---

## PR instructions

- **Title format**: [&lt;project_name&gt;] &lt;Title&gt;
- **Description**: Provide a clear and concise description of the changes made in the PR.
- **Related Issues**: Link any related issues or pull requests.
- **Checklist**:
  - [ ] Code is well-tested
  - [ ] Documentation has been updated
  - [ ] Changes have been reviewed by at least one other person


## vexp <!-- vexp v2.1.7 -->

**MANDATORY: use `run_pipeline` - do NOT grep or glob the codebase.**
vexp returns pre-indexed, graph-ranked context in a single call.

### Workflow
1. `run_pipeline` with your task description - ALWAYS FIRST (replaces all other tools)
2. Make targeted changes based on the context returned
3. `run_pipeline` again only if you need more context

### Available MCP tools
- `run_pipeline` - **PRIMARY TOOL**. Runs capsule + impact + memory in 1 call.
  Auto-detects intent. Includes file content. Example: `run_pipeline({ "task": "fix auth bug" })`
- `get_skeleton` - compact file structure
- `index_status` - indexing status
- `expand_vexp_ref` - expand V-REF placeholders in v2 output

### Agentic search
- Do NOT use built-in file search, grep, or codebase indexing - always call `run_pipeline` first
- If you spawn sub-agents or background tasks, pass them the context from `run_pipeline`
  rather than letting them search the codebase independently

### Smart Features
Intent auto-detection, hybrid ranking, session memory, auto-expanding budget.

### Multi-Repo
`run_pipeline` auto-queries all indexed repos. Use `repos: ["alias"]` to scope. Run `index_status` to see aliases.
<!-- /vexp -->
