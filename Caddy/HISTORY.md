# Caddy deployment archive

The main branch contains current production artifacts and approved future work.
Git preserves the complete deployment journal and executed action files.

## Archive boundary

- Tag: `caddy-pre-cleanup-history-2026-08-16`
- Commit: `3694303a5ac37c449cdda71260af0e3d97487eb3`
- Tag object: `82f3c6ececded19d044effe0fcda6534c22ad1e0`
- Scope: all executed Actions through 34m, the completed Action 33 reliability
  exercise through 33o, and the pre-cleanup Action 35 definition
- Remote state: tag and commit pushed before the production-only cleanup

Use the tag for authorization provenance, exact executed bytes, old manifests,
historical tests, workstation experiments, and the former full deployment
journal. Do not restore archived files to the current branch unless an operator
requests a historical reconstruction.

## Action 35 terminal archive

- Tag: `caddy-action35-terminal-2026-08-16`
- Commit: `b20e834f481944ea3eb5b9d945c256fd8d4fb96f`
- Tag object: `afef8b98bcac6781f9a408adb0ceb0e614c72fa6`
- Action: 35
- Result: failed-consumed before SSH or live mutation
- Scope: exact authorized runner, transaction, manifest, regression, failed
  workstation result, and repository-wide deployment-window framework
- Remote state: terminal tag, terminal commit, and immediate cleanup commit are
  synchronized as one clean-as-you-go checkpoint

## Action 35a terminal archive

- Tag: `caddy-action35a-terminal-2026-08-16`
- Commit: `f0d86ebba58531d2d40b6edb33d535ac18237d09`
- Tag object: `57d194d61e0a5c4c781efe25f1b216cf13aeb64d`
- Action: 35a
- Authorized outer SHA-256:
  `9ee5dca58b4169a326742da8c4e001aa2ecf31f36d65dd9cc1a376a8c996fa6e`
- Result: failed-consumed after Node A SSH preparation contact and before
  upload, transaction dispatch, or persistent mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35a`
- Failure: OpenSSH remote-shell reconstruction split a multiword
  `/bin/bash -c` command boundary
- Remote state: terminal tag and terminal-result commit pushed before the
  immediate production-branch cleanup

## Action 35b terminal archive

- Tag: `caddy-action35b-terminal-2026-08-16`
- Action: 35b
- Authorized outer SHA-256:
  `06bcab00cbd868c96a600499f4d6e8402686a95d62827c2d4d164f3c6db95d58`
- Result: failed-consumed after both bounded payload uploads and before release
  publication, transaction dispatch, service reload, or Keepalived mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35b`
- Retained payload SHA-256:
  `487cebeff7f13da4a301293f1a80ccc70ca4e7c38768136b9694294d9369a6fe`
- Failure: the unprivileged SSH identity could not traverse and resolve
  `/etc/caddy/current`; the successor must use streamed privileged resolution
- Commit: `ad7a5d1197c3cfb48f573eb7845f79c4af3c1156`
- Tag object: `fc5df66631bb0de7445c1e54c7bca0f0aff768a7`
- Status: terminal tag, terminal commit, and immediate cleanup commit are
  synchronized

## Action 35c terminal archive

- Tag: `caddy-action35c-terminal-2026-08-16`
- Commit: `07bf6eaf1bc90d023184c34048d2dc7f5cbbe113`
- Tag object: `ab007a3cb43991755a64e0a3966e6a49c440732d`
- Action: 35c
- Authorized outer SHA-256:
  `eb832297cff590075cc9f70e931cd38f7bbccf7dc594fa1995f59a85d89c525a`
- Transaction SHA-256:
  `a8a9a0210325a18a42d70afbe17395470a052a1beda713f989acbc4518529070`
