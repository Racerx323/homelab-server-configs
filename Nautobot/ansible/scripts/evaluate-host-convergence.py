#!/usr/bin/env python3
"""Offline, fail-closed evaluation of the reviewed Ansible probe results.

Never contacts a host, executes a probe, repairs state, or writes acceptance.
"""
import argparse
import json
import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[3]
OPERATION = ROOT / 'Nautobot/manifests/operation.yaml'


def evaluate(document, results):
    """Return decisions; missing evidence and unresolved expectations block."""
    checks = {}
    outputs = {}
    probes = document['preflight']['probes']
    expected = document['expected']
    if not isinstance(results, list) or len(results) != len(probes):
        return {'result': 'blocked', 'checks': {'complete_probe_set': False}}
    for probe, result in zip(probes, results):
        name = probe['id']
        valid = (isinstance(result, dict)
                 and result.get('item') == probe
                 and result.get('cmd') == probe['argv']
                 and type(result.get('rc')) is int
                 and result.get('unreachable', False) is False
                 and result.get('skipped', False) is False
                 and isinstance(result.get('stdout'), str)
                 and isinstance(result.get('stderr'), str))
        if valid:
            valid = (len(result['stdout'].encode()) <= document['preflight']['stream_limit_bytes']
                     and not result['stderr']
                     and not re.search(r'[\x00-\x08\x0b-\x1f\x7f]', result['stdout']))
        absence = name in {'keepalived_process', 'keepalived_config', 'keepalived_config_symlink'}
        journal = name == 'storage_events'
        if valid:
            valid = (result['rc'] == (1 if absence else 0)
                     or (journal and result['rc'] == 1 and not result['stdout']))
        checks[name + '_command'] = valid
        if valid:
            outputs[name] = result['stdout'].strip()
    # Every command observation must pass before any parsing. Never coerce errors to zero.
    if not all(checks.values()):
        return {'result': 'blocked', 'checks': checks}

    def check(name, predicate):
        try:
            checks[name] = predicate() is True
        except (ValueError, KeyError, IndexError, TypeError, AttributeError):
            checks[name] = False

    def packages():
        rows = [line.split('\t') for line in outputs['packages'].splitlines()]
        if any(len(row) != 3 for row in rows):
            return False
        observed = {name: (version, status) for name, version, status in rows}
        return (len(observed) == len(rows)
                and all(version is not None and observed.get(name) == (version, 'installed')
                        for name, version in expected['packages'].items())
                and not any(name.split(':')[0] == 'keepalived' for name in observed)
                and not any(status == 'config-files' for _, status in observed.values()))

    def account():
        fields = outputs['passwd'].split(':')
        uid, gid = expected['uid'], expected['gid']
        return (type(uid) is int and type(gid) is int and uid > 0 and gid > 0
                and len(fields) == 7 and fields[0] == 'nautobot'
                and fields[2:4] == [str(uid), str(gid)]
                and fields[5:] == [expected['home'], expected['shell']]
                and outputs['identity'] == f'uid={uid}(nautobot) gid={gid}(nautobot) groups={gid}(nautobot)'
                and outputs['home'] in {f'{uid}:{gid}:700:directory', f'{uid}:{gid}:750:directory', f'{uid}:{gid}:755:directory'})

    def subids(name):
        rows = [line.split(':') for line in outputs[name].splitlines()]
        selected = []
        for owner, start, count in rows:
            if not start.isdecimal() or not count.isdecimal() or int(count) <= 0:
                return False
            start, count = int(start), int(count)
            if owner == 'nautobot':
                selected.append((start, count))
            elif start < 231072 and start + count > 165536:
                return False
        return selected == [(165536, 65536)]

    def units():
        blocks = outputs['units'].split('\n\n')
        observed = {}
        for block in blocks:
            rows = [line.split('=', 1) for line in block.splitlines()]
            props = dict(rows)
            if len(props) != len(rows) or set(props) != {'Id', 'LoadState', 'ActiveState', 'UnitFileState'}:
                return False
            if props['Id'] in observed:
                return False
            observed[props['Id']] = props
        names = expected['required_units'] + expected['unwanted_units'] + ['keepalived.service']
        return (set(observed) == set(names)
                and all(observed[name]['ActiveState'] == 'active' and observed[name]['LoadState'] == 'loaded'
                        for name in expected['required_units'])
                and all(observed[name]['ActiveState'] == 'inactive'
                        and observed[name]['LoadState'] == 'masked'
                        and observed[name]['UnitFileState'] == 'masked' for name in expected['unwanted_units'])
                and observed['keepalived.service']['LoadState'] == 'not-found'
                and observed['keepalived.service']['ActiveState'] == 'inactive')

    def permanent_address():
        links = json.loads(outputs['addresses'])
        addresses = [a for link in links if link['ifname'] == 'eth0' for a in link['addr_info']
                     if a.get('local') == expected['permanent_ula']]
        return (len(addresses) == 1 and addresses[0]['prefixlen'] == 64
                and addresses[0]['family'] == 'inet6'
                and addresses[0]['valid_life_time'] == 4294967295
                and addresses[0]['preferred_life_time'] == 4294967295
                and not any(addresses[0].get(flag, False) for flag in ['temporary', 'tentative', 'dadfailed', 'deprecated']))

    def usb():
        blocks = outputs['usb'].split('\n\n')
        bridge = [b for b in blocks if 'ATTRS{idVendor}=="152d"' in b and 'ATTRS{idProduct}=="0583"' in b]
        driver = [b for b in blocks if 'DRIVERS=="usb-storage"' in b]
        return (len(bridge) == 1 and len(driver) == 1 and 'ATTRS{speed}=="5000"' in bridge[0]
                and 'DRIVERS=="uas"' not in outputs['usb'])

    def smart():
        data = json.loads(outputs['smart'])
        health = data['nvme_smart_health_information_log']
        return (data['smartctl']['exit_status'] == 0 and data['smart_status']['passed'] is True
                and all(type(health[key]) is int and health[key] == 0
                        for key in ['critical_warning', 'media_errors', 'num_err_log_entries'])
                and type(data['temperature']['current']) is int
                and 0 < data['temperature']['current'] < expected['maximum_temperature_celsius'])

    def listeners():
        # Retain protocol, state, local and peer endpoint; reject malformed/duplicate rows.
        rows = [line.split() for line in outputs['listeners'].splitlines()]
        if any(len(row) != 6 or row[0] not in {'tcp', 'udp'} for row in rows):
            return False
        observed = sorted(' '.join([row[0], row[1], row[4], row[5]]) for row in rows)
        return (isinstance(expected['listeners'], list) and bool(expected['listeners'])
                and len(set(observed)) == len(observed) and observed == sorted(expected['listeners'])
                and not any(re.search(r':(?:5432|6379|8080)$', row[4]) for row in rows))

    check('exact_packages_and_no_config_residue', packages)
    check('account_identity', account)
    for name in ['subuid', 'subgid']:
        check(name + '_nonoverlap', lambda name=name: subids(name))
    check('lingering', lambda: dict(line.split('=', 1) for line in outputs['linger'].splitlines())
          == {'UID': str(expected['uid']), 'Linger': 'yes', 'State': 'lingering'})
    check('rootless_podman', lambda: json.loads(outputs['podman'])['host']['security']['rootless'] is True
          and json.loads(outputs['podman'])['store']['graphRoot'] == '/var/lib/nautobot/.local/share/containers/storage')
    check('unit_states', units)
    check('zero_failed_units', lambda: outputs['failed_units'] == '')
    check('keepalived_absent', lambda: all(outputs[n] == '' for n in
          ['keepalived_process', 'keepalived_config', 'keepalived_config_symlink', 'keepalived_unit_files', 'keepalived_units']))
    check('permanent_ula', permanent_address)
    check('root_filesystem', lambda: json.loads(outputs['root']) == {'filesystems': [
        {'source': expected['root_source'], 'fstype': expected['root_fstype'], 'target': '/'}]})
    check('exact_quirk', lambda: [x for x in outputs['cmdline'].split() if x.startswith('usb-storage.quirks=')]
          == [expected['quirk_token']])
    check('root_usb_binding', usb)
    check('current_boot_storage_clear', lambda: outputs['storage_events'] == '')
    check('smart_health', smart)
    check('ext4_errors_zero', lambda: outputs['ext4_errors'] == '0')
    check('ext4_metadata_clean', lambda: re.search(r'^Filesystem state:\s+clean$', outputs['ext4_metadata'], re.M) is not None)
    check('temperature', lambda: re.fullmatch(r"temp=([0-9]+\.[0-9]+)'C", outputs['temperature']) is not None
          and 0 < float(outputs['temperature'][5:-2]) < expected['maximum_temperature_celsius'])
    check('throttling_clear', lambda: outputs['throttling'] == 'throttled=0x0')
    check('listeners', listeners)
    check('no_autoremove_residue', lambda: re.search(r'^0 upgraded, 0 newly installed, 0 to remove and [0-9]+ not upgraded\.$', outputs['residue'], re.M) is not None
          and not re.search(r'^(Remv|Inst|Conf)\s', outputs['residue'], re.M))
    validation = document['storage_evidence']['current_boot_validation']
    check('reviewed_current_boot_storage', lambda: validation['state'] == 'passed'
          and isinstance(validation['evidence_reference'], str) and bool(validation['evidence_reference'])
          and outputs['boot_start'] == outputs['boot_end'] == validation['boot_id'])
    return {'result': 'preflight_passed_review_required' if all(checks.values()) else 'blocked',
            'checks': checks, 'accepted_live_state_written': False, 'mutation_attempted': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path)
    args = parser.parse_args()
    document = yaml.safe_load(OPERATION.read_text())
    if args.evidence.is_symlink() or args.evidence.stat().st_size > 32 * 1024 * 1024:
        parser.error('unsafe or oversized evidence')
    result = evaluate(document, json.loads(args.evidence.read_text()))
    print(json.dumps(result, sort_keys=True))
    return 0 if result['result'] == 'preflight_passed_review_required' else 1


if __name__ == '__main__':
    raise SystemExit(main())
