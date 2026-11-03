#!/usr/bin/env python3
"""Preserve an exact stopped qualification tree before a separately approved trial."""
from contextlib import ExitStack
from datetime import datetime
import fcntl
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


def verify_tree(root, spec):
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


def preserve(root, spec, units, show):
    require(re.fullmatch('[0-9a-f]{64}', spec['bundle_sha256']), 'bundle_identity')
    destination = root.with_name(root.name+'-retained-'+spec['bundle_sha256'][:12])
    require(not os.path.lexists(destination), 'retained_destination_exists')
    verify_tree(root, spec)
    terminal = spec.get('terminal')
    if terminal:
        state = json.loads((root/'state/state.json').read_text())
        require(state == terminal['state'] and state['phase'] == 'manual_intervention'
                and state['credential_cleanup'] is True and state['resume_statuses'] == [0, 0, 0], 'terminal_state')
        payload = Path(terminal['payload']['path'])
        staging = root.parent/'staging'
        require(payload.parent == staging and re.fullmatch(r'nautobot-recurring\.[a-z0-9_]+', payload.name), 'payload_scope')
        require(state['root'] == str(payload) and set(staging.iterdir()) == {payload}, 'staging_drift')
        require(not any((payload/n).exists() for n in ('password', 'credentials.json', 'source-password', 'source-credentials.json')), 'credential_residue')
        verify_tree(payload, terminal['payload'])
        require(set(terminal['units']) == set(spec['links']), 'terminal_unit_scope')
    else:
        require(not (root/'state/state.json').exists(), 'capture_started')
        require(not list((root.parent/'staging').iterdir()), 'staging_not_empty')
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
        if terminal:
            require(state == terminal['units'][name], 'terminal_unit_drift')
            require(state['ActiveState'] in ('inactive', 'failed')
                    and state.get('MainPID', '0') == '0' and state.get('ControlPID', '0') == '0'
                    and not state.get('ControlGroup'), 'unit_running')
        else:
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
    def show(name):
        raw = subprocess.check_output(['/usr/bin/systemctl', '--user', 'show', name,
            '--property=ActiveState,SubState,InvocationID,ExecMainStartTimestamp,MainPID,ControlPID,ControlGroup,Result'], text=True, timeout=30)
        return dict(line.split('=', 1) for line in raw.splitlines())
    # Verify before importing the retained runtime, and retain existing lock bytes.
    verify_tree(root, spec)
    sys.path.insert(0, str(root/'scripts'))
    import recurring_node as node
    from recurring_protection import in_window
    require(in_window(json.loads(sys.argv[2]), datetime.now().astimezone()), 'outside_approved_window')
    node.health()
    require(not node.system(['list-jobs', '--no-legend', '--no-pager']).strip(), 'pending_jobs')
    with ExitStack() as locks:
        if spec.get('terminal'):
            for name in ('run.lock', 'recovery.lock', 'state.lock'):
                stream = locks.enter_context((root/'state'/name).open('rb'))
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        print(json.dumps(preserve(root, spec, Path('/run/user/999/systemd/user'), show)))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        raise SystemExit('retained_state_refused; preserve evidence and inspect before retry')