- Result: failed-consumed after exact retained-upload disposition, dual-node
  upload, and privileged current-release capture, but before protocol-v2
  publication, transaction dispatch, service reload, or Keepalived mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35c`
- Original release on both nodes:
  `20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`
- Cleanup: both retained Action 35b uploads and both Action 35c upload trees
  were removed successfully
- Retained exact candidate path on Node A: `/tmp/caddy-action35c-release`
- Failure: candidate Caddy validation did not load `/etc/default/caddy-ha`, so
  `NODE_FQDN` expanded empty and Caddy rejected an empty site label
- Availability evidence: two aggregate samples returned status 9; the direct
  successor must retain independent DNS IPv4, DNS IPv6, HTTPS IPv4, and HTTPS
  IPv6 statuses
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35f terminal archive

- Tag: `caddy-action35f-terminal-2026-08-17`
- Commit: `903ac8b0098a3f2abf4a048b185f074b72a28812`
- Tag object: `7266ae48ab21469cb04fb00e066db669aca6d7e0`
- Action: 35f
- Authorized outer SHA-256:
  `dd160b4a25c5a94dc7d5ae4c15fc1f7195ee8d95a6fd00df493606efdc683c3f`
- Transaction SHA-256:
  `0040150451305ffa43d72eb834d0228f376404123a0eb0cd05721af1e1b3819e`
- Result: failed-consumed during exact Node A retained-candidate validation,
  before upload, publication, transaction dispatch, service reload, or
  Keepalived mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35f`
- Original release on both nodes:
  `20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`
- Retained exact candidate path on Node A: `/tmp/caddy-action35c-release`
- Observed candidate root identity: `root:caddy-tls:0550`
- Failure: Action 35f correctly derived mode `0550` from protocol v2 but
  incorrectly required owner `root:root`; the production reconciler owns
  immutable releases as `root:caddy-tls`
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35g terminal archive

- Tag: `caddy-action35g-terminal-2026-08-17`
- Action: 35g
- Authorized outer SHA-256:
  `2d22ccf81441b159dd99176efd14f7ea3188ca04439903c750ce0eada0eb0ba3`
- Transaction SHA-256:
  `77d7ff81181363bc642efc5b11425e2d343e6a4f2d7f47213fcf91077a9caac3`
- Result: failed-consumed after protocol-v2 publication and Node B release
  selection, before installation transaction dispatch, service reload, or
  Keepalived mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35g` and
  `/tmp/caddy-ssh-evidence/action35g-postcheck`
- Node A current release:
  `20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`
- Node B current release:
  `20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca`
- Published release identity: Node A source, Action 32g parent,
  `root:caddy-tls:0550`, manifest JSON SHA-256
  `6049da00c0e7318c3fce98bc6cc78348ded5286998a346f00657df8c1d2a046d`,
  and payload-manifest SHA-256
  `ecb1a00827899bffc47d9e180b4f0a19a6daf0fc4beee9cb52898a9608102962`
- Ownership: Node A IPv4/IPv6 `MASTER` with all four VIPs; Node B IPv4/IPv6
  `BACKUP` with zero VIPs
- Initial postcheck incorrectly inspected `/var/lib/caddy-lsyncd/outgoing`.
  Corrected privileged inspection of the production protocol-v2 root proves
  Node A retains the exact finalized outbound candidate at
  `/var/lib/caddy-sync/outbound/20260817T160328Z-472d68b9-2bfb-40f1-8563-0754067182ca`
  as `caddy-sync:caddy-sync:0550`; Node B retains the identical selected
  immutable release. Matching incoming and quarantine paths are absent.
- Failure: the unprivileged Node B acceptance poll could not traverse
  `/etc/caddy/current`; the direct successor must use privileged streamed Bash
- Availability evidence: IPv4 DNS and HTTPS passed; WSL lacked an IPv6 route,
  so its IPv6 failures are retained but are not valid node-serving acceptance
- Commit: `e79db2b96ffde720e33cbcd79032b852a9989d69`
- Tag object: `8bed4ea2582be5693601c7c0f5370155abdbdc67`
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35d terminal archive

- Tag: `caddy-action35d-terminal-2026-08-16`
- Commit: `1a9e30b7088093ddf8444838bfca8705a404ed19`
- Tag object: `ffc6864994c62b7293919cff7a4fbefff17ae300`
- Action: 35d
- Authorized outer SHA-256:
  `5e131a1a1ec2e95e1bab6b7cc71475f8b4b9281d8789127516a0aa2b05878727`
- Transaction SHA-256:
  `f0e21e91c5dc0050559eba0bcce99289cf7b974672741204313cab8473c502b1`
- Result: failed-consumed after privileged current-release capture on both
  nodes and during exact Node A retained-candidate validation, before upload,
  publication, transaction dispatch, service reload, or Keepalived mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35d`
