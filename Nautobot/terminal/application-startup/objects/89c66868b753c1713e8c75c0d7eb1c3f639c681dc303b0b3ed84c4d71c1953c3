#!/usr/bin/env python3
"""HTTP session flow through a retained loopback SSH tunnel; secrets stay in memory."""
from contextlib import contextmanager
from html.parser import HTMLParser
import http.cookiejar
import importlib.util
import json
from pathlib import Path
import socket
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

SSH = ['ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5']
TARGET = 'ama@10.1.2.170'
HOST = 'j2-svpi4mf.local.theama.co'


ERROR_CODES = frozenset(('login_form', 'csrf_rejection', 'host_rejection',
    'authenticated_identity', 'logout_session_revocation', 'session_timeout',
    'session_transport', 'session_check_failed', 'session_receipt_count',
    'session_receipt_shape', 'credential_shape', 'nonlocal_redirect',
    'http_output_limit', 'tunnel_failed', 'tunnel_unavailable', 'tunnel_lost',
    'tunnel_cleanup_failed', 'unexpected_session_failure'))


def safe_error(error):
    if isinstance(error, subprocess.TimeoutExpired):
        return 'session_transport'
    return str(error) if type(error) is ValueError and str(error) in ERROR_CODES else 'unexpected_session_failure'


class SessionFailure(Exception):
    def __init__(self, primary, cleanup=None):
        self.primary = primary
        self.cleanup = cleanup


# This timer lives inside the container interpreter, so an SSH disconnect cannot
# leave the Django identity check running indefinitely. No shell child is spawned.
IDENTITY_ENTRYPOINT = ("import signal,runpy;signal.signal(signal.SIGALRM,signal.SIG_DFL);"
                      "signal.alarm(60);runpy.run_path('/usr/local/bin/nautobot-server',run_name='__main__')")


class Form(HTMLParser):
    def __init__(self):
        super().__init__(); self.csrf = None
    def handle_starttag(self, tag, attrs):
        fields = dict(attrs)
        if tag == 'input' and fields.get('name') == 'csrfmiddlewaretoken':
            self.csrf = fields.get('value')


class LocalRedirect(urllib.request.HTTPRedirectHandler):
    def __init__(self, base):
        self.base = base
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parsed = urllib.parse.urlsplit(newurl)
        if parsed.scheme + '://' + parsed.netloc != self.base:
            raise ValueError('nonlocal_redirect')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


