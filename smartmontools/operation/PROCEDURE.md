# Candidate smartd 48-hour observation: execution approval

Target: `ama@10.1.2.170`, hostname `j2-svpi4mf`, explicit `/dev/sda`, ARM64,
JMicron `152d:0583` descriptor `0213`, usb-storage, package `7.5-2~bpo13+1`.
Use the admitted candidate SHA-256
`9fa55e0684180152d3c7e8a3a588ab3caea40745b3cecdd8c13179ae21d13221`.
The single-check acceptance is published under
`smartmontools-smartd-admission-v2-accepted` at `3a236a8f00a9689bdd27f2c242d3ff4d531cca99`.

Latest start: October 6, 2026, **2:00:43 p.m. CDT**. Baseline expires at
2:05:43 p.m. CDT. Startup rechecks identity and freshness; expired or changed
inputs stop before candidate device access. No reuse of a consumed claim.

Replace only HASH with the separately approved SHA-256 of `manifest.json`:

```text
PYTHONDONTWRITEBYTECODE=1 python3 /home/aaron/code/.local-evidence/smartmontools-smartd-observation-preparation-20261006/bundle/execute-smartd-qualification.py HASH
```

This stages one root-owned mode-0700 `/var/tmp/smartd-observation.*` directory.
The controller verifies every nonsecret input and claims execution once. It
returns the exact remote directory and submission status. That receipt is not
terminal success. The host-local supervisor detaches from SSH, records its
PID/start-time/boot identity, and runs the foreground candidate in an owned
process group. It does not register a persistent service or rely on the controller
staying connected. The candidate has a parent-death signal; supervisor loss
kills it and makes the observation incomplete, never accepted.

The exact candidate command, with TRIAL replaced by the reported directory, is:

```text
TRIAL/smartd -d -q errors -i 1800 -c TRIAL/smartd.conf -B TRIAL/empty.drivedb -s TRIAL/state/ -A TRIAL/attributes/ -j TRIAL/json/ -r nvmeioctl,2
```

One effective configuration line: `/dev/sda -d sntjmicron -l selftest`.
Run one continuous process for 172,800 seconds (48 hours), retaining initially
empty private state across 1,800-second checks. Require at least 96 successful
monitoring self-test-log reads; registration does not count. No self-test is
started, no mail/notification recipient is configured, and no production files,
default databases, packages, service state or monitoring policy are changed.
No reboot, production replacement, extra trial or upstream publication is included.

The retained warning pair rose and recovered about 30 minutes apart within a
48-hour query. Full historical retention is not established. This motivates a
bounded observation; it neither estimates recurrence probability nor guarantees
that the original condition will recur. Production smartd/Webmin remain active.
Normal timers, including apt maintenance, stay enabled. This is not an exclusive
quiet window; identity/counter/evidence drift stops the trial for review.

The supervisor enforces observed command/initial-check deadlines of 60 seconds,
a maximum 1,920-second gap between completed checks, 16 MiB per output stream,
15-second independent audits with five-second audit deadlines, owned-process
shutdown, and at least 75 seconds of post-exit observation. A forced kill,
unconfirmed exit, cancellation or missing coverage is incomplete. Exit status
zero from smartd alone cannot establish completion or acceptance. Raw candidate
diagnostics, private state and terminal membership checks remain available for
manual review; no automated result sets `accepted=true`.

Journald uses volatile storage. Every audit verifies its previous cursor, captures
through the last record actually returned, and durably appends kernel and
production-smartd records plus cursor/hash receipts before advancing. Unrelated
journal messages are not saved. Any cursor loss stops the trial. Per-log bounds
are 32 MiB for kernel and production logs and 16 MiB for checkpoint receipts.
At least 256 MiB free is required at startup; audits stop below 64 MiB. Boot/time,
production files/services, frozen private input metadata, observer inactivity,
counters and private self-test state are checked throughout. A candidate warning,
unexpected command, nonzero interpreted self-test count or kernel storage fault
stops observation. Command diagnostics detect an unexpected command after issue;
prevention relies on the pinned binary and exact restricted configuration.

For read-only status, use the exact remote path from the original receipt:

```text
PYTHONDONTWRITEBYTECODE=1 python3 /home/aaron/code/.local-evidence/smartmontools-smartd-observation-preparation-20261006/bundle/execute-smartd-qualification.py HASH status REMOTE_ROOT
```

This verifies the frozen inputs and binds the path to the receipt. It does not
restart or extend the observation. Capture each response privately. States are
submitted, running, stopping and terminal complete/failed/cancelled; a stale
supervisor identity is reported as lost_supervisor. Check initial readiness,
then at 2, 24 and 48 hours, plus faults. The host-local audits continue between
operator checkpoints. Preserve one controller submission; reconnect for status
rather than re-running start.

Initial live readiness requires a new SSH status request after the submitting
connection has closed, with the supervisor alive and at least one completed
monitoring check. Local disconnection tests do not prove the target's login-session
cleanup behavior. If the supervisor disappears, record an incomplete launch and
do not retry or change login/service policy under this approval.

Cancellation is limited to the owned supervisor and its candidate:

```text
PYTHONDONTWRITEBYTECODE=1 python3 /home/aaron/code/.local-evidence/smartmontools-smartd-observation-preparation-20261006/bundle/execute-smartd-qualification.py HASH cancel REMOTE_ROOT
```

Cancellation opens a PID handle and rechecks PID/start-time/boot identity before
signalling. A second cancel cannot interrupt settling. A request receipt is not
proof of terminal cancellation: read status until terminal and verify candidate
exit. Never signal the installed smartd or kill by process name. If identity or
exit cannot be established, stop for manual recovery review rather than guessing.

After terminal status, collect bounded regular files only from the verified
root-owned trial directory, preserve raw evidence privately, and independently
match retrieved SHA-256 values. Review all monitoring transactions, private
state, production warning timestamps, cursor receipts, counters, service/boot
continuity, exits and settling before accepting any result. A complete quiet
run qualifies bounded operation on this host only. If production warnings do
not recur, report non-reproduction rather than proof of elimination.

No production rollback is required. Keep trial files for verified collection
and terminal archival; cleanup is a later exact-path action. Do not mutate the
production journal configuration or automatically restart an interrupted trial.
Native 48-hour behavior remains unqualified; local tests and native disk-free
option/runtime checks qualify preparation, not the eventual live outcome.
