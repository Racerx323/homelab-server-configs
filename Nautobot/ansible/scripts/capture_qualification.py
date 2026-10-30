#!/usr/bin/env python3
"""Configure and inspect one capture-only trial; existing supervisor owns recovery."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
from recurring_protection import atomic, protected, require, in_window
import recurring_node as node


def configure(root):
    protected(root, True)
    op = node.load(root/'operation.json')
    require(op['operation']['execution_enabled'] is True, 'execution_disabled')
    require(os.getuid() == 999 and node.socket.gethostname() == op['target']['host'], 'target')
    for path, digest in op['baseline']['artifact_sha256'].items():
        require(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, 'accepted_artifact_drift')
    for row in op['packages']:
        raw = node.bounded(['/usr/bin/dpkg-query','-W','-f=${Version} ${Architecture}',row['name']]).decode()
        require(raw == row['version']+' '+row['architecture'], 'package_drift')
    actual = node.load(Path(op['binding']['credentials']['metadata_file']))
    require(all(actual[k] == v for k,v in op['credential_identity'].items()), 'credential_metadata_drift')
    from datetime import datetime
    require(in_window(op['supervisor'], datetime.now().astimezone()), 'outside_approved_window')
    require(node.media_directories() == op['baseline']['media_directories'], 'media_drift')
    for name in op['unit_names']:
        require(node.system(['show',name,'--property=LoadState','--value']).strip()==b'not-found','existing_qualification_unit')
    before = node.health()
    state = root/'state'; state.mkdir(mode=0o700)
    atomic(state/'before.json', {'services':before,'boot_id':Path('/proc/sys/kernel/random/boot_id').read_text().strip()})
    binding = op['binding']; binding['execution_authorized'] = True
    atomic(root/'binding.json', binding)
    config = op['supervisor']; config['execution_authorized'] = True
    atomic(root/'supervisor.json', config)
    loader=importlib.util.spec_from_file_location('renderer',Path(__file__).with_name('render-recurring-protection.py'))
    renderer=importlib.util.module_from_spec(loader);loader.loader.exec_module(renderer)
    units=renderer.render(root/'supervisor.json',Path(__file__).with_name('recurring_protection.py'))
    directory=root/'units';directory.mkdir(mode=0o700)
    for name in op['unit_names']:
        p=directory/name;p.write_text(units[name]);p.chmod(0o600)
    print(json.dumps({'prepared':True}))


def inspect(root):
    op=node.load(root/'operation.json')
    state=node.load(root/'state/state.json')
    run=Path(state['root']); protected(run,True)
    require(run.parent == Path(op['supervisor']['staging_directory']), 'run_scope')
    before=node.load(root/'state/before.json')
    current=node.health()
    require(before['boot_id']==Path('/proc/sys/kernel/random/boot_id').read_text().strip(), 'boot_changed')
    require(all(current['nautobot-'+r+'.service']['InvocationID']==before['services']['nautobot-'+r+'.service']['InvocationID'] for r in ('postgresql','redis')), 'data_service_restart')
    require(state['phase']=='complete' and state['exit_status']==0,'capture_not_complete')
    spec=node.load(run/'application-backup.json')
    loader=importlib.util.spec_from_file_location('producer',op['binding']['producer'])
    producer=importlib.util.module_from_spec(loader);loader.loader.exec_module(producer)
    receipt=producer.verified_capture(run,spec)
    require(not receipt['upload_attempted'] and not (run/'application-backup-result.json').exists(),'unexpected_upload')
    require(not any((run/n).exists() for n in ('password','credentials.json','source-password','source-credentials.json')),'credential_residue')
    require(state['resumed_at']-state['started_at']<=op['supervisor']['capture_seconds']+120,'duration')
    for path,digest in op['baseline']['artifact_sha256'].items():
        require(hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,'post_capture_artifact_drift')
    require(node.media_directories()==op['baseline']['media_directories'],'post_capture_media_drift')
    require(node.system(['show',op['supervisor']['unit_prefix']+'-guard.timer','--property=ActiveState','--value']).strip()==b'inactive','guard_still_active')
    result={'capture_seconds':receipt['finished']-receipt['started'],'preflight_plus_pause_upper_bound_seconds':state['resumed_at']-state['started_at'],'accepted':False,'capture_resume_checks_passed':True,'state':state,'capture':receipt,'services':current,'temporary_credentials_removed':True,'payload_retained':True,'independent_failure_recovery_target_qualified':False}
    atomic(root/'result.json', result)
    print(json.dumps(result))


if __name__=='__main__':
    os.umask(0o077)
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['configure','inspect']);parser.add_argument('root',type=Path);a=parser.parse_args()
    try: (configure if a.action=='configure' else inspect)(a.root)
    except Exception:
        raise SystemExit('capture_qualification_refused; inspect protected state; do not replay')
