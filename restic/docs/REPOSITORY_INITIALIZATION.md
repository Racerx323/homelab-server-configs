# Restic repository initialization

## Purpose

Use this procedure to initialize exactly one reviewed, empty Restic repository.
Initialization is a standalone mutation. It must not be hidden inside a backup,
restore, deployment, or read-only preflight.

The consumer owns the active operation, target, repository identity, execution
user, acceptance decision, and terminal history. This Restic component owns the
reusable command, secret-handling, failure, and evidence boundaries.

## Required reviewed inputs

Before readiness, the consumer operation must record:

- the accepted provider endpoint, bucket, and exact prefix;
- the exact Restic repository URL;
- the execution user and reviewed Restic version;
- the repository-password secret reference;
- a confirmed password-recovery locator independent of the primary secret
  store;
- the initialization owner; and
- evidence that a separately authorized read-only preflight classified the
  exact repository config as absent.

For a host-executed consumer operation, also require a terminal accepted-live
host-baseline identity. Hardware qualification, storage soak, package presence,
and repository-absence evidence are independent gates and do not by themselves
accept the host baseline.

The recovery locator identifies an existing protected recovery record. It must
not contain the password and must not claim that the primary Doppler secret is
its own recovery copy.

## Protected execution contract

Disable shell tracing and set `umask 077` before resolving credentials or
creating files. Create one unique operation-owned directory outside Git with
mode `0700`. Write the repository URL and repository password into separate
mode-`0600` files. Supply the accepted Backblaze key only through the protected
process environment as `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

Run initialization once as the reviewed consumer execution user:

```text
restic --no-cache \
  --repository-file PROTECTED_REPOSITORY_FILE \
  --password-file PROTECTED_PASSWORD_FILE \
  init --repository-version stable
```

Immediately record whether the mutation was attempted and its exit status
before evaluating later gates. On success, read back the config without a
cache or repository lock:

```text
restic --no-cache --no-lock \
  --repository-file PROTECTED_REPOSITORY_FILE \
  --password-file PROTECTED_PASSWORD_FILE \
  cat config
```

The current reviewed contract expects Restic's stable repository format,
version 2. A future Restic release that changes `stable` requires a definition
review before execution.

## Absence gate

The read-only preflight must use the same repository URL, credentials, and
password reference. Restic exit status 10 from the exact lock-free, cache-free
`cat config` command may classify the config as absent. Authentication,
authorization, network, TLS, rate-limit, malformed-response, timeout, or other
errors are ambiguous and must stop the operation.

Never turn a generic command failure into permission to initialize. Do not
combine `cat config` and `init` in a conditional shell expression.

## Acceptance

Accept initialization only when:

1. the exact accepted endpoint, bucket, prefix, and repository URL were used;
2. the expected execution user and reviewed Restic version were observed;
3. protected directories and files used modes `0700` and `0600`;
4. the separately authorized absence gate passed;
5. one initialization command succeeded;
6. `cat config` reports format version 2 and a 64-character lowercase
   hexadecimal repository ID;
7. no local cache or repository lock was created; and
8. bounded evidence contains no password or application-key value.

## Failure and recovery

Before `init`, cleanup may remove only proven operation-owned protected local
files. After an `init` attempt, do not retry automatically: an error may have
occurred after the repository config was written. Preserve sanitized evidence,
classify the exact remote state with a new read-only operation, and require a
new authorization for any follow-up.

This procedure never authorizes repository or bucket deletion, object cleanup,
password rotation, repository repair, backup upload, or Restic deployment.

## Local implementation and readiness boundary

The Nautobot consumer now provides:

- `Nautobot/ansible/scripts/run-restic-initialization.py`: active-operation,
  accepted-host/provider, clean-source and bundle gates; uses the existing
  bounded credential-delivery utilities and repository Ansible wrapper;
- `Nautobot/ansible/playbooks/initialize-restic-repository.yaml`: unique protected
  staging, target/user boundary, invocation and unconditional secret cleanup;
- `restic/scripts/initialize-repository.py`: single-use command boundary with
  node-local durable attempt/result records and bounded output; and
- `restic/tests/test_initialization.py`: offline failure injection.

The small node helper owns the interruption-sensitive record boundary around
`init`; it does not replace Ansible deployment orchestration. It records intent
before mutation, the command result before readback, and only allowlisted status
fields. It discards raw command output. Exact version comparison precedes fresh
absence detection. It verifies format/ID and lists repository locks read-only
before returning `initialized_review_required`. Neither that result nor the
launcher exit code grants acceptance.

The active convergence operation is rejected before credentials are resolved.
The unchanged historical deferred initialization contract and schema still mark
initialization unimplemented/unready. That record describes its original review;
these new files are locally tested candidates, not permission to reactivate it.
Activation must review/update the schema and contract, bind terminal accepted
host/provider identities, review fresh read-only absence evidence and exact
version, produce the final bundle and obtain scoped live authorization. Do not
bypass those gates with direct playbook invocation or extra-variable overrides.

Local checks (from repository root):

```bash
PYTHONDONTWRITEBYTECODE=1 python3 restic/tests/test_initialization.py
/bin/bash tests/repository/run-with-ansible-local-temp.sh \
  ansible-playbook --syntax-check --inventory inventory/prod/hosts.yaml \
  Nautobot/ansible/playbooks/initialize-restic-repository.yaml
python3 Nautobot/ansible/scripts/run-restic-initialization.py show-command
```

No live initialization has been exercised. Before readiness, qualify target
privilege/ownership, exact installed Restic behavior, protected staging and
remote cleanup through the reviewed deployment path. If SSH becomes unreachable,
remote credential cleanup is unknown: preserve controller evidence, recover access
and inspect the retained directory before further work. Missing node records
mean unknown mutation state, never proof that initialization was not attempted.

The retained remote `/tmp/nautobot-restic-init.*` directory contains the helper
and sanitized records after credential removal; it is intentional evidence, not
secret residue. Do not delete it until terminal evidence is safely retained.
Do not retry after an attempted initialization, including a new staging directory,
without fresh state classification and authorization.

CLI contract references: [Restic scripting](https://github.com/restic/restic/blob/master/doc/075_scripting.rst),
[repository formats](https://github.com/restic/restic/blob/master/doc/030_preparing_a_new_repo.rst),
and [object listing](https://github.com/restic/restic/blob/master/doc/100_references.rst).
