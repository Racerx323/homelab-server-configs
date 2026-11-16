#!/usr/bin/env python3
"""Bounded unauthenticated Webmin path/counter evidence; no configuration writes."""
import argparse
import http.client
import ipaddress
import json
import re
import socket
import subprocess
import time


def probe(address, hostname, expected_source):
    target = ipaddress.ip_address(address)
    source = str(ipaddress.ip_address(expected_source))
    if not re.fullmatch(r'[a-z0-9.-]+', hostname): raise ValueError('hostname')
    route = json.loads(subprocess.run(['ip', '-j', '-' + str(target.version), 'route', 'get', str(target)],
                                    check=True, capture_output=True, text=True, timeout=3).stdout)
    if len(route) != 1 or route[0].get('prefsrc', route[0].get('src')) != source:
        return {'accepted': False, 'failure': 'route_selected_source_mismatch',
                'target': str(target), 'expected_source': source, 'observed_route': route}
    start = time.monotonic()
    connection = http.client.HTTPConnection(str(target), 10000, timeout=5)
    try:
        connection.connect()
        actual_source = str(ipaddress.ip_address(connection.sock.getsockname()[0]))
        actual_target = str(ipaddress.ip_address(connection.sock.getpeername()[0]))
        if actual_source != source or actual_target != str(target):
            return {'accepted': False, 'failure': 'socket_endpoint_mismatch', 'expected_source': source,
                    'expected_target': str(target), 'observed_source': actual_source, 'observed_target': actual_target}
        connection.request('GET', '/', headers={'Host': hostname, 'X-Forwarded-Proto': 'https', 'Connection': 'close'})
        response = connection.getresponse()
        body = response.read(65537)
        login = len(body) <= 65536 and bool(re.search(rb'name\s*=\s*[\"\x27]?pass\b', body))
        return {'accepted': response.status == 200 and login, 'target': str(target), 'source': actual_source,
                'family': target.version, 'status': response.status, 'login_page': login,
                'seconds': time.monotonic()-start, 'route': route[0]}
    finally:
        connection.close()


def denied(address):
    target = ipaddress.ip_address(address)
    sock = socket.socket(socket.AF_INET6 if target.version == 6 else socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(3)
    try:
        sock.connect((str(target), 10000))
        return {'accepted': False, 'reason': 'connected'}
    except TimeoutError:
        return {'accepted': True, 'reason': 'timeout', 'target': str(target),
                'client_source': sock.getsockname()[0]}
    finally:
        sock.close()


def counters():
    run = subprocess.run(['nft', '-j', 'list', 'table', 'inet', 'webmin'], check=True,
                         capture_output=True, text=True, timeout=3)
    if len(run.stdout) > 65536: raise ValueError('guard_evidence_limit')
    result = {}
    for item in json.loads(run.stdout)['nftables']:
        rule = item.get('rule', {})
        comment = rule.get('comment', '')
        if comment.startswith('webmin-'):
            values = [entry['counter']['packets'] for entry in rule['expr'] if 'counter' in entry]
            if len(values) != 1 or comment in result: raise ValueError('guard_counter_identity')
            result[comment] = values[0]
    if not {'webmin-denied-4', 'webmin-denied-6'} <= result.keys(): raise ValueError('guard_counters_missing')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--counters', action='store_true')
    parser.add_argument('--deny', action='store_true')
    parser.add_argument('--address'); parser.add_argument('--hostname'); parser.add_argument('--source')
    args = parser.parse_args()
    try:
        row = counters() if args.counters else denied(args.address) if args.deny else probe(args.address, args.hostname, args.source)
        print(json.dumps(row)); raise SystemExit(0 if args.counters or row['accepted'] else 1)
    except Exception as error:
        # Fixed classification only; no response bodies or exceptions with private data.
        print(json.dumps({'accepted': False, 'failure': type(error).__name__,
                          'expected_target': args.address, 'expected_source': args.source,
                          'native_exit': getattr(error, 'returncode', None)})); raise SystemExit(1)
