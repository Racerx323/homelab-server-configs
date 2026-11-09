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


def verify_schedule(spec):
    """Read-only guard for an attended trial beside the accepted nightly schedule."""
    root = Path('/var/lib/nautobot/protection/runtime')
    for name, digest in spec['runtime_sha256'].items():
        path = root/name
        require(not Path(name).is_absolute() and '..' not in Path(name).parts, 'schedule_path')
        require(not any(p.is_symlink() for p in (path, *path.parents)), 'schedule_symlink')
        info = path.stat()
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
                and stat.S_IMODE(info.st_mode) == 0o600
                and hashlib.sha256(path.read_bytes()).hexdigest() == digest, 'schedule_drift')
        if name.startswith('units/'):
            link = Path('/var/lib/nautobot/.config/systemd/user')/path.name
            require(link.is_symlink() and os.readlink(link) == str(path), 'schedule_link_drift')
    state = root.parent/'state/state.json'
    info = state.stat()
    require(not any(p.is_symlink() for p in (state, *state.parents))
            and stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
            and stat.S_IMODE(info.st_mode) == 0o600 and json.loads(state.read_text())
            == spec['state'], 'schedule_state_drift')
    require(json.loads(state.read_text())['phase'] == 'complete', 'schedule_incomplete')
    for suffix in ('.service', '-guard.timer', '-guard.service', '-recovery.service',
                   '.timer', '-freshness.timer', '-notification.timer'):
        raw = subprocess.check_output(['/usr/bin/systemctl', '--user', 'show',
            'nautobot-protection'+suffix, '--property=ActiveState,UnitFileState,DropInPaths'], text=True, timeout=30)
        row = dict(line.split('=', 1) for line in raw.splitlines())
        require(not row.get('DropInPaths'), 'schedule_override')
        expected = 'active' if suffix in ('.timer', '-freshness.timer', '-notification.timer') else 'inactive'
        require(row['ActiveState'] == expected, 'schedule_activity')
        if expected == 'active': require(row['UnitFileState'] == 'enabled', 'schedule_disabled')


