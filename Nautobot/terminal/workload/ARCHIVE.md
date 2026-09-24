# Failed workload qualification archive

Exact consumed bundle and source inputs are preserved separately from corrected
reusable code. All 16 bundle files and 24 source inputs match the executed
manifest. The source snapshot is the published preparation commit; the operation
source_commit field records its historical predecessor, not that snapshot.

All 15 Jobs succeeded, but backup finished before audits began. Overall workload
acceptance failed and phase coverage was incomplete. Backup integrity passed;
application restore and persistence remain unverified. Final readback confirmed
service continuity and credential/temporary-module cleanup. Fixture, disabled
registrations and snapshot remain intentionally retained.

Raw evidence stays outside Git. result.json contains sanitized decisions and
private evidence hashes. The annotated tag
`nautobot-workload-qualification-v1-failed` identifies this archive commit.
Publication-pending fields describe the state when this archive was created.
