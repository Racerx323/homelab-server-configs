#!/usr/bin/env python3
"""Preserve an exact, never-started qualification tree before a separately approved trial."""
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def preserve(root, spec, units, show):
    require(re.fullmatch('[0-9a-f]{64}', spec['bundle_sha256']), 'bundle_identity')
    destination = root.with_name(root.name+'-retained-'+spec['bundle_sha256'][:12])
    require(not os.path.lexists(destination), 'retained_destination_exists')
    require(not any(p.is_symlink() for p in (root, *root.parents)), 'unsafe_root')
    paths = list(root.rglob('*'))
    require(all(not p.is_symlink() for p in paths), 'retained_symlink')
    require(all(p.is_file() or p.is_dir() for p in paths), 'special_file')
    files = {str(p.relative_to(root)): p for p in paths if p.is_file()}
    directories = {str(p.relative_to(root)): p for p in [root, *paths] if p.is_dir()}
    require(set(directories) == set(spec['directories']), 'retained_directories')
    for name, path in directories.items():
        info = path.stat()
        require({'uid': info.st_uid, 'gid': info.st_gid, 'mode': stat.S_IMODE(info.st_mode)}
                == spec['directories'][name], 'directory_drift')
    require(set(files) == set(spec['files']), 'retained_members')
    for name, path in files.items():
        info = path.stat()
        require({'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'uid': info.st_uid,
                 'gid': info.st_gid, 'mode': stat.S_IMODE(info.st_mode)} == spec['files'][name], 'retained_file_drift')
    require(not (root/'state/state.json').exists(), 'capture_started')
    require(set(spec['service_invocations']) == {'nautobot-'+role+'.service' for role in
            ('postgresql', 'redis', 'web', 'worker', 'scheduler')}, 'service_scope')
    require(set(spec['links']) == {'nautobot-protection-qualification'+suffix for suffix in
            ('.service', '-guard.timer', '-guard.service', '-recovery.service')}, 'unit_scope')
    for name, invocation in spec['service_invocations'].items():
        state = show(name)
        require(state['ActiveState'] == 'active' and state['SubState'] == 'running'
                and state['InvocationID'] == invocation, 'service_drift')
    for name, target in spec['links'].items():
        require(re.fullmatch(r'nautobot-protection-qualification(?:-guard|-recovery)?\.(?:service|timer)', name), 'unit_scope')
        require(target == str(root/'units'/name) and (units/name).is_symlink()
                and os.readlink(units/name) == target, 'runtime_link_drift')
        state = show(name)
        require(state['ActiveState'] == 'inactive' and state.get('InvocationID', '') == ''
                and state.get('ExecMainStartTimestamp', '') == '', 'unit_started')
    # Rename preserves all evidence. A partial unlink failure stops without deleting the tree.
    root.rename(destination)
    for name in spec['links']:
        (units/name).unlink()
    return {'preserved_directory': str(destination), 'runtime_links_removed': sorted(spec['links'])}


def main():
    require(os.getuid() == 999, 'service_identity')
    spec = json.loads(sys.argv[1])
    root = Path('/var/lib/nautobot/protection/qualification')
    require(Path('/proc/sys/kernel/random/boot_id').read_text().strip() == spec['boot_id'], 'boot_changed')
    require(not list((root.parent/'staging').iterdir()), 'staging_not_empty')
    def show(name):
        raw = subprocess.check_output(['/usr/bin/systemctl', '--user', 'show', name,
            '--property=ActiveState,SubState,InvocationID,ExecMainStartTimestamp'], text=True, timeout=30)
        return dict(line.split('=', 1) for line in raw.splitlines())
    print(json.dumps(preserve(root, spec, Path('/run/user/999/systemd/user'), show)))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        raise SystemExit('retained_state_refused; preserve evidence and inspect before retry')
