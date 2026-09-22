#!/usr/bin/env python3
"""Native continuation with allowlisted, flushed progress; no raw output retained."""
import hashlib
import inspect
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time

PHASES = {
    'Performing database migrations...': 'migrate', 'Clearing cache...': 'clear_cache',
    'Generating cable paths...': 'trace_paths', 'Collecting static files...': 'collectstatic',
    'Removing stale content types...': 'remove_stale_contenttypes', 'Removing expired sessions...': 'clearsessions',
    'Sending installation metrics...': 'send_installation_metrics',
    '--no-send-installation-metrics was specified; skipping installation metrics.': 'metrics_skipped',
    'Refreshing _content_type cache': 'refresh_content_type_cache',
    'Refreshing dynamic group member caches...': 'refresh_dynamic_group_member_caches',
}
STEPS = [('configuration', ['check']), ('plan', ['shell', '--interface', 'python', '--command',
          "exec(compile(open('/run/migration-continuation.py').read(), '/run/migration-continuation.py', 'exec'), {'__name__':'migration_plan'})"]),
         ('post_upgrade', ['post_upgrade']), ('configuration_after', ['check']), ('pending_migrations', ['migrate', '--check'])]
FAILURES = {'migration_graph_conflict', 'ledger_drift', 'unreviewed_migration', 'migration_source_drift', 'non_atomic_migration', 'migration_identifier', 'plan_size', 'plan_failed', 'plan_format', 'plan_identifier', 'missing_plan', 'resource_limits', 'progress_limit', 'deadline', 'native_failed', 'graph_initialization_failed'}
PLAN_PREFIX = 'NAUTOBOT_PLAN='
PREFIX = 'NAUTOBOT_CONTINUATION_RESULT='


def require(ok, code):
    if not ok:
        raise ValueError(code)


def validate_plan(executor, contract):
    """Uses Django's native loaded graph, history and forward plan, including Apps."""
    loader = executor.loader
    loader.check_consistent_history(executor.connection)
    require(not loader.detect_conflicts(), 'migration_graph_conflict')
    require(sorted([list(k) for k in loader.applied_migrations]) == contract['applied'], 'ledger_drift')
    plan = executor.migration_plan(loader.graph.leaf_nodes())
    result = []
    for migration, backwards in plan:
        module = migration.__class__.__module__
        require(not backwards and module in contract['modules'], 'unreviewed_migration')
        source = Path(inspect.getsourcefile(migration.__class__))
        require(hashlib.sha256(source.read_bytes()).hexdigest() == contract['modules'][module]['sha256'], 'migration_source_drift')
        require(migration.atomic or module in contract['reviewed_non_atomic'], 'non_atomic_migration')
        key = [migration.app_label, migration.name]
        require(all(re.fullmatch(r'[A-Za-z0-9_]{1,180}', s) for s in key), 'migration_identifier')
        result.append(key)
    require(len(result) <= 1000, 'plan_size')
    return result


def native_plan():
    from django.db import connection
    from django.db.migrations.executor import MigrationExecutor
    contract = json.loads(Path('/run/migration-continuation-inputs.json').read_text())
    try:
        plan = validate_plan(MigrationExecutor(connection), contract)
        print(PLAN_PREFIX + json.dumps({'passed': True, 'pending': plan}), flush=True)
    except Exception as exc:
        # Django may include connection details in exceptions. Never print them.
        code = str(exc) if isinstance(exc, ValueError) and str(exc) in FAILURES else 'graph_initialization_failed'
        print(PLAN_PREFIX + json.dumps({'passed': False, 'pending': [], 'error': code}), flush=True)
        raise SystemExit(69)
    finally:
        connection.close()


class Progress:
    def __init__(self, emit, known):
        self.emit = emit
        self.known = set(known)
        self.buffers = {}
        self.dropping = set()
        self.started = set()
        self.plan = None
        self.plan_seen = 0

    def line(self, raw, partial=False):
        text = raw.decode('utf-8', errors='replace')
        if not partial and text in PHASES:
            self.emit('phase', phase=PHASES[text])
        m = re.fullmatch(r'  Applying ([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)\.\.\.(.*)', text)
        matches = [k for k in self.known if (k[0]+'.'+k[1])[:50] == (m[1]+'.'+m[2])] if m else []
        if len(matches) == 1:
            key = matches[0]
            if key not in self.started:
                self.emit('migration_start', app=key[0], migration=key[1]); self.started.add(key)
            if not partial and re.fullmatch(r'\s*OK(?:\s*\(\s*[0-9.]+s\)|\s+[0-9.]+s)?\s*', m[3]):
                self.emit('migration_complete', app=key[0], migration=key[1])
        if not partial and text.startswith(PLAN_PREFIX):
            self.plan_seen += 1
            v = json.loads(text[len(PLAN_PREFIX):])
            if v.get('passed') is False:
                code = v.get('error')
                raise ValueError(code if code in FAILURES else 'plan_failed')
            require(set(v) == {'passed', 'pending'} and v['passed'] is True, 'plan_failed')
            require(isinstance(v['pending'], list) and len(v['pending']) <= 1000, 'plan_format')
            require(all(isinstance(k, list) and len(k) == 2 and tuple(k) in self.known for k in v['pending']), 'plan_identifier')
            self.plan = v['pending']

    def feed(self, stream, data):
        buf = self.buffers.get(stream, b'')
        for part in data.splitlines(keepends=True):
            newline = part.endswith(b'\n')
            if stream not in self.dropping:
                buf += part.rstrip(b'\r\n') if newline else part
                if len(buf) > 262144:
                    self.dropping.add(stream); buf = b''
                elif newline:
                    self.line(buf); buf = b''
                else:
                    self.line(buf, partial=True)
            if newline:
                self.dropping.discard(stream); buf = b''
        self.buffers[stream] = buf


