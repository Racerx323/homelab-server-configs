# Webmin upstream publication

Published on October 6, 2026 as [webmin/webmin#2869](https://github.com/webmin/webmin/issues/2869):
**Avoid partition enumeration during scheduled SMART temperature collection**.
The issue was created under the user's publication authorization. Its author,
title and full body were read back and verified against the prepared payload.

The issue includes the reviewed report, pinned upstream patch, source/hash
manifest and runnable synthetic tests in collapsible code sections. No raw
host evidence, device serials, private addresses or command-buffer dumps were
posted. No pull request, repository push or live deployment was performed.
The [report source](DISK_DISCOVERY_UPSTREAM_DRAFT.md) remains available locally.

Submitted body SHA-256:
`244893bde04c198401d10dbc76ac4d99bfca7897111c0c84b1e5cf5af6e4b4b5`.

Proposed patch SHA-256:
`9a210bf7809496e01fb081d42017f8be277eea95105616589a2440a4ce8d199a`.

The authenticated publication output, exact submitted body, issue readback and
live source verification remain private under
`disk-discovery-follow-up-20260929/publication-20261006`.

## Installed versus proposed code

A fresh read-only check on October 6 confirmed installed Webmin version 2.670
and exact matches for all three `after` hashes in the
[qualified deployed manifest](../patches/disk-only-discovery.json). The installed
source therefore still contains the custom disk-only discovery patch that
passed the single-host observation.

The [upstream adaptation](../patches/disk-only-discovery-upstream.json) is a
separate proposal preserving newer upstream RAID-model detection behavior.
It has not been installed. Publication did not alter Webmin, monitoring or the
qualified production patch. Future changes follow the
[upgrade procedure](DISK_DISCOVERY_UPGRADES.md).
