#!/usr/bin/env python3
"""Opt-in native uWSGI regression using pinned server dependencies, not production data."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time
import unittest
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('app', ROOT/'Nautobot/ansible/scripts/startup-application.py')
app = importlib.util.module_from_spec(spec);spec.loader.exec_module(app)


@unittest.skipUnless(os.environ.get('NAUTOBOT_SERVER_TEST_PYTHON'), 'opt-in isolated pinned dependencies required')
class Server(unittest.TestCase):
    def test_native_server_requires_master_and_serves_http_and_static(self):
        python = os.environ['NAUTOBOT_SERVER_TEST_PYTHON']
        with tempfile.TemporaryDirectory(prefix='nautobot-server-test.') as directory:
            root=Path(directory);(root/'static').mkdir();(root/'static/base.css').write_text('body { color: black; }')
            (root/'probe.py').write_text('import uwsgi\nimport uwsgidecorators\ndef application(environ,start_response):\n start_response("200 OK",[("Content-Type","text/plain")])\n return [b"master-ready" if uwsgi.masterpid() > 0 else b"no-master"]\n')
            # Nautobot 3.2.3 start.Command is an unmodified subclass of this command.
            (root/'server.py').write_text('import sys\nfrom importlib.metadata import version\nassert version("django-webserver")=="1.2.0"\nassert version("pyuwsgi")=="2.0.30.post1"\nassert version("Django")=="5.2.17"\nfrom django.conf import settings\nsettings.configure(WSGI_APPLICATION="probe.application",STATIC_URL="/static/",STATIC_ROOT='+repr(str(root/'static'))+',WEBSERVER_WARMUP=False)\nfrom django_webserver.management.commands.pyuwsgi import Command\nCommand().run_from_argv(["nautobot-server","start"]+sys.argv[1:])\n')
            for master in (False,True):
                with socket.socket() as sock:
                    sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
                args=app.COMMANDS['web'][2:]
                args=[f'127.0.0.1:{port}' if a=='0.0.0.0:8080' else a for a in args]
                if not master:args=[a for a in args if a!='--master']
                with tempfile.TemporaryFile() as log:
                    process=subprocess.Popen([python,str(root/'server.py'),*args],cwd=root,stdout=log,stderr=log,start_new_session=True)
                    try:
                        if not master:
                            process.wait(timeout=15);self.assertNotEqual(process.returncode,0)
                            log.seek(0);self.assertIn(b'enable the uWSGI master process',log.read())
                        else:
                            opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
                            for _ in range(100):
                                try:
                                    with opener.open(f'http://127.0.0.1:{port}/',timeout=1) as response:body=response.read()
                                    break
                                except (OSError,urllib.error.URLError):
                                    if process.poll() is not None:
                                        log.seek(0);self.fail(log.read().decode())
                                    time.sleep(.1)
                            else:self.fail('server readiness timeout')
                            self.assertEqual(body,b'master-ready')
                            with opener.open(f'http://127.0.0.1:{port}/static/base.css',timeout=2) as response:
                                self.assertEqual(response.status,200);self.assertIn(b'color: black',response.read())
                    finally:
                        if process.poll() is None:
                            os.killpg(process.pid,signal.SIGTERM)
                            try:process.wait(timeout=10)
                            except subprocess.TimeoutExpired:
                                os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=5)


if __name__=='__main__':unittest.main()
