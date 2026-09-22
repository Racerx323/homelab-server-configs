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
        '/usr/bin/podman', 'exec', '-i', 'nautobot-web', 'nautobot-server', 'shell', '--interface', 'python',
        '--command', "import sys;exec(compile(sys.stdin.read(),'<startup-session>','exec'))"]) + ",input=" + repr(code.encode()) + ",capture_output=True,timeout=20,cwd='/')\nsys.stdout.buffer.write(p.stdout if p.returncode==0 else b'{}');sys.exit(p.returncode)\n"
    result = subprocess.run(SSH + [TARGET, 'cd / && sudo -n /usr/bin/python3 -'], input=remote.encode(),
                            capture_output=True, timeout=30)
    if result.returncode or len(result.stdout) > 65536:
        raise ValueError('session_check_failed')
    lines = [line.removeprefix(b'STARTUP_SESSION_RESULT=') for line in result.stdout.splitlines() if line.startswith(b'STARTUP_SESSION_RESULT=')]
    if len(lines) != 1:
        raise ValueError('session_receipt_count')
    return json.loads(lines[0])['admin']


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
    status, _, _ = request('/login/', data, {'Content-Type': 'application/x-www-form-urlencoded', 'Referer': 'http://' + HOST + '/login/'})
    cookie = next((c.value for c in jar if c.name == 'sessionid'), None)
    try:
        if status != 200 or not cookie or not identity(cookie):
            raise ValueError('authenticated_identity')
    finally:
        # Nautobot 3.2.3 users.views.LogoutView implements GET (not Django's
        # generic POST-only logout). Revoke even if identity validation fails.
        if cookie:
            status, _, _ = request('/logout/')
            if status != 200 or identity(cookie):
                raise ValueError('logout_session_revocation')
        jar.clear()
    return {'administrator_login_logout': True, 'csrf_and_host_rejections': True}


def probe():
    credential = password()
    try:
        with tunnel() as base:
            result = flow(base, credential)
        return {**result, 'tunnel_cleanup': True}
    finally:
        credential = None


if __name__ == '__main__':
    try:
        print(json.dumps(probe()))
    except Exception:
        print(json.dumps({'administrator_login_logout': False, 'csrf_and_host_rejections': False, 'tunnel_cleanup': False}))
        raise SystemExit(69)
