# Nautobot deployment history

This file is the concise terminal-operation index for the Nautobot deployment.
Raw evidence remains outside Git. Annotated tags preserve each terminal
operation definition and its sanitized evidence manifest.

| Operation | Result | Terminal tag | Definition commit | Bundle SHA-256 |
| --- | --- | --- | --- | --- |
| `nautobot-host-baseline-v1` | Rolled back | `nautobot-host-baseline-v1-rolled-back` | `33ae47c6baaeba267b4bdcdbfb5725d5a68383e2` | `e06a61318470a8520edf8c05950d3f8915781492d53165eebe9ceeaf6324c0de` |
| `nautobot-host-baseline-v2` | Rolled back | `nautobot-host-baseline-v2-rolled-back` | `fb3e06ecd7990311cf1b10c0a988325b5923c9b7` | `7d98b1179c7f528ce4c9303bbf0674ba3f3f03dc67a90d4e437d9da8b0287097` |
| `nautobot-host-baseline-v3` | Manual intervention | `nautobot-host-baseline-v3-manual-intervention` | `32d899d1d22d4506daa7710384cd75b026e214a1` | `67bd775d73e2bb05fcf9bb64f794a853b28e4d1dba60dec0a66554ee35a06c50` |
| `nautobot-storage-diagnostic-v1` | Diagnostic complete; rollback conditions met | `nautobot-storage-diagnostic-v1-action-required` | `e633c66dba4fc18cad72897a91f30311d3e33fdb` | `575a5cad32cd4f836fb2851d83a0efb7123caa8fff5d4bf683dc3a1c4a212451` |
| `nautobot-uas-quirk-v1` | Rolled back; storage action required | `nautobot-uas-quirk-v1-rolled-back-action-required` | `c8682930bc6906284b1ffa8d2d17d2a4e556bc16` | `14d4f39a672b6b9ca6843948091fe3c6815779a3ae973b9505b0af337fb912ae` |
| `nautobot-uas-quirk-v2` | Rolled back; storage action required | `nautobot-uas-quirk-v2-rolled-back-action-required` | `e3ab01b8431999027d03f00d5c310822f9356279` | `8b55c1371d1dcffa5e76e4c363869328928ec4e472e8b287604ce11a2ff91166` |
| `nautobot-uas-quirk-v3` | Rolled back after ambiguous broad gate; operator remediation immediately effective, soak pending | `nautobot-uas-quirk-v3-rolled-back-operator-applied` | `f5ce8344ab6f4c2035a617cad4684603586b8c9f` | `0899f68448ca28696044174c7a55fe68621ffdcc29c274f6782aa15875322336` |
| `nautobot-storage-diagnostic-v2` | Immediate post-quirk baseline healthy; soak pending | `nautobot-storage-diagnostic-v2-baseline-healthy-soak-pending` | `8728fc88b13b46315fffa0a3af64bd767e90b4c7` | `616772e4ac259cb99bb4e3a27b7b5024ab3c17fdc03eb8ff94a0ff321f49a05a` |
| `nautobot-storage-soak-verification-v1` | 24-hour storage soak healthy; isolated restore pending | `nautobot-storage-soak-verification-v1-passed` | `eb38b4923ba6bfbc4f458870b6555a6e39d91f77` | `e3a94ecd20ee5070b86e92f6cf4e16faa56762cca3cfec4dc4e31492dc538305` |
| `nautobot-host-baseline-convergence-v1` | Stage-3 host baseline accepted with retained limitations | `nautobot-host-baseline-convergence-v1-accepted` | `e55ac4d5922a347bd2502271e1b850b700cf8bb4` | `dd94e06d18d670338a909890bfea13d32f46d20e693de5aaaa6c272447b16838` |
| `nautobot-dual-stack-identity-v1` | Stage-4 identity accepted with retained limitations | `nautobot-dual-stack-identity-v1-accepted` | `0930dc431d73362bff8ffcd87e010c6a29e40d22` | DNS owner bundle `39b472e210a9ff7e95c027e8fdf683b018921e0520a72d517eb6331fe2b9c50c` |

