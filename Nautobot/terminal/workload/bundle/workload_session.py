"""Node-local timing/stop boundary; Ansible owns staging and operation lifecycle.

No SSH, service restarts, fixture deletion, restore or generic shell commands.
Backup execution is a separately approved Restic-owner input to the bundle.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import threading
import subprocess
import tempfile
import time
import uuid
from concurrent.futures import ThreadPoolExecutor

import workload_sampler as sampler


def require(value, code):
    if not value: raise ValueError(code)


def save(path, value):
    data = json.dumps(value, sort_keys=True).encode() + b'\n'
    require(len(data) <= 4194304, 'receipt_size')
    temporary = path.with_suffix('.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as out:
        out.write(data); out.flush(); os.fsync(out.fileno())
    os.replace(temporary, path)


def verify_backup(receipt, jobs, operation):
    """A verified owner receipt is required; no canary or enqueue-time overlap."""
    require(receipt['kind'] == 'application_backup' and receipt['operation_id'] == operation, 'backup_identity')
    require(receipt['upload_passed'] is True and receipt['integrity_passed'] is True, 'backup_failed')
    require(receipt.get('credential_cleanup') == {'password': True, 'credentials.json': True}, 'backup_credentials_remain')
    require(__import__('re').fullmatch('[0-9a-f]{64}', receipt['snapshot_id']), 'backup_snapshot')
    required = {'postgresql_custom_dump', 'media', 'configuration', 'image_dependency_manifest', 'quadlet_config_hashes', 'versions_migrations'}
    require(set(receipt['content_sha256']) == required and all(__import__('re').fullmatch('[0-9a-f]{64}', x) for x in receipt['content_sha256'].values()), 'backup_content')
    start, end = receipt['started'], receipt['finished']
    require(start < end, 'backup_timing')
    require(any(j['started'] is not None and j['done'] is not None and max(start, j['started']) < min(end, j['done']) for j in jobs), 'backup_did_not_overlap_jobs')


class Session:
    def __init__(self, root, contract, client, backup, clock=time.monotonic, sleep=time.sleep, ownership=None):
        self.root, self.contract, self.client, self.backup = root, contract, client, backup
        self.clock, self.sleep = clock, sleep
        self.owned, self.jobs, self.phases, self.ownership = [], [], [], ownership
        self.monitor = None
        self.backup_future = None
        self.failure = threading.Event()
        self.stop_lock = threading.Lock()
        self.stop_result = None
        self.timing = []
        self.timing_lock = threading.Lock()
        self.started = clock()

    def healthy(self):
        require(not self.failure.is_set(), 'monitor_failed')
        require(self.clock() - self.started < self.contract['limits']['whole_workload_timeout_seconds'], 'whole_timeout')
        if self.backup_future is not None and self.backup_future.done():
            self.backup_future.result()  # Stop further load immediately on backup failure.
        if self.monitor is not None and self.monitor.done():
            self.monitor.result()  # Preserves the sampler's specific failure.
            raise ValueError('sampler_stopped_early')

    def wait(self, deadline):
        while self.clock() < deadline:
            self.healthy(); self.sleep(min(1, deadline - self.clock()))

    def submit(self, kind, dataset, count=1):
        self.healthy()
        identities = [str(uuid.uuid4()) for _ in range(count)]
        self.owned.extend(identities)
        save(self.root/'owned-jobs.json', self.owned)
        kwargs = {'dataset': dataset}
        if self.ownership is not None: kwargs['ownership'] = self.ownership
        self.healthy()
        requests = [{'action': 'submit', 'kind': kind, 'id': identity, 'kwargs': kwargs} for identity in identities]
        self.client({'action': 'submit_batch', 'requests': requests})
        return identities

    def event(self, action):
        with self.timing_lock:
            self.timing.append({'event': action, 'utc_seconds': time.time()})
            save(self.root/'timing.json', self.timing)

    def statuses(self, ids):
        rows = self.client({'action': 'status_batch', 'ids': ids})['results']
        require(len(rows) == len(ids) and {r['id'] for r in rows} == set(ids), 'status_coverage')
        return rows

    def running(self, ids):
        deadline = self.clock() + self.contract['limits']['single_job_timeout_seconds']
        while True:
            self.healthy()
            require(self.clock() < deadline, 'audit_start_timeout')
            rows = self.statuses(ids)
            require(not any(r['terminal'] for r in rows), 'audits_finished_before_backup')
            if all(r['status'] == 'STARTED' and r['started'] is not None for r in rows):
                self.event('audit_pair_running_observed')
                return
            self.wait(min(deadline, self.clock() + 1))

    def completed(self, ids):
        deadline = self.clock() + self.contract['limits']['single_job_timeout_seconds']
        receipts = {}
        while len(receipts) < len(ids):
            self.healthy()
            require(self.clock() < deadline, 'job_timeout')
            for row in self.statuses([i for i in ids if i not in receipts]):
                identity = row['id']
                if row['terminal']:
                    require(row['status'] == 'SUCCESS' and row['started'] is not None and row['done'] is not None, 'job_failed')
                    receipts[identity] = row
            if len(receipts) < len(ids): self.wait(min(deadline, self.clock() + 1))
        self.jobs.extend(receipts.values())
        save(self.root/'job-results.json', self.jobs)
        return [receipts[i] for i in ids]

    def cancel_owned(self):
        with self.stop_lock:
            if self.stop_result is not None: return self.stop_result
            self.event('stop_started')
            try:
                outcome = self.client({'action': 'cancel_batch', 'ids': list(self.owned)})['results'] if self.owned else []
                require(len(outcome) == len(self.owned) and {r['id'] for r in outcome} == set(self.owned), 'stop_coverage')
            except Exception as error:
                outcome = [{'id': i, 'stopped': False, 'error_class': type(error).__name__} for i in self.owned]
            save(self.root/'stop-results.json', outcome)
            self.stop_result = all(r.get('stopped') is True for r in outcome)
            self.event('stop_finished')
            return self.stop_result

    def execute(self, dataset, operation):
        backup_receipt = None
        try:
            for phase in self.contract['phases']:
                start = self.phases[-1]['end'] if self.phases else self.clock()
                if phase['id'] == 'import_and_export':
                    for _ in range(self.contract['jobs'][0]['repetitions']):
                        result = self.completed(self.submit('import', dataset))[0]['result']
                        if self.ownership is not None: require(result['receipt'] == self.ownership, 'repeat_ownership_changed')
                        self.ownership = result['receipt']
                        save(self.root/'ownership.json', self.ownership)
                    exports = [self.completed(self.submit('export', dataset))[0]['result'] for _ in range(self.contract['jobs'][1]['repetitions'])]
                    require(len({r['sha256'] for r in exports}) == 1, 'export_changed')
                if phase['id'] == 'jobs_and_backup_overlap':
                    pool = ThreadPoolExecutor(max_workers=1)
                    try:
                        self.event('audit_pair_dispatch_started')
                        first_pair = self.submit('audit', dataset, count=2)
                        self.event('audit_pair_dispatch_returned')
                        self.running(first_pair)
                        self.healthy()
                        self.event('backup_launch_requested')
                        pending = pool.submit(self.backup)
                        self.backup_future = pending
                        audits = []
                        for index in range(self.contract['jobs'][2]['repetitions']//2):
                            pair = self.completed(first_pair if index == 0 else self.submit('audit', dataset, count=2))
                            require(max(r['started'] for r in pair) < min(r['done'] for r in pair), 'audit_concurrency_unproven')
                            audits.extend(pair)
                        while not pending.done(): self.wait(self.clock() + 1)
                        backup_receipt = pending.result()
                    except BaseException:
                        self.failure.set()  # Interrupt the backup before joining its thread.
                        raise
                    finally:
                        pool.shutdown(wait=True, cancel_futures=True)
                    verify_backup(backup_receipt, audits, operation)
                    save(self.root/'backup-result.json', backup_receipt)
                self.wait(start + phase['minimum_seconds'])
                self.phases.append({'id': phase['id'], 'start': start, 'end': self.clock()})
                save(self.root/'phases.json', self.phases)
            return {'jobs_passed': True, 'backup_overlap_passed': backup_receipt is not None}
        except BaseException:
            self.failure.set()
            self.cancel_owned()
            raise


def native_command(argv, source, timeout=60):
    """Bound controller streams without changing container inherited rlimits."""
    require(len(source) < 4194304, 'native_request_limit')
    with tempfile.TemporaryFile() as incoming, tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        incoming.write(source); incoming.seek(0)
        process = subprocess.Popen(argv, stdin=incoming, stdout=out, stderr=err, cwd='/')
        try:
            deadline=time.monotonic()+timeout
            while process.poll() is None:
                require(time.monotonic()<deadline, 'native_bridge_timeout')
                require(out.tell()<4194304 and err.tell()<4194304, 'native_bridge_output_limit')
                time.sleep(0.02)
            require(process.returncode==0 and out.tell()<4194304 and err.tell()<4194304, 'native_bridge_failed')
            out.seek(0); return out.read().decode()
        finally:
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--preflight', action='store_true')
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    specification = json.loads((root/'execution.json').read_text())
    contract = json.loads((root/'contract.json').read_text())
    require(specification['execution_authorized'] is True and specification['backup']['authorized'] is True, 'not_authorized')
    require(not (root/'owned-jobs.json').exists(), 'already_consumed')
    initial = sampler.Reader(specification['journal_cursor']).sample()
    sampler.validate(initial, initial, None, contract)
    require(initial['boot_id'] == specification['boot_id'], 'baseline_boot_changed')
    for role, expected in specification['baseline_review']['services'].items():
        require(initial['services'][role]['memory_max'] == expected['memory_max']
                and initial['services'][role]['unit']['InvocationID'] == expected['invocation'], 'baseline_service_changed')
    if args.preflight:
        print(json.dumps({'baseline_passed': True})); return
    dataset = json.loads((root/'dataset.json').read_text())
    bridge = (root/'workload_control.py').read_text()

    def client(request):
        source = "__name__='__main__'\nREQUEST=" + repr(request) + '\n' + bridge
        command = sampler.USER + ['/usr/bin/podman', 'exec', '-i', 'nautobot-web', 'nautobot-server', 'shell', '--interface', 'python', '--command', 'import sys;exec(sys.stdin.read())']
        raw = native_command(command, source.encode(), timeout=300 if request['action'] == 'cancel_batch' else 60)
        lines = [x[len('WORKLOAD_CONTROL='):] for x in raw.splitlines() if x.startswith('WORKLOAD_CONTROL=')]
        require(len(lines) == 1, 'bridge_receipt')
        value = json.loads(lines[0]); require(not value.get('failed'), 'native_failure')
        return value

    def backup():
        # Exact argv and script bytes are part of the frozen owner-reviewed bundle.
        owner = specification['backup']
        require(not Path(owner['receipt']).exists(), 'backup_receipt_exists')
        process = subprocess.Popen(owner['argv'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd='/', start_new_session=True)
        deadline = time.monotonic() + 1800
        try:
            while process.poll() is None:
                session.healthy()
                require(time.monotonic() < deadline, 'backup_timeout')
                time.sleep(1)
            require(process.returncode == 0, 'backup_command_failed')
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=10)
        return json.loads(Path(owner['receipt']).read_text())

    resume = specification.get('resume')
    ownership = None
    if resume:
        raw = (root/'retained-ownership.json').read_bytes()
        require(hashlib.sha256(raw).hexdigest() == resume['ownership_sha256'], 'retained_ownership_identity')
        ownership = json.loads(raw)
    session = Session(root, contract, client, backup, ownership=ownership)
    stop = threading.Event()
    registration = resume['registration'] if resume else {name: str(uuid.uuid4()) for name in ('PilotImport', 'PilotExport', 'PilotAudit')}
    save(root/'registration.json', registration)
    def monitor():
        reader = sampler.Reader(specification['journal_cursor'])
        first, previous, size = None, None, 0
        with (root/'samples.jsonl').open('xb') as out:
            os.chmod(root/'samples.jsonl', 0o600)
            while not stop.is_set():
                row = reader.sample()
                require(row['boot_id'] == specification['boot_id'], 'baseline_boot_changed')
                if first is None:
                    for role, expected in specification['baseline_review']['services'].items():
                        require(row['services'][role]['memory_max'] == expected['memory_max']
                                and row['services'][role]['unit']['InvocationID'] == expected['invocation'], 'baseline_service_changed')
                first = first or row
                data = json.dumps(row, separators=(',', ':')).encode()+b'\n'; size += len(data)
                require(size <= contract['limits']['collection_stream_bytes'], 'sample_output_limit')
                out.write(data); out.flush()
                sampler.validate(row, first, previous, contract); previous = row
                stop.wait(max(0, row['start'] + contract['sampling']['interval_seconds'] - time.monotonic()))
    try:
        client({'action': 'register', 'registration': registration, 'reuse_disabled': bool(resume)})
    except BaseException:
        if not resume: client({'action': 'disable', 'registration': registration})
        # Reused rows may have failed the disabled-state check. Never change an
        # unexpectedly enabled registration during cleanup of failed activation.
        raise
    def guarded_monitor():
        try: monitor()
        except BaseException:
            session.failure.set()
            session.cancel_owned()
            raise
    with ThreadPoolExecutor(max_workers=1) as pool:
        session.monitor = pool.submit(guarded_monitor)
        try:
            result = session.execute(dataset, specification['operation_id'])
            stop.set(); session.monitor.result(timeout=60)
            samples = [json.loads(x) for x in (root/'samples.jsonl').read_text().splitlines()]
            result['resources'] = sampler.review_samples(samples, session.phases, contract)
            result['import_mode'] = 'retained_fixture_repeat' if resume else 'new_fixture'
            result['accepted'] = False  # Operator reviews representativeness and all receipts.
            save(root/'result.json', result)
        except BaseException:
            session.cancel_owned()
            save(root/'result.json', {'accepted': False, 'incomplete': True})
            raise
        finally:
            stop.set()
            client({'action': 'disable', 'registration': registration})


if __name__ == '__main__': main()
