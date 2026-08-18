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

## Action 35i terminal archive

- Tag: `caddy-action35i-terminal-2026-08-17`
- Commit: `b1931c917cddcddb369a23214de6b5bb1084c179`
- Tag object: `ba1d9abd52d78e3b506616bd2c8f8bd4a324ca67`
- Action: 35i
- Authorized outer SHA-256:
  `9de2ca4bc38a62e686c26947a07928943f755467b44cab7f1b44b6e4e220457e`
- Transaction SHA-256:
  `658a53d92cbccd50af9d1f906e513fe2e55ead60b79fb749c76ec4036e5924d0`
- Result: failed-consumed during Node B current-production DNS-helper identity
  validation, before candidate validation, backup creation, installation,
  Keepalived reload, publication, Node A promotion, or Node A transaction
  dispatch
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35i.qvBXIf`
- Expected deployed DNS-helper SHA-256:
  `7af57e70d80d32434e9cac717afa4af8d9e67c6c6ccd08d15ca9d7046d337b25`
- Observed on both nodes: `root:root:0755`, SHA-256
  `4972282ef0a0bed1bc2edec941125b2b3275812445039eede3a720099b95f33d`
- Desired repository SHA-256:
  `294afb4db26a3ccac454636efe091b872724e648c901b467142b31fae489e8aa`
- Recovery: both uploaded payload trees were removed successfully; no live
  mutation entrypoint ran, so rollback was neither required nor attempted
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35j terminal archive

- Tag: `caddy-action35j-terminal-2026-08-17`
- Commit: `7ed52a2773cb8195d9430686262d9bc02717d953`
- Tag object: `78b6b12c8f07c66885083f9c68fd8724eeb56c92`
- Action: 35j
- Authorized outer SHA-256:
  `aa354aa398c9b1495e48587c6b3bd670bf4ef495eb5fa5a72e930f9392043658`
- Transaction SHA-256:
  `c3ae04896a4c84bdd67d5e8c6de13b161ae09f2e44e99c709d0c7a2ec9e28b24`
- Result: failed-consumed during Node B current-production Unbound local-zone
  path validation, before candidate validation, backup creation, installation,
  Keepalived reload, publication, Node A promotion, or Node A dispatch
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35j.v2B8Mg`
- Accepted corrected DNS-helper identity:
  `4972282ef0a0bed1bc2edec941125b2b3275812445039eede3a720099b95f33d`
- Failed assertion: `artifact_node_b_unbound_local_zone_regular=false`; the
  inventory incorrectly used repository source name `pihole0-local-zone.conf`
  as the production target instead of `pihole-local-zone.conf`
- Current-contract correction: the ignored private repository source was later
  renamed to `pihole-local-zone.conf`, matching the production filename
- Recovery: Node A and Node B upload preparation, copy, acceptance, and exact
  disposition all returned 0; no mutation entrypoint ran, so rollback was not
  required or attempted
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35k terminal archive

- Tag: `caddy-action35k-terminal-2026-08-17`
- Commit: `19561672df210fc909a70c2b4d5492d621a512ba`
- Tag object: `78323892a9d40b20e199897b42c2baaac40aba06`
- Action: 35k
- Authorized outer SHA-256:
  `bfaab7f1d14cd0e2d718d8d95ea3acc3646d794a982b0a455512a526e08d43e9`
- Transaction SHA-256:
  `b5caa7691086c82d37b7c98d69fc0a0f13a50c882d43eaff841c65a545f664e9`
