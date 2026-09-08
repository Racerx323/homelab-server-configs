# Read-only Restic repository preflight

## Purpose

Use this preflight to verify an existing Restic repository before a consumer
defines a backup, check, or restore operation. The preflight reads the remote
repository config object. It does not initialize the repository, create a lock,
populate a local cache, enumerate snapshots, or write backup data.

The consumer must supply the reviewed non-secret endpoint, bucket, optional
prefix, and initialization owner before execution. The preflight confirms the
repository initialization state and records the repository ID. It cannot infer
the initialization owner from Restic metadata.

## Required inputs

Record these non-secret values in the consumer's active operation:

- the Backblaze S3-compatible endpoint hostname;
- the dedicated private bucket name;
- the exact repository prefix, including an explicit empty prefix; and
- the person, role, or governed operation that initialized the repository.

Supply credentials at execution through protected files or the approved
secrets provider. Keep the repository password, application key ID, and
application key out of Git, command arguments, logs, and evidence.

## Command contract

Run the commands as the consumer's approved execution user. Resolve secrets
with shell tracing disabled. Set `umask 077` before creating protected files.

```text
restic version
restic --no-cache --no-lock \
  --repository-file PROTECTED_REPOSITORY_FILE \
  --password-file PROTECTED_PASSWORD_FILE \
  cat config
```

The repository file must contain this exact non-secret location:

```text
s3:https://ENDPOINT/BUCKET/PREFIX
```

Pass `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` through the protected
execution environment. Do not print the environment or enable command tracing.

`--no-cache` prevents local cache creation. `--no-lock` prevents Restic from
writing a lock object. `cat config` reads the repository config and returns its
format version and repository ID. Do not replace it with `check`, `snapshots`,
`stats`, or a conditional `init`; those commands exceed this preflight.

## Acceptance

Accept the preflight only when all checks pass:

1. the execution user and installed Restic version match the reviewed
   operation;
2. the repository file matches the reviewed endpoint, bucket, and prefix;
3. `cat config` succeeds with `--no-cache --no-lock`;
4. the returned repository ID has 64 lowercase hexadecimal characters;
5. the config reports a supported repository format version;
6. no cache path or repository lock object is created; and
7. bounded evidence contains no credential or password value.

A successful `cat config` proves that the supplied location identifies an
initialized repository that the supplied credentials can read. A missing
config object, authentication failure, or network failure does not prove that
the location is safe to initialize. Stop and classify the cause before any
repository mutation.

## Initialization absence classification

For a separately governed initialization operation using Restic 0.17 or newer,
exit status 10 from this exact `cat config` command classifies the repository
config as absent. Exit status 0 means the repository already exists. Exit
status 11 means locked, exit status 12 means the password is incorrect, and
every other status is ambiguous. None of those other results authorizes
initialization.

For the Nautobot consumer, retrieve the three credential values from their
reviewed Doppler references on the controller. Write them only to a unique
mode-`0700` protected controller directory and pass the resulting mode-`0600`
Ansible extra-vars file by path, never by value on the command line. The
playbook creates a unique mode-`0700` directory owned by `nautobot` on the
target, writes the repository, password, and AWS credential files with mode
`0600`, invokes Restic as `nautobot`, records sanitized status observations
before its absence assertion, and removes that exact directory in an `always`
block. Raw Ansible output remains protected and outside Git.

The transient protected files are execution mechanics, not persistent host
configuration. Their creation requires separate preflight authorization and
their absence after both success and failure is mandatory.

## Evidence

Capture only:

- the execution user and Restic version;
- the endpoint, bucket, prefix, repository format version, and repository ID;
- command status and bounded sanitized stderr; and
- confirmation that the protected directory and files used modes `0700` and
  `0600`.

Keep raw evidence outside Git. A consumer may place sanitized results and
evidence hashes in its terminal operation archive after execution.

## Excluded actions

This preflight does not authorize `init`, `backup`, `restore`, `check`,
`snapshots`, `stats`, `unlock`, `forget`, `prune`, `repair`, repository or
snapshot deletion, retention changes, or secret-system changes. It does not
contact a consumer host until the user authorizes the exact read-only command.
