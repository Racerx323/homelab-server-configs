#!/usr/bin/env python3
"""Unattended credentials and temporary direct standardized Apprise alerts."""
from datetime import datetime, timezone
import json
import hashlib
import http.client
import re
from urllib.parse import urlsplit
import os
from pathlib import Path
import resource
import subprocess
import tempfile
import time
from recurring_protection import atomic, protected, require, lock

NAMES = ('NAUTOBOT_RESTIC_REPOSITORY_PASSWORD', 'NAUTOBOT_RESTIC_B2_APPLICATION_KEY_ID',
         'NAUTOBOT_RESTIC_B2_APPLICATION_KEY')
ENDPOINT = 'http://10.1.3.83:8000/notify/apprise'


def resolve(contract, root):
    """No fallback, personal CLI configuration, provider mutation or secret receipt."""
    protected(root, True)
    require(contract['project'] == 'homelab-dev' and contract['config'] == 'prd_nautobot_backup', 'credential_scope')
    expiry=datetime.fromisoformat(contract['expires_at'])
    require(expiry.tzinfo is not None and contract['read_only'] is True and expiry.astimezone(timezone.utc)
            > datetime.now(timezone.utc), 'credential_expired_or_unreviewed')
    token_path = Path(contract['token_file']); protected(token_path)
    require(token_path.stat().st_size <= 4096, 'token_size')
    token = token_path.read_text().strip()
    require(token.startswith('dp.st.') and not any(c in token for c in '\r\n\x00'), 'service_token_required')
    require(Path(contract['doppler']).is_absolute(), 'doppler_path')
    values = []
    try:
        with tempfile.TemporaryDirectory(prefix='doppler-runtime.', dir=root) as home:
            env = {'HOME':home, 'PATH':'/usr/bin:/bin', 'LC_ALL':'C.UTF-8', 'DOPPLER_TOKEN':token}
            for name in NAMES:
                with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
                    def limit(): resource.setrlimit(resource.RLIMIT_FSIZE, (65536,65536))
                    try:
                        result = subprocess.run([contract['doppler'], '--no-check-version', '--project', contract['project'],
                            '--config', contract['config'], 'secrets', 'get', name, '--plain'],
                            env=env, cwd=home, stdin=subprocess.DEVNULL, stdout=out, stderr=err, timeout=20, preexec_fn=limit)
                    except (OSError, subprocess.TimeoutExpired): raise ValueError('credential_fetch_failed') from None
                    require(result.returncode == 0 and 0 < out.tell() <= 16384, 'credential_fetch_failed')
                    out.seek(0); value=out.read().decode().rstrip('\n')
                    require(value and not any(c in value for c in '\r\n\x00'), 'credential_shape')
                    values.append(value)
        for name, raw in [('source-password',values[0].encode()),
                          ('source-credentials.json',json.dumps(dict(id=values[1],key=values[2])).encode())]:
            fd=os.open(root/name, os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
            with os.fdopen(fd,'wb') as out: out.write(raw)
    except Exception:
        for name in ('source-password','source-credentials.json'):
            path=root/name
            if path.exists(): protected(path); path.unlink()
        raise



def format_alert(contract, payload):
    require(set(payload)=={'event_id','event','observed','severity','transition','impact','failure_class'},'notification_fields')
    require(payload['event'] in ('failure','recovery','missed') and re.fullmatch('[0-9a-f]{64}',payload['event_id']),'notification_identity')
    require(payload['severity']==('success' if payload['event']=='recovery' else 'failure'),'notification_severity')
    require(re.fullmatch(r'(unknown|failure|recovery|missed) -> (failure|recovery|missed)',payload['transition']),'notification_transition')
    require(payload['impact'] in ('Protection restored.','Application recovery coverage needs review.'),'notification_impact')
    require(payload['failure_class'] in ('none','backup-or-writer-recovery','missed-schedule'),'notification_class')
    require(len(payload['observed'])<=40 and datetime.fromisoformat(payload['observed']).tzinfo is not None,'notification_time')
    for key in ('hostname','fqdn'):
        require(re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9.-]{0,252}',contract[key]),'notification_node')
    icon='✅' if payload['event']=='recovery' else '🚨'
    title=f"{icon} [Nautobot] {payload['event'].capitalize()} on {contract['hostname']}"
    body=(f"Summary\n- Node: {contract['fqdn']}\n- Component: recurring application backup\n"
          f"- Event: {payload['event']}\n- State: {payload['transition']}\n\n"
          f"Impact\n{payload['impact']}\n\nDetails\n- Check: nightly-protection\n"
          f"- Failure class: {payload['failure_class']}\n- Observed: {payload['observed']}\n"
          f"- Correlation: {payload['event_id']}\n\nNext step\n"
          "- Evidence: journalctl --user -u nautobot-protection.service\n"
          "- First check: systemctl --user status nautobot-protection.service")
    require(len((title+body).encode())<=4096,'notification_size')
    return dict(title=title,body=body,type=payload['severity'],format='text')


def send_direct(contract,payload):
    """Interim user-selected delivery; no redirects, raw output, or queue claims."""
    require(contract['method']=='direct_apprise' and contract['endpoint']==ENDPOINT,'notification_destination')
    message=format_alert(contract,payload)
    parsed=urlsplit(ENDPOINT)
    conn=http.client.HTTPConnection(parsed.hostname,parsed.port,timeout=5)
    try:
        conn.request('POST',parsed.path,body=json.dumps(message).encode(),headers={
            'Content-Type':'application/json','Idempotency-Key':payload['event_id']})
        return conn.getresponse().status==200
    except (OSError,http.client.HTTPException): return False
    finally: conn.close()


def notify(state_directory, event, contract, sender=send_direct, now=None):
    """Persist transition before direct delivery; retry without changing backup state."""
    require(event in ('failure','recovery','missed'), 'notification_event')
    protected(state_directory, True)
    now=time.time() if now is None else now
    path=state_directory/'notification.json'
    with lock(state_directory/'notification.lock'):
        previous={}
        if path.exists():
            protected(path); require(path.stat().st_size<16384,'notification_state_size'); previous=json.loads(path.read_text())
        # A pending transition is retried unchanged before acknowledging a later one.
        pending=previous.get('pending')
        if pending is not None:
            if not sender(contract,pending): return False
            previous=dict(acknowledged=pending['event'],sequence=previous['sequence'],pending=None)
            atomic(path,previous)
        if previous.get('acknowledged')==event: return True
        if event=='recovery' and not previous: return True
        sequence=previous.get('sequence',0)+1
        event_id=hashlib.sha256((str(state_directory)+':'+str(sequence)+':'+event).encode()).hexdigest()
        payload=dict(event_id=event_id,event=event,observed=datetime.fromtimestamp(now,timezone.utc).isoformat(),severity='success' if event=='recovery' else 'failure',
            transition=previous.get('acknowledged','unknown')+' -> '+event,
            impact='Protection restored.' if event=='recovery' else 'Application recovery coverage needs review.',
            failure_class={'recovery':'none','failure':'backup-or-writer-recovery','missed':'missed-schedule'}[event])
        previous.update(sequence=sequence,pending=payload,observed_at=now)
        atomic(path,previous)
        if not sender(contract,payload): return False
        atomic(path,dict(acknowledged=event,sequence=sequence,pending=None))
        return True
