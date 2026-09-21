#!/usr/bin/env python3
"""Offline tests of actual bundle, worker guards and watchdog paths; no Podman."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import yaml
from jinja2 import Environment, FileSystemLoader, StrictUndefined
from jsonschema import Draft202012Validator, ValidationError

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT/'Nautobot/ansible/scripts'/file)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


node = module('build_node', 'image-build-node.py')
launcher = module('build_launcher', 'prepare-image-build.py')


class ImageBuildTests(unittest.TestCase):
    def setUp(self):
        # Bundle tests use a definition fixture, independent of the live slot.
        files={**launcher.FILES, 'operation.yaml':'Nautobot/tests/fixtures/image-build-operation.yaml'}
        self.mapping=patch.object(launcher,'FILES',files)
        self.mapping.start()
        self.addCleanup(self.mapping.stop)

    def test_actual_bundle_producer_and_tamper_gate(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)/'bundle'
            digest = launcher.prepare(root)
            launcher.verify(root, digest)
            subprocess.run([sys.executable,str(root/'launcher.py'),'verify',str(root),digest],
                           check=True,capture_output=True,timeout=10)
            with patch.object(launcher.subprocess, 'run') as execute:
                with self.assertRaises(ValueError): launcher.execute(root, '0'*64)
                execute.assert_not_called()
            (root/'input/requirements.lock').write_text('tampered')
            with self.assertRaises(ValueError): launcher.verify(root, digest)

    def test_retry_candidate_preserves_consumed_definition_and_blocks_unarchived_execution(self):
        original=(ROOT/'Nautobot/tests/fixtures/image-build-operation.yaml').read_bytes()
        with tempfile.TemporaryDirectory() as tmp:
            bundle=Path(tmp)/'candidate'
            previous=Path(tmp)/'previous'; (previous/'approved-bundle').mkdir(parents=True)
            (previous/'execution').mkdir()
            (previous/'approved-bundle/operation.yaml').write_bytes(original)
            (previous/'approved-bundle/SHA256SUMS.json').write_text(json.dumps({'operation.yaml':hashlib.sha256(original).hexdigest()}))
            (previous/'execution/result.json').write_text(json.dumps({'passed':False,'reason':'failed_unit','stop_confirmed':True,'artifacts_retained':True,'runtime_accepted':False}))
            priorhash=launcher.sha(previous/'approved-bundle/SHA256SUMS.json')
            with patch.object(launcher,'PREVIOUS_EVIDENCE',previous),patch.object(launcher,'PREVIOUS_BUNDLE_SHA256',priorhash):
                digest=launcher.prepare(bundle,retry=True)
            launcher.verify(bundle,digest)
            self.assertEqual(original,(ROOT/'Nautobot/tests/fixtures/image-build-operation.yaml').read_bytes())
            candidate=yaml.safe_load((bundle/'operation.yaml').read_text())
            old=yaml.safe_load(original)
            self.assertNotEqual(candidate['build']['id'],old['build']['id'])
            self.assertEqual(candidate['build']['input_sha256'],old['build']['input_sha256'])
            self.assertEqual(candidate['boundaries'],old['boundaries'])
            with patch.object(launcher.subprocess,'check_output',side_effect=subprocess.CalledProcessError(128,['git'])), \
                 patch.object(launcher.tempfile,'TemporaryDirectory') as stage:
                with self.assertRaises(subprocess.CalledProcessError):launcher.execute(bundle,digest)
                stage.assert_not_called()
            prior=json.loads((bundle/'predecessor.json').read_text())
            terminal=(bundle/'failure-evidence.json').read_bytes()
            with patch.object(launcher.subprocess,'check_output',side_effect=[b'tag',original,terminal,b'abc\n',b'abc refs/tags/'+prior['tag'].encode()+b'\n']):
                launcher.require_predecessor_archive(bundle)
            for outputs in [[b'commit'],[b'tag',b'wrong'],[b'tag',original,b'wrong-evidence'],[b'tag',original,terminal,b'abc',b'']]:
                with patch.object(launcher.subprocess,'check_output',side_effect=outputs):
                    with self.assertRaises(ValueError):launcher.require_predecessor_archive(bundle)

    def test_extra_bundle_content_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'bundle';digest=launcher.prepare(root)
            (root/'extra').mkdir()
            with self.assertRaises(ValueError):launcher.verify(root,digest)
            (root/'extra').rmdir();(root/'extra').write_text('unexpected')
            with self.assertRaises(ValueError):launcher.verify(root,digest)

    def test_symlink_member_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)/'bundle'
            digest = launcher.prepare(root)
            f = root/'input/Containerfile'
            contents = f.read_bytes(); f.unlink()
            target = Path(tmp)/'outside'; target.write_bytes(contents); f.symlink_to(target)
            with self.assertRaises(ValueError): launcher.verify(root, digest)

    def test_schema_rejects_weakening_and_runtime_authority(self):
        schema = json.loads((ROOT/'Nautobot/schemas/image-build.schema.json').read_text())
        op = yaml.safe_load((ROOT/'Nautobot/tests/fixtures/image-build-operation.yaml').read_text())
        Draft202012Validator(schema).validate(op)
        outer=json.loads((ROOT/'Nautobot/schemas/operation.schema.json').read_text())
        self.assertEqual(outer['oneOf'][-1]['const'],schema['const'])
        for category, key, value in [('authorization','mutation_authorized',True),
                                      ('build','host','other-host'),
                                      ('boundaries','production_store_load',True)]:
            bad = copy.deepcopy(op); bad[category][key] = value
            with self.assertRaises(ValidationError): Draft202012Validator(schema).validate(bad)

    def test_real_capture_timeout_output_and_nonzero(self):
        self.assertEqual(node.capture([sys.executable,'-c','print("ok")']).strip(), 'ok')
        for code, timeout, limit in [('import time; time.sleep(2)',.05,100),
                                     ('print("x"*10000)',1,100),
                                     ('raise SystemExit(7)',1,100)]:
            with self.assertRaises(RuntimeError): node.capture([sys.executable,'-c',code],timeout,limit)

    def test_kernel_limits_require_all_bounds(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            good = {'memory.max':str(3*node.GIB),'memory.swap.max':'0','cpu.max':'200000 100000','cgroup.procs':''}
            for n,v in good.items(): (p/n).write_text(v)
            node.limits(p)
            for name, value in [('memory.max','max'),('memory.swap.max','1'),('cpu.max','max 100000'),('cpu.max','300000 100000')]:
                (p/name).write_text(value)
                with self.assertRaises(RuntimeError): node.limits(p)
                (p/name).write_text(good[name])

    def test_actual_health_guards_reject_each_unsafe_signal(self):
        from types import SimpleNamespace
        cases=[{}, {'mem':1536*1024-1}, {'temperature':80001}, {'free':20*node.GIB-1},
               {'size':30*node.GIB+1}, {'errors':1}, {'throttled':'throttled=0x1'},
               {'failed':'other.service failed'}, {'journal':'{"MESSAGE":"reset SuperSpeed USB device"}'},
               {'boot':'changed'}]
        for case in cases:
            with self.subTest(case=case),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp); values={'mem':8*1024**2,'temperature':49000,'free':100*node.GIB,
                    'size':1000,'errors':0,'throttled':'throttled=0x0','failed':'','journal':'','boot':'boot'}
                values.update(case)
                mapping={'/proc/sys/kernel/random/boot_id':values['boot'],
                         '/proc/meminfo':'MemAvailable: '+str(values['mem'])+' kB',
                         '/sys/class/thermal/thermal_zone0/temp':str(values['temperature']),
                         '/sys/fs/ext4/sda2/errors_count':str(values['errors'])}
                files={}
                for n,(name,value) in enumerate(mapping.items()):
                    f=root/str(n);f.write_text(value);files[name]=f
                def capture(argv,*args):
                    return {'du':str(values['size'])+' work','vcgencmd':values['throttled'],
                            'systemctl':values['failed'],'journalctl':values['journal']}[argv[0]]
                with patch.object(node,'Path',side_effect=lambda p:files[p]), \
                     patch.object(node,'capture',side_effect=capture), \
                     patch.object(node.os,'statvfs',return_value=SimpleNamespace(f_bavail=values['free'],f_frsize=1)):
                    if case:
                        with self.assertRaises(RuntimeError):node.health(root,'boot',0,'cursor')
                    else:self.assertEqual(node.health(root,'boot',0,'cursor')['ext4_errors'],0)

    def watchdog(self, states, health_error=False, stop_error=False, missing_result=False, gap=False, start_error=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root/'evidence').mkdir(); (root/'work').mkdir()
            fake = root/'fake'; fake.mkdir()
            (fake/'boot').write_text('boot'); (fake/'errors').write_text('0')
            if not missing_result: (root/'work/worker-result.json').write_text('{"result":"static_image_checks_passed"}')
            calls=[]; samples=[0]
            def health(*args):
                samples[0]+=1
                if health_error and samples[0]>1: raise RuntimeError('resource_guard')
                return {'epoch':1}
            def capture(argv, *args):
                calls.append(argv)
                if argv[0]=='journalctl':return '-- cursor: cursor-token\n'
                if argv[1]=='start':
                    if start_error:raise RuntimeError('command_timeout')
                    return ''
                if argv[1]=='stop':
                    if stop_error:raise RuntimeError('stop_failed')
                    return ''
                if '--value' in argv:return 'inactive\n'
                state=states.pop(0) if len(states)>1 else states[0]
                return f'ActiveState={state}\nSubState=dead\nResult=success\nExecMainStatus=0\nControlGroup=/absent\n'
            real_path=Path
            def paths(value):
                if str(value)=='/proc/sys/kernel/random/boot_id':return fake/'boot'
                if str(value)=='/sys/fs/ext4/sda2/errors_count':return fake/'errors'
                if str(value).startswith('/sys/fs/cgroup/'):return fake/'absent'
                return real_path(value)
            times=iter([0,0,0,20] if gap else [0]*100)
            with patch.object(node,'capture',side_effect=capture), patch.object(node,'health',side_effect=health), \
                 patch.object(node,'Path',side_effect=paths), patch.object(node.os,'getuid',return_value=0), \
                 patch.object(node.time,'sleep'), patch.object(node.time,'monotonic',side_effect=lambda:next(times)):
                if health_error or stop_error or missing_result or gap or start_error or states[0]=='failed':
                    with self.assertRaises(RuntimeError):node.watch(root,{'id':'abc','boot_id':'boot'})
                else:node.watch(root,{'id':'abc','boot_id':'boot'})
            return json.loads((root/'evidence/result.json').read_text()),calls,samples[0]

    def test_watchdog_success_requires_delayed_coverage(self):
        result,calls,samples=self.watchdog(['inactive'])
        self.assertTrue(result['passed']); self.assertGreaterEqual(samples,17)
        self.assertTrue(any(c[1]=='stop' for c in calls))

    def test_watchdog_resource_failure_stops_worker(self):
        result,calls,_=self.watchdog(['inactive'],health_error=True)
        self.assertFalse(result['passed']); self.assertTrue(any(c[1]=='stop' for c in calls))

    def test_watchdog_failed_worker_missing_result_stop_failure_and_gap(self):
        for kwargs in [{'states':['failed']},{'states':['inactive'],'missing_result':True},
                       {'states':['inactive'],'stop_error':True},{'states':['inactive'],'gap':True},
                       {'states':['inactive'],'start_error':True}]:
            result,calls,_=self.watchdog(**kwargs);self.assertFalse(result['passed'])
            self.assertTrue(any(c[1]=='stop' for c in calls))

    def test_actual_worker_sequence_and_oci_artifact_validation(self):
        import io
        import tarfile
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'work').mkdir(); (root/'input').mkdir(); cg=root/'cg'; cg.mkdir()
            for name,text in {'memory.max':str(3*node.GIB),'memory.swap.max':'0','cpu.max':'200000 100000','cgroup.procs':''}.items():
                (cg/name).write_text(text)
            inputs={}
            for name in ['Containerfile','requirements.lock']:
                (root/'input'/name).write_text('fixture')
                inputs[name]=hashlib.sha256(b'fixture').hexdigest()
            config=json.dumps({'architecture':'arm64','os':'linux'}).encode()
            confighash=hashlib.sha256(config).hexdigest()
            manifest=json.dumps({'config':{'digest':'sha256:'+confighash},'layers':[]}).encode()
            manifesthash=hashlib.sha256(manifest).hexdigest()
            index=json.dumps({'manifests':[{'digest':'sha256:'+manifesthash}]}).encode()
            def capture(argv,*args,**kwargs):
                calls.append(argv)
                if 'inspect' in argv:return '[{"Architecture":"arm64","Os":"linux"}]'
                if 'build' in argv:
                    target=next(x.split('=',1)[1] for x in argv if x.startswith('--cgroup-parent='))
                    if target.endswith('.service'):
                        raise OSError(16,'Device or resource busy')
                    self.assertTrue(target.endswith('.service/build'))
                    self.assertEqual((cg/'cgroup.procs').read_text(),'')
                    self.assertEqual(set((cg/'cgroup.subtree_control').read_text().split()),{'cpu','memory','pids'})
                    (root/'work/image.id').write_text('sha256:'+'a'*64)
                if '-c' in argv:return '{"nautobot":"3.2.3","nautobot-dns-models":"2.3.0"}'
                if 'save' in argv:
                    with tarfile.open(root/'work/image.oci.tar','w') as t:
                        for name,data in [('index.json',index),('blobs/sha256/'+manifesthash,manifest),('blobs/sha256/'+confighash,config)]:
                            info=tarfile.TarInfo(name);info.size=len(data);t.addfile(info,io.BytesIO(data))
                return ''
            calls=[]; real_path=Path
            def paths(value):return cg if str(value).startswith('/sys/fs/cgroup') else real_path(value)
            # Kernel-owned control-file behavior is represented by the fixture only;
            # live kernel admission remains a pre-pull execution gate.
            original_write=Path.write_text
            def write(path,data,*args,**kwargs):
                if path.name=='cgroup.subtree_control':data=data.replace('+','')
                return original_write(path,data,*args,**kwargs)
            with patch.object(node,'capture',side_effect=capture),patch.object(node,'Path',side_effect=paths), \
                 patch.object(node,'cgroup',return_value='/system.slice/nautobot-image-fixture.service'), \
                 patch.object(node.os,'getuid',return_value=999),patch.object(node.os,'getgid',return_value=985), \
                 patch.object(node.os,'uname') as uname, patch.dict(node.os.environ),patch.object(Path,'write_text',write):
                uname.return_value.machine='aarch64'
                node.worker(root,{'input_sha256':inputs,'base_image':'fixture@sha256:'+'b'*64,'id':'fixture'})
            result=json.loads((root/'work/worker-result.json').read_text())
            self.assertEqual(result['oci_manifest_digest'],'sha256:'+manifesthash)
            self.assertFalse(result['runtime_accepted'])
            build=next(c for c in calls if 'build' in c)
            self.assertIn('--cgroup-parent=/system.slice/nautobot-image-fixture.service/build',build)
            self.assertNotIn('--cgroup-parent=/system.slice/nautobot-image-fixture.service',build)
            self.assertIn('--pull=never',build)
            for c in calls:
                self.assertIn('--root='+str(root/'work/store'),c)
                if 'run' in c:
                    self.assertIn('--network=none',c); self.assertIn('--cgroups=disabled',c)
                self.assertNotIn('prune',c)

    def test_units_and_ansible_keep_watchdog_independent(self):
        env=Environment(loader=FileSystemLoader(ROOT/'Nautobot/ansible/templates/image-build'),undefined=StrictUndefined)
        values={'build_spec':{'id':'a'*12},'build_root':'/var/tmp/nautobot-image-'+'a'*12}
        build=env.get_template('build.service.j2').render(**values)
        watch=env.get_template('watch.service.j2').render(**values)
        for line in ['User=nautobot','Delegate=yes','MemoryMax=3221225472','MemorySwapMax=0','CPUQuota=200%',
                     'RuntimeMaxSec=2700','KillMode=control-group','BindsTo=nautobot-image-watch-']:
            self.assertIn(line,build)
        self.assertNotIn('User=nautobot',watch)
        self.assertIn('ExecStopPost=/usr/bin/systemctl stop',watch)
        self.assertIn('RuntimeMaxSec=2800',watch)
        play=yaml.safe_load((ROOT/'Nautobot/ansible/playbooks/qualify-image.yaml').read_text())[0]
        self.assertIn('ansible.builtin.assert',play['tasks'][0])
        start=next(t for t in play['tasks'] if t['name']=='Load and start only the watchdog')
        self.assertEqual(start['ansible.builtin.systemd_service']['name'],'{{ watch_unit }}')


if __name__=='__main__':unittest.main()
