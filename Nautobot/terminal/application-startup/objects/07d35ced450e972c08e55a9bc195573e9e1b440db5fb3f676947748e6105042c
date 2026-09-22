"""Run inside native Nautobot shell; verify real asynchronous worker dispatch."""
import hashlib
import json
import time


def probe():
    from django.contrib.auth import get_user_model
    from nautobot.core.celery import app
    from nautobot.extras.models import Job, JobResult
    from nautobot.extras.choices import JobResultStatusChoices
    stats = app.control.inspect(timeout=5).stats()
    if not stats or len(stats) != 1 or next(iter(stats.values()))['pool']['max-concurrency'] != 2:
        raise ValueError('worker_count_or_concurrency')
    job = Job.objects.get(module_name='startup_readiness', job_class_name='StartupReadiness', installed=True)
    user = get_user_model().objects.get(username='admin', is_active=True, is_superuser=True)
    previous = job.enabled
    try:
        if not previous:
            job.enabled = True
            job.save(update_fields=['enabled'])
        result = JobResult.enqueue_job(job_model=job, user=user, job_kwargs={}, synchronous=False)
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            result.refresh_from_db()
            if result.status == JobResultStatusChoices.STATUS_SUCCESS:
                expected = {'digest': hashlib.sha256(bytes(range(256)) * 64).hexdigest()}
                if result.result != expected or not result.date_started or not result.date_done:
                    raise ValueError('job_receipt')
                return {'job_completed': True, 'single_worker_concurrency_two': True}
            if result.status in JobResultStatusChoices.EXCEPTION_STATES:
                raise ValueError('job_failed')
            time.sleep(1)
        raise ValueError('job_timeout')
    finally:
        if not previous:
            job.enabled = False
            job.save(update_fields=['enabled'])


if __name__ == '__main__':
    try:
        print('STARTUP_JOB_RESULT=' + json.dumps(probe()))
    except Exception:
        print(json.dumps({'job_completed': False, 'single_worker_concurrency_two': False}))
        raise SystemExit(69)
