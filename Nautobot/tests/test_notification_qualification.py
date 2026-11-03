#!/usr/bin/env python3
"""Exercise the actual queue and HTTP sender against a disposable local server."""
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import importlib.util
import json
import os
import pwd
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT/'Nautobot/ansible/scripts'
sys.path.insert(0, str(SCRIPTS))
sys.dont_write_bytecode = True
import notification_qualification as node
import recurring_delivery as delivery


class Qualification(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.statuses = []; self.requests = []; self.sleeps = []
        owner = self
        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                owner.requests.append((self.path, self.headers['Idempotency-Key'],
                                       json.loads(self.rfile.read(int(self.headers['Content-Length'])))))
                self.send_response(owner.statuses.pop(0) if owner.statuses else 200)
                self.send_header('Location', '/must-not-follow'); self.end_headers()
            def log_message(self, *_):
                pass
        self.server = HTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
        self.endpoint = f'http://127.0.0.1:{self.server.server_port}/notify/apprise'
        self.op = dict(target=dict(uid=os.getuid(), gid=os.getgid()),
                       boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
                       evidence_root=str(self.root), observed='2026-11-03T20:41:49.652134+00:00',
                       attempts_per_message=2, retry_seconds=15, preserved_trees={}, services={},
                       notification=dict(method='direct_apprise', endpoint=self.endpoint,
                                         hostname='j2-svpi4mf', fqdn='j2-svpi4mf.local.theama.co', qualification=True))
        self.op['messages'] = node.previews(self.op)
        self.backup = self.root/'backup-state'; self.backup.write_text('untouched')

    def tearDown(self):
        self.server.shutdown(); self.thread.join(); self.server.server_close(); self.temp.cleanup()

    def run_node(self):
        with patch.object(delivery, 'ENDPOINT', self.endpoint):
            return node.run(self.op, self.root, lambda: {}, sleep=self.sleeps.append)

    def receipt(self):
        return json.loads((self.root/'result.json').read_text())

    def test_real_http_retry_and_recovery_with_exact_preview(self):
        self.statuses = [503, 200, 200]
        self.assertEqual(self.run_node(), 0)
        self.assertEqual(self.requests[0], self.requests[1])
        self.assertEqual([r[2] for r in self.requests], [self.op['messages'][e]['message'] for e in
                                                       ('failure', 'failure', 'recovery')])
        self.assertEqual(self.sleeps, [15])
        self.assertFalse(self.receipt()['accepted'])
        self.assertTrue(self.receipt()['submission_complete'])
        self.assertEqual(self.backup.read_text(), 'untouched')
        receipt = (self.root/'result.json').read_bytes()
        self.assertEqual(self.run_node(), 1)
        self.assertEqual((self.root/'result.json').read_bytes(), receipt)
        self.assertEqual(len(self.requests), 3)
        with patch.object(delivery, 'ENDPOINT', self.endpoint):
            self.assertTrue(delivery.notify(self.root/'state', 'recovery', self.op['notification']))
        self.assertEqual(len(self.requests), 3)
        for path in (self.root/'result.json', self.root/'state/notification.json'):
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_exhaustion_keeps_failure_pending_without_recovery(self):
        self.statuses = [503, 503]
        self.assertEqual(self.run_node(), 1)
        self.assertEqual(len(self.requests), 2)
        self.assertEqual(self.receipt()['reason'], 'submission_budget_exhausted')
        pending = json.loads((self.root/'state/notification.json').read_text())['pending']
        self.assertEqual(pending['event'], 'failure')
        self.assertEqual(self.backup.read_text(), 'untouched')

    def test_four_request_ceiling(self):
        self.statuses = [503, 200, 503, 200]
        self.assertEqual(self.run_node(), 0)
        self.assertEqual(len(self.requests), 4)
        self.assertEqual(self.requests[2], self.requests[3])
        self.assertEqual(self.sleeps, [15, 15])

    def test_boot_drift_refuses_before_sending(self):
        self.op['boot_id'] = 'changed'
        self.assertEqual(self.run_node(), 1)
        self.assertEqual(self.receipt()['reason'], 'boot_changed')
        self.assertEqual(self.requests, [])

    def test_recovery_exhaustion_and_redirect_not_followed(self):
        self.statuses = [200, 302, 302]
        self.assertEqual(self.run_node(), 1)
        self.assertEqual(len(self.requests), 3)
        self.assertTrue(all(r[0] == '/notify/apprise' for r in self.requests))
        self.assertEqual(json.loads((self.root/'state/notification.json').read_text())['pending']['event'], 'recovery')

    def test_drift_refuses_before_sending(self):
        self.op['messages']['failure']['message']['body'] = 'unreviewed'
        self.assertEqual(self.run_node(), 1)
        self.assertEqual(self.receipt()['reason'], 'message_drift')
        self.assertEqual(self.requests, [])

    def test_interruption_retains_ambiguous_attempt_without_replay(self):
        def interrupted(*_):
            raise InterruptedError('local cancellation')
        self.assertEqual(node.run(self.op, self.root, lambda: {}, sender=interrupted), 1)
        self.assertIsNone(self.receipt()['attempts'][0]['http_200'])
        self.assertEqual(self.run_node(), 1)
        self.assertEqual(self.requests, [])

    def test_real_transport_freeze_verify_and_drift(self):
        current = yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text())
        if current['operation'].get('stage') != 'recurring_notification_qualification':
            self.skipTest('no pending notification operation')
        spec = importlib.util.spec_from_file_location('notification_bundle', SCRIPTS/'notification-bundle.py')
        bundle = importlib.util.module_from_spec(spec); spec.loader.exec_module(bundle)
        candidate = self.root/'candidate'
        accepted = yaml.safe_load((ROOT/'Nautobot/manifests/accepted-live-state.yaml').read_text())
        if accepted.get('recurring_notifications', {}).get('operation_id') == current['operation']['id']:
            with self.assertRaisesRegex(ValueError, 'accepted_source_drift'):
                bundle.transport.freeze(candidate)
            return
        bundle.transport.freeze(candidate)
        digest = hashlib.sha256((candidate/'bundle.json').read_bytes()).hexdigest()
        self.assertTrue(bundle.transport.verify(candidate, digest)['operation']['execution_enabled'])
        (candidate/'runtime/scripts/recurring_delivery.py').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'input_drift'):
            bundle.transport.verify(candidate, digest)

    @unittest.skipUnless(os.environ.get('NAUTOBOT_NOTIFICATION_NATIVE') == '1', 'opt-in local Ansible/user-systemd run')
    def test_real_playbook_and_transient_service(self):
        # Local adaptations: loopback Apprise, current uid and dbus health instead of production Podman.
        capture = self.root/'capture'; capture.mkdir(mode=0o700)
        scripts = capture/'scripts'; scripts.mkdir(mode=0o700)
        probe = scripts/'recurring_node.py'
        probe.write_text('''import subprocess
def health():
    raw = subprocess.check_output(['/usr/bin/systemctl','--user','show','dbus.service',
        '--property=Id,ActiveState,SubState,InvocationID'],text=True,timeout=10)
    return {'dbus.service':dict(line.split('=',1) for line in raw.splitlines())}
'''); probe.chmod(0o600)
        namespace = {}; exec(probe.read_text(), namespace)
        self.op['services'] = namespace['health']()
        self.assertEqual(self.op['services']['dbus.service']['ActiveState'], 'active')
        identity = pwd.getpwuid(os.getuid())
        self.op['target'].update(user=identity.pw_name, home=identity.pw_dir, address='127.0.0.1')
        self.op['operation'] = dict(stage='recurring_notification_qualification', execution_enabled=True, authorization_ready=True)
        self.op['capture_root'] = str(capture)
        evidence = self.root/'evidence'; self.op['evidence_root'] = str(evidence)
        self.op['messages'] = node.previews(self.op)
        meta = lambda p: dict(uid=p.stat().st_uid, gid=p.stat().st_gid, mode=p.stat().st_mode & 0o777)
        self.op['preserved_trees'] = {str(capture):dict(
            directories={'.':meta(capture), 'scripts':meta(scripts)},
            files={'scripts/recurring_node.py':dict(**meta(probe), sha256=hashlib.sha256(probe.read_bytes()).hexdigest())})}
        bundle = self.root/'local-bundle'; runtime = bundle/'runtime'; (runtime/'scripts').mkdir(parents=True)
        for name in ('notification_qualification.py','recurring_delivery.py','recurring_protection.py','capture_retained.py'):
            shutil.copyfile(SCRIPTS/name, runtime/'scripts'/name)
        sender = runtime/'scripts/recurring_delivery.py'
        sender.write_text(sender.read_text().replace(delivery.ENDPOINT, self.endpoint))
        (runtime/'operation.json').write_text(json.dumps(self.op))
        inputs = self.root/'inputs.json'
        inputs.write_text(json.dumps(dict(capture_bundle_verified=True, capture_operation=self.op,
                                         capture_bundle=str(bundle), ansible_become=False)))
        inventory = self.root/'inventory.ini'
        inventory.write_text('[inventory_automation]\nj2-svpi4mf ansible_host=127.0.0.1 ansible_connection=local\n')
        command = ['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
                   shutil.which('ansible-playbook'),'-i',str(inventory),
                   str(ROOT/'Nautobot/ansible/playbooks/qualify-notification.yaml'),'-e','@'+str(inputs)]
        for attempt in range(2):
            result = subprocess.run(command,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240)
            if attempt == 0:
                self.assertEqual(result.returncode, 0, result.stdout[-6000:])
                receipt = json.loads((evidence/'result.json').read_text())
                self.assertTrue(receipt['checks_passed']); self.assertFalse(receipt['accepted'])
            else:
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('File exists', result.stdout)
            self.assertEqual(len(self.requests), 2)
        active = subprocess.check_output(['/usr/bin/systemctl','--user','show',
            'nautobot-notification-qualification.service','--property=ActiveState','--value'],text=True).strip()
        self.assertEqual(active, 'inactive')


if __name__ == '__main__':
    unittest.main()
