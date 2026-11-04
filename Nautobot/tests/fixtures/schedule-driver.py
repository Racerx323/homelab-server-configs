#!/usr/bin/env python3
"""Disposable application/provider adapter; real Ansible, Restic and supervisor."""
import json
import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, '/var/lib/nautobot/protection/runtime/scripts')
from recurring_protection import atomic

BASE = Path('/var/lib/nautobot/schedule-fixture')
RUNTIME = Path('/var/lib/nautobot/protection/runtime')
argv = ['/usr/bin/python3', str(RUNTIME/'scripts/schedule-driver.py')]
action = sys.argv[1]
with (BASE/'events').open('a') as out:
    out.write(action+'\n')
if action == 'prepare':
    root = Path(sys.argv[2])
    for name, value in [('source-password', 'disposable-local-only'), ('source-credentials.json', '{}')]:
        (root/name).write_text(value); (root/name).chmod(0o600)
    names = ('postgresql_custom_dump', 'media', 'configuration', 'image_dependency_manifest',
             'quadlet_config_hashes', 'versions_migrations')
    spec = dict(schema_version=1, operation_id='nautobot-recurring', authorized=True,
        repository_id=(BASE/'repository-id').read_text().strip(), restic='/usr/local/bin/restic',
        restic_version=subprocess.check_output(['/usr/local/bin/restic', 'version']).decode().strip(),
        repository_url=str(BASE/'repository'), hostname='disposable', source_consistency_reviewed=True,
        timeout_seconds=60, execution_uid=999,
        required_filesystem=subprocess.check_output(['findmnt', '-no', 'SOURCE', '-T', str(root)]).decode().strip(),
        captures={n: {'argv': argv+['capture', n], 'maximum_bytes': 1048576} for n in names},
        dump_validator=['/usr/bin/test', '-s', '/dev/stdin'])
    atomic(root/'application-backup.json', spec)
    (root/'repository').write_text(spec['repository_url']); (root/'repository').chmod(0o600)
    atomic(root/'inputs.json', dict(application_capture_authorized=True, application_upload_enabled=True,
        application_pause_commands=[argv+['pause']], application_resume_commands=[argv+['resume']],
        application_health_argv=argv+['health'], application_backup_credentials={
            'password': str(root/'source-password'), 'credentials.json': str(root/'source-credentials.json')},
        application_producer_argv=['/usr/bin/python3', str(RUNTIME/'scripts/application-backup.py')]))
elif action == 'pause':
    (BASE/'paused').touch()
elif action == 'resume':
    (BASE/'paused').unlink(missing_ok=True)
elif action == 'health':
    assert not (BASE/'paused').exists()
elif action == 'capture':
    assert (BASE/'paused').exists()
    # Dump parsing and mapped-media semantics retain their separate target evidence.
    sys.stdout.buffer.write(b'PGDMP-disposable-lifecycle-fixture\n')
else:
    raise ValueError(action)
