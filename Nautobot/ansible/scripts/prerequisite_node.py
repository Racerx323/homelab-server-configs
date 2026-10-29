#!/usr/bin/env python3
"""Bounded prerequisite guards. Ansible owns mutation and rescue ordering."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import selectors
import shutil
import socket
import stat
import subprocess
import time

USER = ['/usr/sbin/runuser', '--user', 'nautobot', '--', '/usr/bin/env',
        'HOME=/var/lib/nautobot', 'PATH=/usr/bin:/bin', 'XDG_RUNTIME_DIR=/run/user/999',
        'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus']
ROLES = ('postgresql', 'redis', 'web', 'worker', 'scheduler')
DIRECTORIES = ('/var/lib/nautobot/protection', '/var/lib/nautobot/protection/staging')
ENV = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'DEBIAN_FRONTEND': 'noninteractive',
       'NEEDRESTART_MODE': 'l'}


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class CommandFailure(ValueError):
    def __init__(self, details):
        self.details = details
        super().__init__('command_failed:' + details['executable'])


def command(argv, timeout=90, data=None):
    import tempfile
    # Bound only captured output, not the package manager's own temporary files.
    with tempfile.TemporaryFile() as source, selectors.DefaultSelector() as selector:
        source.write(data.encode() if data is not None else b'')
        source.seek(0)
        with subprocess.Popen(argv, stdin=source, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              env=ENV, cwd='/') as process:
            streams = {process.stdout: bytearray(), process.stderr: bytearray()}
            for stream in streams:
                selector.register(stream, selectors.EVENT_READ)
            deadline = time.monotonic() + timeout
            timed_out = output_limited = False
            try:
                while selector.get_map() and not output_limited:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise subprocess.TimeoutExpired(argv, timeout)
                    for key, _ in selector.select(remaining):
                        chunk = os.read(key.fileobj.fileno(), 65536)
                        if not chunk:
                            selector.unregister(key.fileobj)
                            continue
                        output = streams[key.fileobj]
                        output.extend(chunk[:4 * 1024**2 - len(output)])
                        output_limited |= len(output) >= 4 * 1024**2
                if output_limited:
                    process.kill()
                status = process.wait(timeout=max(0.01, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                status, timed_out = None, True
            out, err = streams.values()
            if status != 0 or timed_out or output_limited:
                def excerpt(output):
                    return re.sub(r'[\x00-\x08\x0b-\x1f\x7f]', '?', output[:16384].decode(errors='replace'))
                raise CommandFailure({'executable': Path(argv[0]).name, 'exit_status': status,
                                      'timed_out': timed_out, 'output_limited': output_limited,
                                      'stdout': excerpt(out), 'stderr': excerpt(err)})
            return out.decode()


def safe_path(path):
    require(path.is_absolute(), 'absolute_path')
    for p in (path, *path.parents):
        require(not p.is_symlink(), 'symlink_path')


def directory(path, uid=999, gid=985):
    safe_path(path)
    s = path.lstat()
    require(stat.S_ISDIR(s.st_mode) and s.st_uid == uid and s.st_gid == gid
            and stat.S_IMODE(s.st_mode) == 0o700, 'directory_metadata')


def packages():
    raw = command(['/usr/bin/dpkg-query', '-W', '-f=${Package}\t${Version}\t${Architecture}\t${db:Status-Status}\n'])
    rows = {}
    for line in raw.splitlines():
        fields = line.split('\t')
        require(len(fields) == 4 and fields[0] not in rows, 'duplicate_or_malformed_package')
        rows[fields[0]] = fields[1:]
    return rows


def package_digest(rows, excluded):
    return hashlib.sha256(json.dumps({k: v for k, v in rows.items() if k not in excluded},
                                    sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def stanzas(raw):
    for block in raw.split('\n\n'):
        row = dict(line.split(': ', 1) for line in block.splitlines()
                   if ': ' in line and not line.startswith(' '))
        if row:
            yield row


def verify_sources(root, op):
    """Signed Release -> exact index -> exact package bytes and control identity."""
    for origin, source in op['sources'].items():
        key, release, index = [root / source[k] for k in ('keyring', 'release', 'index')]
        for path in (key, release, index):
            require(sha(path) == source['sha256'][path.name], 'source_hash')
        status = command(['/usr/bin/gpgv', '--status-fd=1', '--keyring', str(key), str(release)])
        require(any(line.startswith('[GNUPG:] VALIDSIG ' + source['fingerprint'] + ' ')
                    for line in status.splitlines()), 'signer_identity')
        expected = f"{sha(index)} {index.stat().st_size} {source['index_path']}"
        require(expected in [' '.join(line.split()) for line in release.read_text().splitlines()],
                'signed_index_identity')
        rows = list(stanzas(index.read_text()))
        for package in [p for p in op['packages'] if p['source'] == origin]:
            matches = [r for r in rows if r.get('Package') == package['name']
                       and r.get('Version') == package['version']
                       and r.get('Architecture') == package['architecture']]
            require(len(matches) == 1 and matches[0]['SHA256'] == package['sha256'], 'signed_package_identity')
            path = root / (package['name'] + '.deb')
            require(sha(path) == package['sha256'], 'package_hash')
            fields = command(['/usr/bin/dpkg-deb', '--show', '--showformat=${Package}\t${Version}\t${Architecture}', str(path)])
            require(fields.split('\t') == [package[k] for k in ('name', 'version', 'architecture')], 'package_control')


def transaction(raw, expected, action='Inst'):
    """APT simulation must contain exactly the reviewed changes, with no upgrades."""
    changes = {}
    for line in raw.splitlines():
        if line.startswith(('Inst ', 'Remv ', 'Purg ')):
            if action == 'Inst':
                match = re.fullmatch(r'Inst (\S+) \((\S+) .+\)', line)
                require(match is not None, 'upgrade_or_removal')
                changes[match[1]] = match[2]
            else:
                match = re.fullmatch(r'(?:Remv|Purg) (\S+)(?: \[.*\])?(?: .*)?', line)
                require(match is not None and not line.startswith('Inst '), 'rollback_transaction')
                changes[match[1]] = expected.get(match[1])
    require(changes == expected, 'transaction_drift')


def apt_install(root, missing, simulate=False):
    # Disable repositories, but let APT acquire the verified local deb files.
    # --no-download also skips that local acquisition during real installation.
    return ['/usr/bin/apt-get', *(['--simulate'] if simulate else ['--yes']),
            '--no-remove', '--no-upgrade', '--no-install-recommends',
            '-o', 'Dir::Etc::sourcelist=', '-o', 'Dir::Etc::sourceparts=',
            '-o', 'Dir::Cache::archives=' + str(root / 'archives'),
            'install', *[str(root / (name + '.deb')) for name in sorted(missing)]]


def continuity(op):
    for path, digest in op['baseline']['artifact_sha256'].items():
        p = Path(path)
        safe_path(p)
        require(p.is_file() and sha(p) == digest, 'accepted_artifact_drift')
    for name, expected in op['baseline']['mapped_media'].items():
        path = Path(name)
        safe_path(path)
        s = path.lstat()
        require(stat.S_ISDIR(s.st_mode) and (s.st_uid, s.st_gid, format(stat.S_IMODE(s.st_mode), '04o'))
                == (expected['uid'], expected['gid'], expected['mode']), 'mapped_media_drift')
    states = {}
    for role in ROLES:
        value = dict(line.split('=', 1) for line in command(USER + [
            '/usr/bin/systemctl', '--user', 'show', 'nautobot-' + role + '.service',
            '--property=ActiveState,SubState,InvocationID']).splitlines())
        require(value['ActiveState'] == 'active' and value['SubState'] == 'running', 'service_health')
        states[role] = value
    code = "import http.client;c=http.client.HTTPConnection('127.0.0.1',8080,timeout=3);c.request('GET','/health/',headers={'Host':'j2-svpi4mf.local.theama.co'});print(c.getresponse().status);c.close()"
    require(command(USER + ['/usr/bin/podman', 'exec', 'nautobot-web', 'python3', '-B', '-c', code]).strip() == '200', 'http_health')
    return states


def save(root, name, value):
    path = root / name
    with path.open('x') as stream:
        os.chmod(path, 0o600)
        json.dump(value, stream, sort_keys=True)


def verify_stage(root, hashes):
    require(set(p.name for p in root.iterdir()) == set(hashes) | {'archives'}, 'stage_input_set')
    for name, digest in hashes.items():
        require(Path(name).name == name, 'stage_input_name')
        path = root / name
        safe_path(path)
        s = path.lstat()
        require(stat.S_ISREG(s.st_mode) and (s.st_uid, s.st_gid, stat.S_IMODE(s.st_mode)) == (0, 0, 0o600)
                and sha(path) == digest, 'stage_input_identity')
    directory(root / 'archives', 0, 0)


def preflight(root, op):
    account = pwd.getpwnam('nautobot')
    require((account.pw_uid, account.pw_gid, account.pw_dir) == (999, 985, '/var/lib/nautobot'), 'service_identity')
    require(command(['/usr/bin/dpkg', '--print-architecture']).strip() == 'arm64', 'architecture')
    require(command(['/usr/bin/dpkg', '--print-foreign-architectures']).splitlines()
            == op['baseline']['foreign_architectures'], 'foreign_architecture_drift')
    require(not command(['/usr/bin/dpkg', '--audit']).strip(), 'dpkg_audit')
    rows = packages()
    pinned = {p['name']: p for p in op['packages']}
    require(package_digest(rows, pinned) == op['baseline']['packages_sha256'], 'unrelated_package_drift')
    missing = {}
    for name, p in pinned.items():
        if name not in rows:
            missing[name] = p['version']
        else:
            require(rows[name] == [p['version'], p['architecture'], 'installed'], 'pinned_package_drift')
    require(not missing or len(missing) == len(pinned), 'partial_install_requires_review')
    absent = []
    directory(Path('/var/lib/nautobot'))
    for name in DIRECTORIES:
        path = Path(name)
        safe_path(path)
        if path.exists():
            directory(path)
        else:
            absent.append(name)
    require(command(['/usr/bin/findmnt', '-n', '-o', 'FSTYPE', '-T', '/var/lib/nautobot']).strip() == 'ext4', 'staging_filesystem')
    require(shutil.disk_usage('/var/lib/nautobot').free >= op['minimum_free_bytes'], 'staging_capacity')
    before = {'packages': rows, 'manual': command(['/usr/bin/apt-mark', 'showmanual']),
              'services': continuity(op), 'created_directories': absent, 'missing': missing}
    save(root, 'before.json', before)
    if missing:
        transaction(command(apt_install(root, missing, simulate=True)), missing)
    return {'install_argv': apt_install(root, missing) if missing else [], 'missing': sorted(missing)}


def accept(root, op):
    before = json.loads((root / 'before.json').read_text())
    rows = packages()
    expected = {**before['packages'], **{p['name']: [p['version'], p['architecture'], 'installed'] for p in op['packages']}}
    require(rows == expected and not command(['/usr/bin/dpkg', '--audit']).strip(), 'package_postcondition')
    require(set(command(['/usr/bin/apt-mark', 'showmanual']).splitlines())
            == set(before['manual'].splitlines()) | {p['name'] for p in op['packages']}, 'manual_package_flags')
    services = continuity(op)
    require(services == before['services'], 'service_restarted')
    for name in DIRECTORIES:
        directory(Path(name))
    wrapper = (root / 'ansible-temp.sh').read_text()
    version = command(USER + ['/usr/bin/env', 'LC_ALL=C.UTF-8', '/bin/bash', '-s', '--',
                              '/usr/bin/ansible-playbook', '--version'], data=wrapper)
    require(version.splitlines()[0].startswith('ansible-playbook [core 2.19.11]'), 'service_command_version')
    doppler = command(USER + ['/usr/bin/doppler', '--no-check-version', '--version']).strip()
    require(doppler == 'v3.76.6', 'service_command_version')
    require(command(['/usr/bin/findmnt', '-n', '-o', 'FSTYPE', '-T', DIRECTORIES[-1]]).strip() == 'ext4', 'staging_filesystem')
    require(shutil.disk_usage(DIRECTORIES[-1]).free >= op['minimum_free_bytes'], 'staging_capacity')
    save(root, 'postconditions.json', {
        'packages': rows, 'services': services, 'ansible_version': version.splitlines()[0], 'doppler_version': doppler,
        'directories': {name: {'uid': Path(name).stat().st_uid, 'gid': Path(name).stat().st_gid,
                               'mode': format(stat.S_IMODE(Path(name).stat().st_mode), '04o')} for name in DIRECTORIES},
        'accepted': False})


def rollback_plan(root, op):
    before = json.loads((root / 'before.json').read_text())
    rows = packages()
    introduced = {p['name']: p['version'] for p in op['packages'] if p['name'] not in before['packages'] and p['name'] in rows}
    for package in op['packages']:
        if package['name'] in introduced:
            require(rows[package['name']][:2] == [package['version'], package['architecture']], 'rollback_package_identity')
    require({k: v for k, v in rows.items() if k not in introduced} == before['packages'], 'rollback_unrelated_drift')
    argv = ['/usr/bin/apt-get', '--yes', '--no-download', '--no-auto-remove', 'purge', *sorted(introduced)]
    if introduced:
        transaction(command([argv[0], '--simulate', *argv[2:]]), introduced, 'Purg')
    return {'argv': argv if introduced else []}


def rollback_directories(root, op):
    before = json.loads((root / 'before.json').read_text())
    for name in reversed(before['created_directories']):
        path = Path(name)
        safe_path(path)
        if path.exists():
            directory(path)
            path.rmdir()  # Refuse nonempty trees; never recursively delete payloads.
    require(packages() == before['packages'], 'rollback_package_residue')
    require(command(['/usr/bin/apt-mark', 'showmanual']) == before['manual'], 'rollback_manual_flags')
    require(not command(['/usr/bin/dpkg', '--audit']).strip(), 'rollback_dpkg_audit')
    require(continuity(op) == before['services'], 'rollback_service_drift')
    save(root, 'rollback.json', {'restored': True, 'accepted': False})


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('preflight', 'accept', 'rollback-plan', 'rollback-directories'))
    parser.add_argument('root', type=Path)
    parser.add_argument('--hashes', type=json.loads)
    args = parser.parse_args()
    require(os.geteuid() == 0 and socket.gethostname() == 'j2-svpi4mf', 'target_identity')
    directory(args.root, 0, 0)
    try:
        if args.phase == 'preflight':
            require(isinstance(args.hashes, dict), 'stage_hashes_required')
            verify_stage(args.root, args.hashes)
        op = json.loads((args.root / 'operation.json').read_text())
        require(op['operation']['execution_enabled'] is True, 'execution_disabled')
        function = {'preflight': preflight, 'accept': accept, 'rollback-plan': rollback_plan,
                    'rollback-directories': rollback_directories}[args.phase]
        print(json.dumps(function(args.root, op) or {}))
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        # Only fixed, non-secret commands use command(); never record stdin or
        # environment values. Retain diagnostics even when preflight refuses.
        save(args.root, 'failure-' + args.phase + '.json', {
            'phase': args.phase, 'reason': str(error),
            'command': error.details if isinstance(error, CommandFailure) else None})
        raise


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
