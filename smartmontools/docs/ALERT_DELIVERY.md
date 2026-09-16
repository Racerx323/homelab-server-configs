# smartd alert delivery through the existing mail route

The current fleet msmtp configuration is owned by
[`homelab-dns/msmtp`](../../../homelab-dns/msmtp/docs/msmtp-secrets-configuration.md).
Use its [fleet audit follow-up](../../../homelab-dns/msmtp/docs/FLEET_AUDIT_STANDARDIZATION_PROMPT.md)
for migration and standardization. Repairing a consumer hook on an existing
route does not establish that the host uses the current fleet configuration.

The Debian `smartd-runner` invokes hooks in `/etc/smartmontools/run.d/`.
Its `10mail` hook requires an executable `/usr/bin/mail`. Installing `msmtp-mta`
provides a sendmail-compatible interface but does not alone provide this mail
frontend. Verify the actual installed hook before selecting a repair.

## Fleet package and configuration requirements

The qualified Debian 13 ARM64 repair used these packages. Versions below are
the tested reference, not fleet pins; resolve official candidates and review the
transaction separately for each host.

| Package | Tested version | Deployment purpose |
| --- | --- | --- |
| `smartmontools` | `7.5-2~bpo13+1` | Previously upgraded from `7.4-3`; contains the compiled JMS583 workaround. |
| `bsd-mailx` | `8.1.2-0.20220412cvs-1.1` | Added to provide `/usr/bin/mail` for Debian's `10mail` hook. |
| `liblockfile-bin` | `1.17-2` | Necessary dependency added by the reviewed frontend transaction. |
| `liblockfile1:arm64` | `1.17-2` | Necessary dependency added on ARM64; use the target architecture. |

The existing `msmtp`/`msmtp-mta` transport was retained, not replaced or upgraded
by the alert repair. Qualify an existing approved sendmail provider before adding
packages: do not replace another host's MTA merely to match this reference.
See the [JMicron profile](JMICRON_NVME_PROFILE.md) for package upgrade and rollback.

Render the [smartd template](../configs/jmicron-nvme.smartd.conf.example) with both
a verified device and a verified recipient. The pilot repair changed only the
recipient to `notify@mailrise.xyz`; it did not deploy the explicit-device template
or standardize the inherited DEVICESCAN policy. A recipient does not select an
msmtp account: qualify the effective account and relay as well as alias expansion.
Do not copy the pilot's older msmtp configuration to other hosts. Its replacement
and consumer-account mapping belong to the fleet audit linked above.

Fleet acceptance requires the expected monitored devices, a working mail
frontend and sendmail provider, and confirmed receipt through the intended
channel. The repaired pilot's test was received; this does not qualify other
hosts or resolve the outstanding JMicron log-interpretation anomaly.

## Qualification and repair

1. Inspect the active smartd recipient and notification command, installed hook,
   mail/sendmail executables, and package ownership. Inspect only the necessary
   default-account and alias routing; keep credentials out of evidence.
2. Verify how `root` resolves through the existing alias configuration. Do not
   assume it has a dedicated alias or that SMTP acceptance proves the final
   notification arrived. Mail routing remains owned by the host's mail component.
3. When the frontend is missing, simulate installation of the official Debian
   `bsd-mailx` package without recommendations. Review necessary dependencies,
   exact versions and maintainer scripts. Reject unrelated changes or removals.
4. Preserve package inventory, APT state, relevant configuration bytes/metadata
   and service identities. Bind the selected archives and execution inputs to
   the reviewed operation. Use report-only needrestart behavior where supported
   by the owning procedure; installing a frontend does not require smartd restart.
5. Verify the complete installed-package delta and executable alternatives.
   Debian may report a library as `liblockfile1:arm64`; compare package identities
   with architecture deliberately, rather than assuming unqualified names.
6. Confirm smartd, Webmin and mail routing configurations remain unchanged.
   Preserve the existing sendmail route rather than installing another MTA.

If the relay reports an unconfigured recipient, frontend installation alone has
not repaired delivery. Verify the actual Mailrise configuration key and the
operator's intended destination. Prefer a smartd-specific `-m` recipient change
over altering a shared default alias for unrelated senders. For a verified
`notify` route, that recipient is `notify@mailrise.xyz`. Back up the exact smartd
configuration, review the recipient-only diff, capture a journal cursor, reload
through the owning service procedure, and verify parsing and device coverage.
Preserve the previous file hash and metadata for a guarded rollback/reload.

A successful msmtp exit can coexist with a Mailrise routing rejection. Inspect
relay evidence or confirm downstream receipt; do not equate SMTP acceptance with
notification delivery.

Each host requires its own transaction review. Do not bake one pilot's package
versions or notification recipient into a fleet installer.

## Delivery test and evidence

With notification sending authorized, invoke the existing smartd-runner using
synthetic `SMARTD_ADDRESS`, `SMARTD_SUBJECT`, `SMARTD_FULLMESSAGE` and
`SMARTD_FAILTYPE=EmailTest` values. Match the reviewed configured recipient and
clearly label the subject/body as a test that asserts no device failure.
This exercises the hook without changing smartd policy or starting a self-test.

Preserve hook stdout, stderr and exit status. Verify the sendmail/msmtp child's
status too, so a parent process's success cannot conceal submission failure.
Avoid debug modes that expose credentials or message contents. Confirm downstream
receipt separately. Report hook success, SMTP submission and actual delivery as
distinct results. Do not resend merely because receipt confirmation is pending.

Missing frontend failures are actionable even if smartd is active. Conversely,
repairing delivery does not resolve a device/log warning that triggered an alert.
Do not suppress those warnings to make notification qualification appear clean.

## Rollback

For packages newly installed by this operation, simulate removal of those exact
packages and require no unrelated changes. Do not purge, autoremove, alter shared
mail configuration, or overwrite APT state after unrelated package activity.
Record remaining conffiles and operation evidence explicitly; verify executable
alternatives, original configurations and service identities after rollback.
A rollback cannot retract a delivered test notification.
