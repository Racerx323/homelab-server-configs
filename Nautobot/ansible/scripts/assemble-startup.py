#!/usr/bin/env python3
"""Assemble exact startup artifacts and seven live checks without host contact."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import yaml

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE/(name+'.py'))
    value = importlib.util.module_from_spec(spec);spec.loader.exec_module(value)
    return value


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_cursor(raw):
    lines = [line[len('-- cursor: '):] for line in raw.splitlines() if line.startswith('-- cursor: ')]
    if len(lines) != 1 or not lines[0] or any(c.isspace() for c in lines[0]):
        raise ValueError('journal_cursor_shape')
    return lines[0]


def assemble(output, baseline, recovery):
    os.umask(0o077)
    output.mkdir(mode=0o700)
    for name, source in [('baseline', baseline), ('recovery', recovery)]:
        value = json.loads(source.read_text())
        if value.get('accepted') is not True or value.get('host') != 'j2-svpi4mf':
            raise ValueError('unreviewed_prerequisite')
        shutil.copyfile(source, output/(name+'.json'))
    load('prepare-startup').prepare(output/'artifacts')
    desired = yaml.safe_load((ROOT/'Nautobot/manifests/desired-state.yaml').read_text())
    before = json.loads((output/'baseline.json').read_text())
    accepted = yaml.safe_load((ROOT/'Nautobot/manifests/startup-preservation.yaml').read_text())
    settings = {'boot_id':before['boot_id'], 'journal_cursor':parse_cursor(before['journal_cursor']),
                'limits_mib':{r:v['memory_limit_mib'] for r,v in desired['services'].items()},
                'images':{r:accepted['runtime']['images'][r if r in ('postgresql','redis') else 'custom']['id'] for r in desired['services']},
                'storage_pattern':r'reset.*USB device|I/O error|Buffer I/O|EXT4-fs error|uas_eh|device offline|timing out command|blk_update_request|out of memory|oom-kill'}
    settings_path=output/'runtime-expectations.json';settings_path.write_text(json.dumps(settings,indent=2)+'\n')
    probes=output/'probes';probes.mkdir(mode=0o700)
    names=['startup-runtime-check.py','startup-runtime-controller.py','startup-browser-probe.py',
           'startup-network-probe.py','startup-network-client.py','startup-job-controller.py','provision-credentials.py']
    for name in names:shutil.copyfile(HERE/name,probes/name)
    checks=[]
    def add(identity,group,script,args,timeout,expected):
        checks.append({'id':identity,'group':group,'argv':['/usr/bin/python3',str(probes/script)]+args,
                       'timeout_seconds':timeout,'expected':expected})
    def runtime(identity,group,timeout,expected):
        add(identity,group,'startup-runtime-controller.py',[identity,str(settings_path)],timeout,expected)
    runtime('native','native_configuration_and_migrations',240,{'native_checks_passed':True,'all_services_healthy_without_restarts':True})
    runtime('http','health_and_static_http',60,{'health_and_static_passed':True})
    add('session','administrator_login_logout','startup-browser-probe.py',[],180,{'administrator_login_logout':True,'csrf_and_host_rejections':True,'tunnel_cleanup':True})
    add('network','allowed_denied_dual_stack_access','startup-network-probe.py',[],180,{'allowed_both_proxies_both_families':True,'denied_both_families_with_counters':True})
    add('job','worker_scheduler_and_representative_job','startup-job-controller.py',[],150,{'job_completed':True,'single_worker_concurrency_two':True})
    runtime('resources','resource_and_secret_boundaries',240,{'resources_and_secret_metadata_passed':True})
    runtime('storage','cleanup_and_storage_observation',150,{'delayed_storage_review_passed':True,'boot_and_processes_continuous':True})
    # Total deadline remains within the collector's 1200-second boundary.
    checks[0]['timeout_seconds']=180;checks[5]['timeout_seconds']=180
    artifacts=[]
    for path in sorted((output/'artifacts').iterdir()):
        if path.suffix not in ('.py','.container','.volume','.network'):continue
        folder='runtime' if path.suffix=='.py' else '.config/containers/systemd'
        artifacts.append({'source':str(path),'destination':'/var/lib/nautobot/'+folder+'/'+path.name,'sha256':sha(path)})
    value={'schema_version':1,'host':'j2-svpi4mf','artifacts':artifacts,'acceptance_contract':{'schema_version':1,'checks':checks},
           'baseline':{'path':str(output/'baseline.json'),'sha256':sha(output/'baseline.json')},
           'recovery':{'path':str(output/'recovery.json'),'sha256':sha(output/'recovery.json')},
           'helper_sha256':{name:sha(ROOT/('restic/scripts' if name=='canary-backup.py' else 'Nautobot/ansible/scripts')/name)
                            for name in ('startup-node.py','runtime-initialization-node.py','canary-backup.py')},
           'probe_files':{str(path):sha(path) for path in [*probes.iterdir(),settings_path]}}
    path=output/'startup-specification.json';path.write_text(json.dumps(value,indent=2)+'\n')
    digest=load('run-startup').prepare(path)[3]
    (output/'SHA256').write_text(digest+'\n')
    return digest


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('output',type=Path);p.add_argument('baseline',type=Path);p.add_argument('recovery',type=Path)
    a=p.parse_args();print(assemble(a.output.resolve(),a.baseline,a.recovery))
