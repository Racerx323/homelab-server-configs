#!/usr/bin/env python3
"""Non-secret receipts and bounded verification for recurring credential delivery."""
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import pwd
import resource
import stat
import subprocess
import sys
import tempfile

import prerequisite_node as node
from recurring_delivery import NAMES, resolve


def token_metadata(raw, provider):
    rows = raw.get('tokens') if isinstance(raw, dict) else raw
    node.require(isinstance(rows, list) and len(rows) == 1, 'token_set')
    value = rows[0]
    node.require(all(value.get(k) == provider[k] for k in ('project', 'environment', 'config', 'access'))
                 and value.get('name') == provider['token_name'], 'token_scope')
    created = datetime.fromisoformat(value['created_at'].replace('Z', '+00:00'))
    expires = datetime.fromisoformat(value['expires_at'].replace('Z', '+00:00'))
    now = datetime.now(timezone.utc)
    node.require(created.tzinfo is not None and expires.tzinfo is not None
                 and timedelta(days=89) <= expires - created <= timedelta(days=90, minutes=1)
                 and timedelta(0) <= now - created <= timedelta(minutes=10), 'token_expiry')
    slug = value['slug']
    node.require(isinstance(slug, str) and slug and len(slug) <= 200
                 and all(c.isalnum() or c in '-_' for c in slug), 'token_slug')
    return dict(project=provider['project'], config=provider['config'], read_only=True,
                token_slug=slug, created_at=created.isoformat(), expires_at=expires.isoformat(),
                rotation_due_at=(expires - timedelta(days=14)).isoformat(),
                rotation_owner=provider['rotation_owner'], doppler='/usr/bin/doppler',
                token_file='/var/lib/nautobot/protection/credentials/doppler-service-token')


def snapshot(op, accepted):
    account = pwd.getpwnam('nautobot')
    node.require((account.pw_uid, account.pw_gid, account.pw_dir) == (999, 985, '/var/lib/nautobot'), 'account_drift')
    node.require(node.command(['/usr/bin/hostname', '--short']).strip() == op['target']['host'], 'host_drift')
    rows = node.packages()
    for package in accepted['recurring_prerequisites']['packages']:
        node.require(rows.get(package['name']) == [package['version'], package['architecture'], 'installed'], 'package_drift')
    node.directory(Path('/var/lib/nautobot/protection'))
    node.directory(Path('/var/lib/nautobot/protection/staging'))
    return dict(services=node.continuity(op), packages_sha256=node.package_digest(rows, []),
                boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
                timers=node.command(['/usr/bin/systemctl', 'list-unit-files', '--type=timer', '--no-legend', '--no-pager']))


def probe(directory):
    """Exercise the existing resolver; remove all temporary resolved values."""
    node.directory(directory)
    node.require(os.getuid() == 999, 'service_identity')
    metadata = directory / 'metadata.json'
    node.safe_path(metadata)
    info = metadata.stat()
    node.require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                 and (info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode)) == (999, 985, 0o600), 'metadata_mode')
    contract = json.loads(metadata.read_text())
    token_path = Path(contract['token_file'])
    node.safe_path(token_path)
    info = token_path.stat()
    node.require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                 and (info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode)) == (999, 985, 0o600), 'token_mode')
    with tempfile.TemporaryDirectory(prefix='verify.', dir=directory) as tmp:
        root = Path(tmp)
        # Check the complete exposed name set, then use the production resolver.
        token = Path(contract['token_file']).read_text().strip()
        env = {'HOME': str(root), 'PATH': '/usr/bin:/bin', 'LC_ALL': 'C.UTF-8', 'DOPPLER_TOKEN': token}
        with tempfile.TemporaryFile() as out:
            def limits():
                resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
                resource.setrlimit(resource.RLIMIT_FSIZE, (65536, 65536))
            result = subprocess.run(['/usr/bin/doppler', '--no-check-version', '--attempts', '1', '--timeout', '10s',
                                     '--project', contract['project'], '--config', contract['config'],
                                     'secrets', '--only-names', '--json'], env=env, cwd=root,
                                    stdout=out, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                                    timeout=20, preexec_fn=limits)
            node.require(result.returncode == 0 and out.tell() < 65536, 'scope_readback')
            out.seek(0)
            node.require(set(json.load(out)) == set(NAMES) | {'DOPPLER_PROJECT', 'DOPPLER_ENVIRONMENT', 'DOPPLER_CONFIG'}, 'exposed_names')
        resolve(contract, root)
    return {'named_resolution_verified': True, 'temporary_values_removed': True}


def cleanup(directory, uid=999, gid=985):
    """Remove only owned files through a no-follow directory descriptor."""
    node.safe_path(directory)
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        node.require(info.st_uid in (0, uid) and stat.S_IMODE(info.st_mode) == 0o700, 'cleanup_directory')
        names = os.listdir(fd)
        node.require(set(names) <= {'doppler-service-token', 'metadata.json'}, 'cleanup_residue')
        identities = {}
        for name in names:
            entry = os.stat(name, dir_fd=fd, follow_symlinks=False)
            node.require(stat.S_ISREG(entry.st_mode) and entry.st_nlink == 1
                         and (entry.st_uid, entry.st_gid, stat.S_IMODE(entry.st_mode)) == (uid, gid, 0o600), 'cleanup_file')
            identities[name] = (entry.st_dev, entry.st_ino)
        for name in names:
            entry = os.stat(name, dir_fd=fd, follow_symlinks=False)
            node.require((entry.st_dev, entry.st_ino) == identities[name], 'cleanup_drift')
            os.unlink(name, dir_fd=fd)
        current = directory.lstat()
        node.require((current.st_dev, current.st_ino) == (info.st_dev, info.st_ino), 'cleanup_directory_drift')
        directory.rmdir()
    finally:
        os.close(fd)
    return {'host_credentials_removed': True}


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    action, root = sys.argv[1], Path(sys.argv[2])
    op = json.loads((root / 'operation.json').read_text())
    if action == 'metadata':
        result = token_metadata(json.load(sys.stdin), op['provider'])
    elif action == 'snapshot':
        result = snapshot(op, json.loads((root / 'accepted.json').read_text()))
    elif action == 'cleanup':
        result = cleanup(Path(op['delivery']['directory']))
    elif action == 'probe':
        result = probe(Path(op['delivery']['directory']))
    else:
        raise ValueError('action')
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Never print provider output, token values or exception text.
        raise SystemExit('credential_check_failed')
