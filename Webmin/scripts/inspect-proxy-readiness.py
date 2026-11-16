#!/usr/bin/env python3
"""Read bounded, non-secret Webmin proxy prerequisites on one approved host."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import stat
import subprocess

SETTINGS = {
    '/etc/webmin/miniserv.conf': {
        'port', 'bind', 'sockets', 'ipv6', 'ssl', 'ssl_redirect', 'redirect_ssl',
        'redirect_host', 'redirect_port', 'redirect_prefix', 'musthost', 'musthost_redirect', 'allow', 'deny', 'allowusers', 'sudo',
        'localauth', 'session', 'listen', 'atboot', 'keyfile', 'certfile',
    },
    '/etc/webmin/config': {'referer', 'referers', 'referers_none', 'webprefix', 'webprefixnoredir'},
    '/etc/webmin/system-status/config': {'collect_pkgs'},
}


def project(raw, allowed):
    result = {}
    for line in raw.decode('utf-8').splitlines():
        key, separator, value = line.partition('=')
        if not separator or key not in allowed:
            continue
        if key in result:
            raise ValueError('duplicate_selected_setting')
        if len(value) > 1024 or any(ord(c) < 32 or ord(c) > 126 for c in value):
            raise ValueError('unsafe_selected_setting')
        result[key] = value
    return result


def inspect_file(name, allowed):
    path = Path(name)
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError('symlink_config')
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_size > 262144:
        raise ValueError('unsafe_config_metadata')
    raw = path.read_bytes()
    after = path.stat()
    stable = ('st_dev', 'st_ino', 'st_mode', 'st_uid', 'st_gid', 'st_size', 'st_mtime_ns', 'st_ctime_ns')
    if len(raw) > 262144 or any(getattr(after, key) != getattr(info, key) for key in stable):
        raise ValueError('config_changed_during_read')
    return {'sha256': hashlib.sha256(raw).hexdigest(), 'uid': info.st_uid,
            'gid': info.st_gid, 'mode': oct(stat.S_IMODE(info.st_mode)),
            'selected': project(raw, allowed)}


def command(argv):
    try:
        row = subprocess.run(argv, capture_output=True, timeout=8, check=False)
    except subprocess.TimeoutExpired:
        return {'status': 'timeout'}
    except OSError:
        return {'status': 'launch_failed'}
    if len(row.stdout) > 65536 or len(row.stderr) > 65536:
        return {'status': 'output_limit', 'exit': row.returncode}
    # stderr is never copied; these fixed commands do not request secret data.
    return {'status': 'complete', 'exit': row.returncode,
            'stdout': row.stdout.decode('utf-8', errors='replace'),
            'stderr_bytes': len(row.stderr)}


class HostnameMismatch(ValueError):
    """Retain only bounded hostname characters, never arbitrary system text."""
    def __init__(self, expected, observed):
        super().__init__('hostname_mismatch')
        self.details = {
            'source': 'socket.gethostname', 'expected': expected,
            'observed': observed if re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]{0,252}', observed) else None,
            'observed_status': 'reported' if re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]{0,252}', observed) else 'invalid_or_overlong',
        }


def unit_identities(service):
    if service.get('status') != 'complete' or service.get('exit') != 0:
        raise ValueError('unit_properties_unavailable')
    properties = dict(line.split('=', 1) for line in service['stdout'].splitlines() if '=' in line)
    paths = [properties.get('FragmentPath', '')] + properties.get('DropInPaths', '').split()
    if not paths[0] or len(paths) > 17 or len(set(paths)) != len(paths):
        raise ValueError('invalid_unit_paths')
    for path in paths:
        if not re.fullmatch(r'/(?:usr/lib|lib|etc|run)/systemd/system/webmin\.service(?:\.d/[A-Za-z0-9_.-]+\.conf)?', path):
            raise ValueError('invalid_unit_paths')
    # Hash installed bytes without printing command lines, environment or unit bodies.
    return {path: inspect_file(path, set()) for path in paths}


def collect(expected_hostname, interface, include_unit_identity=False):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,14}', interface):
        raise ValueError('invalid_interface')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]{0,252}', expected_hostname):
        raise ValueError('invalid_expected_hostname')
    observed_hostname = socket.gethostname()
    if observed_hostname != expected_hostname:
        raise HostnameMismatch(expected_hostname, observed_hostname)
    if os.geteuid() != 0:
        raise ValueError('root_read_access_required')
    boot_path = Path('/proc/sys/kernel/random/boot_id')
    boot = boot_path.read_text().strip()
    if not re.fullmatch(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', boot):
        raise ValueError('invalid_boot_identity')
    selected_files = dict(SETTINGS)
    terminal_acl = Path('/etc/webmin/xterm/ama.acl')
    if include_unit_identity and terminal_acl.exists():
        selected_files[str(terminal_acl)] = {'user', 'sudoenforce'}
    files = {name: inspect_file(name, keys) for name, keys in selected_files.items()}
    commands = {
        'webmin_package': ['/usr/bin/dpkg-query', '-W', '-f=${Version}', 'webmin'],
        'webmin_service': ['/usr/bin/systemctl', 'show', 'webmin.service',
                           '--property=ActiveState,SubState,MainPID,NRestarts,MemoryHigh,MemoryMax,MemorySwapMax,FragmentPath,DropInPaths,Type,TasksMax,CPUQuotaPerSecUSec,KillMode,OOMPolicy,TimeoutStartUSec,TimeoutStopUSec,Restart,RestartUSec,StartLimitIntervalUSec,StartLimitBurst,After,BindsTo,Requires,ConditionResult'],
        'listeners': ['/usr/bin/ss', '-H', '-lnt', '( sport = :10000 )'],
        'addresses': ['/usr/sbin/ip', '-j', 'address', 'show', 'dev', interface],
        'ipv4_routes': ['/usr/sbin/ip', '-j', '-4', 'route', 'show'],
        'ipv6_routes': ['/usr/sbin/ip', '-j', '-6', 'route', 'show'],
        'firewall': ['/usr/sbin/nft', '-j', 'list', 'ruleset'],
    }
    if include_unit_identity:
        commands['architecture'] = ['/usr/bin/uname', '-m']
        commands['native_modules'] = ['/usr/bin/perl', '-I/usr/share/webmin',
            '-I/usr/share/webmin/vendor_perl', '-MIO::Pty', '-MNet::WebSocket::Server',
            '-e', 'print "IO::Pty and Net::WebSocket::Server load\\n";']
    observations = {name: command(argv) for name, argv in commands.items()}
    identities = unit_identities(observations['webmin_service']) if include_unit_identity else None
    if boot_path.read_text().strip() != boot:
        raise ValueError('boot_changed_during_inspection')
    after = {name: inspect_file(name, keys) for name, keys in selected_files.items()}
    if after != files:
        raise ValueError('config_changed_during_inspection')
    if include_unit_identity:
        later = command(commands['webmin_service'])
        if unit_identities(later) != identities:
            raise ValueError('unit_changed_during_inspection')
        if later != observations['webmin_service']:
            raise ValueError('service_changed_during_inspection')
        if boot_path.read_text().strip() != boot:
            raise ValueError('boot_changed_during_inspection')
    complete = all(r.get('status') == 'complete' and r.get('exit') == 0
                   for r in observations.values())
    return {'schema': 1, 'hostname': expected_hostname, 'boot_id': boot, 'interface': interface,
            'complete': complete, 'files': files, 'observations': observations,
            'mutation': False, 'unit_identities': identities,
            'terminal_acl_present': str(terminal_acl) in selected_files if include_unit_identity else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-hostname', required=True)
    parser.add_argument('--interface', required=True)
    parser.add_argument('--include-unit-identity', action='store_true')
    args = parser.parse_args()
    try:
        result = collect(args.expected_hostname, args.interface, args.include_unit_identity)
    except (ValueError, OSError, UnicodeError) as error:
        known = {'invalid_interface', 'invalid_expected_hostname', 'hostname_mismatch',
                 'root_read_access_required', 'invalid_boot_identity',
                 'duplicate_selected_setting', 'unsafe_selected_setting',
                 'symlink_config', 'unsafe_config_metadata',
                 'config_changed_during_read', 'config_changed_during_inspection',
                 'boot_changed_during_inspection', 'invalid_unit_paths',
                 'unit_properties_unavailable', 'unit_changed_during_inspection',
                 'service_changed_during_inspection'}
        code = str(error) if isinstance(error, ValueError) and str(error) in known else 'read_failed'
        failure = {'complete': False, 'error': code, 'mutation': False}
        if isinstance(error, HostnameMismatch):
            failure['hostname_check'] = error.details
        print(json.dumps(failure))
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
