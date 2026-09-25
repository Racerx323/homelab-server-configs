#!/usr/bin/env python3
"""Bounded logout evidence reader. Session creation/closure belongs to Ansible."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROLES = ('postgresql', 'redis', 'web', 'worker', 'scheduler')
USER = ['/usr/sbin/runuser','--user','nautobot','--','/usr/bin/env',
        'XDG_RUNTIME_DIR=/run/user/999','DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus']
STORAGE = re.compile(r'USB.*reset|reset.*USB|I/O error|EXT4-fs (error|warning)|Buffer I/O|uas.*(abort|error)|under.voltage|oom-kill',re.I)


def require(condition, code):
    if not condition: raise ValueError(code)


def command(argv):
    import tempfile
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        result = subprocess.run(['/usr/bin/prlimit','--fsize=1048576:1048576','--',*argv],
            stdin=subprocess.DEVNULL,stdout=out,stderr=err,timeout=3,cwd='/',
            env={'PATH':'/usr/bin:/bin','LC_ALL':'C.UTF-8'})
        require(result.returncode==0 and out.tell()<1048576 and err.tell()<1048576,'collection_failed')
        out.seek(0); return out.read().decode()


def pairs(raw):
    return dict(line.split('=',1) for line in raw.splitlines() if '=' in line)


def properties(kind, identity, names):
    args = ['/usr/bin/loginctl',kind,identity]
    for name in names: args += ['-p',name]
    return pairs(command(args))


def sessions():
    user = properties('show-user','nautobot',('UID','Linger','Sessions'))
    require(user.get('UID')=='999' and user.get('Linger')=='yes','user_or_linger')
    result={}
    for identity in user.get('Sessions','').split():
        require(re.fullmatch(r'[a-zA-Z0-9]+',identity),'session_id')
        result[identity]=properties('show-session',identity,('Id','User','Service','Class','Leader','State'))
    return result


def manager(row):
    return row.get('User')=='999' and row.get('Service')=='systemd-user' and row.get('Class') in ('manager','manager-early')


def snapshot():
    raw=command(USER+['/usr/bin/systemctl','--user','show',*['nautobot-'+r+'.service' for r in ROLES],
                      '--property=Id,ActiveState,SubState,Result,NRestarts,InvocationID'])
    units={row['Id']:row for part in raw.strip().split('\n\n') if (row:=pairs(part))}
    code="import http.client; c=http.client.HTTPConnection('127.0.0.1',8080,timeout=2); c.request('GET','/health/',headers={'Host':'j2-svpi4mf.local.theama.co'}); print(c.getresponse().status); c.close()"
    health=command(USER+['/usr/bin/podman','exec','nautobot-web','python3','-c',code]).strip()
    return {'monotonic':time.monotonic(),'utc':time.time(),
        'boot_id':Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
        'units':units,'sessions':sessions(),'http_status':health}


def check_sample(row, expected, allowed_managers):
    require(row['boot_id']==expected['boot_id'],'boot_changed')
    require(row['http_status']=='200','health_failed')
    require(set(row['units'])=={'nautobot-'+r+'.service' for r in ROLES},'service_set')
    for role in ROLES:
        unit=row['units']['nautobot-'+role+'.service']; want=expected['services'][role]
        require(unit.get('ActiveState')=='active' and unit.get('SubState')=='running' and unit.get('Result')=='success','service_state')
        require(unit.get('InvocationID')==want['InvocationID'] and unit.get('NRestarts')==want['NRestarts'],'service_changed')
    require(set(row['sessions'])==set(allowed_managers),'login_session_present')
    for sid, previous in allowed_managers.items():
        require(row['sessions'][sid]==previous and manager(row['sessions'][sid]),'manager_changed')


def write(root, name, value):
    fd=os.open(root/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'w') as stream:
        json.dump(value,stream,sort_keys=True);stream.write('\n');stream.flush();os.fsync(stream.fileno())


def artifacts(op):
    for path,digest in op['baseline']['artifact_sha256'].items():
        p=Path(path)
        require(not p.is_symlink() and p.is_file() and p.stat().st_size<1048576,'artifact_metadata')
        require(hashlib.sha256(p.read_bytes()).hexdigest()==digest,'artifact_changed')
    command(['/usr/bin/python3','-I','/usr/local/lib/nautobot-network/backend_guard.py','check'])


def preflight(root, op):
    require(command(['/usr/bin/hostname']).strip()=='j2-svpi4mf','target')
    artifacts(op)
    recovery=Path(op['recovery']['cold_copy'])
    require(recovery.is_dir() and not recovery.is_symlink() and recovery.stat().st_uid==0
            and recovery.stat().st_mode&0o777==0o700,'recovery_metadata')
    require(all((recovery/name).is_dir() for name in ('nautobot-postgresql_data','nautobot-redis_data')),'recovery_missing')
    row=snapshot()
    require(all(manager(x) for x in row['sessions'].values()),'unowned_login_session')
    check_sample(row,op['baseline'],row['sessions'])
    raw=command(['/usr/bin/journalctl','-n','0','--show-cursor','--no-pager'])
    cursors=[line.removeprefix('-- cursor: ') for line in raw.splitlines() if line.startswith('-- cursor: ')]
    require(len(cursors)==1,'journal_cursor')
    write(root,'before.json',{'sample':row,'cursor':cursors[0]})


def owned_session(before, now, pid):
    require(pid.isdigit() and int(pid)>1,'test_pid')
    require(all(now.get(k)==v for k,v in before.items()),'existing_session_changed')
    added=set(now)-set(before)
    require(len(added)==1,'session_registration')
    sid=added.pop(); row=now[sid]
    require(row.get('User')=='999' and row.get('Service')=='login' and row.get('Leader')==pid
            and row.get('Class') not in ('manager','manager-early') and row.get('State')=='active','session_ownership')
    return sid


def identify(root, op):
    before=json.loads((root/'before.json').read_text())['sample']['sessions']
    pid=command(['/usr/bin/systemctl','show',op['test_unit'],'--property=MainPID','--value']).strip()
    sid=owned_session(before,sessions(),pid)
    write(root,'owned-session.json',{'id':sid,'leader':pid,'unit':op['test_unit']})


def closed(root, op):
    before=json.loads((root/'before.json').read_text())['sample']['sessions']
    require(sessions()==before,'session_not_closed')
    raw=pairs(command(['/usr/bin/systemctl','show',op['test_unit'],'--property=ActiveState,MainPID']))
    require(raw.get('ActiveState') in ('inactive','failed') and raw.get('MainPID')=='0','test_unit_not_stopped')
    write(root,'closed.json',{'utc':time.time(),'monotonic':time.monotonic(),'session_absent':True})


def observe(root, op):
    before=json.loads((root/'before.json').read_text()); closure=json.loads((root/'closed.json').read_text())
    result={'passed':False,'reason':'observer_interrupted'}
    try:
        require(0<=time.monotonic()-closure['monotonic']<=30,'observation_start_gap')
        start=time.monotonic(); last=None; count=0
        with (root/'samples.jsonl').open('x') as stream:
            while True:
                row=snapshot(); check_sample(row,op['baseline'],before['sample']['sessions'])
                require(row['monotonic']-(start if last is None else last)<=10,'collection_gap')
                stream.write(json.dumps(row)+'\n');stream.flush();os.fsync(stream.fileno())
                count+=1;last=row['monotonic']
                if last-start>=300:break
                time.sleep(max(0,5-(time.monotonic()-row['monotonic'])))
        # Require the original cursor to remain available; an empty journal is
        # not sufficient evidence of an error-free window.
        cursor=before['cursor']
        raw=command(['/usr/bin/journalctl','--cursor',cursor,'-n','+1','-o','json','--output-fields=__CURSOR','--quiet','--no-pager'])
        rows=[json.loads(x) for x in raw.splitlines()]
        require(len(rows)==1 and rows[0].get('__CURSOR')==cursor,'journal_gap')
        raw=command(['/usr/bin/journalctl','--after-cursor',cursor,'_TRANSPORT=kernel','-o','json','--output-fields=MESSAGE','--quiet','--no-pager'])
        rows=[json.loads(x) for x in raw.splitlines()]
        require(all(isinstance(r.get('MESSAGE'),str) for r in rows),'journal_message')
        require(not any(STORAGE.search(r['MESSAGE']) for r in rows),'storage_event')
        artifacts(op)
        result={'passed':True,'samples':count,'duration_seconds':last-start,'scope':'PAM_session_logout_only'}
    except Exception as exc:
        allowed={'observation_start_gap','collection_gap','journal_gap','journal_message','storage_event','artifact_changed','artifact_metadata',
                 'boot_changed','health_failed','service_set','service_state','service_changed','login_session_present','manager_changed','collection_failed','user_or_linger'}
        result['reason']=str(exc) if isinstance(exc,ValueError) and str(exc) in allowed else 'collection_unavailable'
    finally:write(root,'result.json',result)
    require(result['passed'],'observation_failed')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('action',choices=('preflight','identify','closed','observe'))
    args=parser.parse_args();root=args.root
    require(os.geteuid()==0 and re.fullmatch(r'/tmp/nautobot-logout\.[0-9a-f]{32}',str(root)),'root_boundary')
    require(not any(p.is_symlink() for p in (root,*root.parents)) and root.stat().st_uid==0 and root.stat().st_mode&0o777==0o700,'root_metadata')
    op=json.loads((root/'operation.json').read_text())
    require(op['root']==str(root),'operation_root')
    globals()[args.action](root,op)

if __name__=='__main__':
    try:main()
    except Exception:raise SystemExit(69)
