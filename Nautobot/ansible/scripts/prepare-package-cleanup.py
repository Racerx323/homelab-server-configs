#!/usr/bin/env python3
"""Preserve exact recovery inputs for a reviewed package purge; never purge."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile


def run(argv, cwd=None):
    return subprocess.check_output(argv, cwd=cwd, text=True, timeout=180)


def reviewed_removals(output, names):
    rows = [line.split() for line in output.splitlines()]
    if any(row and row[0] in {'Inst', 'Conf'} for row in rows):
        raise ValueError('unreviewed_installation_or_configuration')
    actual = [row[1] for row in rows if row and row[0] in {'Purg', 'Remv'}]
    if len(actual) != len(set(actual)) or set(actual) != set(names):
        raise ValueError('unreviewed_removal_set')


def main():
    os.umask(0o077)
    plan = json.loads(Path(sys.argv[1]).read_text())['cleanup']
    root = Path(plan['directory'])
    assert os.geteuid() == 0 and os.uname().nodename == plan['host']
    assert Path('/proc/sys/kernel/random/boot_id').read_text().strip() == plan['boot_id']
    assert os.uname().release == plan['kernel']
    assert root.is_dir() and not root.is_symlink() and root.stat().st_uid == 0
    assert root.stat().st_mode & 0o777 == 0o700
    expected = plan['packages']
    observed = run(['dpkg-query', '-W', '-f=${binary:Package}\t${Version}\t${db:Status-Status}\n', *expected])
    actual = {n: {'version': v, 'state': s} for n, v, s in
              (line.split('\t') for line in observed.splitlines())}
    assert actual == expected
    simulation = run(['apt-get', '--simulate', 'purge', *expected])
    reviewed_removals(simulation, expected)
    (root/'simulation.txt').write_text(simulation)
    debs = root/'debs'
    debs.mkdir(mode=0o700)
    archive_paths = {'var/lib/dpkg/status', 'var/lib/apt/extended_states', 'boot'}
    for name, package in expected.items():
        found = False
        for candidate in Path('/var/cache/apt/archives').glob(name + '_*.deb'):
            identity = run(['dpkg-deb', '-f', str(candidate), 'Package', 'Version'])
            if f'Package: {name}\n' in identity and f"Version: {package['version']}\n" in identity:
                shutil.copy2(candidate, debs/candidate.name)
                found = True
                break
        if not found:
            run(['apt-get', 'download', name + '=' + package['version']], cwd=debs)
        conffiles = run(['dpkg-query', '-W', '-f=${Conffiles}', name])
        for line in conffiles.splitlines():
            fields = line.split()
            if fields and fields[0].startswith('/'):
                p = Path(fields[0])
                if p.exists() or p.is_symlink():
                    archive_paths.add(str(p).lstrip('/'))
        for p in Path('/var/lib/dpkg/info').glob(name + '.*'):
            archive_paths.add(str(p).lstrip('/'))
    recovered = {}
    for p in debs.glob('*.deb'):
        rows = dict(line.split(': ', 1) for line in
                    run(['dpkg-deb', '-f', str(p), 'Package', 'Version']).splitlines())
        name = rows['Package']
        assert name in expected and rows['Version'] == expected[name]['version']
        assert name not in recovered
        recovered[name] = {'file': p.name, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
    assert set(recovered) == set(expected)
    with tarfile.open(root/'recovery.tar.gz', 'w:gz', dereference=False) as archive:
        for name in sorted(archive_paths):
            p = Path('/')/name
            if p.exists() or p.is_symlink():
                archive.add(p, arcname=name)
    record = {'packages': recovered, 'archive_paths': sorted(archive_paths),
              'archive_sha256': hashlib.sha256((root/'recovery.tar.gz').read_bytes()).hexdigest(),
              'status_sha256': hashlib.sha256(Path('/var/lib/dpkg/status').read_bytes()).hexdigest()}
    record['protected_hashes'] = {
        str(p): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in Path('/boot/firmware').iterdir() if p.is_file()
    }
    (root/'recovery.json').write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps(record))


if __name__ == '__main__':
    main()
