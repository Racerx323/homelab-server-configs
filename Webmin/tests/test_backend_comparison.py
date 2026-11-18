#!/usr/bin/env python3
"""Local deadline, process cleanup and evidence gates; no target capacity claims."""
import copy
import importlib.util
import multiprocessing
from pathlib import Path
import time
import json
import sys
import tempfile
import subprocess
import os
import unittest
from unittest.mock import patch
import yaml

ROOT = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('comparison', ROOT/'scripts/compare-backend.py')
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
LIMITS = {u: {'memory.high': '100', 'memory.max': '200', 'memory.swap.max': '0'}
          for u in ('webmin.service', 'uptime-kuma.service')}


def success(*args):
    return {'accepted': True, 'timing': {'request_id': __import__('secrets').token_hex(16)}}


def stalled(*args):
    # Multiple successful blocking stages must still share one five-second budget.
    time.sleep(3)
    time.sleep(3)
    return {'accepted': True}


class Comparison(unittest.TestCase):
    def state(self):
        return {'boot_id': 'same', 'available_kib': 200*1024, 'request_connections': 0,
                'processes': {u: [[i+10, 100]] for i, u in enumerate(LIMITS)},
                'cgroups': {u: {'identity': [1, i], 'limits': value,
                               'memory.events': 'low 0\nhigh 0\nmax 0\noom 0\noom_kill 0\n'}
                            for i, (u, value) in enumerate(LIMITS.items())}}

    def test_single_and_three_clean_up_actual_workers(self):
        previous = {p.pid for p in multiprocessing.active_children()}
        with patch.object(c.probe, 'probe', success):
            for count in (1, 3):
                result = c.batch(count, 'unused', 'unused', 'unused')
                self.assertTrue(result['accepted'])
                self.assertEqual(len(result['requests']), count)
                self.assertTrue(result['owned_clients_reaped'])
        self.assertEqual({p.pid for p in multiprocessing.active_children()}, previous)

    def test_one_total_deadline_and_no_retry(self):
        with patch.object(c.probe, 'probe', stalled):
            start = time.monotonic()
            result = c.batch(3, 'unused', 'unused', 'unused')
        self.assertFalse(result['accepted'])
        self.assertLess(time.monotonic()-start, 7)
        self.assertEqual(len(result['requests']), 3)
        self.assertTrue(all(r['failure'] == 'TimeoutError' for r in result['requests']))
        self.assertFalse(multiprocessing.active_children())

    def test_unapproved_counts_reject(self):
        for count in (0, 2, 4, 5, None):
            with self.assertRaises(ValueError): c.batch(count, '', '', '')

    def test_resource_and_continuity_stops(self):
        base = self.state(); c.healthy(base, base, LIMITS)
        for mutation in ('reserve', 'boot', 'pid', 'limit', 'high', 'max', 'oom', 'oom_kill'):
            row = copy.deepcopy(base)
            if mutation == 'reserve': row['available_kib'] = 96*1024-1
            elif mutation == 'boot': row['boot_id'] = 'changed'
            elif mutation == 'pid': row['processes']['webmin.service'] = [[10, 101]]
            elif mutation == 'limit': row['cgroups']['webmin.service']['limits']['memory.max'] = '300'
            else:
                item = row['cgroups']['webmin.service']
                item['memory.events'] = item['memory.events'].replace(mutation+' 0', mutation+' 1')
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                c.healthy(base, row, LIMITS)

    def test_socket_close_alone_is_not_quiescence(self):
        base = self.state(); row = copy.deepcopy(base)
        self.assertTrue(c.quiescent(row, base))
        row['processes']['webmin.service'].append([99, 200])
        self.assertFalse(c.quiescent(row, base))
        self.assertFalse(c.quiescent(row, row))
        row = copy.deepcopy(base); row['request_connections'] = 1
        self.assertFalse(c.quiescent(row, base))

    def test_wire_overlap_must_be_observed(self):
        receipt = {'count': 3, 'requests': [{'timing': {'request_id': str(i)}} for i in range(3)]}
        rows = [{'event': 'request-headers', 'flow': i, 'request_id': str(i), 'kernel_epoch': 10+i/10}
                for i in range(3)]
        rows += [{'event': 'response-first-byte', 'flow': i, 'kernel_epoch': 11+i/10} for i in range(3)]
        self.assertTrue(c.assess_wire(rows, receipt)['overlap'])
        for invalid in [rows[:-1], rows+[{'terminal': True, 'issues': ['gap']}], rows+[rows[0]]]:
            with self.assertRaises(ValueError): c.assess_wire(invalid, receipt)
        rows[3]['kernel_epoch'] = 10.05
        with self.assertRaises(ValueError): c.assess_wire(rows, receipt)

    def test_parent_has_no_caddy_dispatch_and_fixed_request_plan(self):
        data = yaml.safe_load((ROOT/'ansible/backend-comparison.yaml').read_text())
        parent = next(t for t in data[0]['tasks'] if t.get('name') == 'Run the backend owner with unconditional restoration')
        loop = next(t['loop'] for t in parent['block'] if t.get('ansible.builtin.include_tasks') == 'backend-comparison-phase.yaml')
        self.assertEqual([v['count'] for v in loop], [1, 3, 1])
        self.assertEqual([p['tags'] for p in data], [['comparison-forward'], ['comparison-recovery']])
        self.assertIn('proxy-trial-restore.yaml', str(data[1]))
        self.assertNotIn('proxy_caddy', str(data))
        self.assertNotIn('authorization-ready', str(data))

    def test_supervisor_runs_recovery_after_failure_and_timeout(self):
        for forward in ('pass', 'fail', 'stall'):
            with self.subTest(forward=forward), tempfile.TemporaryDirectory() as name:
                directory = Path(name)
                code = ("import sys,time; from pathlib import Path; "
                        "phase=sys.argv[-1]; "
                        "Path(sys.argv[1],phase).write_text('started'); "
                        "time.sleep(30 if phase=='comparison-forward' and sys.argv[2]=='stall' else 0); "
                        "sys.exit(1 if phase=='comparison-forward' and sys.argv[2]=='fail' else 0)")
                before = time.monotonic()
                result = c.supervise([sys.executable, '-c', code, name, forward], directory, 3, 3)
                self.assertLess(time.monotonic()-before, 6)
                self.assertTrue((directory/'comparison-recovery').exists())
                self.assertEqual(result['processes_succeeded'], forward == 'pass')
                self.assertFalse(result['accepted'])  # No target recovery receipt from this command stub.
                self.assertEqual(result['forward']['timed_out'], forward == 'stall')

    def test_recovery_stall_has_its_own_aggregate_cutoff(self):
        with tempfile.TemporaryDirectory() as name:
            result = c.supervise([sys.executable, '-c',
                "import sys,time; time.sleep(30 if sys.argv[-1]=='comparison-recovery' else 0)"], name, 3, 3)
            self.assertFalse(result['accepted'])
            self.assertTrue(result['recovery']['timed_out'])

    def test_client_stop_latch_rejects_late_dispatch(self):
        with tempfile.TemporaryDirectory() as name:
            with patch.object(c.probe, 'probe', success):
                self.assertTrue(c.client_control(name, 1)['accepted'])
            self.assertTrue(c.client_control(name)['owned_clients_reaped'])
            with self.assertRaisesRegex(ValueError, 'client_stop_latched'):
                c.client_control(name, 1)

    def test_stop_waits_for_owned_batch_and_prevents_next_batch(self):
        with tempfile.TemporaryDirectory() as name:
            def active_request(*args):
                (Path(name)/'request-started').touch()
                return stalled(*args)
            def run():
                with patch.object(c.probe, 'probe', active_request):
                    c.client_control(name, 3)
            child=multiprocessing.get_context('fork').Process(target=run)
            child.start()
            try:
                until=time.monotonic()+2
                while not (Path(name)/'request-started').exists() and time.monotonic()<until:
                    time.sleep(0.01)
                self.assertTrue((Path(name)/'request-started').exists())
                self.assertTrue(c.client_control(name)['stop_latched'])
                child.join(2)
                self.assertFalse(child.is_alive())
                with self.assertRaisesRegex(ValueError,'client_stop_latched'):
                    c.client_control(name,1)
            finally:
                if child.is_alive(): child.kill()
                child.join()

    def terminal_fixture(self, directory):
        state = self.state()
        (directory/'comparison-baseline.json').write_text(json.dumps(state))
        (directory/'observer-exited.json').write_text(json.dumps({'observer_exited':True}))
        samples = [dict(epoch=100+i, monotonic=10+i, boot_id='same', comparison=state) for i in range(8)]
        samples.append(dict(epoch=108, monotonic=18, terminal=True, reason='stop'))
        wire = []
        headers = dict(host='webmin-j2-svpi3bmf.local.theama.co',
            **{'x-forwarded-host':'webmin-j2-svpi3bmf.local.theama.co',
               'x-forwarded-proto':'https','x-forwarded-for':'10.1.0.53',
               'accept':'*/*','accept-encoding':'identity','user-agent':'homelab-proxy-diagnostic','connection':'close'})
        for phase, ids in [('baseline',[0]),('concurrent',[1,2,3]),('recovery-control',[4])]:
            (directory/(phase+'.json')).write_text(json.dumps(dict(count=len(ids), accepted=True,
                owned_clients_reaped=True, requests=[dict(timing=dict(request_id=str(i))) for i in ids])))
            for i in ids:
                start = 101 if i == 0 else 105 if i == 4 else 103+i/10
                for event, stamp in [('request-headers',start),('response-first-byte',start+0.8)]:
                    wire.append(dict(event=event,flow=i,request_id=str(i),headers=headers,
                                     kernel_epoch=stamp,observed_boottime=stamp-90))
        wire.sort(key=lambda r: r['kernel_epoch'])
        wire.append(dict(terminal=True,issues=[],kernel_drops=0))
        def save(rows, path):
            (directory/path).write_text(''.join(json.dumps(r)+'\n' for r in rows))
        save(samples,'resource-samples.jsonl'); save(wire,'backend-wire.jsonl')
        return samples,wire,save

    def test_terminal_rejects_incomplete_confounded_or_uncovered_evidence(self):
        with tempfile.TemporaryDirectory() as name:
            directory=Path(name)
            samples,wire,save=self.terminal_fixture(directory)
            self.assertTrue(c.terminal_evidence(directory,LIMITS)['accepted'])
            for mutation in ('missing_terminal','drops','header','unknown_request','out_of_window','nan'):
                rows=copy.deepcopy(wire)
                if mutation=='missing_terminal': rows.pop()
                elif mutation=='drops': rows[-1]['kernel_drops']=1
                elif mutation=='header': rows[0]['headers']['user-agent']='unexpected'
                elif mutation=='unknown_request': rows[0]['request_id']='other'
                elif mutation=='out_of_window': rows[0]['kernel_epoch']=99
                else: rows[0]['kernel_epoch']=float('nan')
                save(rows,'backend-wire.jsonl')
                with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                    c.terminal_evidence(directory,LIMITS)
            save(wire,'backend-wire.jsonl')
            for mutation in ('sample_gap','clock_step','oom','lost_process','missing_sample','missing_terminal','boot'):
                rows=copy.deepcopy(samples)
                if mutation=='sample_gap': rows=rows[:1]+rows[4:]
                elif mutation=='clock_step': rows[2]['epoch']+=2
                elif mutation=='oom': rows[2]['comparison']['cgroups']['webmin.service']['memory.events']='oom 1'
                elif mutation=='lost_process': rows[2]['comparison']['processes']['webmin.service']=[]
                elif mutation=='missing_sample': rows[2].pop('comparison')
                elif mutation=='boot': rows[2]['boot_id']='changed'
                else: rows.pop()
                save(rows,'resource-samples.jsonl')
                with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                    c.terminal_evidence(directory,LIMITS)

    def test_actual_ansible_recovery_control_flow(self):
        # Native service writes are substituted; the actual task graph, command,
        # fetch, error propagation and independent recovery invocation execute.
        import base64
        import shutil
        if not shutil.which('ansible-playbook'): self.skipTest('ansible-playbook unavailable')
        for scenario in ('pass', 'client-fail', 'restore-fail', 'evidence-fail', 'cancelled'):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as name:
                root=Path(name); backend=root/'backend'; primary=root/'primary'; evidence=root/'evidence'
                for d in (backend,primary,evidence): d.mkdir(mode=0o700)
                self.terminal_fixture(backend)
                (backend/'comparison-limits.json').write_text(json.dumps(LIMITS))
                (backend/'resource-ready').touch()
                (backend/'observer-owner.json').write_text(json.dumps({'process':[99999999,0]}))
                (backend/'state.json').write_text(json.dumps({'phase':'prepared'}))
                if scenario=='evidence-fail': (backend/'backend-wire.jsonl').write_text('bad json\n')
                for f in ('compare-backend.py','probe-proxy-path.py'):
                    shutil.copyfile(ROOT/'scripts'/f, primary/f)
                    shutil.copyfile(ROOT/'scripts'/f, backend/f)
                if scenario=='client-fail': (primary/'compare-backend.py').write_text('raise SystemExit(1)\n')
                phase='cancelled' if scenario=='cancelled' else 'restored'
                (backend/'recover-proxy.py').write_text(
                    "from pathlib import Path; import json\n"
                    f"p=Path({str(backend)!r}); (p/'restore-attempted').touch()\n"+
                    ("raise SystemExit(1)\n" if scenario=='restore-fail' else
                     f"(p/'state.json').write_text(json.dumps({{'phase':{phase!r}}}))\n"))
                tasks=root/'ansible'; tasks.mkdir()
                for source in ('backend-comparison.yaml','backend-comparison-phase.yaml',
                               'proxy-trial.yaml','proxy-trial-restore.yaml'):
                    shutil.copyfile(ROOT/'ansible'/source,tasks/source)
                restore=yaml.safe_load((tasks/'proxy-trial-restore.yaml').read_text())
                disarm=restore[-1]
                self.assertEqual(disarm['ansible.builtin.systemd_service'],
                                 {'name':'webmin-proxy-recovery.timer','state':'stopped'})
                del disarm['ansible.builtin.systemd_service']
                disarm['ansible.builtin.command']={'argv':['/usr/bin/touch',str(root/'timer-disarmed')]}
                (tasks/'proxy-trial-restore.yaml').write_text(yaml.safe_dump(restore,sort_keys=False))
                boot=base64.b64encode(Path('/proc/sys/kernel/random/boot_id').read_bytes()).decode()
                (evidence/'admission.json').write_text(json.dumps(dict(primary_boot=boot,backend_boot=boot)))
                inventory=root/'inventory'
                inventory.write_text('[webmin_trial]\nbackend ansible_connection=local ansible_become=false\n'
                                     '[proxies]\nproxy-a ansible_connection=local ansible_become=false\n'
                                     '[all:vars]\nansible_python_interpreter=/usr/bin/python3\n')
                variables=root/'vars.json'
                variables.write_text(json.dumps(dict(fleet_server_root=str(ROOT.parent),
                    operation_evidence_directory=str(evidence),
                    proxy_trial=dict(work_directory=str(backend)),
                    comparison=dict(primary_directory=str(primary)))))
                env=dict(os.environ,ANSIBLE_LOCAL_TEMP=str(root/'runtime'),ANSIBLE_NOCOLOR='1')
                run=subprocess.run(['ansible-playbook',str(tasks/'backend-comparison.yaml'),
                    '-i',str(inventory),'-e','@'+str(variables),'--tags','comparison-recovery'],
                    env=env,capture_output=True,text=True,timeout=45)
                self.assertTrue((backend/'restore-attempted').exists(),run.stdout+run.stderr)
                self.assertEqual(run.returncode==0,scenario in ('pass','cancelled'),run.stdout+run.stderr)
                self.assertEqual((root/'timer-disarmed').exists(),scenario!='restore-fail',run.stdout+run.stderr)
                self.assertTrue((evidence/'recovery-result.json').exists(),run.stdout+run.stderr)



if __name__ == '__main__':
    unittest.main()
