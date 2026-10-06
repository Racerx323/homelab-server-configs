# Disk-discovery patch and Webmin upgrades

The deployed change modifies three Webmin library files directly. A package or
Webmin-managed update can overwrite it. There is no automatic reapplication or
new background drift monitor from this investigation. The completed observer
no longer monitors hashes; use explicit checks at upgrade boundaries.

## Detect source changes

Before and immediately after any approved Webmin update, read the installed
package version and hash these three files on the qualified host:

```sh
dpkg-query -W -f='${Version}\n' webmin
sha256sum /usr/share/webmin/fdisk/fdisk-lib.pl \
    /usr/share/webmin/smart-status/smart-status-lib.pl \
    /usr/share/webmin/system-status/system-status-lib.pl
```

Compare each result with the corresponding `after` hash in the
[deployed manifest](../patches/disk-only-discovery.json). Preserve the readback
privately. This detects drift; a different hash is not permission to overwrite
it. The old observer also pinned configuration and binary hashes, so retain
those checks when qualifying a replacement observation.

The reviewed upstream head also reports 2.670 but contains a newer RAID-model
fix. Package version alone cannot distinguish it from the installed baseline.
Do not accept a patch because its context applies with offsets or fuzz.

## Prepare an upgrade

1. Preserve the exact installed libraries, permissions, ownership, package
   identity and relevant Webmin/smartd configuration with hashes. Retain the
   accepted pilot rollback files and both observer terminal archives.
2. Review the proposed package's actual source. Check whether it already has
   equivalent disk-only discovery and whether SMART query/RAID behavior changed.
3. If adaptation is needed, create a separate review-only patch and before/after
   manifest. Keep the accepted deployed manifest unchanged. Run the discovery,
   partition-management, RAID, cache and inventory-change regression fixtures
   against that exact source. Include any upstream regression fixes.
4. Prepare exact deployment, backup, rollback and observation commands. Bind
   execution approval to their immutable bundle. Do not update packages or
   reapply a patch merely to test compatibility on the production host.
5. After approved execution, verify actual scheduled collection, expected drive
   coverage and source/configuration continuity for at least two cycles, with
   at least 75 seconds final settling and storage-fault/counter review. A new
   kernel, source or transport combination requires its own qualification.

The [current upstream adaptation](../patches/disk-only-discovery-upstream.json)
is a published review proposal, not an approved upgrade or replacement for the
production patch. It is pinned to one upstream commit and must be reviewed
again if those source hashes change.

## Recovery and retention

If hashes differ unexpectedly, stop patch deployment and identify the source
change while leaving normal health polling and smartd enabled. Preserve failed
results. Do not reset counters, exclude the disk, replace discovery tools, or
restore libraries from an older package version into a newer one blindly.

Recovery must use a reviewed version-consistent backup/package and an authorized
procedure. Recheck health and source identities after recovery; deployment
success does not follow from a successful patch command alone.

Do not remove consumed operation data or remote evidence during this review.
Repository policy requires a sanitized terminal record and the exact operation
definition in an annotated, pushed tag before main-branch removal. Creating or
pushing that tag, public reporting, evidence disposal and any live upgrade remain
separately authorized actions.
