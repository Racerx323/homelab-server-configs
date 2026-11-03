#!/usr/bin/env python3
"""Disposable real user-systemd supervision, with harmless writer adapters."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid
from test_recurring_protection import SCRIPTS, configuration, renderer, module


def ctl(*args):
    return subprocess.run(['/usr/bin/systemctl','--user',*args], capture_output=True, timeout=40)


def wait_for(predicate, seconds=35):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        if predicate(): return
        time.sleep(.2)
    raise RuntimeError('bounded_wait_expired')


def qualify(output):
    output.mkdir(mode=0o700, exist_ok=False)
    records=[]
    for case in ('success','killed','deadline','slow-health','prepare-failure','timer','fault-helper','ansible','ansible-fault'):
        with tempfile.TemporaryDirectory(prefix='nautobot-recurring.') as temporary:
            root=Path(temporary); prefix='nautobot-protection-'+uuid.uuid4().hex[:12]
            config=configuration(root,prefix)
            config.update(start_hour=0,end_hour=24,capture_seconds=12,recovery_seconds=12,run_seconds=60)
            adapter=root/'adapter.py'; path=root/'config.json'
            adapter.write_text('''import json, pathlib, subprocess, sys, time
root=pathlib.Path(sys.argv[1]); action=sys.argv[2]
config=root/'config.json'
if action=='prepare':
    run=pathlib.Path(sys.argv[3]); argv=[sys.executable,__file__,str(root)]
    credentials={}
    for key,name in [('password','source-password'),('credentials.json','source-credentials.json')]:
        p=run/name; p.write_text('DISPOSABLE'); p.chmod(0o600); credentials[key]=str(p)
    data=dict(application_capture_authorized=True, application_pause_commands=[argv+['pause']],
              application_resume_commands=[argv+['resume']], application_health_argv=argv+['health'],
              application_producer_argv=argv+['producer'],application_backup_credentials=credentials)
    if (root/'ansible-fault').exists(): data['application_producer_argv']=argv+['fault-producer']
    p=run/'inputs.json'; p.write_text(json.dumps(data)); p.chmod(0o600)
    if (root/'prepare-failure').exists(): sys.exit(1)
elif action=='pause': (root/'paused').write_text('yes')
elif action=='producer':
    phase=sys.argv[sys.argv.index('--phase')+1]
    assert (root/'paused').exists()==(phase=='capture')
    (root/('observed-'+phase)).touch()
elif action=='fault-producer':
    sys.path.insert(0,(root/'scripts-path').read_text())
    import recovery_qualification as fault
    fault.node.stopped=lambda: None  # native services replaced by the disposable pause marker
    assert (root/'paused').exists()
    fault.blocked(root,pathlib.Path(sys.argv[sys.argv.index('--root')+1]))
elif action=='run':
    state=json.loads((root/'state.json').read_text()); run=pathlib.Path(state['root'])
    p=run/'password'; p.write_text('DISPOSABLE'); p.chmod(0o600)
    (root/'paused').write_text('yes')
    if sys.argv[3]=='fault-helper':
        sys.path.insert(0,str(pathlib.Path(sys.argv[4]).parent))
        import recovery_qualification as fault
        fault.node.stopped=lambda: None  # disposable writer marker replaces production database/service probe
        fault.blocked(root,run)
    if sys.argv[3] in ('success','timer'):
        (root/'paused').unlink()
        cfg=json.loads(config.read_text()); script=cfg['health_argv'][0]
        subprocess.run([sys.executable, sys.argv[4], '--config', str(config), 'recovered'], check=True)
        time.sleep(14)
    else: time.sleep(120)
elif action=='resume': (root/'paused').unlink(missing_ok=True)
elif action=='health':
    if (root/'slow-health').exists(): time.sleep(8)
    sys.exit(int((root/'paused').exists()))
''')
            if case in ('slow-health','prepare-failure','ansible-fault'): (root/case).touch()
            (root/'scripts-path').write_text(str(SCRIPTS))
            argv=[sys.executable,str(adapter),str(root)]
            config.update(prepare_argv=argv+['prepare'],ansible_argv=argv+['run',case,str(SCRIPTS/'recurring_protection.py')],
                          resume_commands=[argv+['resume']],health_argv=argv+['health'])
            if case in ('ansible','ansible-fault'):
                import shutil
                config.update(capture_seconds=60,run_seconds=120,ansible_argv=[
                    '/bin/bash',str(SCRIPTS.parents[2]/'tests/repository/run-with-ansible-local-temp.sh'),
                    shutil.which('ansible-playbook'),'-i','localhost,',str(SCRIPTS.parent/'playbooks/recurring-capture.yaml')])
            module.atomic(path,config)
            if case in ('fault-helper','ansible-fault'):
                module.atomic(root/'supervisor.json',config)
                module.atomic(root/'operation.json',{'supervisor':config})
            units=renderer.render(path,SCRIPTS/'recurring_protection.py')
            if case=='timer':
                # Exercise actual timer dispatch without waiting for the production calendar.
                units[prefix+'.timer']=units[prefix+'.timer'].replace(
                    'OnCalendar=*-*-* 03:20:00 America/Chicago','OnActiveSec=1s')
            unitdir=root/'units'; unitdir.mkdir()
            for name,text in units.items(): (unitdir/name).write_text(text)
            names=list(units)
            try:
                result=subprocess.run(['/usr/bin/systemd-analyze','--user','verify',*[str(unitdir/n) for n in names]],capture_output=True)
                if result.returncode: raise RuntimeError('unit_verification_failed: '+result.stderr.decode()[:1000])
                result=ctl('link','--runtime',*[str(unitdir/n) for n in names])
                if result.returncode: raise RuntimeError('unit_link_failed: '+result.stderr.decode()[:1000])
                assert ctl('daemon-reload').returncode==0
                assert ctl('start','--no-block',prefix+('.timer' if case=='timer' else '.service')).returncode==0
                if case in ('killed','slow-health','fault-helper','ansible-fault'):
                    wait_for(lambda:(root/'paused').exists())
                    if case in ('fault-helper','ansible-fault'):
                        wait_for(lambda:(Path(module.Supervisor(path).state()['root'])/'fault-paused.json').exists())
                    assert ctl('kill','--kill-whom=all','--signal=SIGKILL',prefix+'.service').returncode==0
                def terminal():
                    p=root/'state.json'
                    return p.exists() and json.loads(p.read_text())['phase'] in ('complete','recovered_failure','manual_intervention','failed')
                wait_for(terminal)
                state=json.loads((root/'state.json').read_text())
                expected='complete' if case in ('success','ansible','timer') else 'failed' if case=='prepare-failure' else 'recovered_failure'
                assert state['phase']==expected,state
                if case=='slow-health': assert 8 <= state['recovery_elapsed_seconds'] < 12
                if case=='ansible':
                    assert (root/'observed-capture').exists() and (root/'observed-upload').exists()
                assert not (root/'paused').exists()
                assert not (Path(state['root'])/'password').exists()
                records.append({'case':case,'phase':state['phase'],'writers_resumed':True,'credentials_removed':True})
                # Only supervisor-owned disposable inputs/credentials were generated.
                import shutil
                shutil.rmtree(state['root'])
            finally:
                ctl('stop',*names); ctl('disable','--runtime',*names); ctl('reset-failed',*names); ctl('daemon-reload')
    module.atomic(output/'results.json',records)
    print(json.dumps(records))


if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args(); os.umask(0o077); qualify(args.output)
