#!/usr/bin/env python3
"""Verify a retained capture and contain upload credentials; never pause writers."""
import argparse
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import signal
import sys

from capture_retained import verify_tree
from recurring_delivery import resolve
from recurring_protection import atomic, lock, protected, require

SECRETS=('password','credentials.json','source-password','source-credentials.json')


def load(path):
    protected(path);require(path.stat().st_size<1048576,'metadata_size')
    return json.loads(path.read_text())


def producer():
    spec=importlib.util.spec_from_file_location('producer',Path(__file__).with_name('application-backup.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def preflight(op, health):
    root=Path(op['payload_root']);qualification=Path(op['capture_root'])
    require(os.getuid()==op['target']['uid'] and os.getgid()==op['target']['gid'],'service_identity')
    require(Path('/proc/sys/kernel/random/boot_id').read_text().strip()==op['boot_id'],'boot_changed')
    verify_tree(qualification,op['qualification_tree'])
    verify_tree(root,op['payload_tree'])
    require(not any(os.path.lexists(root/n) for n in SECRETS),'credential_residue')
    require(hashlib.sha256(Path(op['restic']['path']).read_bytes()).hexdigest()==op['restic']['sha256'],'restic_changed')
    require(hashlib.sha256(Path(op['credentials']['doppler']).read_bytes()).hexdigest()==op['doppler_sha256'],'doppler_changed')
    spec=load(root/'application-backup.json');p=producer()
    require(spec['timeout_seconds']==300 and spec['repository_id']==op['repository']['id']
            and spec['repository_url']==op['repository']['url'] and spec['restic_version']==op['restic']['version']
            and spec['restic']==op['restic']['path'],
            'capture_specification')
    require(p.verified_capture(root,spec)['content_sha256']==op['content_sha256'],'capture_changed')
    require(health()==op['services'],'service_changed')
    return spec


def cleanup(op, evidence):
    marker=evidence/'credentials-owned.json'
    if not marker.exists():return {'no_owned_credentials':True}
    require(load(marker)=={'payload_root':op['payload_root']},'credential_ownership')
    results={}
    for name in SECRETS:
        path=Path(op['payload_root'])/name
        try:
            if os.path.lexists(path):protected(path);path.unlink()
            results[name]=not os.path.lexists(path)
        except Exception:results[name]=False
    atomic(evidence/'cleanup.json',results)
    return results


def run(op,evidence,health,resolver=resolve):
    root=Path(op['payload_root']);result={'accepted':False,'upload_started':False}
    try:
        with lock(Path(op['capture_root'])/'state/run.lock',blocking=False):
            spec=preflight(op,health)
            # Claim once only after proving absence; stop-post never deletes pre-existing secrets.
            with (evidence/'credentials-owned.json').open('x') as out:
                os.chmod(out.name,0o600);json.dump({'payload_root':str(root)},out)
            try:
                resolver(op['credentials'],root)
                (root/'source-password').rename(root/'password')
                (root/'source-credentials.json').rename(root/'credentials.json')
                result['upload_started']=True
                uploaded=producer().run(root,spec,phase='upload')
                result['producer']=uploaded
                require(uploaded['integrity_passed'] and all(uploaded['credential_cleanup'].values()),'upload_failed')
                require(health()==op['services'],'post_upload_service_changed')
                result['checks_passed']=True
            finally:
                result['credential_cleanup']=cleanup(op,evidence)
    except Exception as error:
        result['failure_class']=type(error).__name__
        if isinstance(error,ValueError) and re.fullmatch('[a-z_]{1,80}',str(error)):
            result['reason']=str(error)
    atomic(evidence/'result.json',result)
    return 0 if result.get('checks_passed') and all(result.get('credential_cleanup',{}).values()) else 1


def main():
    os.umask(0o077);sys.dont_write_bytecode=True
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=('run','cleanup'));parser.add_argument('operation',type=Path)
    args=parser.parse_args();op=load(args.operation);evidence=args.operation.parent
    require(op['operation']['execution_enabled'] is True,'execution_disabled')
    require(evidence==Path(op['evidence_root']),'evidence_root')
    if args.action=='cleanup':return 0 if all(cleanup(op,evidence).values()) else 1
    # Verify the complete accepted runtime before importing its read-only health probe.
    verify_tree(Path(op['capture_root']),op['qualification_tree'])
    sys.path.insert(0,str(Path(op['capture_root'])/'scripts'))
    import recurring_node
    def terminated(*_):raise InterruptedError('cancelled')
    signal.signal(signal.SIGTERM,terminated)
    return run(op,evidence,recurring_node.health)


if __name__=='__main__':
    try:sys.exit(main())
    except Exception:raise SystemExit('upload_qualification_refused; inspect protected receipts')
