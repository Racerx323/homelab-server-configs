#!/usr/bin/env python3
"""Fault tests for the actual node adapter's immutable bounds and finalizers."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]/'ansible/scripts'
sys.path.insert(0, str(SCRIPTS))
import restore_node as node


class NodeTests(unittest.TestCase):
    def test_command_timeout_and_output_bound(self):
        with self.assertRaisesRegex(node.Blocked, 'command_timeout'):
            node.bounded(['/usr/bin/sleep', '30'], timeout=.1)
        with self.assertRaisesRegex(node.Blocked, 'command_output_bound'):
            node.bounded(['/usr/bin/python3', '-c', 'print("x"*10000)'], maximum=100)

    def test_named_failure_does_not_disclose_stderr(self):
        with self.assertRaisesRegex(node.Blocked, "^production_http_health_command_exit_7$"):
            node.bounded(["/usr/bin/python3", "-c", "import sys; print('synthetic-private-value', file=sys.stderr); sys.exit(7)"], label="production_http_health")
        with self.assertRaisesRegex(node.Blocked, "diagnostic_label"):
            node.bounded(["/usr/bin/true"], label="unsafe value")

    def test_supervised_helpers_bind_working_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime = object.__new__(node.Restore)
            runtime.root = Path(directory); runtime.token = 'nautobot-restore-'+'a'*24
            runtime.unit = runtime.token+'-guard.service'
            runtime.spec = {'restic_helper':'/tmp/application-restore.py'}
            commands = []
            def execute(argv, **kwargs):
                commands.append(argv)
                (runtime.root/'guard.json').write_text('{}')
                return b''
            with patch.object(runtime, 'sample'), patch.object(runtime, 'production', return_value={}), patch.object(runtime, 'active'), patch.object(node, 'bounded', side_effect=execute):
                runtime.arm()
                runtime.retrieve()
            self.assertEqual(len(commands), 2)
            for argv in commands:
                self.assertIn('--property=WorkingDirectory='+directory, argv)

    def test_command_defaults_cover_staging_and_finalization(self):
        import yaml
        play = yaml.safe_load((SCRIPTS.parent/'playbooks/restore-application.yaml').read_text())[0]
        self.assertEqual(play['module_defaults']['ansible.builtin.command']['chdir'],
                         '{{ "/var/lib/nautobot" if restore_context == "target" else "/" }}')
        def visit(tasks):
            for task in tasks:
                if 'ansible.builtin.command' in task:
                    self.assertNotIn('chdir', task['ansible.builtin.command'])
                    self.assertNotIn('module_defaults', task)
                for key in ('block', 'always', 'rescue'):
                    visit(task.get(key, []))
        visit(play['tasks'])
        visit(yaml.safe_load((SCRIPTS.parent/'playbooks/restore-stage.yaml').read_text()))

    def test_stop_latch_interrupts_command(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root/'stopped.json').write_text('{}')
            with self.assertRaisesRegex(node.Blocked, 'guard_stopped'):
                node.bounded(['/usr/bin/sleep', '30'], root=root)

    def test_sampler_rejects_low_memory_before_podman(self):
        runtime = object.__new__(node.Restore); runtime.spec = {'context':'disposable'}
        with patch.object(Path, 'read_text', return_value='MemAvailable: 10 kB\n'), patch.object(node.subprocess, 'run') as run:
            with self.assertRaisesRegex(node.Blocked, 'memory_floor'): runtime.sample()
            run.assert_not_called()

    def test_independent_cleanup_refuses_foreign_container_and_volume(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime = object.__new__(node.Restore)
            runtime.root = Path(directory); runtime.token = 'nautobot-restore-'+'a'*24
            runtime.volume = runtime.token+'-data'
            (runtime.root/'application.env').write_text('synthetic'); (runtime.root/'application.env').chmod(0o600)
            # A symlink must not prevent cleanup of the other credentials.
            (runtime.root/'postgresql.env').symlink_to(runtime.root/'outside')
            commands = []
            def bounded(argv, **kwargs):
                commands.append(argv)
                if argv[1:3] == ['volume', 'inspect']: return b'[{"Labels":{}}]'
                raise AssertionError('unexpected_mutation')
            class Exists: returncode = 0
            with patch.object(node.subprocess, 'run', return_value=Exists()), patch.object(node, 'bounded', side_effect=bounded), patch.object(runtime, 'inspect', return_value={'Config':{'Labels':{}}}):
                with self.assertRaisesRegex(node.Blocked, 'cleanup_incomplete'): runtime.cleanup()
            result = json.loads((runtime.root/'cleanup-result.json').read_text())
            self.assertFalse(result['volume']); self.assertFalse(result['application'])
            self.assertFalse(result['postgresql.env']); self.assertTrue(result['application.env'])
            self.assertTrue((runtime.root/'stopped.json').exists())
            self.assertFalse(any('rm' in command for command in commands))

    def test_terminal_latch_prevents_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime = object.__new__(node.Restore); runtime.root = Path(directory)
            (runtime.root/'stopped.json').write_text('{}')
            with self.assertRaisesRegex(node.Blocked, 'terminal_restore'): runtime.active()

    def test_stale_host_monitor_is_not_health(self):
        runtime = object.__new__(node.Restore)
        runtime.spec = {'context':'target'}; runtime.token = 'nautobot-restore-'+'a'*24
        class Info: st_uid = 0
        with patch.object(Path, 'is_symlink', return_value=False), patch.object(Path, 'stat', return_value=Info()), patch.object(Path, 'exists', return_value=False), patch.object(Path, 'read_text', return_value=json.dumps({'passed':True,'monotonic':0})):
            with self.assertRaisesRegex(node.Blocked, 'host_monitor_stale'): runtime.host_health()

    def test_container_caps_sum_to_approved_budget(self):
        self.assertEqual(sum(node.CPU.values()), 2)
        self.assertEqual(sum(node.MEMORY.values()), 1920)


if __name__ == '__main__': unittest.main()
