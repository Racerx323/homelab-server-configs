#!/usr/bin/env python3
"""Delete only verified successful payload files; caller holds the run/state locks."""
import hashlib
import json
import os
import re
import stat


def dispose(root, protected, require, atomic):
    protected(root,True)
    def read(name):
        path=root/name; protected(path)
        require(path.stat().st_size<1048576,'disposal_receipt_size')
        return json.loads(path.read_text())
    spec=read('application-backup.json')
    capture=read('application-capture-result.json')
    result=read('application-backup-result.json')
    identity=hashlib.sha256(json.dumps(spec,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    names=set(spec['captures'])
    require(0<len(names)<=16 and all(re.fullmatch('[a-z_]+',n) for n in names),'disposal_names')
    require(spec['operation_id']=='nautobot-recurring','disposal_operation')
    for row in (capture,result):
        require(row.get('specification_sha256')==identity and row.get('capture_passed') is True
                and set(row.get('content_sha256',{}))==names
                and all(row.get('credential_cleanup',{}).get(k) is True for k in ('password','credentials.json')),
                'disposal_capture_receipt')
    require(result.get('upload_passed') is True and result.get('integrity_passed') is True
            and result.get('backup_exit_status')==0 and result.get('integrity_exit_status')==0
            and re.fullmatch('[0-9a-f]{64}',result.get('snapshot_id') or '')
            and result.get('new_snapshot_ids')==[result['snapshot_id']]
            and result['content_sha256']==capture['content_sha256'],'disposal_backup_receipt')
    payload=root/'payload'; protected(payload,True)
    fd=os.open(payload,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
    try:
        require(set(os.listdir(fd))==names,'disposal_membership')
        identities={}
        for name in sorted(names):
            child=os.open(name,os.O_RDONLY|os.O_NOFOLLOW,dir_fd=fd)
            with os.fdopen(child,'rb') as stream:
                info=os.fstat(stream.fileno())
                require(stat.S_ISREG(info.st_mode) and info.st_uid==os.getuid() and info.st_nlink==1
                        and stat.S_IMODE(info.st_mode)==0o600 and 0<info.st_size<spec['captures'][name]['maximum_bytes'],
                        'disposal_file')
                digest=hashlib.file_digest(stream,'sha256').hexdigest()
                require(digest==capture['content_sha256'][name],'disposal_content')
                identities[name]=(info.st_dev,info.st_ino)
        atomic(root/'payload-disposal.json',{'phase':'verified','snapshot_id':result['snapshot_id'],'files':sorted(names)})
        for name in sorted(names):
            info=os.stat(name,dir_fd=fd,follow_symlinks=False)
            require((info.st_dev,info.st_ino)==identities[name],'disposal_race')
            os.unlink(name,dir_fd=fd)
        os.fsync(fd)
        # Keep the empty owned directory; never recursively delete a run root.
        atomic(root/'payload-disposal.json',{'phase':'complete','snapshot_id':result['snapshot_id'],'files':sorted(names)})
    finally: os.close(fd)
