"""Disposable application/database fixture and actual restore verification probes."""
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import sys

sys.path.insert(0, '/scripts')
import logical_database


def main():
    phase = sys.argv[1]
    import psycopg2
    if phase == 'logical':
        db = psycopg2.connect(host='postgresql', dbname=os.environ['NAUTOBOT_DB_NAME'], user='nautobot')
        try: print(json.dumps(logical_database.identity(db)))
        finally: db.close()
        return
    import nautobot
    nautobot.setup()
    from django.core.management import call_command
    from django.db import connection
    from nautobot.dcim.models import Manufacturer
    if phase == 'seed':
        call_command('migrate', interactive=False, verbosity=0)
        Manufacturer.objects.create(name='isolated-restore-fixture', description='recover this exact fixture')
    elif phase == 'check':
        call_command('check', verbosity=0)
        call_command('migrate', check=True, verbosity=0)
        from django.test import Client
        response = Client().get('/health/', HTTP_HOST='localhost')
        if response.status_code != 200: raise ValueError('native_health_failed')
        print('NATIVE_HEALTH_PASSED')
    elif phase != 'metadata': raise ValueError('phase')
    with connection.cursor() as cursor:
        cursor.execute('SELECT app,name,applied FROM django_migrations ORDER BY app,name')
        migrations = [[app, name, applied.isoformat()] for app, name, applied in cursor]
    export = list(Manufacturer.objects.order_by('name').values_list('name', 'description'))
    value = {'versions': {name: importlib.metadata.version(name) for name in ('nautobot', 'nautobot-dns-models')},
             'migrations': migrations,
             'export_sha256': hashlib.sha256(json.dumps(export, sort_keys=True).encode()).hexdigest()}
    print('RESTORE_METADATA='+json.dumps(value, sort_keys=True))


if __name__ == '__main__': main()