Accepted baseline identity: [accepted-live-state.yaml](manifests/accepted-live-state.yaml),
semantic SHA-256 `7b54a7f61a174368ebfd2b57d9ddd7033ff6010338866d81541586f4d891b820`.
The terminal tag preserves the exact operation and terminal evidence. At the stage-3 archival boundary the active
slot was clean; runtime, Restic and full workload acceptance remain outstanding.

Accepted dual-stack identity is recorded alongside the unchanged stage-3 baseline
in `manifests/accepted-live-state.yaml`. The stage-4 tag retains
`terminal-identity-definition.json` and `terminal-identity-evidence.json`.
The definition references the DNS owner terminal archive and its additional
restart authorizations. No runtime, Restic or Caddy acceptance is implied.

## Image qualification failure

`nautobot-image-qualification-v1`: failed at OCI cgroup process placement; worker
stopped, partial isolated artifacts retained. Terminal tag:
`nautobot-image-qualification-v1-failed`. The tag preserves the exact consumed
operation and `manifests/image-qualification-failure.json`; its peeled commit is
the terminal definition commit. Bundle SHA-256:
`21c15632af42c3e7d1aeb689889a0538a58e58a6b00b2a2f5024ca243f7c06a4`.
Accepted stage-3/stage-4 identities remain unchanged. The reusable build helper in
this archival commit includes the separately tested retry correction; the failed
execution used the frozen bundle identified above, not that corrected helper.

## Successful bounded image qualification

`nautobot-image-qualification-v2`: passed bounded ARM64 build, static package/CLI
checks, OCI integrity verification and delayed storage observation. Terminal tag:
`nautobot-image-qualification-v2-qualified`. The tag preserves the exact executed
operation and `manifests/image-qualification-result.json`; its peeled commit is
the terminal definition commit. Bundle SHA-256:
`09b71931b20200846384fbc3e1217187adcc600fd481674a63d8f928f2a03224`.
The verified image remains an isolated artifact; application runtime, production
store load, credentials, Restic and pilot workload acceptance remain outstanding.

## Credential provisioning and injection

`nautobot-credentials-v1`: Doppler creation and protected host injection verified;
controller temporary payloads cleaned. Terminal tag:
`nautobot-credentials-v1-provisioned`. Its peeled commit preserves the exact
consumed definition and `manifests/credential-result.json`. Bundle SHA-256:
`4097b449a3722e6e7b65f0da9a28a6e066796e13dc2a4b8571a8e226aec10273`.
Bootstrap password remains only in Doppler; no administrator or runtime was
started. Host baseline and image qualification identities remain unchanged;
application configuration/authentication and runtime acceptance remain open.

Credential archival reconciliation: published tag
`nautobot-credentials-v1-provisioned` peels to
`451b82d38906b7b5ca6770010fe924a0a9ce3ca1`. The consumed files retain their original
formatting; the archive commit skipped only Markdown/YAML formatting hooks for
one bare URL and one sequence-indentation finding. Other hooks passed. Current
files correct those findings and return the operation slot to clean. Durable
credential provenance is in `manifests/provisioned-credentials.json`.

## Runtime image-store readiness

`nautobot-image-load-v1`: all three immutable ARM64 images loaded and verified in
nautobot's default rootless store. Terminal tag: `nautobot-image-load-v1-ready`.
Its peeled commit preserves the consumed definition and sanitized
`manifests/image-load-result.json`. Approved bundle:
`f2228436dc8cf2e6f0b9b0714928f94363f7aa0f7a450af9319778f0e3552cde`.
All four bounded steps passed at least 75 seconds of delayed observation; host,
credential metadata and network configuration continuity passed. No application
containers, administrator, database initialization or Restic stage ran. The earlier
preflight failure is retained in `manifests/image-load-preflight-result.json`.

