# Configuration diagnostic authorization

Bundle SHA-256: `fdcc26eadc64e103f732273a5894ee1340f3878ba28f4a27693e317df8f583ca`

Target: `ama@10.1.2.170` (`j2-svpi4mf`).

Execute:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 /tmp/nautobot-configuration-diagnostic-20260922/run-startup-diagnostic.py execute fdcc26eadc64e103f732273a5894ee1340f3878ba28f4a27693e317df8f583ca
```

Scope: stage private helper files; verify expected boot, installed nonsecret
hashes and image; arm a twenty-minute cleanup guard; temporarily start only
PostgreSQL and Redis; run only `nautobot-server check` in a disposable rootless
container with the installed migration environment and configuration; preserve
bounded redacted failure text privately; remove only the matching labeled probe;
stop all runtime processes. Normal PostgreSQL/Redis activity can write volumes.

Cleanup acceptance: explicit zero MainPID/ControlPID, inactive/dead or
failed/failed units, no containers. Preserve the failed migration marker.
Only after cleanup proof, stop the new timer and prior startup timer
`nautobot-startup-08gcyvou.timer`. If cleanup fails, retain guard and report.
No production volume deletion/restoration, application startup, migration,
bootstrap, network changes, package changes, commit or push is included.
A native check failure is a valid diagnostic capture, not acceptance.

Local checks: 36 startup tests passed, including real Ansible terminal-state
readiness, redacted native diagnostics, cursor extraction, processless failed
state handling and diagnostic scope/foreign-container protection. Frozen
playbook syntax passed. No live execution of this bundle has occurred.
