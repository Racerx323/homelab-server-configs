# smartmontools architecture

## Scope

This document governs reusable smartctl health collection and smartd
monitoring within `homelab-server-configs`. Consumer plans define device
membership, workload limits, alert routing, collection intervals, self-test
schedules, and health acceptance.

The first consumer is Nautobot on `j2-svpi4mf`. Its deployment plan remains the
authority for Nautobot host and workload acceptance. `host-storage/` owns
implementation of the selected USB transport profile.

## Ownership

The `smartmontools/` component owns:

- device discovery and device-type selection rules;
- smartctl exit-mask decoding and sanitized result schemas;
- reusable smartd configuration and validation;
- self-test authorization and evidence boundaries; and
- shared operator procedures.

Each consumer owns its devices, expected protocol and bridge identity,
thresholds, schedules, maintenance windows, operation state, accepted-live
state, and terminal history. The mail system owns relay configuration. The
approved secrets system owns credential values.

## Device discovery

Start with `smartctl --scan` and operating-system block topology. Record the
canonical device path, transport, bridge identity, kernel driver, and smartctl
device type before health collection. Use smartctl's default `auto` type when
it identifies the device and returns the required data.

USB bridge support varies by controller, firmware, driver, and attached media.
Test a candidate type such as `sat`, `usbjmicron`, or another documented type
in a read-only preflight. Select one type from observed output and keep the
choice with the consumer's device definition. Do not add permissive mode to
hide a mandatory command failure from an acceptance decision.

## Read-only collection

A read-only collection may request identity, health, attributes, capability,
error-log, self-test-log, and extended data. Prefer smartctl JSON output for a
machine-consumed result when the installed version supports the required
fields. Preserve the raw bounded output outside Git and commit a sanitized
summary.

Health reads can wake a sleeping drive or add I/O through a bridge. A consumer
with power, latency, or media-wear constraints must review that impact before
scheduling collection.

## Exit status

smartctl returns an eight-bit mask. Scripts must preserve the full value and
decode each bit:

- bits 0 through 2 report command-line, device-open or identification, and
  SMART command or checksum failures;
- bit 3 reports a failing health status;
- bits 4 and 5 report current or historical prefailure thresholds; and
- bits 6 and 7 report device error-log or self-test-log records.

An implementation must classify each set bit and retain the supporting health
data. It must not reduce all nonzero values to one command-failed result.

## Mutation classes

The following actions require a separately reviewed and authorized operation:

- enabling or disabling SMART;
- starting offline collection or a short, long, conveyance, or vendor test;
- canceling a running test;
- changing drive power, acoustic, error-recovery, or autosave settings; and
- adding or changing a smartd self-test schedule.

A self-test operation must record the canonical device, smartctl type, test
kind, estimated duration, workload impact, start result, completion evidence,
and cancellation boundary. Do not combine a self-test with package, storage
transport, filesystem repair, or reboot changes.

## smartd configuration

Keep reviewed non-secret smartd configuration under `smartmontools/` once a
consumer approves it. Use explicit device selectors for production hosts.
Review monitoring flags, temperature thresholds, self-test schedules, and
notification commands as separate concerns.

Route alerts through the approved host mail transport without embedding relay
credentials. Validate configuration before service reload. Service enable,
restart, or reload requires authorization from the consumer operation that
owns the host change.

## Evidence and acceptance

Raw output belongs in a protected bounded directory outside Git. Sanitize
serial numbers, WWNs, host-unique paths, and unrelated device data before
committing a terminal manifest.

A sanitized result may record the model family, protocol, bridge and driver,
smartctl version and type, exit mask and decoded bits, health status,
temperature, wear indicators, media errors, error-log count, self-test result,
command status, and raw-evidence hashes.

The consumer accepts health only after it matches the canonical device,
decodes the full exit mask, evaluates the protocol-specific fields, and checks
kernel or service errors for the operation window.

## References

The approved [JMicron NVMe profile](JMICRON_NVME_PROFILE.md) standardizes
qualification and monitoring for the pilot's USB/NVMe path. It preserves working
`sntjmicron` autodetection, requires the compiled self-test-log workaround for
full log reads, and keeps the Webmin reduced-query patch as a complementary
change. Device membership and accepted live state remain consumer-owned.

Its explicit-device template is a definition for per-host review, not evidence
that every similar server has been deployed or qualified. The pilot's retained
DEVICESCAN configuration is documented separately to preserve attribution during
the package upgrade.

- [smartctl manual](https://www.smartmontools.org/browser/src/smartctl.8.in)
- [smartd manual](https://www.smartmontools.org/browser/src/smartd.8.in)
- [smartd configuration manual](https://www.smartmontools.org/browser/src/smartd.conf.5.in)
- [SAT with UAS on Linux](https://www.smartmontools.org/wiki/SAT-with-UAS-Linux)
- [Supported USB devices](https://www.smartmontools.org/wiki/Supported_USB-Devices)

## Host transport ownership

[Host storage](../../host-storage/docs/HOST_STORAGE_ARCHITECTURE.md) owns
root transport, boot configuration, reboot and recovery. Host inventory selects
the shared hardware/transport profile. `smartmontools/` owns the package workaround,
SMART collection and smartd policy; `Webmin/` owns temperature polling behavior.
Nautobot and other Restic consumers retain workload/storage acceptance and
backup/restore criteria. Transport convergence does not clear those gates.
Historical Nautobot remediation definitions and evidence remain retained; future
transport operations use the shared component without modifying active observers.
