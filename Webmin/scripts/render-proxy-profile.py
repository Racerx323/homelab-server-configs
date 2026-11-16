#!/usr/bin/env python3
"""Render managed-key policies from reviewed non-secret host inputs; never deploy."""
import argparse
import ipaddress
import json
import re
from pathlib import Path


def hostname(value):
    if not isinstance(value, str) or len(value) > 253 or not all(
            re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label)
            for label in value.split('.')):
        raise ValueError('invalid_browser_hostname')
    return value


def addresses(values):
    if not isinstance(values, list) or not values:
        raise ValueError('explicit_addresses_required')
    result = []
    for value in values:
        address = ipaddress.ip_address(value)
        if address.is_unspecified or address.is_multicast or '%' in str(address):
            raise ValueError('unusable_address')
        if str(address) not in result:
            result.append(str(address))
    return result


def policies(review):
    if set(review) != {'browser_hostname', 'backend_addresses', 'proxy_sources',
                       'backend_transport', 'miniserv', 'webmin'}:
        raise ValueError('exact_review_fields_required')
    name = hostname(review['browser_hostname'])
    backends, sources = addresses(review['backend_addresses']), addresses(review['proxy_sources'])
    mini, webmin = review['miniserv'], review['webmin']
    for settings in (mini, webmin):
        if not isinstance(settings, dict) or any(not isinstance(v, str) or
                any(ord(c) < 32 or ord(c) > 126 for c in v) for v in settings.values()):
            raise ValueError('invalid_selected_settings')
    transport = review['backend_transport']
    if transport not in ('http', 'https') or mini.get('ssl') != str(int(transport == 'https')):
        raise ValueError('transport_change_requires_separate_review')
    if mini.get('session') != '1' or mini.get('localauth', ''):
        raise ValueError('explicit_session_auth_required')
    if webmin.get('referers_none', '0') not in ('0', '1') or webmin.get('webprefix', ''):
        raise ValueError('referer_or_subpath_policy_requires_review')
    if mini.get('redirect_prefix', '') or mini.get('musthost', '') not in ('', name):
        raise ValueError('existing_redirect_policy_requires_review')
    port = mini.get('port', '')
    if not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise ValueError('invalid_backend_port')
    allowed = list(dict.fromkeys(['127.0.0.1', '::1', *sources]))
    if any(value not in allowed for value in mini.get('allow', '').split()) or mini.get('deny', ''):
        raise ValueError('existing_access_policy_requires_review')
    refs = webmin.get('referers', '').split()
    if name not in refs:
        refs.append(name)
    # Authentication, SSL/key settings, paths and all unrelated settings stay untouched.
    return {
        'miniserv': {
            'bind': '127.0.0.1', 'sockets': ' '.join(
                f'{ip}:{port}' for ip in dict.fromkeys(['::1', *backends]) if ip != '127.0.0.1'),
            'ipv6': '1', 'allow': ' '.join(allowed), 'listen': '',
            'redirect_ssl': '1', 'redirect_host': name, 'redirect_port': '443',
        },
        'webmin': {'referer': '0', 'referers': ' '.join(refs)},
    }


def ingress(review):
    """Use the existing fleet guard pattern, scoped exclusively to Webmin's table."""
    policies(review)
    port = int(review['miniserv']['port'])
    backends, sources = addresses(review['backend_addresses']), addresses(review['proxy_sources'])
    lines = ['# Webmin-owned table only; never flush the host ruleset.',
             'destroy table inet webmin', 'table inet webmin {',
             '    chain backend_prerouting {',
             '        type filter hook prerouting priority -310; policy accept;',
             '        iifname "lo" accept']
    for version, family in [(4, 'ip'), (6, 'ip6')]:
        selected = [ip for ip in sources if ipaddress.ip_address(ip).version == version]
        for backend in backends:
            if ipaddress.ip_address(backend).version == version:
                if not selected:
                    raise ValueError('proxy_source_family_missing')
                for source in selected:
                    label = f'webmin-{version}-{source}-to-{backend}'
                    lines.append(f'        {family} daddr {backend} tcp dport {port} '
                                 f'{family} saddr {source} counter accept comment "{label}"')
    lines.extend([f'        meta nfproto ipv4 fib daddr type local tcp dport {port} counter drop comment "webmin-denied-4"',
                  f'        meta nfproto ipv6 fib daddr type local tcp dport {port} counter drop comment "webmin-denied-6"', '    }', '}'])
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--review', type=Path, required=True)
    parser.add_argument('--format', choices=['policies', 'ingress'], default='policies')
    args = parser.parse_args()
    review = json.loads(args.review.read_text())
    if args.format == 'ingress':
        print(ingress(review), end='')
    else:
        print(json.dumps(policies(review), indent=2, sort_keys=True))
