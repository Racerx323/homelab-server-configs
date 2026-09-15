# Host storage component

`docs/HOST_STORAGE_ARCHITECTURE.md` is the governing architecture.
Keep profiles reusable and inventory opt-in. Never discover targets and mutate
all matching hardware automatically. One explicit host per operation.

Preflight must not run SMART requests, alter boot settings, install packages,
restart services, or reboot. Live mutation needs the reviewed exact bundle and
scoped operation authority. Do not modify another component's active observer.

Keep raw topology, kernel logs, boot bytes and operation records outside Git in
private evidence directories. Historical Nautobot operations remain retained;
future transport operations use this component. Do not delete old evidence.

Run Python fixture tests and every Ansible syntax check through the repository's
Ansible temporary-directory wrapper. Local checks do not establish live recovery
or storage acceptance. Record remaining qualification explicitly.
