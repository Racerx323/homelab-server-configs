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