Image-store archival reconciliation: published tag `nautobot-image-load-v1-ready`
peels to `0dd657bc6f7c1a5c742bc8e07e64e3ab6d50d27b`. Durable store provenance is
`manifests/runtime-image-store.json`. The active slot is clean; configuration and
authentication qualification remains a separate, inactive preparation.

## Disposable authentication trial

`nautobot-configuration-auth-v1`: failed at the application-probe step; cause not
retained. All three disposable containers and the private network were removed.
Configuration continuity and 77.733 seconds of delayed observation passed.
Terminal tag: `nautobot-configuration-auth-v1-failed`; its peeled commit preserves
the consumed definition, executable inputs and `manifests/authentication-trial-result.json`.
Bundle: `fda654ad9614e022ecbe9c5f27e7930a9cae21c8ec33fefd44f3680ac5028f04`.
Authentication and production runtime remain unaccepted; baseline and image-store
identities are unchanged.

Failure archive reconciliation: `nautobot-configuration-auth-v1-failed` peels to
`18d5bf8442bbc410272917544d69ae4ac6172ffd`. All frozen source inputs match the tag.
The single active slot now holds the separately approved diagnostic retry v2;
accepted host and runtime identities remain unchanged.

## Diagnostic authentication retry

`nautobot-configuration-auth-v2`: running PostgreSQL tmpfs-set validation failed
before application authentication. All trial containers and the private network
were removed; continuity and 77.778 seconds of delayed observation passed.
Terminal tag: `nautobot-configuration-auth-v2-failed`; its peeled commit retains
the exact consumed inputs and `manifests/authentication-trial-retry-result.json`.
Bundle: `ab01aacd5616c0c13a98766d0feb16b9dbc5c34a92e639c9a9bed41dd5abb426`.
Host baseline and image-store identities remain unchanged; authentication remains
unaccepted.

Diagnostic retry archival reconciliation: `nautobot-configuration-auth-v2-failed`
peels to `2ac53754aabb3a0d15b44656ef3b9a366ac11c2a`. All consumed source inputs match the
published tag. Only YAML indentation lint was skipped to preserve executed bytes;
behavioral, schema and secret checks passed. The successor definition uses canonical
formatting and the corrected socket tmpfs path. No authentication acceptance is
claimed.

## Canonical-path authentication trial

`nautobot-configuration-auth-v3`: all running-container checks passed; Django
shell exited 1 without a valid probe result. All disposable objects were removed,
continuity passed and 77.743 seconds of delayed observation were quiet. Terminal
tag: `nautobot-configuration-auth-v3-failed`; its peeled commit retains the exact
consumed inputs and `manifests/authentication-trial-canonical-result.json`. Bundle:
`98f25b29939fa8a2282374429986f1150ff7039fc8a9f8f46f9b3a87298e22e0`.
Authentication remains unaccepted; baseline and image-store identities unchanged.

Canonical trial archival reconciliation: `nautobot-configuration-auth-v3-failed`
peels to `951fb7edefbc2ef65f48b051124386d324d68601`. All consumed source inputs match
the published tag; all archive hooks passed. The successor is definition-only,
with bounded disposable startup-directory mounts and sanitized startup diagnostics.

## Startup-directory authentication trial

`nautobot-configuration-auth-v4`: container checks passed; the probe rejected its
settings phase without retaining the specific assertion. Cleanup and continuity
passed with 77.769 seconds of quiet delayed observation. Terminal tag:
`nautobot-configuration-auth-v4-failed`; its peeled commit preserves all consumed
source inputs and `manifests/authentication-trial-startup-result.json`. Bundle:
`55c31c6b7531bbc66d9aa5a8961c3ff9238124433218f37aa45075e9186329cd`.
Authentication remains unaccepted; accepted host/image-store identities unchanged.

