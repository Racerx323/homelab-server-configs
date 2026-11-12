#!/usr/bin/env python3
"""Render the real owner schedule task without installing or invoking a job."""
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[2]


class ScheduleTests(unittest.TestCase):
    def test_real_schedule_expression_preserves_transport_and_lock(self):
        tasks = yaml.safe_load((ROOT / 'Needrestart/ansible/enable-schedule.yaml').read_text())
        task = next(t for t in tasks if t['name'] == 'Enable the owner daily schedule with a bounded scan scope')
        with tempfile.TemporaryDirectory(prefix='guarded-schedule-') as name:
            directory = Path(name)
            copy = task['ansible.builtin.copy']
            output = directory / 'cron'
            play = [{'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
                     'vars': {'fleet_server_root': str(ROOT)}, 'tasks': [
                         {'ansible.builtin.copy': {'content': copy['content'], 'dest': str(output), 'mode': '0600'}}]}]
            path = directory / 'render.yaml'
            path.write_text(yaml.safe_dump(play))
            run = subprocess.run(['/bin/bash', str(ROOT / 'tests/repository/run-with-ansible-local-temp.sh'),
                                  'ansible-playbook', '-i', 'localhost,', str(path)],
                                 cwd=ROOT, capture_output=True, text=True, timeout=60)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            text = output.read_text()
            self.assertIn('30 5 * * * root ', text)
            self.assertIn('/usr/bin/flock -n /run/lock/needrestart-check.lock', text)
            self.assertIn('observe-needrestart.py --guard --producer 2>&1', text)
            self.assertIn('RECIPIENT=notify@mailrise.xyz', text)
            self.assertIn('MAILTO=notify.failure@mailrise.xyz', text)
            self.assertNotIn('systemd-run --scope', text)
            self.assertIn('470s', text)
            self.assertIn('exit "$needrestart_cron_status"', text)


if __name__ == '__main__':
    unittest.main()