def run(argv, timeout, observer):
    p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         env={**os.environ, 'PYTHONUNBUFFERED': '1'}, start_new_session=True)
    end = time.monotonic() + timeout
    selector = selectors.DefaultSelector(); count = 0
    for stream in (p.stdout, p.stderr):
        os.set_blocking(stream.fileno(), False); selector.register(stream, selectors.EVENT_READ)
    error = None; completed = False
    try:
        while selector.get_map():
            if time.monotonic() >= end:
                error = 'timeout'; break
            for key, _ in selector.select(min(.2, max(0, end-time.monotonic()))):
                data = os.read(key.fileobj.fileno(), 65536)
                if not data:
                    selector.unregister(key.fileobj); continue
                count += len(data)
                if count > 8*1024*1024:
                    error = 'output_limit'; break
                observer.feed('stdout' if key.fileobj is p.stdout else 'stderr', data)
            if error:
                break
        rc = None if error else p.wait(timeout=max(.01, end-time.monotonic()))
        completed = True
        return {'exit_status': rc, 'error': error, 'bytes': count}
    except subprocess.TimeoutExpired:
        return {'exit_status': None, 'error': 'timeout', 'bytes': count}
    finally:
        # Kill the whole native process group on timeout/parser failure, including descendants.
        if not completed or p.poll() is None or error:
            try: os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError: pass
        p.wait(); selector.close(); p.stdout.close(); p.stderr.close()


def continue_application(contract, evidence, token, runner=run, boundary=True):
    start = time.monotonic(); count = 0
    result = {'passed': False, 'token': token, 'steps': {}, 'migration_attempted': False}
    # Owned tmpfs directory is mounted into only this bounded migration container.
    def emit(event, **values):
        nonlocal count
        require(count < 5000, 'progress_limit'); count += 1
        record = {'event': event, 'elapsed': round(time.monotonic()-start, 3), 'token': token, **values}
        with (evidence/'progress.jsonl').open('a') as f:
            f.write(json.dumps(record, sort_keys=True)+'\n'); f.flush(); os.fsync(f.fileno())
    # Module keys supply known migration names; app labels are supplied by the reviewed ledger
    # and static mapping, not arbitrary child output.
    known = [tuple(k) for k in contract['known_migrations']]
    try:
        if boundary:
            require(Path('/sys/fs/cgroup/memory.max').read_text().strip() == '1610612736'
                    and Path('/sys/fs/cgroup/memory.swap.max').read_text().strip() == '0'
                    and os.getuid() == 999, 'resource_limits')
            result.update(memory_limit_bytes=1610612736, swap_limit_bytes=0, uid=os.getuid())
            import tempfile
            for name in ('git', 'jobs', 'media', 'static'):
                with tempfile.TemporaryFile(dir='/opt/nautobot/'+name): pass
        for name, args in STEPS:
            remaining = 1800-(time.monotonic()-start)
            require(remaining > 0, 'deadline')
            emit('step_start', step=name)
            observer = Progress(emit, known)
            if name == 'post_upgrade': result['migration_attempted'] = True
            r = runner(['nautobot-server']+args+['--no-color'], remaining, observer)
            result['steps'][name] = r
            emit('step_end', step=name, exit_status=r['exit_status'], error=r.get('error'))
            require(r['exit_status'] == 0 and not r.get('error'), 'native_failed')
            if name == 'plan':
                require(observer.plan_seen == 1 and observer.plan is not None, 'missing_plan')
                result['pending_before'] = observer.plan
                known = [tuple(k) for k in observer.plan]
        result['passed'] = True
    except Exception as exc:
        result['error'] = str(exc) if isinstance(exc, ValueError) and str(exc) in FAILURES else 'continuation_failed'
    finally:
        result['elapsed'] = round(time.monotonic()-start, 3)
        (evidence/'receipt.json').write_text(json.dumps(result, sort_keys=True)+'\n')
    return result


def main():
    os.umask(0o077)
    evidence = Path('/run/continuation-evidence')
    require(evidence.is_dir() and not evidence.is_symlink(), 'evidence_directory')
    require(not any(evidence.iterdir()), 'existing_receipt')
    token = os.environ['CONTINUATION_TOKEN']
    require(re.fullmatch('[0-9a-f]{64}', token), 'token')
    contract = json.loads(Path('/run/migration-continuation-inputs.json').read_text())
    result = continue_application(contract, evidence, token)
    print(PREFIX+json.dumps({'passed':result['passed'], 'token':token}), flush=True)
    return 0 if result['passed'] else 69


if __name__ == 'migration_plan': native_plan()
if __name__ == '__main__': raise SystemExit(main())
