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
