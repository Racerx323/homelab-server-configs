# Host storage

Reusable host transport configuration, initially for Raspberry Pi 4 with an
X872 USB/NVMe adapter and bridge `152d:0583`. Inventory selects a profile; the
profile defines the boot backend, matching bridge, quirk and expected driver.

- [Architecture and ownership](docs/HOST_STORAGE_ARCHITECTURE.md)
- [Operations, authorization and recovery](docs/OPERATIONS.md)
- [Follow-on fleet qualification planning prompt](docs/FLEET_QUALIFICATION_PROMPT.md)
- [Initial hardware profile](profiles/rpi4-x872-usb-storage.yaml)
- [Operation schema](schemas/operation.schema.json)
- [Ansible storage role](ansible/roles/storage_transport/tasks/main.yaml)

The first milestone is repository implementation plus read-only pilot validation.
Apply/reboot/recovery definitions require separate live qualification on a host
with verified console recovery. No deployment or storage acceptance follows from
an inventory selector, passing unit tests, or an already-correct boot file.

Run local tests:

```sh
python3 -m unittest discover -s host-storage/tests -v
```

The real Ansible write/rollback fixture uses disposable local files:

```sh
fixture_dir="$(mktemp -d /tmp/host-storage-fixture.XXXXXXXX)"
/bin/bash tests/repository/run-with-ansible-local-temp.sh ansible-playbook \
  -i localhost, host-storage/tests/filesystem-fixture.yaml \
  -e "fixture_dir=$fixture_dir"
```

It verifies byte/mode preservation, no-op behavior, exact rollback and rejection
of a reused backup. Inspect its result and remove only that generated fixture
directory after review. It never reboots or contacts the pilot. Ansible needs
local RPC socket access even for this local fixture.

Run Ansible validation through `tests/repository/run-with-ansible-local-temp.sh`.
The controller needs Python PyYAML, jsonschema and Ansible; the target needs
Python 3, findmnt and systemd's journal tools. No SMART query is used here.
