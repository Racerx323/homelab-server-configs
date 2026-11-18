#!/usr/bin/env python3
"""Execute the real parent's Ansible block/always flow with synthetic owner adapters.

This tests sequencing, not backend/Caddy acceptance or host capacity. No browser,
SSH or service operation is executed. Native owner components have separate tests.
"""
import base64
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[2]


class ParentFlow(unittest.TestCase):
    def test_evidence_admission_before_target_contact(self):
        original = yaml.safe_load((ROOT / 'Webmin/ansible/proxy-combined-trial.yaml').read_text())[0]
        tasks = original['tasks']
        admission = next(t for t in tasks if t.get('name') == 'Admit private controller evidence storage before any target contact')
        self.assertLess(tasks.index(admission), next(i for i, t in enumerate(tasks) if t.get('name') == 'Check native host identity without accepting historical boot IDs'))
        for case in ('missing', 'file', 'symlink', 'public', 'read-only', 'valid'):
            with self.subTest(case=case), tempfile.TemporaryDirectory(prefix='webmin-admission-') as name:
                root = Path(name); evidence = root / 'evidence'; reached = root / 'target-reached'
                if case == 'file': evidence.write_text('preserve')
                elif case == 'symlink': evidence.symlink_to(root, target_is_directory=True)
                elif case != 'missing':
                    mode = {'public': 0o755, 'read-only': 0o500}.get(case, 0o700)
                    evidence.mkdir(mode=mode)
                    # The private test wrapper's umask must not erase this test input.
                    evidence.chmod(mode)
                play = [{'hosts': 'localhost', 'connection': 'local', 'become': False, 'gather_facts': False,
                         'vars': {'fleet_server_root': str(ROOT), 'operation_evidence_directory': str(evidence)},
                         'tasks': [admission, {'ansible.builtin.copy': {'dest': str(reached), 'content': 'reached', 'mode': '0600'}}]}]
                path = root / 'play.yaml'; path.write_text(yaml.safe_dump(play, sort_keys=False))
                run = subprocess.run(['/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
                                      'ansible-playbook', '-i', 'localhost,', str(path)], cwd=ROOT,
                                     capture_output=True, text=True, timeout=30)
                self.assertIn('TASK [Admit private controller evidence storage', run.stdout, run.stdout + run.stderr)
                self.assertEqual(run.returncode == 0, case == 'valid', run.stdout + run.stderr)
                self.assertEqual(reached.exists(), case == 'valid')
                if case == 'valid': self.assertEqual(list(evidence.iterdir()), [])
                if case == 'missing': self.assertFalse(evidence.exists())
                if case == 'file': self.assertEqual(evidence.read_text(), 'preserve')

    def test_primary_only_success_and_failure(self):
        self.check_scenarios(('diagnostic-primary-success', 'diagnostic-primary-caddy-fail', 'diagnostic-primary-paths-fail'))

    def test_owner_failure_and_cleanup_order(self):
        self.check_scenarios(('success', 'diagnostic-success', 'diagnostic-caddy-fail', 'diagnostic-clock-before-fail', 'diagnostic-clock-after-fail', 'diagnostic-coverage-fail', 'snapshot-fail', 'paths-fail', 'workload-fail', 'caddy-fail', 'cleanup-unverified'))

    def check_scenarios(self, scenarios):
        original = yaml.safe_load((ROOT / 'Webmin/ansible/proxy-combined-trial.yaml').read_text())[0]
        parent = next(t for t in original['tasks'] if t.get('name') == 'Run the temporary owner stages')
        for scenario in scenarios:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory(prefix='webmin-parent-flow-') as name:
                directory = Path(name); directory.chmod(0o700)
                trace = directory / 'trace'; fixture = directory / 'adapter.py'
                fixture.write_text('''import json,os,pathlib,sys,time,tempfile,shutil
os.umask(0o077)
root=pathlib.Path(sys.argv[1]); scenario=sys.argv[2]; phase=sys.argv[3]
with (root/'trace').open('a') as f:f.write(phase+'\\n')
if scenario=='diagnostic-'+phase+'-fail':raise SystemExit(1)
if phase=='resource':
 (root/'resource-ready').write_text('ready')
 (root/'resource-samples.jsonl').write_text('{}')
 (root/'backend-wire.jsonl').write_text('{}')
if phase=='snapshot' and scenario=='snapshot-fail':raise SystemExit(1)
if phase=='workload':
 (root/'workload-result.json').write_text(json.dumps({'browser_cleanup':{'group_gone':scenario!='cleanup-unverified'}}))
 raise SystemExit(1 if scenario in ('workload-fail','cleanup-unverified') else 0)
if phase=='paths' and scenario in ('paths-fail','diagnostic-primary-paths-fail'):raise SystemExit(1)
if phase=='caddy':
 if scenario.startswith('diagnostic-primary-'):
  with (root/'trace').open('a') as f:f.write('caddy-restored\\n')
  raise SystemExit(1 if scenario.endswith('-fail') else 0)
 if scenario in ('caddy-fail', 'diagnostic-caddy-fail'):raise SystemExit(1)
 target=pathlib.Path(__import__('subprocess').check_output(['mktemp','-d','/tmp/caddy-ssh-evidence-serving_health.XXXXXX'],text=True).strip())
 try:
  (target/'application-trial-ready.tsv').write_text('fixture-child\\n')
  print('application_trial_ready='+str(target/'application-trial-ready.tsv'),flush=True)
  until=time.monotonic()+12
  while time.monotonic()<until and not (target/'application-trial-finish.tsv').exists():time.sleep(.1)
  with (root/'trace').open('a') as f:f.write('caddy-restored\\n')
  raise SystemExit(0 if (target/'application-trial-finish.tsv').exists() else 1)
 finally:shutil.rmtree(target)
''')
                def command(phase):
                    return {'ansible.builtin.command': {'argv': ['/usr/bin/python3', str(fixture), name, scenario, phase]}, 'changed_when': False}
                block = copy.deepcopy(parent)
                replacements = {'proxy-trial.yaml': 'backend', 'proxy-path-trial.yaml': 'paths', 'proxy-trial-restore.yaml': 'backend-restore'}
                def adapt(tasks):
                    for index, task in enumerate(tasks):
                        if 'ansible.builtin.import_tasks' in task:
                            tasks[index] = command(replacements[task['ansible.builtin.import_tasks']]); continue
                        if task.get('name') == 'Stage the existing collector before the diagnostic observation':
                            tasks[index] = command('stage-collector'); continue
                        if task.get('name') == 'Retain bounded backend resource evidence before native restoration':
                            task['block'][0]['ansible.builtin.command'] = command('snapshot')['ansible.builtin.command']
                        clock_phases = {'Capture bounded pre-operation clock uncertainty on the selected hosts': 'clock-before',
                                        'Capture bounded post-operation clock uncertainty': 'clock-after',
                                        'Require request coverage within the observed resource interval': 'coverage'}
                        if task.get('name') in clock_phases:
                            task['ansible.builtin.command'] = command(clock_phases[task['name']])['ansible.builtin.command']
                        if task.get('name') == 'Start bounded diagnostic resource sampling before Caddy activation':
                            task['ansible.builtin.command'] = command('resource')['ansible.builtin.command']
                        if task.get('name') == 'Supervise the single observer and private statistics client':
                            task['ansible.builtin.command'] = command('workload')['ansible.builtin.command']
                        for key in ('block', 'always', 'rescue'):
                            if key in task: adapt(task[key])
                adapt([block])
                caddy = directory / 'caddy.sh'
                caddy.write_text('#!/bin/bash\nexec /usr/bin/python3 '+str(fixture)+' '+name+' '+scenario+' caddy\n')
                variables = {'fleet_server_root': str(ROOT), 'operation_evidence_directory': name,
                             'proxy_trial': {'work_directory': name, 'diagnostic_only': scenario.startswith('diagnostic-'), 'primary_ipv4': scenario.startswith('diagnostic-primary-'), 'workload_result': str(directory/'workload-result.json')},
                             'proxy_caddy': {'argv': ['/bin/bash', str(caddy)], 'environment': {}},
                             'ansible_async_dir': str(directory/'async')}
                acceptance = copy.deepcopy(next(t for t in original['tasks'] if t.get('name') == 'Require paired Caddy completion and unchanged boot continuity'))
                acceptance['block'][0] = {'ansible.builtin.set_fact': {'proxy_trial_boot_after': {'content': 'fixture'}}}
                variables['proxy_trial_boot'] = {'content': 'fixture'}
                play = [{'hosts': 'localhost', 'connection': 'local', 'become': False, 'gather_facts': False,
                         'vars': variables, 'tasks': [copy.deepcopy(next(t for t in original['tasks'] if t.get('name') == 'Admit private controller evidence storage before any target contact')), block, acceptance]}]
                path = directory / 'play.yaml'; path.write_text(yaml.safe_dump(play, sort_keys=False))
                run = subprocess.run(['/bin/bash', str(ROOT/'tests/repository/run-with-ansible-local-temp.sh'),
                                      'ansible-playbook', '-i', 'localhost,', str(path)], cwd=ROOT,
                                     capture_output=True, text=True, timeout=60)
                self.assertTrue(trace.exists(), run.stdout + run.stderr)
                observed = trace.read_text().splitlines()
                self.assertEqual(run.returncode == 0, scenario in ('diagnostic-primary-success', 'success', 'diagnostic-success', 'snapshot-fail'), run.stdout + run.stderr)
                self.assertEqual(observed[0], 'backend')
                self.assertEqual(observed[-1], 'backend-restore', run.stdout + run.stderr)
                self.assertLess(observed.index('snapshot'), observed.index('backend-restore'))
                self.assertTrue((directory/'backend-before-restoration.json').is_file())
                if scenario.startswith('diagnostic-'): self.assertNotIn('workload', observed)
                if scenario == 'diagnostic-clock-before-fail': self.assertNotIn('caddy', observed)
                if scenario == 'paths-fail': self.assertNotIn('caddy', observed)
                if scenario in ('success', 'snapshot-fail', 'workload-fail', 'cleanup-unverified'):
                    self.assertLess(observed.index('workload'), observed.index('caddy-restored'))
                    self.assertLess(observed.index('caddy-restored'), observed.index('backend-restore'))
                outcomes = json.loads((directory/'parent-owner-outcomes.json').read_text())
                if scenario == 'cleanup-unverified': self.assertNotEqual(outcomes['caddy_finish'], 0)
                if scenario == 'diagnostic-primary-paths-fail':
                    self.assertNotIn('caddy', observed)
                    self.assertNotIn('coverage', observed)
                    expected = {'coverage_accepted': False, 'proxy_request': 'not-run', 'reason': 'caddy-not-started'}
                    self.assertEqual(outcomes['diagnostic_coverage'], expected)
                    self.assertEqual(json.loads((directory/'diagnostic-coverage.json').read_text()), expected)


if __name__ == '__main__': unittest.main()
