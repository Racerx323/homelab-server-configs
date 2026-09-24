"""Native shell bridge; REQUEST is supplied on stdin by the frozen node runner."""
import json


def perform(request):
    from django.contrib.auth import get_user_model
    from nautobot.extras.models import Job, JobResult
    from nautobot.extras.jobs import get_jobs
    from nautobot.extras.jobs_cancel import CancelFactory
    classes = {'import': 'PilotImport', 'export': 'PilotExport', 'audit': 'PilotAudit'}
    user = get_user_model().objects.get(username='admin', is_active=True, is_superuser=True)
    action = request['action']
    if action == 'register':
        from django.db import transaction
        with transaction.atomic():
            return register(request, classes, Job, get_jobs)
    if action == 'disable':
        Job.objects.filter(pk__in=request['registration'].values(), module_name='workload_jobs', job_class_name__in=classes.values()).update(enabled=False)
        return {'disabled': True}
    if action == 'submit_batch':
        from django.db import transaction
        with transaction.atomic():
            return {'submitted': [perform(item) for item in request['requests']]}
    if action == 'submit':
        job = Job.objects.get(module_name='workload_jobs', job_class_name=classes[request['kind']], enabled=True)
        result = JobResult.objects.create(pk=request['id'], name=job.name, job_model=job, user=user)
        JobResult.enqueue_job(job_model=job, user=user, job_result=result, job_kwargs=request['kwargs'])
        return {'id': str(result.pk)}
    result = JobResult.objects.filter(pk=request['id']).first()
    if result is None:
        if action == 'cancel': return {'absent': True}
        raise ValueError('job_result_missing')
    if (result.job_model is None or result.job_model.module_name != 'workload_jobs'
            or result.job_model.job_class_name not in classes.values() or result.user != user):
        raise ValueError('job_identity')
    if action == 'cancel':
        strategy = CancelFactory.get_strategy(result.queue_type)
        revocation_confirmed = True
        if result.is_unready_state:
            from nautobot.core.celery import app
            # A queued task can be absent from query_task yet still execute later.
            # Request termination as well as revocation: flagging an active task
            # alone can change its result status without stopping its process.
            revocation_confirmed = revoke_acknowledged(app.control.revoke(
                str(result.pk), terminate=True, signal='SIGKILL', reply=True, timeout=1))
        import time
        deadline = time.monotonic() + 15
        absent = False
        while True:
            result.refresh_from_db()
            absent = confirmed_worker_absence(str(result.pk))
            # Native termination is asynchronous. Reap a remaining STARTED row
            # only after the responding worker proves it no longer owns the task.
            if absent and revocation_confirmed and result.is_unready_state:
                strategy.perform_reap(result, user)
                result.refresh_from_db()
            if (not result.is_unready_state and absent) or time.monotonic() >= deadline:
                break
            time.sleep(0.25)
        return {'terminal': not result.is_unready_state, 'worker_absent': absent and revocation_confirmed}
    if action != 'status': raise ValueError('unknown_action')
    return {'id': str(result.pk), 'status': result.status, 'terminal': not result.is_unready_state,
            'started': result.date_started.timestamp() if result.date_started else None,
            'done': result.date_done.timestamp() if result.date_done else None,
            'result': result.result if result.status == 'SUCCESS' else None}


def revoke_acknowledged(replies):
    return (isinstance(replies, list) and len(replies) == 1
            and isinstance(replies[0], dict) and len(replies[0]) == 1
            and all(isinstance(value, dict) and isinstance(value.get('ok'), str) and 'error' not in value
                    for value in replies[0].values()))


def confirmed_worker_absence(identity, inspector=None):
    """No reply is unknown, not evidence that the single pilot worker is idle."""
    if inspector is None:
        from nautobot.core.celery import app
        inspector = app.control.inspect(timeout=1)
    try:
        peers = inspector.ping()
        if not isinstance(peers, dict) or len(peers) != 1 or any(v != {'ok': 'pong'} for v in peers.values()):
            return False
        replies = inspector.query_task(identity)
        return (isinstance(replies, dict) and set(replies) == set(peers)
                and all(isinstance(tasks, dict) and 'error' not in tasks and identity not in tasks
                        for tasks in replies.values()))
    except Exception:
        return False


def register(request, classes, Job, get_jobs):
    available = get_jobs(reload=True)
    from django.conf import settings
    from nautobot.extras.models import JobQueue
    from nautobot.extras.utils import refresh_job_model_from_job_class
    rows = []
    for cls in classes.values():
        if Job.objects.filter(module_name='workload_jobs', job_class_name=cls).exists():
            raise ValueError('preexisting_workload_job')
        native = available['workload_jobs.' + cls]
        job = Job.objects.create(pk=request['registration'][cls], module_name='workload_jobs', job_class_name=cls,
                                 name=native.name, grouping=native.grouping,
                                 default_job_queue=JobQueue.objects.get(name=settings.CELERY_TASK_DEFAULT_QUEUE))
        job, _ = refresh_job_model_from_job_class(Job, native, JobQueue)
        if job is None: raise ValueError('native_registration_failed')
        job.enabled = True
        job.validated_save()
        rows.append(str(job.pk))
    return {'registered': rows}


if __name__ == '__main__':
    try:
        print('WORKLOAD_CONTROL=' + json.dumps(perform(REQUEST), sort_keys=True))
    except Exception as error:
        # Class only: Django/driver exceptions can contain data or credentials.
        print('WORKLOAD_CONTROL=' + json.dumps({'failed': True, 'error_class': type(error).__name__}))
        raise SystemExit(1)
