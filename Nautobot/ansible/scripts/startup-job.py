"""Local-only startup dispatch check; no inventory mutation or external requests."""
import hashlib
from nautobot.apps.jobs import Job, register_jobs


class StartupReadiness(Job):
    class Meta:
        name = 'Homelab startup readiness'
        read_only = True
        has_sensitive_variables = False
        soft_time_limit = 20
        time_limit = 30

    def run(self):
        from django.db import connection
        with connection.cursor() as cursor:
            cursor.execute('SELECT 1')
            if cursor.fetchone() != (1,):
                raise RuntimeError('database_probe_failed')
        # Deterministic bounded work. JobResult/log writes are framework-owned.
        return {'digest': hashlib.sha256(bytes(range(256)) * 64).hexdigest()}


register_jobs(StartupReadiness)