@contextmanager
def tunnel():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
    process = subprocess.Popen(SSH + ['-N', '-o', 'ExitOnForwardFailure=yes', '-o', 'ServerAliveInterval=5',
        '-o', 'ServerAliveCountMax=2', '-L', f'127.0.0.1:{port}:127.0.0.1:8080', TARGET],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            if process.poll() is not None:
                raise ValueError('tunnel_failed')
            with socket.socket() as sock:
                sock.settimeout(.2)
                if sock.connect_ex(('127.0.0.1', port)) == 0:
                    break
            time.sleep(.1)
        else:
            raise ValueError('tunnel_unavailable')
        yield 'http://127.0.0.1:' + str(port)
        if process.poll() is not None:
            raise ValueError('tunnel_lost')
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill(); process.wait(timeout=5)
        with socket.socket() as sock:
            sock.settimeout(1)
            if sock.connect_ex(('127.0.0.1', port)) == 0:
                raise ValueError('tunnel_cleanup_failed')


def session_identity(cookie):
    # Password and cookie never appear in process arguments or evidence files.
    code = """from django.contrib.sessions.models import Session
from django.contrib.auth import get_user_model
from django.utils import timezone
import json
s=Session.objects.filter(session_key=COOKIE,expire_date__gt=timezone.now()).first()
u=None if s is None else get_user_model().objects.filter(pk=s.get_decoded().get('_auth_user_id')).first()
print('STARTUP_SESSION_RESULT='+json.dumps({'admin':bool(u and u.get_username()=='admin' and u.is_active and u.is_superuser)}))
""".replace('COOKIE', repr(cookie))
    remote = "import subprocess,sys\np=subprocess.run(" + repr([
        '/usr/sbin/runuser', '--user', 'nautobot', '--', '/usr/bin/env', 'XDG_RUNTIME_DIR=/run/user/999',
        '/usr/bin/podman', 'exec', '-i', 'nautobot-web', 'python3', '-c', IDENTITY_ENTRYPOINT, 'shell', '--interface', 'python',
        '--command', "import sys;exec(compile(sys.stdin.read(),'<startup-session>','exec'))"]) + ",input=" + repr(code.encode()) + ",capture_output=True,timeout=70,cwd='/')\nsys.stdout.buffer.write(p.stdout if p.returncode==0 else b'{}');sys.exit(p.returncode)\n"
    result = subprocess.run(SSH + [TARGET, 'cd / && sudo -n /usr/bin/python3 -'], input=remote.encode(),
                            capture_output=True, timeout=75)
    if result.returncode == 142:
        raise ValueError('session_timeout')
    if result.returncode or len(result.stdout) > 65536:
        raise ValueError('session_check_failed')
    lines = [line.removeprefix(b'STARTUP_SESSION_RESULT=') for line in result.stdout.splitlines() if line.startswith(b'STARTUP_SESSION_RESULT=')]
    if len(lines) != 1:
        raise ValueError('session_receipt_count')
    receipt = json.loads(lines[0])
    if set(receipt) != {'admin'} or type(receipt['admin']) is not bool:
        raise ValueError('session_receipt_shape')
    return receipt['admin']


def password():
    path = Path(__file__).with_name('provision-credentials.py')
    spec = importlib.util.spec_from_file_location('provider', path)
    provider = importlib.util.module_from_spec(spec); spec.loader.exec_module(provider)
    value = provider.doppler('secrets', 'get', 'NAUTOBOT_INITIAL_ADMIN_PASSWORD', '--plain', '--config', 'prd_nautobot').strip()
    if len(value) != 64 or any(c not in '0123456789abcdef' for c in value):
        raise ValueError('credential_shape')
    return value


def flow(base, credential, identity=session_identity):
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPCookieProcessor(jar), LocalRedirect(base))
    def request(path, data=None, headers=None):
        req = urllib.request.Request(base + path, data=data, headers={'Host': HOST, **(headers or {})})
        try:
            response = opener.open(req, timeout=10)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            payload = response.read(1048577)
            if len(payload) > 1048576:
                raise ValueError('http_output_limit')
            return response.status, payload, response.headers
    status, page, _ = request('/login/')
    form = Form(); form.feed(page.decode())
    if status != 200 or not form.csrf:
        raise ValueError('login_form')
    # Missing CSRF token and hostile Host must be rejected independently.
    if request('/login/', b'username=admin&password=invalid')[0] != 403:
        raise ValueError('csrf_rejection')
    if request('/login/', headers={'Host': 'invalid.example'})[0] != 400:
        raise ValueError('host_rejection')
    data = urllib.parse.urlencode({'username': 'admin', 'password': credential, 'csrfmiddlewaretoken': form.csrf, 'next': '/'}).encode()
    primary = cleanup = None
    cookie = None
    try:
        status, _, _ = request('/login/', data, {'Content-Type': 'application/x-www-form-urlencoded', 'Referer': 'http://' + HOST + '/login/'})
        cookie = next((c.value for c in jar if c.name == 'sessionid'), None)
        if status != 200 or not cookie or not identity(cookie):
            raise ValueError('authenticated_identity')
    except Exception as error:
        primary = safe_error(error)
    finally:
        # Attempt logout even when identity or redirected response validation fails.
        cookie = cookie or next((c.value for c in jar if c.name == 'sessionid'), None)
        try:
            if cookie:
                status, _, _ = request('/logout/')
                if status != 200 or identity(cookie):
                    raise ValueError('logout_session_revocation')
        except Exception as error:
            cleanup = safe_error(error)
        finally:
            jar.clear()
    if primary or cleanup:
        raise SessionFailure(primary, cleanup)
    return {'administrator_login_logout': True, 'csrf_and_host_rejections': True}


def probe():
    credential = None
    failure = None
    tunnel_cleanup = False
    try:
        credential = password()
        with tunnel() as base:
            try:
                result = flow(base, credential)
            except SessionFailure as error:
                failure = error
            except Exception as error:
                failure = SessionFailure(safe_error(error))
        tunnel_cleanup = True
        if failure:
            raise failure
        return {**result, 'tunnel_cleanup': True}
    except Exception as error:
        if isinstance(error, SessionFailure):
            failure = error
        elif failure is None:
            failure = SessionFailure(safe_error(error))
        else:
            # Keep the primary and logout failures when tunnel teardown also fails.
            tunnel_error = safe_error(error)
        receipt = {'administrator_login_logout': False, 'csrf_and_host_rejections': False,
                   'tunnel_cleanup': tunnel_cleanup,
                   'error_class': failure.primary or failure.cleanup or 'unexpected_session_failure'}
        if failure.cleanup:
            receipt['cleanup_error_class'] = failure.cleanup
        if 'tunnel_error' in locals():
            receipt['tunnel_error_class'] = tunnel_error
        return receipt
    finally:
        credential = None


if __name__ == '__main__':
    result = probe()
    print(json.dumps(result))
    raise SystemExit(0 if result.get('administrator_login_logout') is True else 69)
