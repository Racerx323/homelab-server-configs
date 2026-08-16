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
