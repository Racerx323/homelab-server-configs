#!/usr/bin/env python3
"""Read-only verification for a two-artifact boot-readiness deployment."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import time

spec=importlib.util.spec_from_file_location('reader',Path(__file__).with_name('logout-node.py'))
reader=importlib.util.module_from_spec(spec);spec.loader.exec_module(reader)


def verify(root,op,phase):
    expected=dict(op['baseline']['artifact_sha256'])
    if phase=='after':
        expected.update({x['destination']:x['after_sha256'] for x in op['artifacts']})
    for path,digest in expected.items():
        p=Path(path)
        reader.require(p.is_file() and not p.is_symlink() and p.stat().st_size<1048576,'artifact_metadata')
        reader.require(hashlib.sha256(p.read_bytes()).hexdigest()==digest,'artifact_changed')
    reader.command(['/usr/bin/python3','-I','/usr/local/lib/nautobot-network/backend_guard.py','check'])
    row=reader.snapshot()
    reader.check_sample(row,op['baseline'],op['baseline']['sessions'])
    if phase=='before':
        raw=reader.command(['/usr/bin/journalctl','-n','0','--show-cursor','--no-pager'])
        cursor=[s.removeprefix('-- cursor: ') for s in raw.splitlines() if s.startswith('-- cursor: ')]
        reader.require(len(cursor)==1,'journal_cursor')
        row['cursor']=cursor[0]
        row['migration_unit']=reader.command(reader.USER+['/usr/bin/systemctl','--user','show','nautobot-migration.service','--property=InvocationID,ActiveState,SubState,TimeoutStartUSec'])
    else:
        before=json.loads((root/'before.json').read_text())
        unit=reader.pairs(reader.command(reader.USER+['/usr/bin/systemctl','--user','show','nautobot-migration.service','--property=InvocationID,ActiveState,SubState,TimeoutStartUSec']))
        old=reader.pairs(before['migration_unit'])
        reader.require(all(unit.get(k)==old.get(k) for k in ('InvocationID','ActiveState','SubState')),'migration_restarted')
        reader.require(unit.get('TimeoutStartUSec')==('5min' if phase=='after' else old.get('TimeoutStartUSec')),'generated_timeout')
        row['migration_unit']=unit
        cursor=before['cursor']
        seen=reader.command(['/usr/bin/journalctl','--cursor',cursor,'-n','+1','-o','json','--output-fields=__CURSOR','--quiet','--no-pager'])
        reader.require(json.loads(seen)['__CURSOR']==cursor,'journal_gap')
        raw=reader.command(['/usr/bin/journalctl','--after-cursor',cursor,'_TRANSPORT=kernel','-o','json','--output-fields=MESSAGE','--quiet','--no-pager'])
        reader.require(not any(reader.STORAGE.search(json.loads(s)['MESSAGE']) for s in raw.splitlines()),'storage_event')
    reader.write(root,phase+'.json',row)
    return row


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('phase',choices=('before','after','rollback'));p.add_argument('root',type=Path);a=p.parse_args()
    reader.require(os.geteuid()==0 and re.fullmatch(r'/var/lib/nautobot/boot-readiness\.[0-9a-f]{32}',str(a.root)),'root_boundary')
    reader.require(not any(x.is_symlink() for x in (a.root,*a.root.parents)) and a.root.stat().st_uid==0 and a.root.stat().st_mode&0o777==0o700,'root_metadata')
    op=json.loads((a.root/'operation.json').read_text())
    if a.phase=='after':time.sleep(75)
    verify(a.root,op,a.phase)