- Result: failed-consumed during Node B current-production Unbound local-zone
  identity validation, before candidate validation or any mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35k.gLE53y`
- Expected repository and deployed SHA-256:
  `f1f422d64a55a77af4d77a829ed3360341cf89f5f78c8e87419f01c3e593054d`
- Observed Node B SHA-256:
  `c3cf7224451a17e419cc4f2401d032aca435e6fe6e0ac61d37acb3e48b829dd9`
- Recovery: Node A and Node B upload preparation, copy, acceptance, and exact
  disposition all returned 0; no mutation entrypoint ran, so rollback was not
  required or attempted
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35l terminal archive

- Tag: `caddy-action35l-terminal-2026-08-17`
- Commit: `ad14e3e8f14a5794c6f9037e3505b3e7fa330920`
- Tag object: `bf0c3ac2fa83b17fdca25ae28961a2843592fef4`
- Action: 35l
- Authorized outer SHA-256:
  `452d9e6d2640ce6442fed74154c3a17b768e543c1da48789f585f06f18f47602`
- Transaction SHA-256:
  `967a63621b682dbb4aefb979f0d152f8437f17b4779daad68f33dd122516460d`
- Result: failed-consumed during Node B current-production tmpfiles artifact
  path validation, before candidate validation or any mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35l.LHr03k`
- Accepted local-zone SHA-256:
  `f1f422d64a55a77af4d77a829ed3360341cf89f5f78c8e87419f01c3e593054d`
- Failed assertion: `artifact_node_b_apprise_tmpfiles_regular=false`; the stale
  inventory target was `/usr/lib/tmpfiles.d/caddy-ha.conf`, while the installed
  file is `/etc/tmpfiles.d/caddy-ha.conf` as shown by operator readback
- Recovery: Node A and Node B upload preparation, copy, acceptance, and exact
  disposition all returned 0; no mutation entrypoint ran, so rollback was not
  required or attempted
- Status: terminal tag and terminal commit are synchronized; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35m terminal archive

- Tag: `caddy-action35m-terminal-2026-08-17`
- Commit: `c3db8d17a2dadc1ee969049f44c18a1ab88aa8f1`
- Tag object: `f538ee163aa3ba53d916a8438d21b116d0f750eb`
- Action: 35m
- Authorized outer SHA-256:
  `337f0ef966da2dc15206952f73e47ca32531ccef734b8e789cfaf7aa5751e0de`
- Transaction SHA-256:
  `a845b7999db81b390778d3bbb21cd7082dd58bbcdcb6c32c5b352bb1c7295195`
- Result: failed-consumed during Node B current-production incoming inventory
  validation, before candidate validation or any mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35m.huceey`
- Failed assertion: `incoming_node_a_inventory_empty=false`
- Bounded completion readback: Node B
  `/tmp/caddy-action35m-completion-readback.tsv` contains the sole regular
  `action17p-node-a-to-node-b-bootstrap` directory with exact
  `caddy-sync:caddy-sync:0500` metadata
- Recovery: Node A and Node B upload preparation, copy, acceptance, and exact
  disposition all returned 0; no mutation entrypoint ran, so rollback was not
  required or attempted
- Status: terminal tag and terminal commit are recorded; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35n terminal archive

- Tag: `caddy-action35n-terminal-2026-08-17`
- Commit: `364349a7f416d0800b56eb5c500f0bad15759626`
- Tag object: `34d993ffe5c13d18629158a0accd1258c81140ac`
- Action: 35n
- Authorized outer SHA-256:
  `e0eac2c04da696c5545ad2439a4a59d295a0c38e389b75e035a97a935f5648bd`
- Transaction SHA-256:
  `1a3ef5c67aae2a57bcd20cce26c1fa8be0e97cc230fee3caef72c2cd2f2da2f8`
- Result: failed-consumed during exact Node B retained-entry inventory
  validation, before disposition or any other mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35n.XLa3wW`
- Failed assertion: `retained_file_inventory_exact=false`
- Bounded read-only completion inventory: Node B and workstation
  `/tmp/caddy-action35n-retained-inventory.txt`, SHA-256
  `190986c5ca8976ac50729dd5cb040eff4eea9426d17f7e9aa73c1c4c4b170b40`
- Finding: the exact entry is marker-free; `.finalize-request` and `.complete`
  are both absent, while pinned manifests and every payload hash validate
- Recovery: Node A and Node B upload preparation, copy, acceptance, evidence
  readback, and exact disposition all returned 0; no mutation entrypoint ran,
  so rollback was not required or attempted
- Status: terminal tag and terminal commit are recorded; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35o terminal archive

