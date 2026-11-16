import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


profile = load('render-proxy-profile')
config = load('configure-miniserv')
REVIEW = {
    'browser_hostname': 'webmin-host.example.test',
    'backend_addresses': ['192.0.2.75', 'fd00::75'],
    'proxy_sources': ['192.0.2.53', 'fd00::53'],
    'backend_transport': 'http',
    'miniserv': {'port': '10000', 'ssl': '0', 'session': '1', 'localauth': '',
                 'allow': '127.0.0.1 ::1', 'allowusers': 'existing', 'sudo': '1'},
    'webmin': {'referers': 'existing.example.test', 'referers_none': '1'},
}


class ProxyProfile(unittest.TestCase):
    def test_profile_preserves_auth_transport_and_unmanaged_bytes(self):
        before = copy.deepcopy(REVIEW)
        result = profile.policies(REVIEW)
        self.assertEqual(REVIEW, before)
        self.assertEqual(result['miniserv']['sockets'], '::1:10000 192.0.2.75:10000 fd00::75:10000')
        self.assertEqual(result['webmin']['referers'], 'existing.example.test webmin-host.example.test')
        raw = b'allowusers=existing\nsudo=1\nssl=0\nkeyfile=/private/key\ncustom=value\n'
        rendered = config.render(raw, result['miniserv'])
        self.assertTrue(rendered.startswith(raw))
        self.assertEqual(config.render(rendered, result['miniserv']), rendered)

    def test_referrer_policy_enables_global_check_and_preserves_missing_referrer_rejection(self):
        review = copy.deepcopy(REVIEW)
        review['webmin']['referer'] = '1'
        policy = profile.policies(review)['webmin']
        self.assertEqual(policy['referer'], '0')
        self.assertNotIn('referers_none', policy)
        raw = b'referer=1\nreferers_none=1\nreferers=existing.example.test\nother=value\n'
        result = config.render(raw, policy)
        self.assertIn(b'referers_none=1\n', result)
        self.assertIn(b'referer=0\n', result)
        self.assertIn(b'other=value\n', result)
        self.assertEqual(config.render(result, policy), result)

    def test_ingress_is_scoped_and_requires_both_source_families(self):
        result = profile.ingress(REVIEW)
        self.assertIn('destroy table inet webmin', result)
        self.assertNotIn('flush ruleset', result)
        self.assertIn('ip daddr 192.0.2.75 tcp dport 10000 ip saddr 192.0.2.53 counter accept', result)
        self.assertIn('ip6 daddr fd00::75 tcp dport 10000 ip6 saddr fd00::53 counter accept', result)
        self.assertIn('fib daddr type local tcp dport 10000 counter drop', result)
        self.assertIn('comment "webmin-denied-4"', result)
        self.assertIn('webmin-4-192.0.2.53-to-192.0.2.75', result)
        review = copy.deepcopy(REVIEW)
        review['proxy_sources'] = ['192.0.2.53']
        with self.assertRaisesRegex(ValueError, 'proxy_source_family_missing'):
            profile.ingress(review)

    def test_https_is_preserved_never_downgraded(self):
        review = copy.deepcopy(REVIEW)
        review['backend_transport'] = 'https'
        with self.assertRaises(ValueError):
            profile.policies(review)
        review['miniserv']['ssl'] = '1'
        self.assertNotIn('ssl', profile.policies(review)['miniserv'])

    def test_unsafe_or_ambiguous_review_stops(self):
        changes = [('browser_hostname', 'bad\nssl=0'), ('backend_addresses', ['0.0.0.0']),
                   ('proxy_sources', ['192.0.2.0/24']), ('proxy_sources', []),
                   ('backend_addresses', ['ff02::1'])]
        for key, value in changes:
            with self.subTest(key=key, value=value):
                review = copy.deepcopy(REVIEW)
                review[key] = value
                with self.assertRaises(ValueError):
                    profile.policies(review)

    def test_existing_access_auth_and_referer_exceptions_require_review(self):
        for section, key, value in [('miniserv', 'allow', '192.0.2.99'),
                                    ('miniserv', 'deny', '192.0.2.53'),
                                    ('miniserv', 'localauth', '1'),
                                    ('miniserv', 'session', '0'),
                                    ('webmin', 'referers_none', 'invalid'),
                                    ('webmin', 'webprefix', '/admin'),
                                    ('miniserv', 'redirect_prefix', '/old'),
                                    ('miniserv', 'musthost', 'old.example.test')]:
            review = copy.deepcopy(REVIEW)
            review[section][key] = value
            with self.assertRaises(ValueError):
                profile.policies(review)


if __name__ == '__main__':
    unittest.main()
