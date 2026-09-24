"""Run ONLY in the disposable qualification database, never on the pilot."""
import json
import os
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from pathlib import Path

assert os.environ.get('NAUTOBOT_DB_NAME') == 'workload_disposable'
sys.path.insert(0, '/work')
sys.path.insert(0, '/work/jobs')
import nautobot
nautobot.setup()
from django.core.management import call_command
from django.db import connection, connections, transaction
from django.apps import apps
from workload_adapter import DjangoStore, apply, plan
from workload_jobs import PilotImport, PilotExport, PilotAudit

call_command('migrate', interactive=False, verbosity=0)
dataset = json.loads(Path('/work/dataset.json').read_text())
models = sorted({n['model'] for n in plan(dataset)})

def counts():
    return {m: apps.get_model(m).objects.count() for m in models}

before = counts()

class FailingStore(DjangoStore):
    n = 0
    def create(self, *args):
        self.n += 1
        if self.n == 12:
            raise RuntimeError('injected_partial_import')
        return super().create(*args)

try:
    apply(dataset, FailingStore(), write=True)
    raise AssertionError('failure_not_injected')
except RuntimeError as error:
    assert str(error) == 'injected_partial_import'
assert counts() == before, 'native_transaction_rollback'
namespace = apps.get_model('ipam.namespace').objects.create(name='pilot-synthetic')
try:
    apply(dataset, DjangoStore(), write=True)
    raise AssertionError('unowned_collision_accepted')
except ValueError as error:
    assert str(error) == 'unowned_object'
namespace.delete()  # Disposable, explicitly created collision fixture only.
assert counts() == before
first = PilotImport().run(dataset)
# Compare all native rows, including timestamps, to prove repeat writes absent.
def rows():
    return {m: list(apps.get_model(m).objects.order_by('pk').values()) for m in models}
first_rows = rows()
assert PilotImport().run(dataset, first['receipt']) == first
assert rows() == first_rows, 'repeat_import_wrote_rows'
for _ in range(3):
    assert PilotExport().run(dataset, first['receipt'])['sha256'] == first['sha256']
barrier = threading.Barrier(2)
class ConcurrentStore(DjangoStore):
    @contextmanager
    def transaction(self, write):
        with super().transaction(write):
            barrier.wait(timeout=30)  # Both real PostgreSQL shared locks held.
            yield

def audit(_):
    try:
        return apply(dataset, ConcurrentStore(), first['receipt'])['sha256']
    finally:
        connections.close_all()
with ThreadPoolExecutor(max_workers=2) as pool:
    for _ in range(5):
        assert list(pool.map(audit, (0, 1))) == [first['sha256']]*2
assert PilotAudit().run(dataset, first['receipt'])['sha256'] == first['sha256']
interface = apps.get_model('dcim.interface').objects.get(pk=first['receipt']['objects']['pilot-device-0001/eth0'])
with transaction.atomic():
    interface.enabled = False
    interface.save()
    try:
        apply(dataset, DjangoStore(), first['receipt'])
        raise AssertionError('drift_accepted')
    except ValueError as error:
        assert str(error) == 'owned_object_drift'
    transaction.set_rollback(True)
assert rows() == first_rows
# Exercise the actual native bridge's registration and JobResult path as well.
from django.contrib.auth import get_user_model
from nautobot.extras.models import Job, JobResult
from workload_control import perform
from unittest.mock import patch
import uuid
user = get_user_model().objects.create(username='admin', is_active=True, is_superuser=True)
# post_migrate discovers these disposable test Job files automatically.
Job.objects.filter(module_name='workload_jobs').delete()
registration = {name: str(uuid.uuid4()) for name in ('PilotImport', 'PilotExport', 'PilotAudit')}
assert set(perform({'action': 'register', 'registration': registration})['registered']) == set(registration.values())
original_enqueue = JobResult.enqueue_job
# Real synchronous Celery task execution; separate worker dispatch remains unproven.
def synchronous(**kwargs):
    return original_enqueue(**kwargs, synchronous=True)
identity = str(uuid.uuid4())
with patch.object(JobResult, 'enqueue_job', side_effect=synchronous):
    perform({'action': 'submit_batch', 'requests': [{'action': 'submit', 'kind': 'audit', 'id': identity,
             'kwargs': {'dataset': dataset, 'ownership': first['receipt']}}]})
job_result = perform({'action': 'status', 'id': identity})
assert job_result['terminal'] and job_result['status'] == 'SUCCESS', job_result['status']
assert job_result['result']['sha256'] == first['sha256']
perform({'action': 'disable', 'registration': registration})
assert not Job.objects.filter(pk__in=registration.values(), enabled=True).exists()
print('NATIVE_WORKLOAD_RESULT=' + json.dumps({'passed': True, 'version': nautobot.__version__,
    'counts': first['counts'], 'projection_sha256': first['sha256'],
    'checks': ['native_rollback', 'unowned_refusal', 'repeat_import_no_writes', 'three_exports',
               'ten_concurrent_audits', 'drift_refusal', 'native_registration', 'native_synchronous_job_result', 'disable_owned_registration'], 'celery_dispatch_tested': False}, sort_keys=True))