- Tag: `caddy-action35o-terminal-2026-08-17`
- Commit: `a99fd56522224591580ff29b21fca545b65a7674`
- Tag object: `3e0bd6df5b58987b57947868877cfe9f9f05bef2`
- Action: 35o
- Authorized outer SHA-256:
  `8e287b33412fe6e710feae7cb75b160b766ee9bd4b6e1fea18433f0b31cd7e28`
- Transaction SHA-256:
  `a87579d6a2d74992b8af60cbf3c952bf7356d6eb667667920ed2c49a3ab119d4`
- Result: failed-consumed during Node B pre-mutation inventory validation,
  before retained-entry disposition or any production mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35o.lHdOqM`
- Failed assertions: the role-inapplicable
  `/var/lib/caddy-sync/incoming/node-b` path was absent but passed through an
  empty-directory helper, and the nonempty quarantine was incorrectly required
  to be empty
- Bounded read-only completion inventory: Node B and workstation
  `/tmp/caddy-action35o-quarantine-inventory.txt`, SHA-256
  `320a6b0718233c69c939f9cd471006f284efcee060cbca7df6b53be2438af7e9`
- Finding: `incoming/node-b` is absent as required on Node B. The quarantine is
  `caddy-sync:caddy-sync:0750` and contains four exact, safe, payload-valid
  retained trees: Action 17p, Action 33k normalized, and two Action 30c Node B
  outbound releases. They were classified read-only and remain unchanged.
- Recovery: both node upload paths and readbacks were disposed successfully;
  no retained-entry disposition or production mutation ran, so rollback was
  not required or attempted
- Status: terminal tag and terminal commit are recorded; the consumed
  machinery was removed by the immediate cleanup commit

## Action 35p terminal archive

- Tag: `caddy-action35p-terminal-2026-08-17`
- Commit: `2e9f757b43cc120bb6736b764aea0bbb5e55d136`
- Tag object: `adb7f88c7934959b3ce413e604c68a730e62786f`
- Action: 35p
- Authorized outer SHA-256:
  `70da8af9e01c5449607a3cada7579c12c933adde5fd0dd5a616f2b7912a646cb`
- Transaction SHA-256:
  `9a99c0f86090bea279f66a9fd2b2bc06f4d58cdaf9ee7dc6fb37860fc4ebbd1b`
- Result: failed-consumed during Node A current-production inventory
  validation, before retained-entry disposition or any production mutation
  entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35p.RTAd6J`
- Failed assertion:
  `action_35_p_check_artifact_node_a_lighttpd_prepare_helper_regular=false`
- Finding: `/usr/local/libexec/prepare-lighttpd-config.sh` is absent on Node A;
  it is a repository migration tool rather than a required runtime artifact.
  Node B retains the exact legacy `root:root:0755` copy with SHA-256
  `ce9a78aa487ce55c6fbba553b238160687852361d81c9b37179e4def8f83166f`.
- Recovery: both node upload paths were disposed successfully; no quarantine
  disposition, candidate validation, installation, reload, or production
  mutation ran, so rollback was not required or attempted
- Status: terminal tag and commit are synchronized; consumed machinery and the
  stale runtime-inventory requirement were removed by the immediate cleanup
  commit

## Action 35q terminal archive

- Tag: `caddy-action35q-terminal-2026-08-17`
- Commit: `502c80d93b6672eac5459486247954c1de57d23b`
- Tag object: `3a64fc8fc314b59a588e205335aa12b5af9bf3ce`
- Action: 35q
- Authorized outer SHA-256:
  `042e8bb25c5b44c7e3f6f7c330bb128ba1b6be54128913ad9ea6f6526c5fb7f5`
- Transaction SHA-256:
  `d07bc39db0316a52e82fb3aa94bfc5354b8576b1e487527aca0ad5692597764a`
