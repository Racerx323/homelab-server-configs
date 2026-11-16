#!/usr/bin/env python3
"""Exercise unmodified Webmin init_config referrer checks with isolated CGI inputs."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--webmin-root', type=Path, required=True)
    args = parser.parse_args()
    scripts = Path(__file__).parents[1] / 'scripts'
    profile = load(scripts / 'render-proxy-profile.py', 'profile')
    editor = load(scripts / 'configure-miniserv.py', 'editor')
    with tempfile.TemporaryDirectory(prefix='webmin-referrers-') as directory:
        root = Path(directory)
        var = root / 'var'
        var.mkdir()
        mini = root / 'miniserv.conf'
        mini.write_text(f'root={args.webmin_root}\nport=10000\nssl=0\nsession=1\n')
        settings = root / 'config'
        baseline = (f'os_type=debian-linux\nos_version=13\nlang=en\nroot={args.webmin_root}\n'
                    'referer=1\nreferers_none=1\nreferers=existing.example.test\n')
        settings.write_text(baseline)
        probe = root / 'probe.cgi'
        probe.write_text('require "$ARGV[0]/web-lib.pl"; &init_config(); print "NATIVE_REFERER_ACCEPTED\\n";\n')
        env = {'PATH': '/usr/bin:/bin', 'WEBMIN_CONFIG': str(root), 'WEBMIN_VAR': str(var),
               'MINISERV_CONFIG': str(mini), 'SERVER_ROOT': str(args.webmin_root),
               'SCRIPT_NAME': '/probe.cgi', 'REQUEST_URI': '/probe.cgi',
               'HTTP_HOST': 'webmin-host.example.test', 'SERVER_PORT': '10000',
               'REQUEST_METHOD': 'POST', 'HTTP_USER_AGENT': 'OfflineQualification',
               'REMOTE_USER': 'fixture', 'HTTPS': 'off', 'LC_ALL': 'C'}

        def check(label, referer, accepted, script=probe):
            current = dict(env)
            if referer is not None:
                current['HTTP_REFERER'] = referer
            row = subprocess.run(['/usr/bin/perl', '-I', str(args.webmin_root), str(script),
                                  str(args.webmin_root)], cwd=args.webmin_root, env=current,
                                 capture_output=True, timeout=10)
            assert row.returncode == 0, (label, row.returncode, row.stderr[:500].decode(errors='replace'))
            passed = b'NATIVE_REFERER_ACCEPTED' in row.stdout
            if accepted:
                assert passed, (label, 'unexpected_denial', row.stdout[:500].decode(errors='replace'))
            else:
                assert not passed and b'Security Warning' in row.stdout, (label, 'expected_native_referrer_denial', row.stdout[:500].decode(errors='replace'))
            return {'case': label, 'accepted': passed}

        results = [check('global-bypass-control', 'https://evil.example.test/', True)]
        review = {'browser_hostname': 'webmin-host.example.test',
                  'backend_addresses': ['192.0.2.75'], 'proxy_sources': ['192.0.2.53'],
                  'backend_transport': 'http', 'miniserv': {'port': '10000', 'ssl': '0',
                  'session': '1', 'localauth': '', 'allow': '127.0.0.1 ::1'},
                  'webmin': {'referer': '1', 'referers_none': '1', 'referers': 'existing.example.test'}}
        editor.configure(settings, profile.policies(review)['webmin'])
        assert 'referers_none=1\n' in settings.read_text()
        for label, referer, expected in [
            ('proxy-https-front-back-port-difference', 'https://webmin-host.example.test/', True),
            ('preserved-existing-referer', 'https://existing.example.test/', True),
            ('foreign-site', 'https://evil.example.test/', False),
            ('suffix-spoof', 'https://webmin-host.example.test.evil.example/', False),
            ('missing-referrer-protected-action', None, False),
        ]:
            results.append(check(label, referer, expected))
        login = root / 'session_login.cgi'
        login.write_bytes(probe.read_bytes())
        results.append(check('native-login-exemption', None, True, login))
        print(json.dumps({'passed': True, 'native_init_config': True,
                          'authentication_tested': False, 'http_transport_tested': False,
                          'cases': results, 'web_lib_sha256': hashlib.sha256(
                              (args.webmin_root / 'web-lib-funcs.pl').read_bytes()).hexdigest()}))


if __name__ == '__main__':
    main()