Startup trial archival reconciliation: `nautobot-configuration-auth-v4-failed`
peels to `3b8e9a73ac5c2386f2eea1970a2adc0aaf290186`. Every consumed source input matches
the published tag; all commit hooks passed. The successor corrects database-port
assumptions and preserves categorical assertion diagnostics. Live authentication
remains unaccepted.

## Settings-qualified authentication trial

`nautobot-configuration-auth-v5`: settings/plugin checks passed; PostgreSQL rejected
with `postgres_unexpected_failure`. The failed attempt and underlying cause remain
unproven; Redis checks were not reached. All disposable objects were removed,
continuity passed and 77.774 seconds of delayed observation were quiet. Terminal
tag: `nautobot-configuration-auth-v5-failed`; its peeled commit retains all consumed
source inputs and `manifests/authentication-trial-settings-result.json`. Bundle:
`a3abb94558e035ae7c6cd1cd56a053e5e8e3c0a05239a8f8378651293acbd808`.
Authentication remains unaccepted; accepted host/image-store identities unchanged.

Settings trial archival reconciliation: `nautobot-configuration-auth-v5-failed`
peels to `6e4f6ca6eb943d584986e5ee7b3aa878c3568c48`. All consumed source inputs match
the published tag; all archive hooks passed. The diagnostic successor is prepared
for separate execution approval. Authentication remains unaccepted.

## PostgreSQL diagnostic authentication trial

`nautobot-configuration-auth-v6`: settings/plugin and positive PostgreSQL checks
passed; the wrong-password attempt raised OperationalError without SQLSTATE.
The negative criterion failed and Redis checks were not reached. All disposable
objects were removed; continuity and 77.804 seconds of delayed observation passed.
Terminal tag: `nautobot-configuration-auth-v6-failed`; its peeled commit retains
all consumed source inputs and `manifests/authentication-trial-postgresql-result.json`.
Bundle: `b2b00f10eea4a7accb65bcd905f5e429467a668303967ab2a3a3aa512ba98cd1`.
No full authentication or production-runtime acceptance is claimed.

PostgreSQL trial archival reconciliation: `nautobot-configuration-auth-v6-failed`
peels to `f55d3a2a77b3a163a23dbe1f7e95786c7c7441e1`. All consumed source inputs match
the published tag; all archive hooks passed. The revised readiness successor uses
native checks and positive connections. Negative security testing remains unresolved.

## Successful disposable readiness qualification

`nautobot-configuration-auth-v7`: all five checks passed: settings/plugin, native
configuration, positive PostgreSQL identity/port, Redis cache and Redis broker.
All disposable objects were removed; continuity and 77.795 seconds of delayed
observation passed. Terminal tag: `nautobot-configuration-auth-v7-ready`; its peeled
commit retains all consumed source inputs and `manifests/configuration-readiness-result.json`.
Bundle: `53bd35086e31f99a414e09a24373eb0a74fd3e3ec52b8fe7126a755c6576b54f`.
Negative security tests remain unresolved; production runtime is not accepted.

Readiness archival reconciliation: `nautobot-configuration-auth-v7-ready` peels to
`cd15ca72e440654012e34593e049b20e9e125d43`. All consumed source inputs match the
published tag; all hooks passed. Durable readiness identity is recorded in
`manifests/configuration-readiness.json`. The active slot is clean; Restic pre-data
and production runtime acceptance remain outstanding.

## Fresh Restic absence preflight

Passed; repository config absent and credential cleanup verified. Terminal tag
`nautobot-restic-absence-20260921-passed`, commit `2d96737d863cea67cc7222e439e0a293db2f0131`.
Approved bundle: `928e084f6a0bdbcd4a713b8bc74e97de08f4048293a52b4b2b25a04dceb0ad79`.
No initialization attempted. Consumed inputs and sanitized result are archived.

## Restic initialization