- Result: failed-consumed during Node A quarantine inventory validation,
  before retained-entry disposition or any production mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35q.rtMxPJ`
- Failed assertions: `action_35_q_check_quarantine_empty_inventory=false` and
  `action_35_q_check_quarantine_inventory_empty=false`
- Finding: Node A retains four exact top-level quarantine families: two Node B
  release revisions and two Action 30d outbound revisions. Node B preflight
  and every preceding Node A assertion passed.
- Recovery: Node A and Node B upload preparation, copy, acceptance, failure
  readback, and exact disposition all returned 0. No mutation entrypoint ran,
  so rollback was not required or attempted.
- Status: terminal tag and commits are complete locally; remote synchronization
  is pending explicit approval. Consumed machinery was removed by the immediate
  cleanup commit.

## Action 35t terminal archive

- Tag: `caddy-action35t-terminal-2026-08-17`
- Commit: `0ff0afcfb45bf7bcc60a2a32ca1a77f67e9a0be4`
- Tag object: `a4404b5918d480f457761006b43c8d60e4e9220a`
- Action: 35t
- Authorized outer SHA-256:
  `61e1a6c582b76e5c95efcfdeea3b5038043b8270df44c2eb644e985020818f81`
- Transaction SHA-256:
  `e3280a9eebedce710db1596d00ad2bc07d56d09d1d522ce20c11c2619bab6c83`
- Result: failed-consumed during Node A candidate real-identity Caddy
  validation, before disposition or any production mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35t.68VRV6`
- Failed assertion: `caddy_serving_health_check_ipv4_https=false`; Node A
  DNS identity and Unbound validation passed, and Node B candidate validation
  passed completely
- Recovery: both failure readbacks and exact upload dispositions returned 0;
  no mutation ran, so rollback was not required
- Status: terminal tag and commit are synchronized; consumed machinery was
  removed by the immediate cleanup commit

## Action 35s terminal archive

- Tag: `caddy-action35s-terminal-2026-08-17`
- Commit: `61a05390f7eb1d63f3a5e1d2a6fed4217872443f`
- Tag object: `aff561a82bf4528748399462930ab8caccd72e0c`
- Action: 35s
- Authorized outer SHA-256:
  `52a7a1f6dc9cd6eeadef8aafe72a093c081634bb9a3f63a0595de39c4a2aeb4b`
- Transaction SHA-256:
  `100e584cdaed7a53bcdd44868f9061275af3226f80e0b338c465330b7a6b5574`
- Result: failed-consumed during Node B candidate Keepalived parser validation,
  before disposition or any production mutation entrypoint
- Exit status: 143
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35s.BCbKva`
- Failed boundary: the transaction incorrectly used the known-broken,
  unsupported `keepalived --config-test` interface on the installed Keepalived
  version. It terminated with empty stdout/stderr and retained status 143; this
  is not evidence that the candidate configuration was invalid.
- Recovery: both failure readbacks and exact upload dispositions completed;
  no mutation ran, so rollback was not required
- Status: terminal tag and commit are synchronized; consumed machinery was
  removed by the immediate cleanup commit

## Action 35r terminal archive

- Tag: `caddy-action35r-terminal-2026-08-17`
- Commit: `f264e43fd6176132104f7dd1f351c295e58700ec`
- Tag object: `7a716beff8b8ea1503c594f2d7ce685b090bdd3d`
- Action: 35r
- Authorized outer SHA-256:
  `347b9044acde81f2ec9d5dd5b4e86da108bf64c93c731654b78e67b98c201640`
- Transaction SHA-256:
  `7f4b7303eb6666b0651ee0110f609021298e0710825da3439f9cf88d2eb3e50c`
- Result: failed-consumed during Node A quarantine semantic validation,
  before disposition or any production mutation entrypoint
- Exit status: 1
- Workstation evidence: `/tmp/caddy-ssh-evidence-action35r.QXPhkL`
- Failed assertion:
  `action_35_r_check_node_a_quarantine_baseline_node_b_20260811t174240z_31d43261_5cd7_44ce_83e5_947927184d29_file_inventory_exact=false`
- Recovery: both failure readbacks and exact upload dispositions completed;
  no mutation ran, so rollback was not required
- Status: terminal tag and commit are synchronized; consumed machinery was
  removed by the immediate cleanup commit
