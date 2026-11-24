#!/usr/bin/env python3
"""Read-only comparison and native checks inside the isolated restored application."""
import hashlib
import importlib.metadata
import json
import os
import sys


def main():
    import psycopg2
    if sys.argv[1] == 'logical':
        import logical_database
        db = psycopg2.connect(host=os.environ['NAUTOBOT_DB_HOST'], dbname=os.environ['NAUTOBOT_DB_NAME'],
                              user=os.environ['NAUTOBOT_DB_USER'], password=os.environ['NAUTOBOT_DB_PASSWORD'], connect_timeout=10)
        try: result = logical_database.identity(db)
        finally: db.close()
    elif sys.argv[1] == 'check':
        import nautobot
        nautobot.setup()
        from django.core.management import call_command
        from django.db import connection
        from django.test import Client
        from django.conf import settings
        call_command('check', verbosity=0)
        call_command('migrate', check=True, verbosity=0)
        if Client().get('/health/', HTTP_HOST=settings.ALLOWED_HOSTS[0]).status_code != 200:
            raise RuntimeError('health_failed')
        with connection.cursor() as cursor:
            cursor.execute('SELECT app,name,applied FROM django_migrations ORDER BY app,name')
            migrations = [{'app': a, 'name': n, 'applied': t.isoformat()} for a,n,t in cursor]
        from nautobot.dcim.models import Manufacturer
        def export():
            return hashlib.sha256(json.dumps(list(Manufacturer.objects.order_by('id').values_list('id','name','description')),default=str).encode()).hexdigest()
        first_export = export()
        if export() != first_export: raise RuntimeError('export_changed')
        result = {'manufacturer_export_sha256': first_export, 'versions': {name: importlib.metadata.version(name) for name in ('nautobot','nautobot-dns-models')},
                  'migrations': migrations, 'native_checks': True, 'django_health': True}
    else: raise ValueError('phase')
    print('RESTORE_RESULT='+json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    try: main()
    except Exception as error:
        import traceback
        result = {'class':type(error).__name__, 'frames':[
            {'file':os.path.basename(frame.filename), 'function':frame.name, 'line':frame.lineno}
            for frame in traceback.extract_tb(error.__traceback__)[-6:]]}
        if isinstance(error, OSError):
            result['errno'] = error.errno
            if isinstance(error.filename, str) and error.filename.startswith('/opt/nautobot/'):
                result['path'] = error.filename
        print('RESTORE_RESULT='+json.dumps({'failure':result}, sort_keys=True))
