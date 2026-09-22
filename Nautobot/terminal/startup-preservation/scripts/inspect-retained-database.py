#!/usr/bin/env python3
"""Bounded local data checks; Ansible owns service and guard lifecycle."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import pwd
import resource
import tempfile
import shutil
import stat
import subprocess
import sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('runtime', Path(__file__).with_name('runtime-initialization-node.py'))
runtime = importlib.util.module_from_spec(spec); spec.loader.exec_module(runtime)
USER = runtime.USER


def require(value, code):
    if not value:
        raise ValueError(code)


def command(args, timeout=30):
    return runtime.call(args, timeout)


def state(role):
    raw = command(USER + ['/usr/bin/systemctl', '--user', 'show', 'nautobot-'+role+'.service',
                          '--property=ActiveState,SubState,Result,InvocationID,ExecMainStatus'])
    return dict(line.split('=', 1) for line in raw.splitlines() if '=' in line)


def stopped():
    states = {role: state(role) for role in ('postgresql', 'redis', 'migration')}
    require(all(s['ActiveState'] in ('inactive', 'failed') for s in states.values()), 'service_not_stopped')
    require(runtime.podman('ps', '--all', '--format', 'json') == [], 'container_residue')
    return states


def file_hash(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def tree(root):
    """Independent content, ownership, permissions, timestamps and link topology."""
    require(root.is_dir() and not root.is_symlink(), 'tree_root')
    device = root.stat().st_dev
    rows = {}; links = {}; count = 0; total = 0
    def walk(p):
        nonlocal count, total
        s = p.lstat(); count += 1
        require(count <= 100000 and s.st_dev == device, 'tree_boundary')
        name = str(p.relative_to(root))
        row = {'uid': s.st_uid, 'gid': s.st_gid, 'mode': stat.S_IMODE(s.st_mode), 'mtime_ns': s.st_mtime_ns}
        row['xattrs'] = {k: hashlib.sha256(os.getxattr(p, k, follow_symlinks=False)).hexdigest()
                        for k in os.listxattr(p, follow_symlinks=False)}
        if stat.S_ISLNK(s.st_mode):
            target = os.readlink(p)
            require(not os.path.isabs(target) and p.resolve().is_relative_to(root.resolve()), 'external_link')
            row.update(kind='link', target=target)
        elif stat.S_ISDIR(s.st_mode):
            row['kind'] = 'directory'
            for child in sorted(p.iterdir()): walk(child)
        elif stat.S_ISREG(s.st_mode):
            total += s.st_size
            require(total <= 2*1024**3, 'tree_size')
            row.update(kind='file', size=s.st_size, sha256=file_hash(p))
            links.setdefault((s.st_dev, s.st_ino), []).append(name)
        else:
            raise ValueError('special_file')
        rows[name] = row
    walk(root)
    for names in links.values():
        for name in names: rows[name]['hardlinks'] = sorted(names)
    return rows


def no_submounts(path):
    # Decode mountinfo octal escapes before testing containment, including bind mounts.
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        value = re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), line.split()[4])
        mount = Path(value)
        require(not mount.is_relative_to(path), 'nested_mount')


def identities(op):
    account = pwd.getpwnam('nautobot')
    require((account.pw_uid, account.pw_gid, account.pw_dir) == (999, 985, '/var/lib/nautobot'), 'account_drift')
    home = Path('/var/lib/nautobot/runtime')
    runtime.protected(home/'nautobot_config.py', 0o644)
    runtime.environments(home)
    require(file_hash(home/'nautobot_config.py') == op['runtime']['configuration_sha256'], 'configuration_drift')
    require(Path('/proc/sys/kernel/random/boot_id').read_text().strip() == op['runtime']['expected_boot_id'], 'boot_drift')
    units = Path('/var/lib/nautobot/.config/containers/systemd')
    require({p.name for p in units.iterdir()} == set(op['runtime']['artifact_sha256']), 'unit_set')
    for name, digest in op['runtime']['artifact_sha256'].items():
        p = units/name; s = p.lstat()
        require(stat.S_ISREG(s.st_mode) and s.st_uid == 999 and stat.S_IMODE(s.st_mode) == 0o600, 'unit_metadata')
        require(file_hash(p) == digest, 'unit_drift')
    for image in op['runtime']['images'].values():
        data = runtime.podman('image', 'inspect', image['reference'])[0]
        require(data['Id'].removeprefix('sha256:') == image['id'].removeprefix('sha256:')
                and data['Architecture'] == 'arm64' and data['Os'] == 'linux', 'image_drift')


def copy_tree(source, dest):
    a = tree(source)
    require(not dest.exists() and not dest.is_symlink(), 'copy_exists')
    subprocess.run(['/usr/bin/cp', '--archive', '--reflink=never', '--one-file-system', '--', str(source), str(dest)],
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   timeout=300, check=True)
    require(tree(source) == a and tree(dest) == a, 'copy_mismatch')
    return {'verified': True, 'entries': len(a),
            'tree_sha256': hashlib.sha256(json.dumps(a, sort_keys=True).encode()).hexdigest()}


def preserve(root, op):
    identities(op); before = stopped()
    for suffix in ('.timer', '.service'):
        require(command(['/usr/bin/systemctl', 'show', op['guard_unit']+suffix, '--property=LoadState', '--value']).strip() == 'not-found', 'existing_guard')
    parent = Path('/var/lib/nautobot/recovery')
    # The parent is root-owned, never traversable by the application account.
    runtime.storage.ancestry(parent)
    if not parent.exists(): parent.mkdir(mode=0o700)
    s = parent.lstat()
    require(stat.S_ISDIR(s.st_mode) and s.st_uid == 0 and stat.S_IMODE(s.st_mode) == 0o700, 'preservation_parent')
    target = parent/op['operation']['id']
    target.mkdir(mode=0o700)  # Existing/partial copy requires review, never reuse.
    results = {}
    for name in ('nautobot-postgresql_data', 'nautobot-redis_data'):
        v = runtime.podman('volume', 'inspect', name)[0]
        source = Path(v['Mountpoint'])
        expected = Path('/var/lib/nautobot/.local/share/containers/storage/volumes')/name/'_data'
        require(source == expected and source.resolve() == expected, 'volume_path')
        no_submounts(source)
        if name.endswith('postgresql_data'):
            require((source/'PG_VERSION').read_text().strip() == '17' and not (source/'postmaster.pid').exists(), 'postgres_not_cold')
        require(shutil.disk_usage(parent).free >= 4*1024**3, 'copy_headroom')
        results[name] = copy_tree(source, target/name)
    os.sync(); stopped(); identities(op)
    record = {'passed': True, 'cold_copy': str(target), 'volumes': results,
              'previous_postgresql_invocation': before['postgresql'].get('InvocationID', '')}
    runtime.storage.record(root, 'preservation.json', record)
    return record


def ready(root, op):
    old = json.loads((root/'preservation.json').read_text())['previous_postgresql_invocation']
    s = state('postgresql')
    require(s['ActiveState'] == 'active' and re.fullmatch('[0-9a-f]{32}', s.get('InvocationID', ''))
            and s['InvocationID'] != old, 'postgres_not_ready')
    v = runtime.podman('inspect', 'nautobot-postgresql')[0]
    runtime.container_evidence(v, 'postgresql', op['runtime']['images']['postgresql']['id'])
    require(all(state(role)['ActiveState'] in ('inactive', 'failed') for role in ('redis', 'migration')), 'excluded_service_active')
    return {'passed': True, 'invocation_id': s['InvocationID']}


def parse_ledger(raw):
    data = json.loads(raw)
    require(set(data) == {'database', 'version', 'read_only', 'ledger_exists', 'migrations'}, 'ledger_shape')
    require(data['database'] == 'nautobot' and re.fullmatch(r'17[0-9]{4}', data['version'])
            and data['read_only'] == 'on' and type(data['ledger_exists']) is bool, 'database_identity')
    require(isinstance(data['migrations'], list) and len(data['migrations']) <= 10000, 'ledger_size')
    require(data['ledger_exists'] or not data['migrations'], 'absent_ledger_rows')
    seen = set()
    for row in data['migrations']:
        require(set(row) == {'app', 'name', 'applied'}, 'row_shape')
        require(all(isinstance(row[k], str) and re.fullmatch('[A-Za-z0-9_]{1,180}', row[k]) for k in ('app','name')), 'identifier')
        require(isinstance(row['applied'], str) and re.fullmatch(r'[0-9T:+. -]{10,40}', row['applied']), 'timestamp')
        key = (row['app'], row['name']); require(key not in seen, 'duplicate_migration'); seen.add(key)
    return data


def ledger(root, op):
    ready(root, op)
    # psql conditional expansion avoids querying a missing relation. No writes,
    # application rows, custom functions, shell interpolation or password argv.
    sql = r"""BEGIN READ ONLY;