Accepted repository format 2 and identity, no locks/cache and credential cleanup.
Terminal tag: `nautobot-restic-initialization-v1-accepted`; archive commit:
`08a7e622aa2e15650d8ba1beb0695b10e06cb134`. Bundle:
`faf95642acbcc2c3c370a4e63c91419cda0988489ecaa568cf852cfe4adbb4c4`.
Repository ID: `536d6d1dc29c7c6ea79eed972efb43cc37445fe0be73d0bf8518e2771394f8a9`.
No backup or restore performed. Exact 24 consumed inputs verified in the archive.

## Canary upload and full integrity

Accepted one matching snapshot, full read-data check, unchanged source, 75-second
quiet storage review and credential cleanup. Terminal tag
`nautobot-canary-backup-v1-accepted`, archive commit `7521e023a19c874fd276f36ccbba71840fbf9a3a`.
Bundle: `e8170dbb0f4ebe60c5ace3dccc1b51767bfda453878a57b5806347548117ee98`.
Snapshot: `7a86d7a5d0748ec72d5a99be099be0922958b290662324a4c416b6825a5f5cf3`. Isolated restore remains separate.
All 32 consumed input hashes verified against the terminal archive.

## Accepted isolated canary restore

`nautobot-predata-canary-restore-v1`: accepted exact snapshot/subtree restore,
independent tree comparison, unchanged source, delayed storage review and
credential cleanup. Terminal tag: `nautobot-canary-restore-v1-accepted`, archive
commit `01bb9660fb4f30dcd275fe6301e0a06a92dc6f75` (published and read back).
Bundle: `0260d585cdcd54e90f96e6a6a0b0de6c4f884c1eef25fcd662aa0fdcc402d606`.
The tag preserves the exact consumed definition and
`manifests/canary-restore-result.json`; its archival-pending field describes the
pre-archive review. Source, snapshot and restored tree remain retained. The
pre-data canary gate is satisfied; application recovery and runtime remain
unaccepted. The active operation slot was cleared after remote tag verification.

## Initialization blocked before installation

`nautobot-runtime-initialization-v1` stopped before units, containers, volumes or
migrations were created. Read-only comparison established an inaccessible
inherited working directory; original Ansible task details were not retained.
Terminal tag: `nautobot-runtime-initialization-v1-blocked`; archive commit
`c5040e37dc5b79e16c004f5f8e78904db1318a78` (published and read back).
Bundle: `3f8e0dfcc957d9e5001b6e843c703ada9fd660ef316613dac4d644d293ee3afb`.
All 47 consumed input identities were verified. The exact definition and
`manifests/runtime-initialization-result.json` remain in the tag; its pending
archival field is historical. Accepted live state did not advance. The successor
corrects command working directories and retains sanitized Ansible task events;
its execution requires a new exact-bundle approval.

## Retained partial initialization

`nautobot-runtime-initialization-v2` failed on the native `post_upgrade` timeout.
Independent failure stops succeeded; volumes and installed artifacts remain.
Terminal tag `nautobot-runtime-initialization-v2-failed` points to
`6f11f0c34f4ae10046e875cc4f21e94cffd6e2c4` (published and verified).
All 48 consumed input identities match that archive. Its sanitized result's
pending-archival field is historical. Runtime acceptance did not advance.
Recovery inspection is separate and cannot rerun migration or replace volumes.

## Accepted retained-database inspection

`nautobot-retained-database-inspection-v1`: verified cold copies of both stopped
volumes; read-only ledger inspection; PostgreSQL stopped, Redis stayed stopped,
no containers remained; guard disarmed and 75-second storage review quiet.
Terminal tag `nautobot-database-inspection-v1-accepted`, archive commit
`16835ade6b92376d12b9834286fa57f0a81cbb17` (published and read back).
All 53 consumed input identities were verified, including six bound rendered
artifacts. Bundle `4976dfe6bb7bd005a8e425468a9149eda3f52848a0e32868ac9c35a88588defd`.
The tag preserves the exact operation and `manifests/database-inspection-result.json`;
its pending-archival field is historical. Ledger: 423 applied migrations; static
comparison found 16 core and 10 DNS Models files unrecorded. Initialization and
runtime acceptance did not advance. Originals and protected host copies remain;
no restoration or migration retry occurred. The consumed slot is now clean.

