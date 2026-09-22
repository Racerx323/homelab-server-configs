#!/usr/bin/env python3
"""Offline native startup, actual Quadlet rendering, gates and cleanup tests."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import yaml
from jsonschema import Draft202012Validator, ValidationError
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT/'Nautobot/ansible/scripts'/file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


app = load('startup_app', 'startup-application.py')
node = load('startup_node', 'startup-node.py')
preparation = load('startup_preparation', 'prepare-startup.py')


class Startup(unittest.TestCase):
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

    def test_repeatable_migration_native_sequence_and_bounds(self):
        calls = []
        def run(argv, timeout):
            calls.append((argv, timeout))
            return {'exit_status': 0}
        self.assertTrue(app.prepare('migration', run, inspect=False)['passed'])
        self.assertEqual([x[0][1:] for x in calls], [['check'], ['post_upgrade'], ['migrate', '--check']])
        self.assertEqual([x[1] for x in calls], [120, 1800, 120])

    def test_each_failure_stops_subsequent_commands(self):
        for role in app.LIMITS:
            total = 3 if role in ('web', 'migration') else 2
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
            return {'ActiveState': 'inactive', 'SubState': 'dead'}
        value = node.stop_all(run, inspect)
        self.assertFalse(value['passed'])
        self.assertEqual(calls, ['nautobot-'+role+'.service' for role in node.STOP])
        self.assertTrue(value['stopped']['postgresql'])

    def test_service_acceptance_rejects_stale_failed_or_partial_state(self):
        good = {'ActiveState': 'active', 'SubState': 'running', 'Result': 'success', 'ExecMainStatus': '0', 'InvocationID': 'new'}
        self.assertTrue(node.healthy('web', good))
        for key, value in [('Result', 'exit-code'), ('ActiveState', 'activating'), ('InvocationID', ''), ('ExecMainStatus', '1')]:
            self.assertFalse(node.healthy('web', {**good, key: value}))
        self.assertFalse(node.healthy('migration', good))
        self.assertTrue(node.healthy('migration', {**good, 'SubState': 'exited'}))

    def test_inactive_policy_rejects_activation(self):
        policy = yaml.safe_load((ROOT/'Nautobot/manifests/startup-policy.yaml').read_text())
        schema = json.loads((ROOT/'Nautobot/schemas/startup-policy.schema.json').read_text())
        Draft202012Validator(schema).validate(policy)
        with self.assertRaises(ValidationError):
            Draft202012Validator(schema).validate({**policy, 'execution_authorized': True})

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

    def test_archived_baseline_review_preserves_database_units(self):
        with tempfile.TemporaryDirectory() as directory:
            report = preparation.prepare(Path(directory)/'rendered')
            self.assertFalse(report['execution_authorized'])
            self.assertIn('nautobot-postgresql.container', report['unchanged_existing_units'])
            self.assertIn('nautobot-redis.container', report['unchanged_existing_units'])
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
        self.assertEqual(handoff['state'], 'proxy_routes_accepted_backend_guard_pending')
        self.assertTrue(handoff['accepted_primary_route']['accepted'])
        self.assertFalse(handoff['primary_preparation']['execution_ready'])
        self.assertFalse(handoff['backend_guard_preparation']['execution_ready'])
        self.assertFalse(handoff['backend_guard_preparation']['fresh_preflight_performed'])
        self.assertEqual(handoff['accepted_standby_route']['scope'], 'standby_preferred_source_route_only')
        self.assertNotIn('10.1.0.56', str(handoff['allowed_sources']))

    def test_playbook_syntax(self):
        result = subprocess.run(['/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'), 'ansible-playbook', '--syntax-check', '-i', 'j2-svpi4mf,', str(ROOT/'Nautobot/ansible/playbooks/start-application.yaml')], capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout.decode()+result.stderr.decode())


if __name__ == '__main__':
    unittest.main(verbosity=2)
