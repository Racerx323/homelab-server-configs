#!/usr/bin/env python3
"""Migration container entrypoint: native checks, bounded output, safe receipt."""
import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time

PREFIX = 'NAUTOBOT_INITIALIZATION_RESULT='
STEPS = [('configuration', ['check']), ('post_upgrade', ['post_upgrade']),
         ('configuration_after', ['check']), ('pending_migrations', ['migrate', '--check'])]


def command(argv, timeout):
    # Drain/discard output, without imposing a file-size limit on static assets.
    try:p=subprocess.Popen(argv,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    except OSError:return {'exit_status':None,'error':'command_unavailable'}
    deadline=time.monotonic()+timeout;counts={};selector=selectors.DefaultSelector()
    for stream in (p.stdout,p.stderr):
        os.set_blocking(stream.fileno(),False);selector.register(stream,selectors.EVENT_READ);counts[stream]=0
    error=None
    try:
        while selector.get_map():
            if time.monotonic()>=deadline:error='timeout';break
            for key,_ in selector.select(min(0.1,max(0,deadline-time.monotonic()))):
                data=os.read(key.fileobj.fileno(),65536)
                if not data:selector.unregister(key.fileobj);continue
                counts[key.fileobj]+=len(data)
                if counts[key.fileobj]>=4194304:error='output_limit';break
            if error:break
        if error:
            p.kill();p.wait()
            return {'exit_status':None,'error':error,'output_limited':error=='output_limit'}
        return {'exit_status':p.wait(timeout=max(0.01,deadline-time.monotonic())),'output_limited':False}
    except subprocess.TimeoutExpired:
        p.kill();p.wait();return {'exit_status':None,'error':'timeout'}
    finally:
        selector.close();p.stdout.close();p.stderr.close()


def initialize(runner=command, clock=time.monotonic, inspect=True):
    result = {'passed': False, 'steps': {}, 'migration_attempted': False}
    start = clock()
    try:
        if inspect:
            memory = Path('/sys/fs/cgroup/memory.max').read_text().strip()
            swap = Path('/sys/fs/cgroup/memory.swap.max').read_text().strip()
            if memory != '1610612736' or swap != '0':
                raise ValueError('resource_limits')
            if os.getuid() == 0:
                raise ValueError('application_must_be_unprivileged')
            result.update(memory_limit_bytes=int(memory), swap_limit_bytes=0, uid=os.getuid())
            for path in ('git', 'jobs', 'media', 'static'):
                try:
                    with tempfile.TemporaryFile(dir='/opt/nautobot/'+path):pass
                except OSError:
                    raise ValueError('writable_'+path) from None
        for name, argv in STEPS:
            remaining = 840 - (clock() - start)
            if remaining <= 0:
                raise ValueError('deadline')
            if name == 'post_upgrade': result['migration_attempted'] = True
            step = runner(['nautobot-server'] + argv, remaining)
            result['steps'][name] = step
            if step.get('exit_status') != 0 or step.get('output_limited'):
                return result
        result['passed'] = True
    except Exception as exc:
        allowed={'resource_limits','application_must_be_unprivileged','deadline',
                 'writable_git','writable_jobs','writable_media','writable_static'}
        result['error'] = str(exc) if isinstance(exc,ValueError) and str(exc) in allowed else 'startup_or_boundary_failed'
    return result


if __name__ == '__main__':
    result = initialize()
    print(PREFIX + json.dumps(result, sort_keys=True), flush=True)
    raise SystemExit(0 if result['passed'] else 69)