## Accepted runtime initialization

`nautobot-runtime-continuation-v1`: initialization accepted. Published annotated
tag `nautobot-runtime-initialization-v1-accepted` resolves to
`6a31396b0a54868911c294abc586f0beac06f09b`; remote identity verified on
September 22, 2026. Definition commit:
`983cf0b3a09b876dcb3194c045263afd26ef26e3`. Approved bundle:
`ba3bc760d334955a3d56eb743038471a88df43cdea8c011e8b253745c0910677`.
All 57 consumed input identities were verified before archival.

The tag preserves the consumed definition and
`manifests/runtime-initialization-result.json`: five native steps passed, the
native plan covered 58 migrations, and the final check found no pending
migrations. The parser recognized 56 individual completion events; two individual
timings remain unobserved. Data services and migration were stopped, cold copies
remained verified, and the 75-second storage review was quiet. The archived
result's pending Git archival field is historical; publication is now verified.
The operation slot was cleared only after remote verification. Administrator
bootstrap, application startup and full workload acceptance remain outstanding;
accepted stage-3/stage-4 identities are unchanged.

## Failed administrator bootstrap

`nautobot-administrator-bootstrap-v1` failed before administrator creation.
Published annotated tag `nautobot-administrator-bootstrap-v1-failed` resolves to
`d8336e5b65b112d9e1e1d8ec55b2cdec226fb592`, remotely verified September 22, 2026.
It retains the consumed definition and sanitized `administrator-bootstrap-result.json`.
Native configuration and migration checks passed; the account check failed.
Pinned-source reproduction identified the `shell -c` configuration-path collision;
the exact live traceback was not retained. Creation was not attempted. Cleanup,
stopped-state verification and the 75-second storage review passed. Accepted live
state is unchanged. The archived pending-publication field is historical.
The successor uses `--command`, parser regressions and recognized callback task
names; its execution requires separate exact-bundle approval.

## Accepted administrator bootstrap

`nautobot-administrator-bootstrap-v2` is accepted. Published annotated tag
`nautobot-administrator-bootstrap-v2-accepted` resolves to
`17dbc01d45e591ebcbc019865f1ac010df7238bc`; remote identity verified on
September 22, 2026. Definition commit `45e10f33eb9deefc2a2f29d68f12d5d7dcc60e08`;
approved bundle `370f9ea861b96e0923dc3d886ca16560f2b609beefbcefa1930da3b6e1461f5f`.
All 70 frozen inputs were verified. The tag preserves the consumed definition
and `manifests/administrator-bootstrap-result.json`; its pending-archival field
is historical. All five native checks passed, including account absence, native
creation and exact administrator flags/identity with positive authentication.
Transient credentials and the disposable container were removed; data services
stopped; identities/cold copies verified; guard disarmed without activation;
75-second storage review quiet. The administrator is now present: do not rerun
bootstrap. The active slot is clean. Application startup and browser acceptance
remain unperformed; stage-3/stage-4 accepted identities are unchanged.

## Accepted startup database preservation

`nautobot-startup-database-preservation-v1` passed on September 22, 2026.
Bundle `eabbf6cdb678acb38e38019b280ccdc0e310bc1fc54f3c0be2af7333739de074`;
PostgreSQL 3218 entries and Redis 6 entries matched source-before, source-after
and copy content/metadata. Final stopped-state and installed-identity checks
passed. `manifests/startup-preservation-result.json` records sanitized evidence;
`terminal/startup-preservation/` retains the exact consumed bundle. Published annotated tag
`nautobot-startup-preservation-v1-accepted` resolves to
`42b6b18ae476ce3467c9f51f04f515d1b7337fde`; remote identity verified. The tagged pending-publication
field is historical; the exact bundle remains in the tag. No restore or
application startup was performed.

## Failed application startup

