#!/usr/bin/env python3
"""Single-dispatch and real Ansible failure/recovery boundaries, no target contact."""
import copy
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import yaml

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT/'Nautobot/ansible/scripts'
sys.path.insert(0, str(SCRIPTS))


def module(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS/(name+'.py'))
    obj = importlib.util.module_from_spec(spec); spec.loader.exec_module(obj)
    return obj


bundle = module('reboot-bundle')
node = module('reboot-node')


class RebootTests(unittest.TestCase):
    def test_durable_intent_is_exclusive_and_requires_comparison(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError):
                bundle.arm(root)
            for name in ('before', 'drain-before', 'logical-before', 'logical-before-verified'):
                (root/(name+'.json')).write_text(json.dumps({'equal': True}))
            bundle.arm(root)
            self.assertEqual((root/'reboot-intent.json').stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                bundle.arm(root)

    def test_native_gate_rejects_stale_failed_or_duplicate_receipts(self):
        invocation = 'a'*32
        receipt = {'role': 'migration', 'invocation': invocation, 'passed': True,
                   'steps': {k: {'exit_status': 0, 'output_limited': False} for k in ('configuration', 'pending_migrations')}}
        def raw(value):
            return json.dumps({'MESSAGE': 'NAUTOBOT_STARTUP_RESULT='+json.dumps(value)})
        self.assertTrue(node.native_receipt(raw(receipt), 'migration', invocation)['passed'])
        for data in (raw({**receipt, 'invocation': 'b'*32}), raw({**receipt, 'passed': False}), raw(receipt)+'\n'+raw(receipt)):
            with self.assertRaises(ValueError):
                node.native_receipt(data, 'migration', invocation)

    def test_readiness_timeout_does_not_control_services(self):
        with patch.object(node, 'running', side_effect=ValueError('not_ready')) as observe, \
                patch.object(node.time, 'monotonic', side_effect=[0, 1, 601]), patch.object(node.time, 'sleep'), patch.object(node.p, 'save'):
            with self.assertRaisesRegex(ValueError, 'automatic_startup_timeout'):
                node.observe(Path('/unused'), {})
            self.assertEqual(observe.call_count, 1)

    def test_changed_identity_is_rejected(self):
        with patch.object(node.p.logical_database, 'compare', return_value={'equal': False}):
            with self.assertRaisesRegex(ValueError, 'logical_identity_changed'):
                node.compare({}, {})

    def test_unchanged_boot_cannot_pass_automatic_observation(self):
        with patch.object(node.p, 'verify_artifacts'), patch.object(node, 'healthy'), \
                patch.object(node.p.node, 'snapshot', return_value={'boot_id': 'same'}):
            with self.assertRaisesRegex(ValueError, 'boot_identity'):
                node.running(Path('/unused'), {'boot_id': 'same'}, postboot=True)

    def test_frozen_contract_rejects_tampering_and_execution_before_activation(self):
        from datetime import datetime, timezone
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); repo = root/'repo'; repo.mkdir()
            for source in bundle.FILES.values():
                target = repo/source; target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT/source, target)
            logical = root/'logical.json'; logical.write_text('{}')
            accepted_path = repo/'Nautobot/manifests/accepted-live-state.yaml'
            accepted = yaml.safe_load(accepted_path.read_text())
            accepted['recovery_preservation']['logical_before_sha256'] = bundle.sha(logical)
            accepted_path.write_text(yaml.safe_dump(accepted))
            (repo/'Nautobot/manifests/operation.yaml').write_text('operation: {state: clean}\n')
            op = {'schema_version': 1, 'operation': {'state': 'definition', 'stage': 'reboot_persistence',
                  'id': 'nautobot-reboot-persistence-v1', 'target': 'j2-svpi4mf',
                  'authorization_ready': False, 'source_commit': 'a'*40},
                  'plan_sha256': bundle.sha(repo/bundle.FILES['PLAN.md']),
                  'accepted_state_sha256': bundle.sha(accepted_path), 'ci_success_commit': None,
                  'root': '/tmp/nautobot-reboot.'+'a'*32, 'token': 'a'*32,
                  'baseline_collected_at': datetime.now(timezone.utc).isoformat(),
                  'boot_id': '00000000-0000-4000-8000-000000000000',
                  'artifact_sha256': {'/var/lib/nautobot/runtime/nautobot_config.py': 'b'*64},
                  'app_image_id': 'sha256:'+'c'*64,
                  'image_ids': {r: 'sha256:'+'c'*64 for r in node.p.node.ROLES},
                  'expected_kernel': 'fixture', 'preserved_logical_sha256': bundle.sha(logical),
                  'snapshot_id': accepted['recovery_preservation']['snapshot_id'],
                  'boundaries': json.loads((repo/bundle.FILES['schema.json']).read_text())['properties']['boundaries']['const']}
            operation = root/'op.json'; operation.write_text(json.dumps(op))
            with patch.object(bundle, 'ROOT', repo):
                identity = bundle.freeze(operation, root/'bundle', logical)
                bundle.verify(root/'bundle', identity, executing=False)
                with self.assertRaisesRegex(ValueError, 'inactive_operation'):
                    bundle.verify(root/'bundle', identity)
                (root/'bundle/recovery_probe.py').write_text('modified')
                with self.assertRaisesRegex(ValueError, 'bundle_drift'):
                    bundle.verify(root/'bundle', identity, executing=False)

    def test_ansible_failure_boundaries(self):
        # Replace external side effects only. Execute the actual block/always and
        # include structure through Ansible, including its real failed-task routing.
        ansible = shutil.which('ansible-playbook')
        self.assertIsNotNone(ansible)
        source = ROOT/'Nautobot/ansible/playbooks'
        for failed, expected_reboot, expected_resumes in (
                ('Collect logical-before', False, True),
                ('Collect automatic', True, False),
                ('Collect logical-after', True, True),
                ('Request exactly one reboot', True, True),
                ('start writers', True, True)):
            with self.subTest(failed=failed), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); trace = root/'trace'
                script = root/'command.py'
                script.write_text('import sys\nfrom pathlib import Path\n'
                    'name=sys.argv[2]; item=sys.argv[3]\n'
                    'with Path(sys.argv[1]).open("a") as s:s.write(name+":"+item+"\\n")\n'
                    'raise SystemExit(1 if name==sys.argv[4] else 0)\n')
                def rewrite(tasks):
                    rows = []
                    for original in tasks:
                        t = copy.deepcopy(original)
                        if 'block' in t:
                            t['block'] = rewrite(t['block']); t['always'] = rewrite(t['always'])
                        elif t.get('ansible.builtin.include_tasks') == 'reboot-quiesce.yaml':
                            pass
                        elif 'ansible.builtin.set_fact' in t:
                            pass
                        elif 'ansible.builtin.meta' in t:
                            continue
                        else:
                            name = t['name']
                            old = t
                            t = {k: v for k, v in old.items() if k in ('name', 'loop', 'when', 'register', 'failed_when', 'ignore_unreachable', 'changed_when')}
                            t['ansible.builtin.command'] = {'argv': [sys.executable, str(script), str(trace), name, '{{ item | default("") }}', failed]}
                        rows.append(t)
                    return rows
                play = yaml.safe_load((source/'reboot-persistence.yaml').read_text())[0]
                play['hosts'] = 'localhost'; play['become'] = False; play['pre_tasks'] = []
                play['tasks'] = rewrite(play['tasks'])
                (root/'play.yaml').write_text(yaml.safe_dump([play], sort_keys=False))
                quiesce = rewrite(yaml.safe_load((source/'reboot-quiesce.yaml').read_text()))
                (root/'reboot-quiesce.yaml').write_text(yaml.safe_dump(quiesce, sort_keys=False))
                result = subprocess.run([ansible, '-i', 'localhost,', '-c', 'local', str(root/'play.yaml')],
                    cwd=root, capture_output=True, text=True, timeout=90)
                observed = trace.read_text()
                self.assertIn(failed+':', observed, result.stdout+result.stderr)
                self.assertEqual('Request exactly one reboot:' in observed, expected_reboot, observed)
                for role in ('worker', 'web', 'scheduler'):
                    self.assertEqual('start writers:'+role in observed, expected_resumes, observed)
                self.assertLessEqual(observed.count('Request exactly one reboot:'), 1)


if __name__ == '__main__':
    unittest.main()
