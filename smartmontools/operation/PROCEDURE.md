# Candidate smartd single-check approval

Preparation only. Execute once only after approval of the SHA-256 of
`manifest.json`; every executable and nonsecret input is bound by that manifest.
Target: `ama@10.1.2.170` / `j2-svpi4mf`, explicit `/dev/sda`, ARM64,
JMicron `152d:0583` / `0213`, usb-storage, installed package `7.5-2~bpo13+1`.

Exact controller command, substituting only the approved manifest digest:

```text
PYTHONDONTWRITEBYTECODE=1 python3 /home/aaron/code/.local-evidence/smartmontools-smartd-retry-20261006/bundle/execute-smartd-qualification.py APPROVED_SHA256
```

Latest start: October 6, 2026 at 01:01:25 PM CDT. Baseline expires at
01:06:25 PM CDT. A changed or expired baseline requires review and a new bundle,
not an override or automatic retry. The baseline found no observer, pending host
jobs or failed units. Ordinary smartd/Webmin polling remains active. These are
point-in-time checks, not a global maintenance lock; do not start other storage
maintenance during the trial. The next observed system timer was after 1 p.m.

The controller verifies file hashes and modes, makes an exclusive execution
claim, and stages a root-owned mode-0700 `/var/tmp/smartd-qualification.*` directory.
It changes only that private directory and writes local controller evidence.
The trial verifies baseline identities and candidate version before any disk
access, then invokes exactly this command with TRIAL replaced by that directory:

```text
TRIAL/smartd -d -q onecheck -c TRIAL/smartd.conf -B TRIAL/empty.drivedb -s TRIAL/state/ -A TRIAL/attributes/ -j TRIAL/json/ -r nvmeioctl,2
```

Configuration is exactly one effective line:
`/dev/sda -d sntjmicron -l selftest`.
Registration and the check issue multiple Identify/SMART/Health/self-test-log
reads. There is no self-test schedule, test initiation, scan, mail recipient,
notification command, service registration, package installation, restart,
production state sharing or default database change. Source review establishes
that no mail or warning script is invoked without recipient/command directives.
Debug mode directs logs to captured output and suppresses PID creation. The
corrected command omits -p, which this candidate rejects in debug mode.
State, attributes and JSON are private even on normal exit. Zero-valued state
fields are omitted by this revision's writer.

Candidate execution is bounded at 60 seconds, with 4 MiB per captured stream.
Timeout/output overflow kills only the owned candidate process group and keeps
partial output. If kernel I/O prevents confirmed exit, stop for manual review;
never kill the installed smartd. Observe at least 75 seconds after return on
success or failure. The remote parent has a 420-second emergency bound and the
controller 480 seconds. An emergency termination or transport loss is incomplete,
never acceptance. Do not replay the claim to recover evidence.

Admission checks require a normal exit, actual registration/check completion,
a newly written private state file with zero interpreted self-test error count,
no failure/ignored directive, unchanged immediate/settled counters, journal
cursor coverage, no matched kernel storage fault and preserved production
configuration/binary/service/boot identities. Exit zero is not a smartctl bitmask
and is insufficient: smartd can also exit zero after termination or report a
failed read while completing the cycle. The runner never sets `accepted=true`.

After execution, collect the exact reported remote directory read-only into
private controller storage. Inventory only regular files inside that verified
root-owned directory, bound transfer sizes, and verify each retrieved SHA-256
against a remote manifest. Review actual self-test-log transactions/return data
and private daemon state before accepting admission. Record the candidate exit
and all transport/coverage failures separately. Raw diagnostics and state can
contain disk serials; do not publish them.

Production rollback is unnecessary because production files/services are not
changed. On a fault, preserve evidence and confirm only the owned candidate has
exited; inspect production health read-only and request separate recovery scope
if needed. Do not reboot, stop monitoring, install a database, replace smartd or
remove trial evidence automatically. Cleanup requires verified collection and
exact trial-path ownership. A passing admission allows preparation of a later
repeated-check observation; it does not qualify intermittent-warning resolution
or authorize a daemon upgrade or upstream publication.

The prior failure is preserved in published tag
`smartmontools-smartd-admission-v1-failed`. Its consumed bundle is not reused.
A disk-free native probe confirmed corrected option compatibility by reaching a
deliberately unreadable configuration (exit 6). That is not device qualification.
The empty database emits a missing-DEFAULT warning; it remains deliberately empty.