SET LOCAL statement_timeout = '10s';
SELECT (to_regclass('public.django_migrations') IS NOT NULL) AS present \gset
\if :present
SELECT json_build_object('database',current_database(),'version',current_setting('server_version_num'),
 'read_only',current_setting('transaction_read_only'),'ledger_exists',true,
 'migrations',COALESCE((SELECT json_agg(x) FROM (SELECT app,name,applied FROM public.django_migrations ORDER BY applied,app,name LIMIT 10001) x),'[]'::json));
\else
SELECT json_build_object('database',current_database(),'version',current_setting('server_version_num'),
 'read_only',current_setting('transaction_read_only'),'ledger_exists',false,'migrations','[]'::json);
\endif
COMMIT;
"""
    # stdin carries only fixed SQL, never credentials. Container local socket uses
    # its existing authentication configuration; an authentication failure stops.
    raw = query_sql(sql)
    return {'passed': True, 'ledger': parse_ledger(raw)}


def query_sql(sql):
    def limit(): resource.setrlimit(resource.RLIMIT_FSIZE, (2*1024*1024, 2*1024*1024))
    with tempfile.TemporaryFile() as output:
        p = subprocess.run(USER+['/usr/bin/podman','exec','-i','--user','postgres','nautobot-postgresql',
                                'psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','nautobot','-d','nautobot'],
                           input=sql.encode(), stdout=output, stderr=subprocess.DEVNULL, timeout=30, preexec_fn=limit)
        require(p.returncode == 0 and output.tell() < 2*1024*1024, 'ledger_query')
        output.seek(0); return output.read()



def main():
    os.umask(0o077); os.chdir('/')
    mode, directory = sys.argv[1:]; root = Path(directory)
    require(root.parent == Path('/tmp') and re.fullmatch(r'nautobot-inspection\.[A-Za-z0-9_]+', root.name), 'root_boundary')
    op = json.loads((root/'operation.json').read_text())
    try:
        if mode == 'preserve': result = preserve(root, op)
        elif mode == 'ready': result = ready(root, op)
        elif mode == 'ledger': result = ledger(root, op)
        elif mode == 'stopped': result = {'passed': True, 'services': stopped()}
        else: result = runtime.storage.journal(mode, root, op)
        print(json.dumps(result)); return 0 if result.get('passed', True) else 69
    except Exception as exc:
        code = str(exc) if isinstance(exc, ValueError) and re.fullmatch('[a-z_]+', str(exc)) else 'boundary_or_command_failed'
        print(json.dumps({'passed': False, 'error_class': code})); return 69

if __name__ == '__main__': raise SystemExit(main())
