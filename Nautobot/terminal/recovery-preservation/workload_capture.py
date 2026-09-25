#!/usr/bin/env python3
"""Pilot-only backup captures: quiet application, completed import, empty media.

Called by the bounded Restic producer. Output is private backup content, never a
public receipt. This helper neither resolves secrets nor starts/stops services.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tarfile

USER = ['/usr/sbin/runuser', '--user', 'nautobot', '--', '/usr/bin/env',
        'XDG_RUNTIME_DIR=/run/user/999', 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus']
MEDIA = Path('/var/lib/nautobot/.local/share/containers/storage/volumes/nautobot-nautobot_media/_data')
CONFIG = Path('/var/lib/nautobot/runtime/nautobot_config.py')
QUADLETS = Path('/var/lib/nautobot/.config/containers/systemd')
SECTIONS = ('postgresql_custom_dump', 'media', 'configuration', 'image_dependency_manifest',
            'quadlet_config_hashes', 'versions_migrations', 'validate_dump')


def require(value, code):
    if not value:
        raise ValueError(code)


def empty_media(path=MEDIA):
    require(not path.is_symlink() and path.is_dir(), 'media_root')
    require(not any(p.is_symlink() for p in path.parents), 'media_ancestor')
    entries = list(path.rglob('*'))
    require(len(entries) <= 100, 'media_entry_limit')
    require(all(stat.S_ISDIR(p.lstat().st_mode) for p in entries), 'media_not_empty')
    return sorted(str(p.relative_to(path)) for p in entries)


def reviewed_files(expected):
    require(str(CONFIG) in expected, 'configuration_missing')
    result = {}
    for name, digest in expected.items():
        path = Path(name)
        require(path == CONFIG or (path.parent == QUADLETS and path.name.startswith('nautobot-')
                and path.suffix in ('.container', '.volume', '.network')), 'source_not_allowed')
        require(not path.is_symlink() and not any(p.is_symlink() for p in path.parents), 'source_symlink')
        info = path.stat()
        require(stat.S_ISREG(info.st_mode) and info.st_size < 1048576, 'source_metadata')
        data = path.read_bytes()
        require(hashlib.sha256(data).hexdigest() == digest, 'source_changed')
        result[name] = data
    return result


def archive(files, output):
    with tarfile.open(fileobj=output, mode='w|') as stream:
        for name, data in sorted(files.items()):
            info = tarfile.TarInfo(name.lstrip('/')); info.mode = 0o600
            info.size = len(data); info.mtime = 0
            stream.addfile(info, io.BytesIO(data))


def command(argv):
    # Owner enforces whole-command time/output limits; container exec itself uses
    # timeout so loss of its host client cannot leave a long-running dump behind.
    return USER + ['/usr/bin/podman', 'exec', '-i', '--user', 'postgres',
                   'nautobot-postgresql', 'timeout', '600', *argv]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('section', choices=SECTIONS)
    args = parser.parse_args()
    spec = json.loads((args.root/'backup-sources.json').read_text())
    require(spec['consistency'] == 'quiet_pilot_empty_media' and spec['quiet_window_confirmed'] is True,
            'quiet_window_unconfirmed')
    before = empty_media()
    files = reviewed_files(spec['files'])
    output = sys.stdout.buffer
    if args.section == 'postgresql_custom_dump':
        subprocess.run(command(['pg_dump', '--no-password', '-U', 'nautobot', '-d', 'nautobot',
                                '--format=custom']), check=True, timeout=620)
    elif args.section == 'validate_dump':
        subprocess.run(command(['pg_restore', '--list']), check=True, timeout=620)
    elif args.section == 'media':
        with tarfile.open(fileobj=output, mode='w|') as stream:
            for name in ['.'] + before:
                info = tarfile.TarInfo(name); info.type = tarfile.DIRTYPE; info.mode = 0o750
                stream.addfile(info)
    elif args.section in ('configuration', 'quadlet_config_hashes'):
        if args.section == 'quadlet_config_hashes':
            files['SHA256.json'] = json.dumps(spec['files'], sort_keys=True).encode()
        archive(files, output)
    elif args.section == 'image_dependency_manifest':
        files = {}
        for name in ('desired-state.yaml', 'requirements.lock', 'qualified-image.json'):
            files[name] = (args.root/name).read_bytes()
        images = subprocess.run(USER + ['/usr/bin/podman', 'inspect', '--format',
            '{{.Name}} {{.Image}}', 'nautobot-postgresql', 'nautobot-redis', 'nautobot-web',
            'nautobot-worker', 'nautobot-scheduler'], stdout=subprocess.PIPE, check=True, timeout=30)
        require(len(images.stdout) < 65536, 'image_output_limit')
        files['observed-images.txt'] = images.stdout
        archive(files, output)
    else:
        query = "SELECT json_agg(row_to_json(m)) FROM (SELECT app,name,applied FROM django_migrations ORDER BY app,name) m"
        result = subprocess.run(command(['psql', '-X', '-q', '-A', '-t', '--no-password', '-U',
             'nautobot', '-d', 'nautobot', '-c', 'BEGIN READ ONLY; '+query+'; COMMIT;']),
             stdout=subprocess.PIPE, check=True, timeout=30)
        require(len(result.stdout) < 1048576, 'migration_output_limit')
        code = "import importlib.metadata as m,json;print(json.dumps({p:m.version(p) for p in ('nautobot','nautobot-dns-models')}))"
        versions = subprocess.run(USER + ['/usr/bin/podman', 'exec', 'nautobot-web', 'python3', '-B', '-c', code],
                                  stdout=subprocess.PIPE, check=True, timeout=30)
        output.write(json.dumps({'versions': json.loads(versions.stdout),
                                 'migrations': json.loads(result.stdout)}).encode())
    require(empty_media() == before, 'media_changed')
    reviewed_files(spec['files'])


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        reasons = {'media_root', 'media_ancestor', 'media_entry_limit', 'media_not_empty',
                   'configuration_missing', 'source_not_allowed', 'source_symlink',
                   'source_metadata', 'source_changed', 'quiet_window_unconfirmed',
                   'migration_output_limit', 'image_output_limit', 'media_changed'}
        failure = {'failure_class':type(error).__name__}
        if isinstance(error,ValueError) and str(error) in reasons: failure['reason']=str(error)
        if isinstance(error,subprocess.CalledProcessError): failure['exit_status']=error.returncode
        try:
            root=Path(sys.argv[sys.argv.index('--root')+1]);info=root.lstat()
            require(stat.S_ISDIR(info.st_mode) and info.st_uid==os.getuid()
                    and stat.S_IMODE(info.st_mode)==0o700 and not root.is_symlink()
                    and not any(p.is_symlink() for p in root.parents),'source_metadata')
            fd=os.open(root/'capture-error.json',os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
            with os.fdopen(fd,'w') as stream:json.dump(failure,stream)
        except Exception:pass
        print(json.dumps(failure),file=sys.stderr)
        raise SystemExit(1)
