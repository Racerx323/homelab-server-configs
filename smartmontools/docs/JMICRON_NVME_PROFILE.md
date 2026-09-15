# JMicron USB/NVMe monitoring profile

> Qualify each host before deployment. Matching appearance or USB ID does not
> establish identical bridge firmware, media, transport, or failure behavior.
> This profile does not accept storage or authorize fleet changes.

## Hardware and device type

The pilot is Debian 13/trixie ARM64 with bridge `152d:0583`, WD_BLACK SN7100
1TB NVMe media, and `usb-storage` at 5 Gbps. USB bcdDevice `0213` is a descriptor
value, not a verified bridge firmware release string.

Autodetection selects `sntjmicron`. Preserve working autodetection. Do not force
`sat` or `usbjmicron` merely because this NVMe drive is connected over USB; those
ATA paths differ from this NVMe path. Transport quirks, power, firmware, and
reboot changes belong to `host-storage/` and remain separate from this procedure.

### Where the transport quirk is owned

The pilot's host inventory records `storage.root.transport: usb_storage` and
`storage.root.uas_disabled: true` in
[its host definition](../../inventory/prod/hosts/j2-svpi4mf.yaml). The exact token
is `usb-storage.quirks=152d:0583:u`; `u` means ignore UAS for that vendor/product
ID, as defined in the [kernel documentation](https://docs.kernel.org/admin-guide/kernel-parameters.html).
It matches that USB ID, not an individual disk serial number.

The original boot-file procedure and rollback are documented in
[Nautobot's storage decision](../../Nautobot/docs/STORAGE_REMEDIATION_DECISION.md)
and [Ansible operations](../../Nautobot/ansible/README.md#jmicron-uas-quirk-remediation).
The retained implementation is
[apply-uas-quirk.yaml](../../Nautobot/ansible/playbooks/apply-uas-quirk.yaml), with
its guarded [runner](../../Nautobot/ansible/scripts/run-uas-quirk.sh).
That procedure targets `/boot/firmware/cmdline.txt` on the pilot. It is a
single-host remediation operation, not a fleet installer to rerun unchanged.

For future operations, [host-storage](../../host-storage/README.md) owns the
reusable transport role, profile, boot changes and recovery. Inventory selects
`storage.root.transport_profile: rpi4-x872-usb-storage`; the shared profile owns
the quirk token. The Nautobot paths above are retained historical implementation,
not the entrypoint for new operations. This smartmontools profile owns SMART
policy only; do not duplicate boot mutation in its installer.

Record topology and detected type before health collection:

```sh
dpkg --print-architecture
findmnt -n -o SOURCE,FSTYPE,OPTIONS /
lsblk -o NAME,TYPE,TRAN,MODEL,MOUNTPOINTS
lsusb -t
smartctl --version
sudo smartctl --scan
```

Resolve a stable whole-disk `/dev/disk/by-id/` selector and verify its canonical
target. Keep serials, selectors, and raw reports outside Git. Do not assume
another host's root disk is `/dev/sda`.

## Workarounds

smartmontools commit `c4a26cba430a4638f7d86ee70363b33e9ea491e0` (r5650), included
in 7.5, adjusts the JMicron NVMe self-test-log request to `0x218` (19 records).
It emits a warning about truncation to work around a controller bug. This is
compiled code, not a drive-database update or configurable `-F` flag.

The selected pilot upgrade is Debian `7.4-3` to `7.5-2~bpo13+1` from official
trixie-backports. Verify the actual package and workaround on each deployment.

Webmin commit `725362b9f0e26a2f88f81dd36d4bfbd784166cf3` separately changes
scheduled temperature queries from `-a` to `-A -l error`, retaining `-i` and
`-H`. Keep that patch or a verified release containing it. Webmin avoids the
unnecessary request; smartmontools handles it when another caller requests it.

## Configuration

The pilot retains this existing active smartd line during the package test:

```text
DEVICESCAN -d removable -n standby -m root -M exec /usr/share/smartmontools/smartd-runner
```

There is no explicit interval override. This records the pilot's retained
configuration; it is not the fleet template. The inherited `-n standby` is not
evidence of NVMe power-state protection.

Use the [explicit-device template](../configs/jmicron-nvme.smartd.conf.example)
for a separately reviewed production configuration. Render one verified
whole-disk selector per device. `-d auto` preserves discovery and `-a` selects
normal monitoring; it does not schedule self-tests. Do not add `-s`, `-o`, `-S`,
or device-setting flags incidentally. Temperature thresholds and notification
frequency are consumer decisions.

Verify that `root` routes through the approved mail transport and that the
Debian smartd-runner hook exists. Validate delivery under the consumer's
notification authorization before accepting alert coverage. No relay secrets
belong here. Active smartd alone is not proof of delivery.

Validate rendered configuration with the installed manual and a controlled
start/reload, inspecting monitored-device records and kernel messages. smartd
foreground/one-check commands may perform real device reads; do not treat them
as syntax-only checks or launch another daemon blindly beside the existing one.

## Upgrade and rollback

1. Preserve the old package archive, every registered conffile and metadata,
   package inventory, service identities, and APT source state. Keep patched
   Webmin's `collect_notemp=1` during the isolated upgrade and comparison.
2. Verify Debian 13 and its archive keyring before installing the reviewed
   [backports source](../configs/trixie-backports.sources). Refresh metadata;
   do not globally raise backports priority.
3. Simulate `apt-get --simulate --no-install-recommends install
   smartmontools/trixie-backports`. Review all changes and reject unrelated
   upgrades or removals. Pin the chosen version in the operation.
4. Download and hash the authenticated package; review architecture, maintainer
   scripts and workaround presence. Put it in APT's cache before using
   `--no-download`; a separate staged archive was insufficient in the pilot.
5. Install the reviewed version, preserving conffiles. `NEEDRESTART_MODE=l`
   keeps needrestart report-only; smartd's package-managed restart is expected.
6. Verify the complete package delta, configuration hashes/metadata, binaries,
   smartd's device monitoring, retained Webmin patch, and kernel events.

Example transaction shape after the exact version and inputs are reviewed:

```sh
sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l \
  apt-get -y --no-remove --no-download --no-install-recommends \
  -o Dpkg::Options::=--force-confold install smartmontools=REVIEWED_VERSION
```

For a deliberate downgrade, disable Webmin temperature collection and stop its
observer first. Cache the verified old archive, simulate the old exact version,
then use `--allow-downgrades --no-remove --no-download`. Refuse unexpected
configuration drift and verify original conffile bytes/metadata and smartd.
Remove only an operation-created APT source whose hash still matches if that
is the selected rollback scope. Preserve runtime SMART state and evidence;
do not purge the package.

## Controlled comparison

With the canonical device verified, compare these forms on the upgraded tool:

```sh
sudo smartctl -r nvmeioctl,1 -q noserial -H -i -c -A -l error /dev/sda
sudo smartctl -r nvmeioctl,1 -q noserial -H -i -c -A -l error -l selftest /dev/sda
```

Keep raw output private. Observe at least 75 seconds after each command returns;
the previous reset occurred approximately 31 seconds after a successful exit.
Stop further reads if resets or storage errors appear. The 19-record warning
is expected, but is not itself evidence of stable storage. Neither command
starts a self-test.

Decode the complete exit mask: bits 0–2 concern invocation/open/SMART-command
problems; bit 3 health; bits 4–5 current/historical prefailure attributes; bits
6–7 error/self-test records. A trial can stop on any nonzero result, but must
retain the decoded reason and protocol-specific health data rather than label
every nonzero result a generic command failure.

## Combined observation and consumer acceptance

After a quiet comparison, enable patched Webmin polling in a new bounded
observation using the updated binary hashes and smartd identity. Review actual
temperatures, reduced queries, disk activity, errors, and monitoring continuity
at two hours and 24 hours. The Webmin observer disables polling at completion.

Keep package verification, pending combined observation, and accepted storage
distinct. Nautobot additionally requires corrected ext4 metadata, SMART health
and media/error-log review, transport/power checks, host-baseline acceptance,
and backup/isolated-restore validation. Resume those under the consumer's
criteria after the combined window. A zero SMART exit does not authorize
Restic initialization or establish accepted host state.

## References

- [smartmontools issue 256](https://github.com/smartmontools/smartmontools/issues/256)
- [7.5 implementation](https://github.com/smartmontools/smartmontools/blob/RELEASE_7_5/smartmontools/scsinvme.cpp)
- [Debian backports](https://backports.debian.org/Instructions/)
- [Webmin patch](https://github.com/webmin/webmin/issues/2838)
