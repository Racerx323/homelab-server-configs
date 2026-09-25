#!/usr/bin/env python3
"""Offline native startup, actual Quadlet rendering, gates and cleanup tests."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch
import yaml
from jsonschema import Draft202012Validator, ValidationError
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]



def startup_operation_fixture():
    return {
        'schema_version': 1,
        'operation': {'state': 'definition', 'stage': 'application_startup',
                      'id': 'offline-startup-fixture', 'authorization_ready': True,
                      'target': 'j2-svpi4mf'},
        'prerequisites': {
            'preservation_tag': 'nautobot-startup-preservation-v1-accepted',
            'preservation_commit': 'a' * 40,
            'bootstrap_tag': 'nautobot-administrator-bootstrap-v2-accepted',
            'network_packet_tag': 'nautobot-packet-qualification-accepted'},
        'scope': {'success': 'running_pending_workload_acceptance',
                  'failure': 'stopped_data_retained', 'automatic_restore': False,
                  'reboot': False, 'caddy_publication': False},
        'plan_sha256': 'b' * 64,
    }


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT/'Nautobot/ansible/scripts'/file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


app = load('startup_app', 'startup-application.py')
node = load('startup_node', 'startup-node.py')
preparation = load('startup_preparation', 'prepare-startup.py')
collector = load('startup_collector', 'collect-startup.py')
launcher = load('startup_launcher', 'run-startup.py')
preflight = load('startup_preflight', 'startup-preflight.py')
browser = load('startup_browser', 'startup-browser-probe.py')
network = load('startup_network', 'startup-network-probe.py')
freeze_preservation = load('freeze_preservation', 'freeze-preservation.py')
preservation_runner = load('preservation_runner', 'run-preservation.py')


class Startup(unittest.TestCase):
    def contract(self):
        return {'schema_version': 1, 'checks': [
            {'id': 'check_' + str(index), 'group': group,
             'argv': ['/usr/bin/python3', '/tmp/frozen-probe.py'],
             'timeout_seconds': 10, 'expected': {'healthy': True}}
            for index, group in enumerate(sorted(collector.GROUPS))]}

    def test_job_uses_async_dispatch_and_restores_disabled_flag_on_error(self):
        module = load('startup_job_probe', 'startup-job-probe.py')
        changes = []
        job = types.SimpleNamespace(enabled=False, save=lambda **kw: changes.append(job.enabled))
        calls = []
        def enqueue(**kwargs):
            calls.append(kwargs)
            raise ValueError('fixture broker failure')
        def fake(name, **attrs):
            value = types.ModuleType(name)
            value.__dict__.update(attrs)
            return value
        modules = {name: fake(name) for name in ('django', 'django.contrib', 'nautobot', 'nautobot.core', 'nautobot.extras')}
        modules.update({
            'django.contrib.auth': fake('django.contrib.auth', get_user_model=lambda: types.SimpleNamespace(objects=types.SimpleNamespace(get=lambda **kw: 'fixture-user'))),
            'nautobot.core.celery': fake('nautobot.core.celery', app=types.SimpleNamespace(control=types.SimpleNamespace(inspect=lambda **kw: types.SimpleNamespace(stats=lambda: {'worker': {'pool': {'max-concurrency': 2}}})))),
            'nautobot.extras.models': fake('nautobot.extras.models', Job=types.SimpleNamespace(objects=types.SimpleNamespace(get=lambda **kw: job)), JobResult=types.SimpleNamespace(enqueue_job=enqueue)),
            'nautobot.extras.choices': fake('nautobot.extras.choices', JobResultStatusChoices=types.SimpleNamespace(STATUS_SUCCESS='SUCCESS', EXCEPTION_STATES={'FAILURE'})),
        })
        with patch.dict(sys.modules, modules):
            with self.assertRaisesRegex(ValueError, 'fixture broker failure'):
                module.probe()
        self.assertEqual(changes, [True, False])
        self.assertIs(calls[0]['synchronous'], False)
        self.assertEqual(calls[0]['job_kwargs'], {})

    def test_collector_retains_only_fixed_failure_categories(self):
        contract = self.contract()
        result = collector.collect(contract, lambda *a: (0, json.dumps({'error_class': 'native_receipt_shape', 'raw': 'private'}), '', False))
        self.assertFalse(result['accepted'])
        self.assertEqual(result['checks'][0]['error_class'], 'native_receipt_shape')
        self.assertNotIn('private', json.dumps(result))
        result = collector.collect(contract, lambda *a: (0, json.dumps({'error_class': 'private'}), '', False))
        self.assertNotIn('error_class', result['checks'][0])

    def test_nonzero_probe_retains_only_allowlisted_diagnostics(self):
        result=collector.collect(self.contract(), lambda *a:(69,json.dumps({
            'error_class':'session_timeout','cleanup_error_class':'logout_session_revocation',
            'tunnel_error_class':'private-cookie','raw':'private-password'}),'private-stderr',False))
        row=result['checks'][0]
        self.assertFalse(result['accepted'])
        self.assertEqual(row['error_class'],'session_timeout')
        self.assertEqual(row['cleanup_error_class'],'logout_session_revocation')
        self.assertNotIn('private',json.dumps(result))

    def test_identity_deadline_is_inside_container_and_receipt_is_strict(self):
        with patch.object(browser.subprocess,'run',return_value=types.SimpleNamespace(returncode=142,stdout=b'')) as run:
            with self.assertRaisesRegex(ValueError,'session_timeout'):browser.session_identity('private-cookie')
            args=run.call_args
            self.assertNotIn('private-cookie',str(args.args[0]))
            self.assertIn(b'signal.alarm(60)',args.kwargs['input'])
            self.assertEqual(args.kwargs['timeout'],75)
        with patch.object(browser.subprocess,'run',return_value=types.SimpleNamespace(returncode=0,stdout=b'STARTUP_SESSION_RESULT={"admin":"true"}')):
            with self.assertRaisesRegex(ValueError,'session_receipt_shape'):browser.session_identity('private-cookie')
        # Execute the real timer preamble with a disposable sleeping body.
        preamble=browser.IDENTITY_ENTRYPOINT.split('runpy.run_path')[0].replace('signal.alarm(60)','signal.alarm(1)')
        result=subprocess.run([sys.executable,'-c',preamble+'import time;time.sleep(10)'],timeout=5)
        self.assertEqual(result.returncode,-14)

    def test_probe_preserves_primary_cleanup_and_tunnel_failures(self):
        from contextlib import contextmanager
        @contextmanager
        def healthy():yield 'http://127.0.0.1:1'
        @contextmanager
        def broken():
            yield 'http://127.0.0.1:1'
            raise ValueError('tunnel_cleanup_failed')
        for ctx in (healthy,broken):
            with patch.object(browser,'password',return_value='private-password'), patch.object(browser,'tunnel',ctx), patch.object(browser,'flow',side_effect=browser.SessionFailure('session_timeout','logout_session_revocation')):
                result=browser.probe()
            self.assertEqual(result['error_class'],'session_timeout')
            self.assertEqual(result['cleanup_error_class'],'logout_session_revocation')
            self.assertEqual(result['tunnel_cleanup'],ctx is healthy)
            if ctx is broken:self.assertEqual(result['tunnel_error_class'],'tunnel_cleanup_failed')
            self.assertNotIn('private',json.dumps(result))
        self.assertEqual(browser.safe_error(ValueError('private-password')),'unexpected_session_failure')

    def test_native_receipts_require_exact_steps_and_no_hidden_failure(self):
        check = load('runtime_checks', 'startup-runtime-check.py')
        def rows(value):
            return [{'MESSAGE': 'NAUTOBOT_STARTUP_RESULT='+json.dumps(value)}]
        value = {'role': 'web', 'passed': True, 'steps': {k: {'exit_status': 0, 'output_limited': False}
                 for k in ('configuration', 'pending_migrations', 'static_collection')}}
        check.native_receipt(rows(value), 'web')
        with self.assertRaisesRegex(ValueError, 'native_receipt_count'):
            check.native_receipt(rows(value)*2, 'web')
        value['steps']['configuration']['error'] = 'timeout'
        with self.assertRaisesRegex(ValueError, 'native_failure'):
            check.native_receipt(rows(value), 'web')

    def test_heartbeat_creation_freshness_and_failure_codes(self):
        import time
        check=load('heartbeat_checks','startup-runtime-check.py')
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'heartbeat'
            def status():return subprocess.run([sys.executable,'-c',check.heartbeat_code(),str(path)],capture_output=True,timeout=5).returncode
            self.assertEqual(status(),70)
            path.touch();self.assertEqual(status(),0)
            os.utime(path,(time.time()-65,time.time()-65));self.assertEqual(status(),72)
            os.utime(path,(time.time()+120,time.time()+120));self.assertEqual(status(),73)
            path.unlink();path.symlink_to(Path(directory)/'other');self.assertEqual(status(),74)
            with patch('os.lstat',side_effect=PermissionError('private-path')), patch.object(sys,'argv',['probe','unused']):
                with self.assertRaises(SystemExit) as failure:exec(check.heartbeat_code(),{'__name__':'__main__'})
            self.assertEqual(failure.exception.code,71)

    @unittest.skipUnless(os.environ.get('NAUTOBOT_SOURCE_WHEEL'),'optional pinned producer source test')
    def test_pinned_worker_produces_fresh_file_only_when_enabled(self):
        import ast,zipfile
        check=load('producer_heartbeat_checks','startup-runtime-check.py')
        with zipfile.ZipFile(os.environ['NAUTOBOT_SOURCE_WHEEL']) as archive:
            tree=ast.parse(archive.read('nautobot/core/celery/__init__.py').decode())
        cls=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='LivenessProbe')
        methods=[n for n in cls.body if isinstance(n,ast.FunctionDef) and n.name in ('start','update_worker_heartbeat_file','stop')]
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'heartbeat'
            for enabled in (False,True):
                scope={'settings':types.SimpleNamespace(CELERY_HEALTH_PROBES_AS_FILES=enabled)}
                exec(compile(ast.fix_missing_locations(ast.Module(body=methods,type_ignores=[])),'<pinned-producer>','exec'),scope)
                obj=types.SimpleNamespace(WORKER_HEARTBEAT_FILE=path)
                obj.update_worker_heartbeat_file=lambda parent:scope['update_worker_heartbeat_file'](obj,parent)
                callbacks=[]
                parent=types.SimpleNamespace(timer=types.SimpleNamespace(call_repeatedly=lambda interval,callback,args,**kw:callbacks.append((interval,callback,args))))
                scope['start'](obj,parent)
                self.assertEqual(bool(callbacks),enabled)
                for interval,callback,args in callbacks:
                    self.assertEqual(interval,1.0);callback(*args)
                self.assertEqual(path.exists(),enabled)
                if enabled:
                    result=subprocess.run([sys.executable,'-c',check.heartbeat_code(),str(path)],timeout=5)
                    self.assertEqual(result.returncode,0)
                scope['stop'](obj,parent)
                self.assertFalse(path.exists())

    def test_resource_commands_report_only_fixed_identity_and_status(self):
        check=load('command_diagnostics','startup-runtime-check.py')
        cases=[([sys.executable,'-c','import sys;print("private-secret");sys.exit(70)'],'exit_status',70),
               (['/nonexistent-private-path'],'launch_error',None)]
        for argv,category,rc in cases:
            with self.assertRaises(check.CommandFailure) as failure:check.run(argv,'heartbeat','worker')
            receipt=check.failure_receipt(failure.exception)
            self.assertEqual(receipt['command_failure'],{'command':'heartbeat','role':'worker','category':category,'returncode':rc})
            result=collector.collect(self.contract(),lambda *a:(69,json.dumps(receipt),'private-stderr',False))
            self.assertEqual(result['checks'][0]['command_failure'],receipt['command_failure'])
            self.assertNotIn('private',json.dumps(result))
        with patch.object(check.subprocess,'run',side_effect=subprocess.TimeoutExpired('private',40)):
            with self.assertRaises(check.CommandFailure) as failure:check.run(['ignored'],'container_inspect','redis')
        self.assertEqual(check.failure_receipt(failure.exception)['command_failure']['category'],'timeout')
        for stream in ('stdout','stderr'):
            argv=[sys.executable,'-c',f'import sys;sys.{stream}.write("x"*4194304)']
            with self.assertRaises(check.CommandFailure) as failure:check.run(argv,'container_inspect','web')
            self.assertEqual(failure.exception.diagnostic['category'],'output_limit')
        bad={'command':'private','role':'worker','category':'exit_status','returncode':70}
        result=collector.collect(self.contract(),lambda *a:(69,json.dumps({'command_failure':bad}),'',False))
        self.assertNotIn('command_failure',result['checks'][0])

    def test_cgroup_check_uses_effective_limits_and_oom_events(self):
        check = load('runtime_cgroups', 'startup-runtime-check.py')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory);proc=root/'proc';groups=root/'cgroup'
            (proc/'42').mkdir(parents=True);(groups/'runtime').mkdir(parents=True)
            (proc/'42/cgroup').write_text('0::/runtime\n')
            (groups/'runtime/memory.max').write_text(str(384*1024**2))
            (groups/'runtime/memory.swap.max').write_text('0')
            events=groups/'runtime/memory.events';events.write_text('oom 0\noom_kill 0\n')
            check.cgroup_evidence(42,384,True,proc,groups)
            with self.assertRaisesRegex(ValueError,'effective_memory'):
                check.cgroup_evidence(42,1536,True,proc,groups)
            events.write_text('oom 1\noom_kill 0\n')
            with self.assertRaisesRegex(ValueError,'oom'):
                check.cgroup_evidence(42,384,True,proc,groups)

    def test_startup_operation_requires_recovery_and_forbids_reboot(self):
        value = startup_operation_fixture()
        schema = json.loads((ROOT/'Nautobot/schemas/startup-operation.schema.json').read_text())
        Draft202012Validator(schema).validate(value)
        value['scope']['reboot'] = True
        with self.assertRaises(ValidationError):
            Draft202012Validator(schema).validate(value)
        value['scope']['reboot'] = False
        del value['prerequisites']['preservation_commit']
        with self.assertRaises(ValidationError):
            Draft202012Validator(schema).validate(value)

    def test_preservation_bundle_detects_tampering_and_wrong_authorization(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)/'bundle'
            freeze_preservation.freeze(root)
            digest = (root/'SHA256').read_text().strip()
            self.assertEqual(preservation_runner.verify(root, digest)['stage'], 'startup_database_preservation')
            with self.assertRaisesRegex(ValueError, 'authorization_hash'):
                preservation_runner.verify(root, '0'*64)
            (root/'scripts/inspect-retained-database.py').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'bundle_file'):
                preservation_runner.verify(root, digest)

    def test_preservation_playbook_has_no_service_start_or_restore(self):
        path = ROOT/'Nautobot/ansible/playbooks/preserve-startup-database.yaml'
        play = yaml.safe_load(path.read_text())[0]
        commands = [task['ansible.builtin.command']['argv'] for task in play['pre_tasks'] + play['tasks'] if 'ansible.builtin.command' in task]
        self.assertEqual(len(commands), 2)
        self.assertIn('preserve', commands[-1])
        self.assertNotIn('systemctl', str(commands))
        result = subprocess.run(['/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'), 'ansible-playbook', '--syntax-check', '-i', 'j2-svpi4mf,', str(path)], capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode())

    def test_network_denial_requires_timeout_source_and_family_counter(self):
        before = {'deny-v4': 4, 'deny-v6': 8}
        value = {'outcome': 'timeout', 'source': '10.1.3.83'}
        self.assertTrue(network.denied(value, before, {'deny-v4': 5, 'deny-v6': 8}, 0, '10.1.3.83'))
        self.assertFalse(network.denied({**value, 'outcome': 'error'}, before, {'deny-v4': 5, 'deny-v6': 8}, 0, '10.1.3.83'))
        self.assertFalse(network.denied(value, before, before, 0, '10.1.3.83'))
        self.assertFalse(network.denied(value, before, {'deny-v4': 5, 'deny-v6': 9}, 0, '10.1.3.83'))
        self.assertFalse(network.denied(value, before, {'deny-v4': 5, 'deny-v6': 8}, 0, 'other'))

    def test_browser_redirect_cannot_send_session_to_other_origin(self):
        import urllib.request
        handler = browser.LocalRedirect('http://127.0.0.1:8123')
        request = urllib.request.Request('http://127.0.0.1:8123/login/')
        with self.assertRaisesRegex(ValueError, 'nonlocal_redirect'):
            handler.redirect_request(request, None, 302, 'Found', {}, 'http://external.example/')

    def test_browser_real_http_cookie_csrf_login_and_revocation(self):
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
        from threading import Thread
        from urllib.parse import parse_qs
        active = set()
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def reply(self, status, payload=b'', cookie=None):
                self.send_response(status)
                if cookie: self.send_header('Set-Cookie', cookie)
                self.end_headers(); self.wfile.write(payload)
            def do_GET(self):
                if self.headers.get('Host') != browser.HOST:
                    return self.reply(400)
                if self.path == '/logout/':
                    active.clear(); return self.reply(200)
                self.reply(200, b'<input name="csrfmiddlewaretoken" value="fixture-csrf">', 'csrftoken=fixture-csrf; Path=/')
            def do_POST(self):
                data = parse_qs(self.rfile.read(int(self.headers['Content-Length'])).decode())
                if data.get('csrfmiddlewaretoken') != ['fixture-csrf']:
                    return self.reply(403)
                if self.path == '/login/':
                    if data.get('password') != ['fixture-password']: return self.reply(400)
                    active.add('fixture-session')
                    return self.reply(200, cookie='sessionid=fixture-session; Path=/')
                if self.path == '/logout/':
                    active.clear(); return self.reply(200)
                self.reply(404)
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            result = browser.flow('http://127.0.0.1:' + str(server.server_port), 'fixture-password', lambda cookie: cookie in active)
            self.assertTrue(result['administrator_login_logout'])
            self.assertFalse(active)
            calls=[]
            def failing_identity(cookie):
                calls.append(cookie)
                raise ValueError('session_timeout' if len(calls)==1 else 'session_check_failed')
            with self.assertRaises(browser.SessionFailure) as failure:
                browser.flow('http://127.0.0.1:' + str(server.server_port), 'fixture-password', failing_identity)
            self.assertEqual(failure.exception.primary,'session_timeout')
            self.assertEqual(failure.exception.cleanup,'session_check_failed')
            self.assertEqual(len(calls),2)
            self.assertFalse(active, 'HTTP logout must run after identity failure')
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_baseline_metadata_never_reads_or_hashes_environment_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'postgresql.env').write_text('PASSWORD=do-not-retain')
            (root/'app.py').write_text('pass')
            (root/'alias.env').symlink_to(root/'postgresql.env')
            report = preflight.files(root)
            self.assertNotIn('sha256', report['postgresql.env'])
            self.assertNotIn('PASSWORD', json.dumps(report))
            self.assertFalse(report['alias.env']['regular'])
            self.assertEqual(report['app.py']['sha256'], hashlib.sha256(b'pass').hexdigest())

    def test_collector_executes_all_groups_and_retains_no_payload(self):
        calls = []
        def run(argv, timeout):
            calls.append(argv)
            return 0, b'{"healthy":true,"sensitive":"not retained"}', b'', False
        result = collector.collect(self.contract(), run)
        self.assertTrue(result['accepted'])
        self.assertEqual(len(calls), 7)
        self.assertNotIn('sensitive', json.dumps(result))
        self.assertNotIn('not retained', json.dumps(result))

    def test_collector_rejects_command_errors_truncation_wrong_types_and_bad_json(self):
        for outcome in [(1, b'{"healthy":true}', b'', False),
                        (0, b'{"healthy":true}', b'', True),
                        (0, b'{"healthy":1}', b'', False),
                        (0, b'{"healthy":true} extra', b'', False),
                        (0, b'{}', b'', False)]:
            calls = []
            def run(argv, timeout):
                calls.append(argv)
                return outcome
            self.assertFalse(collector.collect(self.contract(), run)['accepted'])
            self.assertEqual(len(calls), 1)

    def test_collector_validates_whole_contract_before_any_probe(self):
        for mutate in [lambda c: c['checks'].pop(),
                       lambda c: c['checks'][-1].update(timeout_seconds=301),
                       lambda c: c['checks'][-1].update(id=c['checks'][0]['id']),
                       lambda c: c['checks'][-1].update(expected={})]:
            contract = self.contract(); mutate(contract)
            with patch.object(collector, 'run') as runner:
                with self.assertRaises(ValueError):
                    collector.collect(contract, runner)
                runner.assert_not_called()

    def test_launcher_hashes_artifacts_probes_and_recovery_and_rejects_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in launcher.FILES:
                destination = root/name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes((ROOT/name).read_bytes())
            probe = root/'probe.py'; probe.write_text('print("fixture")')
            artifact = root/'web.container'; artifact.write_text('fixture')
            baseline = root/'baseline.json'
            baseline.write_text(json.dumps({'accepted': True, 'host': 'j2-svpi4mf',
                'boot_id': '00000000-0000-0000-0000-000000000000',
                'services': {role: {'ActiveState': 'inactive', 'SubState': 'dead', 'InvocationID': '', 'MainPID': '0', 'ControlPID': '0'}
                             for role in node.ROLES}}))
            recovery = root/'recovery.json'
            recovery.write_text(json.dumps({'accepted': True, 'host': 'j2-svpi4mf'}))
            digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
            contract = self.contract()
            for check in contract['checks']:
                check['argv'] = ['/usr/bin/python3', str(probe)]
            helpers = {name: digest(root/('restic/scripts/' if name == 'canary-backup.py' else 'Nautobot/ansible/scripts/')/name)
                       for name in ('startup-node.py', 'runtime-initialization-node.py', 'canary-backup.py')}
            specification = root/'specification.json'
            specification.write_text(json.dumps({'schema_version': 1, 'host': 'j2-svpi4mf',
                'artifacts': [{'source': str(artifact), 'destination': '/var/lib/nautobot/runtime/test.py', 'sha256': digest(artifact)}],
                'acceptance_contract': contract,
                'baseline': {'path': str(baseline), 'sha256': digest(baseline)},
                'recovery': {'path': str(recovery), 'sha256': digest(recovery)},
                'helper_sha256': helpers, 'probe_files': {str(probe): digest(probe)}}))
            value, before, rows, identity = launcher.prepare(specification, root)
            self.assertEqual(len(identity), 64)
            self.assertIn((digest(probe), 'probe:' + str(probe)), rows)
            probe.write_text('changed')
            with self.assertRaisesRegex(ValueError, 'probe_file_hash'):
                launcher.prepare(specification, root)
            probe.unlink(); probe.symlink_to(artifact)
            with self.assertRaisesRegex(ValueError, 'unsafe_input'):
                launcher.prepare(specification, root)

    def test_launcher_rejects_unapproved_or_inactive_before_ansible(self):
        with patch.object(launcher, 'prepare', return_value=({}, {}, [], 'expected')):
            with patch.object(launcher.subprocess, 'check_output') as command:
                with self.assertRaisesRegex(ValueError, 'authorization_hash'):
                    launcher.execute(Path('/tmp/spec.json'), 'wrong')
                policy = yaml.safe_load((ROOT/'Nautobot/manifests/startup-policy.yaml').read_text())
                operation = startup_operation_fixture()
                with patch.object(launcher.yaml, 'safe_load', side_effect=[{**policy, 'execution_authorized': False}, operation]):
                    with self.assertRaisesRegex(ValueError, 'startup_inactive'):
                        launcher.execute(Path('/tmp/spec.json'), 'expected')
                command.assert_not_called()

    def test_playbook_collects_evidence_instead_of_supplied_acceptance_boolean(self):
        play = yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/start-application.yaml').read_text())[0]
        self.assertNotIn('startup_live_acceptance_verified', str(play))
        tasks = play['tasks'][0]['block']
        names = [task['name'] for task in tasks]
        self.assertLess(names.index('Collect bounded live acceptance evidence on controller'),
                        names.index('Disarm guard after all live evidence passes'))
        self.assertIn('Stage independent stop helpers before arming guard',
                      [task['name'] for task in play['pre_tasks']])

    def test_web_collects_assets_before_exec_without_migrating(self):
        calls = []
        def run(argv, timeout):
            calls.append((argv, timeout))
            return {'exit_status': 0, 'output_limited': False}
        value = app.prepare('web', run, inspect=False)
        self.assertTrue(value['passed'])
        self.assertEqual([x[0][1:] for x in calls], [['check'], ['migrate', '--check'], ['collectstatic', '--noinput']])
        self.assertNotIn('post_upgrade', str(calls))
        self.assertNotIn('createsuperuser', str(calls))

    def test_boot_readiness_never_runs_upgrade(self):
        calls = []
        def run(argv, timeout):
            calls.append((argv, timeout))
            return {'exit_status': 0}
        self.assertTrue(app.prepare('migration', run, inspect=False)['passed'])
        self.assertEqual([x[0][1:] for x in calls], [['check'], ['migrate', '--check']])
        self.assertEqual([x[1] for x in calls], [120, 120])

    def test_each_failure_stops_subsequent_commands(self):
        for role in app.LIMITS:
            total = 3 if role == 'web' else 2
            for fail_at in range(total):
                calls = []
                def run(argv, timeout):
                    calls.append(argv)
                    return {'exit_status': 69 if len(calls) == fail_at + 1 else 0}
                result = app.prepare(role, run, inspect=False)
                self.assertFalse(result['passed'])
                self.assertEqual(len(calls), fail_at + 1)
                self.assertIn('failed_phase', result)

    def test_main_never_execs_server_after_prepare_failure(self):
        with patch.object(sys, 'argv', ['startup', 'web']), patch.object(app, 'prepare', return_value={'passed': False}), patch.object(app.os, 'execvp') as execute:
            self.assertEqual(app.main(), 69)
            execute.assert_not_called()

    def test_all_stop_attempts_survive_first_command_and_state_failure(self):
        calls = []
        def run(argv, timeout):
            calls.append(argv[-1])
            if 'scheduler' in argv[-1]:
                raise RuntimeError('fixture stop failure')
        def inspect(role):
            if role == 'worker':
                raise RuntimeError('fixture inspection failure')
            return {'ActiveState': 'inactive', 'SubState': 'dead', 'MainPID': '0', 'ControlPID': '0'}
        value = node.stop_all(run, inspect)
        self.assertFalse(value['passed'])
        self.assertEqual(calls, ['nautobot-'+role+'.service' for role in node.STOP])
        self.assertTrue(value['stopped']['postgresql'])

    def test_native_command_retains_redacted_failure_and_bounds_timeout(self):
        runner=load('startup_diagnostic_command','startup-command.py')
        secret='fixture-private-credential'
        with patch.dict(os.environ, {'STARTUP_TEST_SECRET':secret}):
            result=runner.command(['/usr/bin/python3','-c',
                'import os,sys;print("configuration E001",file=sys.stderr);print(os.environ["STARTUP_TEST_SECRET"],file=sys.stderr);sys.exit(1)'],5)
        self.assertEqual(result['exit_status'],1)
        self.assertIn('configuration E001',result['diagnostics']['stderr'])
        self.assertNotIn(secret,json.dumps(result))
        self.assertIn('[REDACTED]',result['diagnostics']['stderr'])
        result=runner.command(['/usr/bin/python3','-c','import time;time.sleep(3)'],.1)
        self.assertEqual(result['error'],'timeout')
        self.assertNotIn('diagnostics',runner.command(['/usr/bin/python3','-c','print("ok")'],5))

    def test_failed_unit_cleanup_requires_both_pids_zero_and_retains_failure(self):
        value = {'ActiveState':'failed', 'SubState':'failed', 'MainPID':'0', 'ControlPID':'0'}
        self.assertTrue(node.processless(value))
        self.assertTrue(node.terminal(value))
        for key in ('MainPID','ControlPID'):
            self.assertFalse(node.processless({**value,key:'5'}))
            missing=dict(value);del missing[key]
            self.assertFalse(node.processless(missing))
        result=node.stop_all(lambda *a:None,lambda role:value)
        self.assertTrue(result['passed'])
        self.assertEqual(result['failed_units_retained'],list(node.STOP))
        self.assertFalse(node.processless({**value,'ActiveState':'activating'}))

    def test_retry_baseline_retains_only_reviewed_processless_migration_failure(self):
        state = {'ActiveState':'failed','SubState':'failed','Result':'exit-code',
                 'ExecMainStatus':'69','InvocationID':'retained','MainPID':'0','ControlPID':'0'}
        self.assertTrue(node.baseline_stopped('migration',state))
        self.assertFalse(node.healthy('migration',state))
        for role in ('web','worker','scheduler','postgresql','redis'):
            self.assertFalse(node.baseline_stopped(role,state))
        for key,value in [('MainPID','1'),('ControlPID','1'),('ExecMainStatus','1'),('InvocationID',''),('Result','timeout')]:
            self.assertFalse(node.baseline_stopped('migration',{**state,key:value}))
        play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/start-application.yaml').read_text())[0]
        assertion=next(t for t in play['pre_tasks'] if t['name'].startswith('Require the exact reviewed service state'))
        from jinja2 import Environment
        # Actual Ansible from_json filter, with observed state differing from the frozen review.
        env=Environment();env.filters['from_json']=json.loads
        check=env.compile_expression(assertion['ansible.builtin.assert']['that'])
        before={'migration':state}
        self.assertTrue(check(startup_current_baseline={'stdout':json.dumps({'services':before})},startup_before=before))
        self.assertFalse(check(startup_current_baseline={'stdout':json.dumps({'services':{'migration':{**state,'InvocationID':'different'}}})},startup_before=before))

    def test_reviewed_cleanup_markers_require_exact_processless_failure_shape(self):
        state = {'ActiveState':'failed','SubState':'failed','Result':'exit-code',
                 'ExecMainStatus':'137','InvocationID':'retained','MainPID':'0','ControlPID':'0'}
        for role in ('web','worker','scheduler'):
            self.assertTrue(node.baseline_stopped(role,state))
            self.assertFalse(node.healthy(role,state))
            for key,value in [('MainPID','1'),('ControlPID','1'),('ExecMainStatus','1'),
                              ('InvocationID',''),('Result','timeout')]:
                self.assertFalse(node.baseline_stopped(role,{**state,key:value}))
        for role in ('migration','postgresql','redis'):
            self.assertFalse(node.baseline_stopped(role,state))

    def test_cursor_parser_rejects_ambiguous_or_missing_cursor(self):
        assemble=load('startup_assembly','assemble-startup.py')
        self.assertEqual(assemble.parse_cursor('-- No entries --\n-- cursor: s=abc;i=1\n'),'s=abc;i=1')
        for value in ('', '-- No entries --', '-- cursor: ', '-- cursor: x\n-- cursor: y', '-- cursor: a b'):
            with self.assertRaisesRegex(ValueError,'journal_cursor_shape'):
                assemble.parse_cursor(value)

    def test_service_acceptance_rejects_stale_failed_or_partial_state(self):
        good = {'ActiveState': 'active', 'SubState': 'running', 'Result': 'success', 'ExecMainStatus': '0', 'InvocationID': 'new'}
        self.assertTrue(node.healthy('web', good))
        for key, value in [('Result', 'exit-code'), ('ActiveState', 'activating'), ('InvocationID', ''), ('ExecMainStatus', '1')]:
            self.assertFalse(node.healthy('web', {**good, key: value}))
        self.assertFalse(node.healthy('migration', good))
        self.assertTrue(node.healthy('migration', {**good, 'SubState': 'exited'}))

    def test_policy_requires_boolean_and_exact_bundle_gate(self):
        policy = yaml.safe_load((ROOT/'Nautobot/manifests/startup-policy.yaml').read_text())
        schema = json.loads((ROOT/'Nautobot/schemas/startup-policy.schema.json').read_text())
        Draft202012Validator(schema).validate(policy)
        with self.assertRaises(ValidationError):
            Draft202012Validator(schema).validate({**policy, 'execution_authorized': 'true'})

    def test_actual_ansible_gate_rejects_before_contact(self):
        play = yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/start-application.yaml').read_text())[0]
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)/'gate.yaml'
            p.write_text(yaml.safe_dump([{'hosts': 'j2-svpi4mf', 'gather_facts': False,
                'vars': {'startup_policy': yaml.safe_load((ROOT/'Nautobot/manifests/startup-policy.yaml').read_text()),
                         'startup_operation': {'operation': {'state': 'clean'}}},
                'tasks': play['pre_tasks'][:1]}]))
            result = subprocess.run(['/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'), 'ansible-playbook', '-i', 'j2-svpi4mf,', '-c', 'local', str(p)], capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 2)
            self.assertIn(b'Startup candidate inactive', result.stdout)

    def test_real_ansible_migration_failure_does_not_start_web(self):
        tasks = yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/start-service-tasks.yaml').read_text())
        # Run the actual include loop with a disposable systemctl boundary.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); log = root/'calls'
            stub = root/'systemctl'
            stub.write_text('#!/usr/bin/python3\nimport sys\nfrom pathlib import Path\np=Path('+repr(str(log))+')\np.write_text(p.read_text() + sys.argv[-1] + "\\n" if p.exists() else sys.argv[-1] + "\\n")\nraise SystemExit(1)\n')
            stub.chmod(0o700)
            # Replace only executable transport; preserve production task failure semantics.
            tasks[0]['ansible.builtin.command']['argv'] = [str(stub), '{{ startup_role }}']
            (root/'tasks.yaml').write_text(yaml.safe_dump(tasks))
            play = [{'hosts': 'localhost', 'gather_facts': False, 'tasks': [{'ansible.builtin.include_tasks': 'tasks.yaml', 'loop': ['migration', 'web'], 'loop_control': {'loop_var': 'startup_role'}}]}]
            (root/'play.yaml').write_text(yaml.safe_dump(play))
            result = subprocess.run(['/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'), 'ansible-playbook', '-i', 'localhost,', '-c', 'local', str(root/'play.yaml')], capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(log.read_text(), 'migration\n')

    def test_real_ansible_terminal_readiness_stops_without_retries(self):
        tasks = yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/start-service-tasks.yaml').read_text())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); log = root/'calls'
            stub = root/'state.py'
            stub.write_text('import json,sys\nfrom pathlib import Path\np=Path('+repr(str(log))+')\np.write_text(p.read_text()+"check\\n" if p.exists() else "check\\n")\nprint(json.dumps({"terminal":True}))\nsys.exit(69)\n')
            tasks[0]['ansible.builtin.command']['argv'] = ['/bin/true']
            tasks[1]['ansible.builtin.command']['argv'] = ['/usr/bin/python3',str(stub)]
            (root/'tasks.yaml').write_text(yaml.safe_dump(tasks))
            play = [{'hosts':'localhost','gather_facts':False,'vars':{'startup_controller_evidence':str(root)},'tasks':[{'ansible.builtin.include_tasks':'tasks.yaml','loop':['migration','web'],'loop_control':{'loop_var':'startup_role'}}]}]
            (root/'play.yaml').write_text(yaml.safe_dump(play))
            result = subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','localhost,','-c','local',str(root/'play.yaml')],capture_output=True,timeout=30)
            self.assertEqual(result.returncode,2)
            self.assertEqual(log.read_text(),'check\n')

    def test_exhausted_readiness_preserves_evidence_and_blocks_next_role(self):
        tasks = yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/start-service-tasks.yaml').read_text())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); log = root/'calls'
            stub = root/'state.py'
            stub.write_text('import json,sys\nfrom pathlib import Path\np=Path('+repr(str(log))+')\np.write_text(p.read_text()+"check\\n" if p.exists() else "check\\n")\nprint(json.dumps({"terminal":False}))\nsys.exit(69)\n')
            tasks[0]['ansible.builtin.command']['argv'] = ['/bin/true']
            tasks[1]['ansible.builtin.command']['argv'] = ['/usr/bin/python3',str(stub)]
            tasks[1]['retries'] = 0
            (root/'tasks.yaml').write_text(yaml.safe_dump(tasks))
            play = [{'hosts':'localhost','gather_facts':False,'vars':{'startup_controller_evidence':str(root)},'tasks':[{'ansible.builtin.include_tasks':'tasks.yaml','loop':['migration','web'],'loop_control':{'loop_var':'startup_role'}}]}]
            (root/'play.yaml').write_text(yaml.safe_dump(play))
            result = subprocess.run(['/bin/bash',str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),'ansible-playbook','-i','localhost,','-c','local',str(root/'play.yaml')],capture_output=True,timeout=30)
            self.assertEqual(result.returncode,2)
            self.assertEqual(log.read_text(),'check\n')
            self.assertEqual(json.loads((root/'readiness-migration.json').read_text()),{'terminal':False})

    def test_native_phase_progress_contains_no_command_output(self):
        phases = []
        result = app.prepare('web',runner=lambda *_:{'exit_status':0,'output_limited':False},
                             inspect=False,report=phases.append)
        self.assertTrue(result['passed'])
        self.assertEqual([p['state'] for p in phases],['started','completed']*3)
        self.assertEqual([p['phase'] for p in phases[::2]],
                         ['configuration','pending_migrations','static_collection'])
        self.assertTrue(all(set(p)=={'role','invocation','phase','state','elapsed_seconds'} for p in phases))

    def test_current_invocation_native_receipt_is_required(self):
        calls = []
        def query(argv):
            calls.append(argv)
            return ''
        value = node.native_status('web', 'a'*32, query)
        self.assertFalse(value['passed']); self.assertFalse(value['terminal'])
        self.assertIn('CONTAINER_NAME=nautobot-web', calls[0])
        self.assertIn('_UID=999', calls[0])
        steps = {key: {'exit_status':0,'output_limited':False} for key in
                 ('configuration','pending_migrations','static_collection')}
        receipt = {'role':'web','passed':True,'steps':steps,'invocation':'a'*32}
        row = json.dumps({'MESSAGE':'NAUTOBOT_STARTUP_RESULT='+json.dumps(receipt)})
        self.assertTrue(node.native_status('web','a'*32,lambda _:row)['passed'])
        self.assertTrue(node.native_status('web','a'*32,lambda _:row+'\n'+row)['terminal'])
        receipt['steps']['configuration']['exit_status'] = 1
        row = json.dumps({'MESSAGE':'NAUTOBOT_STARTUP_RESULT='+json.dumps(receipt)})
        self.assertTrue(node.native_status('web','a'*32,lambda _:row)['terminal'])

    def test_journal_receipts_exclude_prior_invocations_and_attached_duplicates(self):
        steps={k:{'exit_status':0,'output_limited':False} for k in
               ('configuration','pending_migrations','static_collection')}
        def row(invocation):
            return {'MESSAGE':'NAUTOBOT_STARTUP_RESULT='+json.dumps(
                {'role':'web','passed':True,'steps':steps,'invocation':invocation})}
        rows=[row('b'*32),row('a'*32)]
        check=load('runtime_receipt_restart','startup-runtime-check.py')
        check.native_receipt(rows,'web','a'*32)
        raw='\n'.join(json.dumps(x) for x in rows)
        self.assertTrue(node.native_status('web','a'*32,lambda _:raw)['passed'])
        self.assertFalse(node.native_status('web','c'*32,lambda _:raw)['passed'])
        with self.assertRaisesRegex(ValueError,'native_receipt_count'):
            check.native_receipt(rows+[row('a'*32)],'web','a'*32)
        # Only CONTAINER_NAME journal records are queried: attached service output
        # lacks that field and cannot be counted as a duplicate receipt.
        calls=[]
        node.native_status('web','a'*32,lambda argv:calls.append(argv) or raw)
        self.assertIn('CONTAINER_NAME=nautobot-web',calls[0])

    def test_readiness_waits_for_native_then_http_and_rejects_restart(self):
        state = {'ActiveState':'active','SubState':'running','Result':'success',
                 'ExecMainStatus':'0','InvocationID':'a'*32}
        with patch.object(node,'http_checks') as unused:
            result = node.readiness('web',lambda _:state,
                lambda *_:{'passed':False,'terminal':False},unused)
            self.assertFalse(result['passed']); unused.assert_not_called()
        for good in (False,True):
            result = node.readiness('web',lambda _:state,
                lambda *_:{'passed':True,'terminal':False},lambda:{'passed':good})
            self.assertEqual(result['passed'],good)
        states = iter([state,{**state,'InvocationID':'b'*32}])
        result = node.readiness('worker',lambda _:next(states),
            lambda *_:{'passed':True,'terminal':False})
        self.assertFalse(result['passed'])
        self.assertEqual(result['reason'],'service_changed_during_probe')

    def test_http_failures_are_classified_without_response_content(self):
        for error, expected in [
            (node.urllib.error.URLError(ConnectionRefusedError('private text')), 'connection_refused'),
            (TimeoutError('private text'), 'timeout'),
            (node.urllib.error.HTTPError('private-url',503,'private text',{},None), 'http_status')]:
            opener = types.SimpleNamespace(open=lambda *a, **k: None)
            with patch.object(opener,'open',side_effect=error):
                result = node.http_checks(opener)
            self.assertFalse(result['passed'])
            self.assertEqual(result['details']['health']['error'],expected)
            self.assertNotIn('private',json.dumps(result))

    def test_diagnostic_runs_only_native_check_and_redacts_inside_container(self):
        diagnostic = load('diagnostic', 'diagnose-startup-configuration.py')
        inputs = {'image':'localhost/test@sha256:'+'a'*64,'identity':'test'}
        def state(role):
            if role in ('postgresql','redis'):
                return {'ActiveState':'active','SubState':'running','Result':'success','ExecMainStatus':'0','InvocationID':'new'}
            return {'ActiveState':'failed','SubState':'failed','MainPID':'0','ControlPID':'0'}
        response = types.SimpleNamespace(returncode=0,stdout=b'{"exit_status":1,"diagnostics":{"stderr":"E001"}}')
        with patch.object(diagnostic,'containers',return_value=[]), patch.object(diagnostic.node,'service',side_effect=state), patch.object(diagnostic.subprocess,'run',return_value=response) as run:
            value = diagnostic.check(inputs)
        self.assertTrue(value['passed']);self.assertFalse(value['configuration_passed'])
        argv = run.call_args.args[0];payload=run.call_args.kwargs['input'].decode()
        self.assertIn("command(['nautobot-server','check'],120)",payload)
        self.assertNotIn('post_upgrade',payload)
        self.assertIn('def redact(',payload)
        self.assertIn('--read-only',argv)
        self.assertIn('--pull',argv)

    def test_diagnostic_does_not_remove_foreign_probe(self):
        diagnostic = load('diagnostic_cleanup','diagnose-startup-configuration.py')
        with patch.object(diagnostic,'containers',return_value=[{'Id':'x','Names':[diagnostic.NAME]}]), patch.object(diagnostic.node.base,'podman',return_value=[{'Config':{'Labels':{diagnostic.LABEL:'foreign'}}}]), patch.object(diagnostic.node.base,'call') as call:
            with self.assertRaisesRegex(ValueError,'foreign_container'):
                diagnostic.cleanup({'identity':'ours'})
            call.assert_not_called()

    def test_archived_baseline_review_records_logging_delta_and_preserves_storage(self):
        original_read = Path.read_text
        def fixture_read(path, *args, **kwargs):
            if path == ROOT/'Nautobot/manifests/operation.yaml':
                return 'schema_version: 1\noperation: {state: clean, authorization_ready: false}\n'
            return original_read(path, *args, **kwargs)
        with tempfile.TemporaryDirectory() as directory, patch.object(Path, 'read_text', fixture_read):
            report = preparation.prepare(Path(directory)/'rendered')
            self.assertFalse(report['execution_authorized'])
            for name in ('nautobot-postgresql.container', 'nautobot-redis.container'):
                delta=report['artifact_changes'][name]
                rendered=(Path(directory)/'rendered'/name).read_text()
                self.assertIn('LogDriver=journald\n',rendered)
                self.assertEqual(hashlib.sha256(rendered.replace('LogDriver=journald\n','').encode()).hexdigest(),delta['before_sha256'])
                self.assertNotEqual(delta['before_sha256'],delta['after_sha256'])
            for name in ('nautobot-postgresql_data.volume','nautobot-redis_data.volume','nautobot-private.network'):
                self.assertIn(name,report['unchanged_existing_units'])
            self.assertNotEqual(report['artifact_changes']['nautobot-migration.container']['before_sha256'], report['artifact_changes']['nautobot-migration.container']['after_sha256'])
            with self.assertRaises(FileExistsError):
                preparation.prepare(Path(directory)/'rendered')

    def test_media_recovery_and_wrapper_render(self):
        desired = yaml.safe_load((ROOT/'Nautobot/manifests/desired-state.yaml').read_text())
        inputs = json.loads((ROOT/'Nautobot/manifests/runtime-inputs.json').read_text())
        files = preparation.render.render(desired, inputs)
        for role in ('migration', 'web', 'worker', 'scheduler'):
            text = files['nautobot-'+role+'.container']
            self.assertIn('nautobot-nautobot_media.volume:/opt/nautobot/media', text)
            self.assertIn('Exec=/run/startup-application.py '+role, text)
            self.assertIn('ReadOnly=true', text)
            self.assertNotIn('CONTINUATION_TOKEN', text)
            self.assertIn('Tmpfs=/prom_cache:rw,size=16m,mode=1777,noexec,nosuid,nodev', text)
            self.assertIn('Environment=PROMETHEUS_MULTIPROC_DIR=/prom_cache', text)
            self.assertIn('Environment=prometheus_multiproc_dir=/prom_cache', text)
            self.assertNotIn('Volume=/prom_cache', text)
        for role in ('postgresql', 'redis'):
            self.assertNotIn('/prom_cache', files['nautobot-'+role+'.container'])
        self.assertIn('PublishPort=127.0.0.1:8080:8080', files['nautobot-web.container'])
        self.assertIn('User=999', files['nautobot-nautobot_media.volume'])
        verifier = 'ExecStartPre=/usr/bin/sudo -n /usr/bin/python3 -I /usr/local/lib/nautobot-network/backend_guard.py check'
        self.assertIn(verifier, files['nautobot-web.container'])
        for role in ('postgresql', 'redis', 'migration', 'worker', 'scheduler'):
            self.assertNotIn(verifier, files['nautobot-'+role+'.container'])

    def test_network_handoff_matches_owner_source_and_stays_inactive(self):
        handoff = yaml.safe_load((ROOT/'Nautobot/manifests/startup-network-handoff.yaml').read_text())
        source = yaml.safe_load((ROOT/handoff['source_reference']).read_text())
        expected = {node['management_fqdn'].split('.')[0]: [node['ipv4'], node['ipv6']]
                    for node in source['nodes'].values()}
        self.assertEqual(handoff['allowed_sources'], expected)
        self.assertFalse(handoff['execution_authorized'])
        self.assertEqual(handoff['state'], 'packet_qualification_accepted_startup_pending')
        self.assertTrue(handoff['accepted_backend_guard']['accepted'])
        self.assertTrue(handoff['accepted_backend_guard']['packet_qualification_accepted'])
        self.assertTrue(handoff['accepted_primary_route']['accepted'])
        self.assertFalse(handoff['primary_preparation']['execution_ready'])
        self.assertFalse(handoff['backend_guard_preparation']['execution_ready'])
        self.assertTrue(handoff['backend_guard_preparation']['fresh_preflight_performed'])
        self.assertEqual(handoff['accepted_standby_route']['scope'], 'standby_preferred_source_route_only')
        self.assertNotIn('10.1.0.56', str(handoff['allowed_sources']))

    def test_playbook_syntax(self):
        result = subprocess.run(['/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'), 'ansible-playbook', '--syntax-check', '-i', 'j2-svpi4mf,', str(ROOT/'Nautobot/ansible/playbooks/start-application.yaml')], capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout.decode()+result.stderr.decode())


if __name__ == '__main__':
    unittest.main(verbosity=2)
