"""Native replacement checks in an isolated disposable database only."""
import copy
import json
import os
import sys
from pathlib import Path

assert os.environ.get('NAUTOBOT_DB_NAME') == 'workload_disposable'
sys.path[:0] = ['/work', '/work/jobs']
import nautobot
nautobot.setup()
from django.apps import apps
from django.core.management import call_command
from django.db import transaction
from workload_adapter import DjangoStore, apply, replace, plan
from workload_jobs import PilotImport

call_command('migrate', interactive=False, verbosity=0)
print('REPLACEMENT_PHASE=migrated', flush=True)
old = json.loads(Path('/work/dataset.json').read_text())
new = copy.deepcopy(old)
new['devices'] = new['devices'][:2]
new['ip_assignments'] = [r for r in new['ip_assignments'] if r['device'] in {d['key'] for d in new['devices']}]
models = {n['model'] for n in plan(old)}
def rows():
    return {m: list(apps.get_model(m).objects.order_by('pk').values()) for m in models}

first = apply(old, DjangoStore(), write=True)
replacement = {'dataset': old, 'ownership': first['receipt']}
before = rows()
print('REPLACEMENT_PHASE=owned_fixture_created', flush=True)

class FailingStore(DjangoStore):
    def create(self, *args):
        if args[0] == 'dcim.device': raise RuntimeError('injected_replacement_failure')
        return super().create(*args)

try:
    replace(new, FailingStore(), replacement)
    raise AssertionError('failure_not_injected')
except RuntimeError as error:
    assert str(error) == 'injected_replacement_failure'
assert rows() == before, 'replacement_rollback'
print('REPLACEMENT_PHASE=rollback_verified', flush=True)

device = apps.get_model('dcim.device').objects.get(pk=first['receipt']['objects']['pilot-device-0001'])
with transaction.atomic():
    device.name = 'drifted-device'
    device.save()
    try:
        replace(new, DjangoStore(), replacement)
        raise AssertionError('drift_accepted')
    except ValueError:
        pass
    transaction.set_rollback(True)
assert rows() == before

with transaction.atomic():
    device.refresh_from_db()
    device.comments = 'unrelated operator note'
    device.save()
    try:
        replace(new, DjangoStore(), replacement)
        raise AssertionError('extra_metadata_accepted')
    except ValueError as error:
        assert str(error).startswith('owned_extra_field_drift:'), str(error)
    transaction.set_rollback(True)
assert rows() == before

# An unowned child of an owned manufacturer must not disappear in a cascade.
extra = apps.get_model('dcim.devicetype').objects.create(
    manufacturer_id=first['receipt']['objects']['manufacturer'], model='unowned-sentinel')
with_extra = rows()
try:
    replace(new, DjangoStore(), replacement)
    raise AssertionError('unowned_cascade_accepted')
except ValueError as error:
    assert str(error) == 'unowned_delete_closure', str(error)
assert rows() == with_extra, 'unowned_cascade_rollback'
extra.delete()

# Generic object links must be refused just like foreign keys.
from django.contrib.contenttypes.models import ContentType
from nautobot.extras.models import Tag, TaggedItem
tag = Tag.objects.create(name='unowned-sentinel', color='ffffff')
link = TaggedItem.objects.create(tag=tag, content_type=ContentType.objects.get_for_model(device), object_id=device.pk)
try:
    replace(new, DjangoStore(), replacement)
    raise AssertionError('generic_relation_accepted')
except ValueError as error:
    assert str(error) == 'unowned_delete_closure', str(error)
assert TaggedItem.objects.filter(pk=link.pk).exists()
assert rows() == before
link.delete(); tag.delete()

def unowned(receipt):
    return {m: list(apps.get_model(m).objects.exclude(pk__in=receipt['objects'].values()).order_by('pk').values()) for m in models}
unowned_before = unowned(first['receipt'])

from django.contrib.auth import get_user_model
from nautobot.extras.models import Job, JobResult
from workload_control import perform
user = get_user_model().objects.create(username='admin', is_active=True, is_superuser=True)
jobs = Job.objects.filter(module_name='workload_jobs')
jobs.update(enabled=False)
registration = {job.job_class_name: str(job.pk) for job in jobs}
perform({'action':'register', 'registration':registration, 'reuse_disabled':True})
job = Job.objects.get(pk=registration['PilotImport'])
result = JobResult.objects.create(name=job.name, job_model=job, user=user)
JobResult.enqueue_job(job_model=job, user=user, job_result=result,
                      job_kwargs={'dataset':new, 'replacement':replacement}, synchronous=True)
result.refresh_from_db()
assert result.status == 'SUCCESS', result.status
second = result.result
assert second['receipt']['fixture_sha256'] != first['receipt']['fixture_sha256']
assert not set(second['receipt']['objects'].values()) & set(first['receipt']['objects'].values())
assert unowned(second['receipt']) == unowned_before, 'unrelated_rows_changed'
after = rows()
assert PilotImport().run(new, ownership=second['receipt']) == second
assert rows() == after, 'replacement_repeat_writes'
perform({'action':'disable', 'registration':registration})
print('NATIVE_REPLACEMENT_RESULT=' + json.dumps({'passed': True, 'checks': [
    'atomic_replacement', 'rollback_after_delete', 'drift_refusal',
    'unowned_cascade_refusal', 'generic_relation_refusal', 'extra_metadata_refusal',
    'unrelated_rows_preserved', 'native_job_result', 'reuse_disabled_registration', 'repeat_no_writes']}))
