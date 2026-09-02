# Upstream proposal: handle SIGTERM through graceful shutdown

## Target

- Repository: `Dyneteq/reconya`
- Affected release: v0.26.0
- Confirmed current branch behavior: `master` on September 2, 2026
- Component: `backend/cmd/main.go`

## Proposed issue title

```text
Handle SIGTERM through the existing graceful shutdown path
```

## Proposed issue body

The exact public text is maintained in
[`upstream-sigterm-issue-body.md`](upstream-sigterm-issue-body.md). It excludes
the private hostname and other environment-specific identifiers.

## Pull-request plan

1. Add `syscall.SIGTERM` to the shutdown notification set and remove it from
   `signal.Ignore`.
2. Add the subprocess regression test described in the public issue body.
3. Run the Go test suite and a Linux service-level stop test.
4. Update shutdown documentation and release notes.

J1-SVMF should retain `KillSignal=SIGINT` until a released binary passes the
same controlled `SIGTERM` stop test.

## Submission record

The duplicate check found no open or closed issue containing `SIGTERM`. The
proposal was submitted on September 2, 2026 as
[Dyneteq/reconya issue 145](https://github.com/Dyneteq/reconya/issues/145).
The public issue title and body were read back after creation and matched the
reviewed repository artifacts.