`nautobot-application-startup-v1` failed native configuration validation before
migration or application services started. Annotated published tag
`nautobot-application-startup-v1-failed` resolves to
`a39d1391b6b07373a1006f1489a245a8a99862b0`; remote tag object
`4784564b875791c632fae1af7fa78e0bb6946eb5` verified September 22, 2026.
All 47 consumed input hashes are preserved in `terminal/application-startup/`
in that tag, alongside the original definition and approved diagnostic bundle.
The diagnostic identified read-only `/prom_cache` as the configuration failure.
Final cleanup was independently verified: all service PIDs zero, no containers,
both stop timers inactive; migration failed marker retained. The initial armed
guard fields are historical. Accepted application state is unchanged.
The successor binds a bounded per-container metrics tmpfs and the reviewed
processless failed migration state; it requires separate execution approval.

## Second application startup failure

`nautobot-application-startup-v2` exhausted HTTP readiness after successful
native migration. Terminal tag: `nautobot-application-startup-v2-failed`; its
peeled commit identifies this archive. All 48 consumed inputs are preserved
under `terminal/application-startup/objects/`. Bundle:
`93c7f56eb7fc7c57d4ad88b206624e7b96c7a2f516e8e170ed05c6948621a3b3`.
All service processes and containers were stopped; data and recovery copies
were retained. Exit 137 followed cleanup, not a proven initial crash. Exact
HTTP errors were not retained. Accepted application state is unchanged.
Published archive commit `a9b65628bc41bc8f2665be830ec25e963a21b77f`; annotated
tag object `dc90a2cf1b714c74e1ea6d6787ca673744406d46` verified remotely.
Consumed inputs were removed from the current branch only after verification.
The corrected successor remains subject to separate execution approval.

## Third application startup failure

`nautobot-application-startup-v3` passed native migration and web preparation,
but uWSGI failed without master mode. Container logs used k8s-file while readiness
looked in the journal. Worker and scheduler were not started. Final cleanup
verified no service processes or containers; data and recovery copies remain.
All 48 consumed inputs and sanitized results are preserved in the archive
for published tag `nautobot-application-startup-v3-failed`.
The peeled annotated tag identifies the archive commit. Accepted state is unchanged.

Archive commit `332c3dc6ec4aafcd69c36bc181c00f8515d86830` and annotated tag
object `00114c42ba064614221eb852b8f5cd875880aa02` were verified remotely.
Consumed files were removed only after exact archive comparison.

## Fourth application startup failure

`nautobot-application-startup-v4` passed all six readiness gates and native/HTTP
acceptance, then failed its administrator session probe. Remaining acceptance
groups were not run. Independent cleanup verified all services inactive with
zero exit status, no processes/containers, inactive timer and no storage/OOM
events. Data remains. Tag `nautobot-application-startup-v4-failed` preserves all
48 consumed inputs and sanitized results; publication verified. Its peeled commit
identifies the archive. Accepted application state is unchanged. Read-only
diagnosis supports a too-short identity-check deadline; discarded exceptions
prevent proving the exact historical failure branch.

Published archive commit `7932af040294eee4b332a951c63df15ede45de2f` and tag
object `4c7deb721d6f6d5113fa91db8fedb5e7ca44928f` were verified remotely before
removing consumed operation files from the current branch.

## Fifth application startup failure

`nautobot-application-startup-v5` passed all startup gates and native, HTTP,
session, dual-stack network and Job acceptance. Resource acceptance returned
`command_or_output_boundary`; storage acceptance was not run. Independent cleanup
verified inactive successful services, no processes or containers, inactive guard
and no matching kernel storage/OOM events. Data and recovery copies remain.
Tag `nautobot-application-startup-v5-failed` preserves all 48 consumed inputs and
sanitized results; publication pending. Its peeled commit identifies the archive.
Accepted application state is unchanged. Read-only diagnosis confirmed worker
heartbeat-file production was disabled while the probe required its file.