def preserve(root, spec, units, show):
    require(re.fullmatch('[0-9a-f]{64}', spec['bundle_sha256']), 'bundle_identity')
    destination = root.with_name(root.name+'-retained-'+spec['bundle_sha256'][:12])
    require(not os.path.lexists(destination), 'retained_destination_exists')
    verify_tree(root, spec)
    if spec.get('kind') == 'completed_capture':
        terminal = spec['terminal']
        state = json.loads((root/'state/state.json').read_text())
        require(state == terminal['state'] and state['phase'] == 'complete'
                and state['exit_status'] == 0, 'completed_state')
        payload = Path(terminal['payload']['path'])
        require(payload.parent == root.parent/'staging' and state['root'] == str(payload)
                and re.fullmatch(r'nautobot-recurring\.[a-z0-9_]+', payload.name), 'payload_scope')
        verify_tree(payload, terminal['payload'])
        require(not spec['links'] and not terminal['units'], 'completed_links')
        for suffix in ('.service', '-guard.timer', '-guard.service', '-recovery.service'):
            name = 'nautobot-protection-qualification'+suffix
            row = show(name)
            require(not os.path.lexists(units/name) and row['LoadState'] == 'not-found'
                    and row['ActiveState'] == 'inactive', 'completed_unit_present')
        require(set(spec['service_invocations']) == {'nautobot-'+role+'.service' for role in
                ('postgresql', 'redis', 'web', 'worker', 'scheduler')}, 'service_scope')
        for name, invocation in spec['service_invocations'].items():
            row = show(name)
            require(row['ActiveState'] == 'active' and row['SubState'] == 'running'
                    and row['InvocationID'] == invocation, 'service_drift')
        root.rename(destination)
        return {'preserved_directory': str(destination), 'runtime_links_removed': []}
    if spec.get('kind') == 'unstarted_recovery':
        require(root.name == 'recovery-qualification', 'recovery_root')
        require((root/'killed').is_dir() and not list((root/'killed').iterdir())
                and not any(os.path.lexists(root/n) for n in ('deadline', 'timer', 'state', 'units')), 'recovery_started')
        names = ['nautobot-protection-'+case+suffix for case in ('killed', 'deadline')
                 for suffix in ('.service', '-guard.timer', '-guard.service', '-recovery.service')]
        names += ['nautobot-protection-timerqual.service', 'nautobot-protection-timerqual.timer']
        for name in names:
            row = show(name)
            require(not os.path.lexists(units/name) and row['LoadState'] == 'not-found'
                    and row['ActiveState'] == 'inactive' and row.get('MainPID', '0') == '0'
                    and row.get('ControlPID', '0') == '0' and not row.get('ControlGroup'), 'recovery_unit_present')
        require(set(spec['service_invocations']) == {'nautobot-'+role+'.service' for role in
                ('postgresql', 'redis', 'web', 'worker', 'scheduler')}, 'service_scope')
        for name, invocation in spec['service_invocations'].items():
            row = show(name)
            require(row['ActiveState'] == 'active' and row['SubState'] == 'running'
                    and row['InvocationID'] == invocation, 'service_drift')
        root.rename(destination)
        return {'preserved_directory': str(destination), 'runtime_links_removed': []}
    terminal = spec.get('terminal')
    if terminal:
        state = json.loads((root/'state/state.json').read_text())
        require(state == terminal['state'] and state['phase'] in ('manual_intervention', 'recovered_failure')
                and state['credential_cleanup'] is True and state['resume_statuses'] == [0, 0, 0], 'terminal_state')
        require(state['phase'] != 'recovered_failure' or state.get('health_status') == 0, 'recovered_health')
        payload = Path(terminal['payload']['path'])
        staging = root.parent/'staging'
        payloads = [terminal['payload'], *terminal.get('retained_payloads', [])]
        paths = [Path(item['path']) for item in payloads]
        require(len(set(paths)) == len(paths) and all(p.parent == staging and
                re.fullmatch(r'nautobot-recurring\.[a-z0-9_]+', p.name) for p in paths), 'payload_scope')
        require(state['root'] == str(payload) and set(staging.iterdir()) == set(paths), 'staging_drift')
        for path, item in zip(paths, payloads):
            require(not any(os.path.lexists(path/n) for n in ('password', 'credentials.json', 'source-password', 'source-credentials.json')), 'credential_residue')
            verify_tree(path, item)
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
    recovery = spec.get('kind') == 'unstarted_recovery'
    root = Path('/var/lib/nautobot/protection')/('recovery-qualification' if recovery else 'qualification')
    require(Path('/proc/sys/kernel/random/boot_id').read_text().strip() == spec['boot_id'], 'boot_changed')
    def show(name):
        properties = 'ActiveState,SubState,InvocationID,ExecMainStartTimestamp,MainPID,ControlPID,ControlGroup,Result'
        if recovery or spec.get('kind') == 'completed_capture': properties += ',LoadState'
        raw = subprocess.check_output(['/usr/bin/systemctl', '--user', 'show', name,
            '--property='+properties], text=True, timeout=30)
        return dict(line.split('=', 1) for line in raw.splitlines())
    # Verify before importing the retained runtime, and retain existing lock bytes.
    verify_tree(root, spec)
    sys.path.insert(0, str(root/'scripts'))
    import recurring_node as node
    from recurring_protection import in_window
    require(in_window(json.loads(sys.argv[2]), datetime.now().astimezone()), 'outside_approved_window')
    if len(sys.argv) > 3 and json.loads(sys.argv[3]):
        verify_schedule(json.loads(sys.argv[3]))
    node.health()
    require(not node.system(['list-jobs', '--no-legend', '--no-pager']).strip(), 'pending_jobs')
    with ExitStack() as locks:
        if spec.get('terminal'):
            for name in ('run.lock', 'recovery.lock', 'state.lock'):
                if spec.get('kind') == 'completed_capture' and name == 'recovery.lock' and not (root/'state'/name).exists():
                    continue  # Successful captures need not have invoked recovery.
                stream = locks.enter_context((root/'state'/name).open('rb'))
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        print(json.dumps(preserve(root, spec, Path('/run/user/999/systemd/user'), show)))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        raise SystemExit('retained_state_refused; preserve evidence and inspect before retry')