- Original release on both nodes:
  `20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`
- Retained exact candidate path on Node A: `/tmp/caddy-action35c-release`
- Failure: Action 35c's real `cp -a current/. candidate/` producer preserved
  the source release root mode as `0755`; Action 35d incorrectly required
  `0700`, and its isolated test hid the mismatch by forcing `0700` after the
  copy
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35e terminal archive

- Tag: `caddy-action35e-terminal-2026-08-16`
- Commit: `e66e55e3c19b275bab1b604fd5b0fce34831599b`
- Tag object: `97c731ddb69f22be220f2101eaf1b689168065ee`
- Action: 35e
- Authorized outer SHA-256:
  `1ac3ae3dd8ac24938794f2ef9731fc534d0ce164f8b8ae78ee34ae8ac77c1ec1`
- Transaction SHA-256:
  `2c31fcabc2357bfc11e21f67ba8bac041f0a12c5eb29e110ac5c453e3ca5f903`
- Result: failed-consumed after privileged current-release capture on both
  nodes and during exact Node A retained-candidate validation, before upload,
  publication, transaction dispatch, service reload, or Keepalived mutation
- Exit status: 1
- Evidence: `/tmp/caddy-ssh-evidence/action35e`
- Original release on both nodes:
  `20260811T180754Z-d7816a72-48c7-461c-a86f-451027f5de04`
- Retained exact candidate path on Node A: `/tmp/caddy-action35c-release`
- Observed candidate root mode: `0550`
- Failure: protocol-v2 declares and enforces final release directories as
  `0550`, but the Action 35e isolated baseline created its source release as
  `0755`; its real `cp -a` path therefore reproduced the wrong source mode
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35h terminal archive

- Tag: `caddy-action35h-terminal-2026-08-17`
- Commit: `1db3debe848fb2b1913e7fb592f2272403a7e18f`
- Tag object: `3c058c962181b5bc2e9294aa781e0699d27eb1be`
- Action: 35h
- Authorized outer SHA-256:
  `e921503c9a46d5a18777933cc3518b1868a982aa48e1004a14a6f782cff4b9a3`
- Transaction SHA-256:
  `f77dc10659ec610fb88a5ac1371e083ce3ac5e442ce2a334e17dabc75441986a`
- Result: failed-consumed during Node B current-production baseline identity
  validation, before candidate validation, backup creation, serving-health
  installation, Keepalived reload, Node A promotion, or Node A dispatch
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence/action35h`
- Recovered Node B evidence:
  `/tmp/caddy-ssh-evidence/action35h-evidence-recovery`
- Accepted baseline checks: exact split-release and protocol identities, all
  required active/enabled unit checks, baseline residue, and the deployed Node
  B Caddy-helper identity
- Failed assertion: `node_b_dns_health_helper` was the next production
  inventory row and was not accepted or recorded. Expected deployed SHA-256 was
  `7af57e70d80d32434e9cac717afa4af8d9e67c6c6ccd08d15ca9d7046d337b25`.
  The executed transaction did not emit the observed identity, which is an
  evidence-contract defect and must not be guessed.
- Availability: all 384 retained DNS and trusted-HTTPS IPv4/IPv6 samples from
  both nodes returned status 0
- Recovery: both upload trees were removed; Node B rollback and restoration
  handlers returned 0. The exact pre-35h split-release selection was restored.
  No serving-health or Keepalived configuration mutation occurred.
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit
