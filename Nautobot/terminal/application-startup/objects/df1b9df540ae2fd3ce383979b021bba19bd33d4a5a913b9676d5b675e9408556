#!/usr/bin/env python3
"""Actual application packet matrix; no network or HA configuration changes."""
import json
from pathlib import Path
import subprocess

SSH = ['ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5']
DESTINATIONS = ('10.1.2.170', 'fd36:5aa8:6971:1::170')
PROXIES = {'10.1.0.53': ('10.1.0.53', 'fd36:5aa8:6971:1::53'),
           '10.1.0.54': ('10.1.0.54', 'fd36:5aa8:6971:1::54')}


def command(host, command, code=None):
    result = subprocess.run(SSH + [host, command], input=code, capture_output=True, text=True, timeout=15)
    if result.returncode or len(result.stdout) > 65536:
        raise ValueError('network_probe_failed')
    return json.loads(result.stdout)


def counters():
    value = command('ama@10.1.2.170', 'cd / && sudo -n /usr/sbin/nft -j list table inet nautobot_backend')
    found = {}
    for entry in value['nftables']:
        rule = entry.get('rule', {})
        if rule.get('comment') in ('deny-v4', 'deny-v6'):
            found[rule['comment']] = next(item['counter']['packets'] for item in rule['expr'] if 'counter' in item)
    if set(found) != {'deny-v4', 'deny-v6'}:
        raise ValueError('counter_missing')
    return found


def denied(value, before, after, index, source):
    key, other = ('deny-v4', 'deny-v6') if index == 0 else ('deny-v6', 'deny-v4')
    return (value['outcome'] == 'timeout' and value['source'] == source
            and after[key] > before[key] and after[other] == before[other])


def probe():
    code = Path(__file__).with_name('startup-network-client.py').read_text()
    def client(host, index):
        return command('pi@' + host, 'cd / && /usr/bin/python3 - ' + DESTINATIONS[index], code)
    def allow(host, index):
        value = client(host, index)
        if value != {'status': 200, 'source': PROXIES[host][index], 'outcome': 'response'}:
            raise ValueError('allowed_probe_failed')
    for host in PROXIES:
        for index in (0, 1):
            allow(host, index)
    for index in (0, 1):
        route = command('pi@10.1.3.83', 'ip -' + ('4' if index == 0 else '6') + ' -j route get ' + DESTINATIONS[index])
        allow('10.1.0.53', index)
        before = counters()
        value = client('10.1.3.83', index)
        after = counters()
        allow('10.1.0.53', index)
        if not denied(value, before, after, index, route[0]['prefsrc']):
            raise ValueError('denial_unproven')
    return {'allowed_both_proxies_both_families': True, 'denied_both_families_with_counters': True}


if __name__ == '__main__':
    try:
        print(json.dumps(probe()))
    except Exception:
        print(json.dumps({'allowed_both_proxies_both_families': False, 'denied_both_families_with_counters': False}))
        raise SystemExit(69)
