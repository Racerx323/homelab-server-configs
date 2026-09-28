#!/usr/bin/env python3
"""Rootless binding and durable-producer tests, without production access."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import secrets
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS=Path(__file__).resolve().parents[1]/'ansible/scripts'
sys.path.insert(0,str(SCRIPTS))
import recurring_delivery as delivery
import recurring_node as node
import recurring_protection as protection
import workload_capture as historical


class Bindings(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='nautobot-recurring.')
        self.root=Path(self.tmp.name);self.root.chmod(0o700)
    def tearDown(self): self.tmp.cleanup()

    def credential_contract(self, fail=False):
        token=self.root/'token';token.write_text('dp.st.'+secrets.token_hex(20));token.chmod(0o600)
        program=self.root/'doppler'
        program.write_text('#!/usr/bin/python3\n'+'''import json,os,pathlib,sys
assert os.environ['DOPPLER_TOKEN'].startswith('dp.st.')
assert os.environ['HOME'].startswith('''+repr(str(self.root))+''')
assert '--token' not in sys.argv and 'DOPPLER_TOKEN' not in sys.argv
assert sys.argv[sys.argv.index('--config')+1]=='prd_nautobot_backup'
assert '--plain' in sys.argv and 'get' in sys.argv
'''+("sys.exit(7)\n" if fail else "print('disposable-'+sys.argv[-2])\n"))
        program.chmod(0o700)
        return dict(project='homelab-dev',config='prd_nautobot_backup',read_only=True,
                    expires_at='2099-01-01T00:00:00+00:00',token_file=str(token),doppler=str(program))

    def test_named_secrets_isolated_environment_protected_files(self):
        delivery.resolve(self.credential_contract(),self.root)
        for name in ('source-password','source-credentials.json'):
            protection.protected(self.root/name)
        self.assertEqual(set(json.loads((self.root/'source-credentials.json').read_text())),{'id','key'})
        self.assertEqual(list(self.root.glob('doppler-runtime.*')),[])

    def test_provider_failure_has_no_partial_or_fallback_credentials(self):
        with self.assertRaises(ValueError): delivery.resolve(self.credential_contract(True),self.root)
        self.assertFalse((self.root/'source-password').exists())
        self.assertFalse((self.root/'source-credentials.json').exists())

    def test_expired_token_rejected_before_provider(self):
        contract=self.credential_contract();contract['expires_at']='2020-01-01T00:00:00+00:00'
        with self.assertRaises(ValueError): delivery.resolve(contract,self.root)

    def test_durable_pending_transition_retries_same_id_then_recovery(self):
        sent=[]
        def unavailable(contract,payload): sent.append(dict(payload));return False
        self.assertFalse(delivery.notify(self.root,'failure',{},sender=unavailable))
        original=sent[0]
        def available(contract,payload): sent.append(dict(payload));return True
        self.assertTrue(delivery.notify(self.root,'recovery',{},sender=available))
        self.assertEqual(original,sent[1]);self.assertNotEqual(sent[1]['event_id'],sent[2]['event_id'])
        self.assertEqual(sent[2]['transition'],'failure -> recovery')
        self.assertTrue(delivery.notify(self.root,'recovery',{},sender=available));self.assertEqual(len(sent),3)
        self.assertNotIn('delivered',json.loads((self.root/'notification.json').read_text()))

    def test_direct_http_uses_standard_format_and_no_redirect(self):
        from http.server import BaseHTTPRequestHandler, HTTPServer
        import threading
        requests=[]
        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                requests.append((self.path,json.loads(self.rfile.read(int(self.headers['Content-Length']))),self.headers['Idempotency-Key']))
                self.send_response(200);self.end_headers()
            def log_message(self,*args): pass
        server=HTTPServer(('127.0.0.1',0),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            endpoint=f'http://127.0.0.1:{server.server_port}/notify/apprise'
            contract=dict(method='direct_apprise',endpoint=endpoint,hostname='test-node',fqdn='test-node.invalid')
            with patch.object(delivery,'ENDPOINT',endpoint):
                self.assertTrue(delivery.notify(self.root,'failure',contract))
                self.assertTrue(delivery.notify(self.root,'recovery',contract))
            self.assertEqual(len(requests),2)
            self.assertTrue(requests[0][1]['title'].startswith('🚨 [Nautobot]'))
            self.assertTrue(requests[1][1]['title'].startswith('✅ [Nautobot]'))
            for path,message,event_id in requests:
                self.assertEqual(path,'/notify/apprise')
                for section in ('Summary','Impact','Details','Next step'): self.assertIn(section,message['body'])
                self.assertIn(event_id,message['body']);self.assertEqual(message['format'],'text')
                self.assertNotIn('HA and network',message['body'])
        finally: server.shutdown();server.server_close();thread.join()

    def test_notification_failure_preserves_pending_and_backup_state(self):
        protection.atomic(self.root/'state.json',dict(phase='complete',last_success=1))
        with patch.object(delivery,'send_direct',return_value=False):
            self.assertFalse(delivery.notify(self.root,'failure',{},sender=lambda c,p:False))
        self.assertEqual(json.loads((self.root/'state.json').read_text())['phase'],'complete')
        self.assertIsNotNone(json.loads((self.root/'notification.json').read_text())['pending'])

    def test_inactive_production_binding_and_rendered_notifier(self):
        from test_recurring_protection import renderer
        config=node.supervisor_binding('/var/lib/nautobot/protection/binding.json',self.root,
                                       '/var/lib/nautobot/protection/scripts','/usr/bin/ansible-playbook')
        self.assertFalse(config['execution_authorized'])
        self.assertEqual([a[-1] for a in config['resume_commands']],['worker','web','scheduler'])
        # Activate only a disposable rendering fixture, never the candidate manifest.
        config['execution_authorized']=True
        path=self.root/'supervisor.json';protection.atomic(path,config)
        units=renderer.render(path,SCRIPTS/'recurring_protection.py')
        self.assertIn('OnSuccess=nautobot-protection-notification.service',units['nautobot-protection.service'])
        self.assertIn('OnUnitActiveSec=15min',units['nautobot-protection-notification.timer'])
        self.assertNotIn('OnFailure=',units['nautobot-protection-notification.service'])
        self.assertNotIn('notify/apprise',units['nautobot-protection.service'])
        unitdir=self.root/'units';unitdir.mkdir()
        for name,text in units.items(): (unitdir/name).write_text(text)
        import subprocess
        result=subprocess.run(['/usr/bin/systemd-analyze','--user','verify',*[str(unitdir/n) for n in units]],capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr.decode())

    def test_scrub_admission_is_fail_closed(self):
        for state in (b'active\n',b'activating\n',b'failed\n',b''):
            with patch.object(node,'bounded',return_value=state):
                with self.assertRaisesRegex(ValueError,'filesystem_scrub_not_idle'): node.scrub_idle()
        with patch.object(node,'bounded',return_value=b'inactive\n'): node.scrub_idle()

    def test_stopped_writers_reject_external_database_clients(self):
        rows={'nautobot-'+r+'.service':{'ActiveState':'active' if r in ('postgresql','redis') else 'inactive'} for r in node.ROLES}
        with patch.object(node,'states',return_value=rows),patch.object(node,'bounded',return_value=b'1\n'):
            with self.assertRaisesRegex(ValueError,'other_database_clients_present'): node.stopped()
        with patch.object(node,'states',return_value=rows),patch.object(node,'bounded',return_value=b'0\n'):
            node.stopped()

    def test_historical_root_execution_unchanged(self):
        self.assertEqual(historical.USER[0],'/usr/sbin/runuser');self.assertEqual(node.capture.USER,[])
        self.assertEqual(node.capture.command(['pg_dump'])[0],'/usr/bin/podman')

    def test_prepare_orders_snapshot_metadata_before_credentials(self):
        cfg=dict(artifact_sha256={},minimum_free_bytes=1,maximum_retained_bytes=1000000,
                 image_ids={r:'sha256:abc' for r in node.ROLES},versions={'nautobot':'3.2.3'},
                 metadata_files={},credentials={},capture_limits={n:1024 for n in node.capture.SECTIONS if n!='validate_dump'},
                 producer=str(SCRIPTS.parents[2]/'restic/scripts/application-backup.py'),
                 backup_template=dict(schema_version=1,operation_id='placeholder',authorized=False,repository_id='a'*64,
                    restic='/usr/bin/restic',restic_version='reviewed',repository_url='local:test',hostname='j2-svpi4mf',
                    captures={},dump_validator=['/bin/true'],source_consistency_reviewed=False,timeout_seconds=100,
                    execution_uid=999,required_filesystem='reviewed'))
        for name in ('desired-state.yaml','requirements.lock','qualified-image.json'):
            path=self.root/('source-'+name);path.write_text('nonsecret')
            cfg['metadata_files'][name]=dict(path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        def pod(argv,**kwargs):
            return b'abc' if argv[0]=='inspect' else json.dumps(cfg['versions']).encode()
        def resolve(contract,root):
            self.assertTrue((root/'recurring-before.json').exists())
        with patch.object(node,'scrub_idle'),patch.object(node,'health',return_value={}),patch.object(node,'media_directories',return_value=[]),patch.object(
                node.capture,'reviewed_files',return_value={}),patch.object(node,'pod',side_effect=pod),patch.object(node,'resolve',side_effect=resolve):
            node.prepare(self.root/'binding.json',cfg,self.root)
        inputs=json.loads((self.root/'inputs.json').read_text())
        self.assertEqual([x[-2:] for x in inputs['application_pause_commands'][:2]],[['stop','scheduler'],['stop','web']])
        self.assertEqual(inputs['application_pause_commands'][2][-1],'drain')
        self.assertEqual(inputs['application_pause_commands'][3][-2:],['stop','worker'])
        self.assertEqual([x[-1] for x in inputs['application_resume_commands']],['worker','web','scheduler'])
        spec=json.loads((self.root/'application-backup.json').read_text())
        self.assertEqual(spec['operation_id'],'nautobot-recurring');self.assertEqual(spec['execution_uid'],999)


if __name__=='__main__': unittest.main()
