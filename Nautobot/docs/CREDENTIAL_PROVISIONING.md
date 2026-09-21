# Credential provisioning and injection operation

This operation creates one Doppler config and four application credentials, then
injects protected inputs on j2-svpi4mf. It does not start containers, load images,
initialize databases, create the administrator or change Restic/network/Caddy.
The bootstrap password stays only in Doppler until its separate one-time operation.

The completed pilot is archived at `nautobot-credentials-v1-provisioned`.
Do not rerun its create-only bundle. The following procedure applies only after
reviewing a new operation and its prerequisites.

## Bundle and execution

```text
python3 Nautobot/ansible/scripts/provision-credentials.py prepare /tmp/NEW_BUNDLE
python3 /tmp/NEW_BUNDLE/launcher.py verify /tmp/NEW_BUNDLE EXACT_SHA256
python3 /tmp/NEW_BUNDLE/launcher.py execute /tmp/NEW_BUNDLE EXACT_SHA256
```

Only execute contacts Doppler and the host. Obtain approval for the exact hash;
preparation approval is not authorization to run an unseen bundle. The digest
covers the controller, Ansible playbook, settings, operation/schema, selected
credential policy, accepted host/image inputs, inventory, tests and procedure.
Ansible handles the host; the controller owns secret generation, bounded private
CLI output, frozen-input verification and inter-system failure accounting.

Preflight checks the accepted boot/account, active user manager, zero failed
units, absent runtime directory, and empty rootless container/secret lists.
Commands use `/` as their working directory so rootless queries never inherit
the SSH user's private home. A successful empty secret-list response is treated
as an empty list; failed commands and malformed nonempty JSON still stop.
Unknown command/JSON results stop the operation. Doppler must report existing prd,
absent prd_nautobot and only three metadata names in the parent. Create only that
config, verify it starts empty, generate independent hex credentials, and write
only the four policy keys. Refuse existing configs; never auto-rotate or overwrite.
There is no conditional-create API for individual secrets in this implementation:
the newly created config must remain exclusively owned by this operation until
verification. Concurrent writers are outside its contract.

Doppler uses the existing controller authentication context and explicit
`https://api.doppler.com` with TLS verification. Do not supply tokens on the command
line. Private command stdout/stderr live in anonymous descriptors with 1 MiB output
and bounded execution time; they are never copied into evidence. API write retries
are disabled. Secret-bearing uploads and injection payloads use an exclusive
0700 controller directory and 0600 files, removed on success and ordinary failure.
Cleanup is checked; failures retain the path and fail acceptance. No secret values
or hashes enter evidence. Ansible secret tasks use no_log and diff=false.

## Injection and verification

Create /var/lib/nautobot/runtime exclusively, owned 999:985, mode 0700. Install six
0600 service environments and 0644 non-secret nautobot_config.py. Create rootless
Podman secret nautobot-redis-config via stdin. Compare environment and Redis-secret
contents privately, and verify environment modes/owners. No bootstrap password is
sent to the host. Redis health receives REDISCLI_AUTH; applications receive
NAUTOBOT_SECRET_KEY, NAUTOBOT_DB_PASSWORD and NAUTOBOT_REDIS_PASSWORD with matching
service endpoints. These names and inherited settings were inspected in the
qualified Nautobot 3.2.3 image. DNS Models is enabled in the settings file.

This verifies stored inputs, not application operation. Full settings import,
database/cache authentication, migrations, plugin behavior and bootstrap remain
runtime qualification checks. No live configuration check is claimed by the
fixture tests. The image's general CLI help is not a substitute for those checks.

## Failure and recovery

A stage checkpoint is written before cloud or host mutation. Any ambiguous write
stops without automatic retry, deletion, rotation or rollback. Cloud credentials
already created remain the recovery source. A partial host injection remains
protected and is reported as requiring review; no services are started from it.
After an interruption, inspect the fixed config, exact runtime directory and
Redis secret before deciding how to resume. Do not rerun this create-only bundle.
Controller loss can leave an SSH-initiated task finishing remotely; inspect before
retrying. Never infer absence from a failed query.

Separately scoped rollback can remove only this operation's verified unused
runtime directory and Redis secret, and its unused new Doppler config/keys. First
prove no consumer was started and preserve required evidence. Do not delete shared
prd, unrelated credentials or the initial-administrator secret merely because it
has not yet been consumed. Secret cleanup failure is manual intervention.

The controller result distinguishes Doppler state, host injection state, overall
acceptance and temporary-payload cleanup. No accepted-runtime identity changes.
