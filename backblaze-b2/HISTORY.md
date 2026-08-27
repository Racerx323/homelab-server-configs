# Backblaze B2 operation history

This file is the concise terminal-operation index for the Backblaze B2
component. Raw evidence remains outside Git. Annotated tags preserve each
terminal operation definition and its sanitized evidence manifest.

| Operation | Result | Terminal tag | Definition commit | Bundle SHA-256 |
| --- | --- | --- | --- | --- |
| `backblaze-b2-nautobot-bootstrap-v1` | Rejected; provider key preset exceeded reviewed capability scope | `backblaze-b2-nautobot-bootstrap-v1-rejected-capability-scope` | `04067b6d0961277acbc64d4643e4a10194852a31` | `58f908209899b31d132029dec5b857434664de8d435d13faacfb5c02580872d1` |
| `backblaze-b2-capability-remediation-preflight-v1` | Blocked; supplied credential authenticated but lacked required management authority | `backblaze-b2-capability-remediation-preflight-v1-blocked-insufficient-authority` | `a1eb21b458528b024488ee0b5091e09af1ca43f7` | `5c18337c188f70dc4078c84653b6750335155fe4bc548a086b57ef2c9fcaade9` |
| `backblaze-b2-master-key-rotation-v1` | Completed by operator after two protected-write failures; recovered credential passed read-only authentication | `backblaze-b2-master-key-rotation-v1-completed-operator-recovery` | `281a1375e1cea471205004445e48c481fe2b6610` | `d51bb60f563fa71eea51fcbc93d16038d65eb71523d068012ccbb4a11a6deb34` |
| `backblaze-b2-capability-remediation-preflight-v2` | Blocked; invalid Doppler metadata command after bounded provider reads | `backblaze-b2-capability-remediation-preflight-v2-blocked-doppler-metadata-command` | `3e9754765365b5cf804743359128ac3c147c351f` | `402010b2bda16dea599e755eac449931367ae0461dc3585e01f75e6d73b1c4ef` |
| `backblaze-b2-capability-remediation-preflight-v3` | Passed; management authority and exact bucket, key, and Doppler residue confirmed read-only | `backblaze-b2-capability-remediation-preflight-v3-passed` | `a9666394a32a433a108fdbf5077c632cd3b0f7a4` | `720b9155986511add97b8d0fe3fc367c84c7b5977c52ba5004fd1156819e57fa` |
