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
