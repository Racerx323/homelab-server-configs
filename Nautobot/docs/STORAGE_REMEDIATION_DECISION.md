# Nautobot storage-remediation decision

## Purpose and authorization boundary

This document presents the storage-remediation decision for `j2-svpi4mf`.
It does not authorize a shutdown, reboot, package change, kernel-command-line
change, USB reset, filesystem operation, hardware change, or host-baseline
rollback. Each selected live action requires its own operation, validation,
recovery boundary, and authorization.

The Nautobot deployment remains paused. Do not build or start application
containers until storage stability has been demonstrated and the host baseline
has reached a separately accepted terminal state.

## Evidence that constrains the decision

The read-only diagnostic preserved by tag
`nautobot-storage-diagnostic-v1-action-required` established:

- one root-device read I/O error followed by six additional UAS device-reset
  and SuperSpeed USB-reset cycles;
- a JMicron `152d:0583` bridge attached through UAS at 5 Gbps;
- passing NVMe SMART health, zero media/data-integrity errors, zero NVMe error
  log entries, and zero live ext4 errors;
- no Raspberry Pi throttling history and no kernel undervoltage event; and
- incomplete ext4 metadata collection because the diagnostic used an invalid
  `tune2fs` long option.

These observations show transport instability but do not identify whether the
cause is the X872 bridge, its USB jumper or connector, PoE transient capacity,
USB/UAS compatibility, or another physical-path fault. Healthy NVMe media and
the absence of recorded undervoltage make media failure and sustained
undervoltage less likely; they do not exclude intermittent faults.

## Options

### A. Controlled physical-path inspection

Perform a clean shutdown with local-console recovery available. Remove power,
inspect and reseat the X872 board, M.2 device, spacers, GPIO connection, and USB
jumper, then inspect for mechanical strain or heat damage. Reapply power and
run the corrected read-only diagnostic.

This is the lowest-complexity way to address a connector or seating problem,
but it requires physical access and downtime. It must not be combined with a
package rollback or software transport change.

### B. Isolate the power path

With the host cleanly shut down, temporarily power it from a known-good supply
that can support the Raspberry Pi and NVMe load without the GAT-PiHAT. Preserve
Ethernet connectivity separately and repeat the same read-only workload and
observation window.

This can distinguish a PoE-path transient from the storage adapter, but it
changes the physical power design and requires a separately reviewed test and
recovery procedure.

### C. Replace the USB-to-NVMe transport

Replace the X872 board or its USB interconnect with a known-compatible unit,
then repeat SMART, ext4 metadata, UAS/link, reboot, and soak validation.

This directly tests the bridge path but requires replacement hardware and does
not prove the original GAT-PiHAT innocent unless the power path remains fixed.

### D. Disable UAS for JMicron `152d:0583`

Define a kernel transport quirk that forces the bridge to use USB mass-storage
instead of UAS, reboot once, prove the active driver, and repeat storage
validation. This may avoid a UAS compatibility fault at the cost of lower
performance and a persistent boot configuration change.

The selected controlled software A/B test uses
`usb-storage.quirks=152d:0583:u`. Read-only inspection established that this
host boots from `/boot/firmware/cmdline.txt`; `/boot/cmdline.txt` is only a
relocation notice. The operation must bind to the observed boot-file hash,
preserve its single logical line and missing trailing newline, retain an exact
rollback copy, and stop for local-console recovery if the host does not return
after reboot.

### E. Restore the pre-v3 host baseline

Execute the separately defined `nautobot-host-baseline-rollback-v1` operation.
This restores package, account, subordinate-ID, lingering, and service state;
it does not repair the storage transport. Running APT against an unstable root
filesystem is unsafe, so the rollback preflight requires a quiet storage
window and an explicit sequencing decision.

## Required decision and sequence

Select one hardware or transport option independently from the host-baseline
rollback decision. The selected sequence is:

1. Confirm local-console recovery and backup status.
2. Perform Option D under the separately defined and hash-authorized
   corrected `nautobot-uas-quirk-v2` operation. Version 2 reuses the retained,
   hash-verified rollback backup from the rolled-back version 1 operation.
3. Prove the running kernel command line contains the quirk exactly once, the
   root source remains `/dev/sda2`, and JMicron `152d:0583` binds to
   `usb-storage` rather than `uas`.
4. Run the corrected read-only diagnostic and observe at least 24 hours with
   no I/O error, USB reset, UAS reset, ext4 error, or SMART degradation.
5. If instability recurs, roll back the boot file and reboot when the host is
   reachable; use the confirmed local-console recovery path if it is not.
6. After storage is stable, separately resume and authorize the pre-v3 host-baseline
   rollback or approve a new host-baseline convergence operation.

Do not combine physical changes, UAS changes, filesystem repair, package
rollback, or Nautobot deployment in one authorization.

## Acceptance gates for storage remediation

- corrected ext4 metadata collection succeeds;
- SMART health passes with zero media and error-log entries;
- the expected USB driver and negotiated link are recorded;
- no power or throttling fault is recorded;
- no new storage, USB, UAS, or ext4 error occurs across reboot and a minimum
  24-hour observation window; and
- an isolated backup restore is completed before Nautobot data is entrusted to
  the device.
