# Host foundation tasks

These native Ansible tasks provide the host-owned phase of a reviewed application
operation. They are not a standalone fleet installer. Inventory selects the host;
the caller provides exact package payloads, observed baseline identities and its
qualified operation. No inventory flag triggers execution.

Uptime Kuma's [change record](../../homelab-monitoring-observability/changes/2026-11-09-uptime-kuma/WORK.md)
owns its current candidate and approval. The application coordinator imports this
phase; no second transaction runner or parallel project ledger is introduced.

## Ownership and selected profiles

- [Needrestart](../Needrestart/README.md) owns the producer and daily 05:30 cron
  policy. Its `rpi-v8-list-only` profile preserves the Raspberry Pi vendor file,
  selects only v8 images and prevents automatic service restarts. Batch mode
  explicitly checks kernels even when the vendor kernelhints setting is zero.
- [Webmin](../Webmin/README.md) owns its pinned installation asset, configuration
  helper and `ssh-loopback` profile. Keep port 10000 on loopback, permit only
  `ama` through existing sudo/PAM, and require operator login acceptance.
- [Fleet msmtp](../../homelab-dns/msmtp/docs/FLEET_AUDIT_STANDARDIZATION_PROMPT.md)
  owns mail accounts/aliases. Its desired default is Mailrise (`apprise` account);
  Mailgun is explicitly selected and secret references remain external.
- [Watchdog](../watchdog/readme.md) owns adoption and recovery qualification.
  For the observed Pi, adopt the unchanged vendor systemd owner and 60/120-second
  policy; do not install another daemon or claim tested hardware-expiry recovery.

## Installation and failure boundaries

`preflight.yaml` checks absent application-owned paths, package baseline and
unchanged vendor inputs before the first prerequisite change. `prepare.yaml`
installs a persistent Webmin start condition before its package can request a
direct start, and a temporary package-start denial. Needrestart is suspended only
during package installation; the durable profile remains list-only afterward.

The scoped `APT_CONFIG` selects a private apt-listchanges profile with no email
address. Existing host configuration and hooks are preserved. Do not rely on
`DEBIAN_FRONTEND=noninteractive` or frontend selection alone to suppress email.

After exact package acceptance, `configure.yaml` applies owned mail/Webmin
configuration and removes the temporary package-start policy. `accept.yaml`
checks native sockets, service limits, non-sending SMTP connectivity, actual
needrestart batch reporting and the original watchdog owner/settings. Repeat
these checks after the approved reboot and after application promotion.

The caller enables the Needrestart owner schedule only after combined acceptance
and private administrator setup. A bounded systemd scope caps each daily scan at
96 MiB, no swap and one CPU. Normal daily notifications are an explicit effect
of schedule enablement; this does not authorize synthetic test messages.

On failure, `contain.yaml` removes the owned schedule and Webmin permit, requests
Webmin stop/disable and verifies no TCP listener. Keep the persistent guard.
Packages and configuration may remain. An interrupted installation may retain
`policy-rc.d`; inspect actual state before separately reviewed recovery. Do not
remove packages, change the vendor watchdog or claim whole-host rollback.

Local AMD64 parsing/runtime results are not ARM64 acceptance or proof of hardware
watchdog expiry. Keep raw package, service and qualification evidence private.

## Continue from installed package residue

`installed-preflight.yaml` verifies the reviewed package pins, stopped and disabled
Webmin, absent permit/package-start policy/schedule, and unchanged mail,
needrestart and persistent guard files. It never installs packages. The caller
also verifies accepted boot/address state and absent application state.

`resume.yaml` applies the selected Webmin profiles under a native five-minute
startup containment timer. Foundation acceptance must pass before cancelling the
timer and proceeding to application installation. Failure cleanup verifies the
stopped/disabled service and absent listeners before cancelling an owned fallback;
if the controller disconnects during this phase, PID1 removes the permit and
stops/disables Webmin. Packages and the corrected collection setting may remain.
Needrestart acceptance uses a 96 MiB/no-swap transient service with a 90-second
native runtime bound. Real hardware watchdog and kernel acceptance remain target
checks; disposable containers cannot establish them.

## Measure scan-time headroom

`scripts/observe-needrestart.py` measures one list-only needrestart scan under
the existing 96 MiB/no-swap/one-CPU budget. The caller supplies a fresh protected
volatile directory and runs the observer under its separate 32 MiB/no-swap cap
and 120-second native lifetime. The scan uses a native oneshot service with a
90-second start timeout and five-second stop timeout. RemainAfterExit retains
systemd's exact MemoryPeak until the observer reads it and stops the unit.
This helper does not invoke the notification producer or enable its schedule.

Samples include host MemAvailable and every visible finite ancestor cgroup's
remaining allowance, excluding the observer's own cap. A sample below the 96 MiB
reserve stops the scan. Record the actual sample gaps; gaps above one second,
missing samples while the scan runs, missing native peak/no-swap evidence or
cleanup failure reject the measurement. The nominal interval is 200 ms; this
does not exclude shorter dips between samples. Observer overhead is included,
never estimated away. Retain the receipt on failure as well as success.
Before launching the scan, the already-running observer requires 192 MiB of host
and finite-parent headroom: the scan's full 96 MiB cap plus the 96 MiB reserve.
This fresh check includes the resident observer and orchestration footprint.

The Uptime Kuma measurement playbook owns its target preconditions, three paired
raw/Ansible memory observations, local evidence, staging and cleanup. Its exact
bundle and approval belong in the existing change record. A measurement with
applications stopped does not accept combined application capacity. Later
combined acceptance must repeat scan-time observation with those services running
under the separately approved continuation. `accept.yaml` now invokes the shared guard and retains receipts at every checkpoint.

## Approved staged guard

`observe-needrestart.py --guard DIRECTORY` requires 224 MiB before starting its
32 MiB observer, then the existing observer requires fresh 192 MiB and samples a
96 MiB reserve during its bounded scan. It rejects overlaps, stale unit names,
missing evidence, late samples, scan memory-limit/OOM events and cleanup failure.
`guarded-scan.yaml` retains receipts even on failure before application containment.

The scheduled `--guard --producer` path creates a private volatile directory,
invokes the real owner notification producer within the 96 MiB scan unit and
passes only its explicit recipient environment. Its five-minute internal timeout
and 30-second kill grace remain; native scan/producer lifetime is bounded to 420
seconds, observer to 440 seconds, and cron to 470 seconds, each with bounded stop.
Failures are nonzero and flow through existing cron capture; insufficient capacity
skips that run without a tight retry. Temporary evidence is removed after terminal
cleanup; failed cleanup retains it. No production qualification is claimed by source.

`--admit-mib` is a read-only fresh admission helper for the 416 MiB restore stage
and 160 MiB ingress stage. It emits exact host/finite-parent readings before the
caller evaluates the result. These stages do not overlap the scan observer.
