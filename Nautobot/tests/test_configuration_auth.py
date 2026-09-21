#!/usr/bin/env python3
"""Offline probe logic tests; no database, cache, image, or host contact."""
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import unittest
from unittest.mock import patch
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('probe',ROOT/'Nautobot/ansible/scripts/configuration-auth-probe.py')
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)


class Probe(unittest.TestCase):
    def test_settings_and_sensitive_inputs_are_not_mutated(self):
        env={'NAUTOBOT_SECRET_KEY':'a'*128,'NAUTOBOT_DB_PASSWORD':'b'*64,'NAUTOBOT_REDIS_PASSWORD':'c'*64}
        settings=SimpleNamespace(SETTINGS_PATH='/opt/nautobot/nautobot_config.py',DEBUG=False,INSTALLATION_METRICS_ENABLED=False,
            ALLOWED_HOSTS=['nautobot.local.theama.co','j2-svpi4mf.local.theama.co'],CSRF_TRUSTED_ORIGINS=['https://nautobot.local.theama.co'],
            SECURE_PROXY_SSL_HEADER=('HTTP_X_FORWARDED_PROTO','https'),SECRET_KEY=env['NAUTOBOT_SECRET_KEY'],PLUGINS=['nautobot_dns_models'],
            DATABASES={'default':{'ENGINE':'django.db.backends.postgresql','HOST':'postgresql','PORT':5432,'NAME':'nautobot','USER':'nautobot','PASSWORD':env['NAUTOBOT_DB_PASSWORD']}},
            CACHES={'default':{'LOCATION':'redis://:'+env['NAUTOBOT_REDIS_PASSWORD']+'@redis:6379/1'}},CELERY_BROKER_URL='redis://:'+env['NAUTOBOT_REDIS_PASSWORD']+'@redis:6379/0')
        versions={'nautobot':'3.2.3','nautobot-dns-models':'2.3.0'}
        p.settings_check(settings,env,['nautobot_dns_models'],versions)
        for field,value in [('DEBUG',True),('PLUGINS',[]),('ALLOWED_HOSTS',['*']),('SETTINGS_PATH','/wrong')]:
            bad=copy.deepcopy(settings);setattr(bad,field,value)
            with self.assertRaises(p.CheckFailed):p.settings_check(bad,env,['nautobot_dns_models'],versions)
        with self.assertRaises(p.CheckFailed):p.settings_check(settings,{**env,'NAUTOBOT_INITIAL_ADMIN_PASSWORD':'sensitive'},['nautobot_dns_models'],versions)

    def postgres(self,mode):
        calls=[];closed=[]
        class Cursor:
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def execute(self,query):calls.append(query)
            def fetchone(self):return ('nautobot','nautobot')
        class Connection:
            def __init__(self,config,alias):self.bad=alias.endswith('negative');calls.append(copy.deepcopy(config))
            def cursor(self):
                if (self.bad and mode!='accept_wrong') or mode=='positive_failure':
                    error=Exception('password must never escape')
                    error.sqlstate='08001' if mode=='network' else '28P01'
                    raise error
                return Cursor()
            def close(self):
                closed.append(self.bad)
                if mode=='close_failure':raise Exception('secret cleanup error')
        config={'PASSWORD':'original','OPTIONS':{}}
        if mode=='ok':p.postgres_check(Connection,config)
        else:
            with self.assertRaises(Exception):p.postgres_check(Connection,config)
        self.assertEqual(config,{'PASSWORD':'original','OPTIONS':{}})
        self.assertTrue(closed)
        return calls,closed

    def test_postgres_real_identity_and_password_rejection_semantics(self):
        calls,closed=self.postgres('ok');self.assertEqual(closed,[False,True])
        self.assertEqual(calls[0]['OPTIONS']['connect_timeout'],5)
        self.assertIn('SELECT current_user, current_database()',calls)
        for mode in ['accept_wrong','network','positive_failure','close_failure']:self.postgres(mode)

    def test_wrapped_sqlstate_without_message_matching(self):
        underlying=Exception('private');underlying.pgcode='28P01';outer=Exception('private');outer.__cause__=underlying
        self.assertEqual(p.sqlstate(outer),'28P01');self.assertIsNone(p.sqlstate(Exception('password authentication failed')))

    def redis(self,mode):
        events=[]
        class AuthenticationError(Exception):pass
        class Client:
            def __init__(self,**kwargs):self.kw=kwargs;self.connection_pool=self;events.append(kwargs)
            def ping(self):
                if mode=='network':raise TimeoutError('sensitive URL')
                if self.kw['password']!='real' and mode!='accept_wrong':raise AuthenticationError('sensitive URL')
                return True
            def close(self):
                events.append('close')
                if mode=='close_failure':raise Exception('sensitive')
            def disconnect(self):events.append('disconnect')
        config={'host':'redis','password':'real','db':1}
        if mode=='ok':p.redis_check(Client,config,AuthenticationError)
        else:
            with self.assertRaises(Exception):p.redis_check(Client,config,AuthenticationError)
        self.assertEqual(config['password'],'real');self.assertIn('disconnect',events)
        return events

    def test_redis_positive_missing_wrong_password_and_cleanup(self):
        events=self.redis('ok');self.assertEqual(events.count('disconnect'),3)
        options=[x for x in events if isinstance(x,dict)]
        self.assertEqual(options[1]['password'],None);self.assertNotEqual(options[2]['password'],'real')
        self.assertTrue(all(x['socket_timeout']==5 for x in options))
        for mode in ['network','accept_wrong','close_failure']:self.redis(mode)

    def test_explicit_shell_namespace_executes_the_entrypoint(self):
        source=(ROOT/'Nautobot/ansible/scripts/configuration-auth-probe.py').read_text()
        out=io.StringIO()
        with patch.object(Path,'read_text',side_effect=FileNotFoundError('private')), contextlib.redirect_stdout(out):
            with self.assertRaises(SystemExit) as outcome:
                exec(compile(source,'candidate-probe.py','exec'), {'__name__':'__main__'})
        self.assertEqual(outcome.exception.code,69)
        self.assertFalse(json.loads(out.getvalue())['accepted'])

    def test_no_marker_fails_before_framework_or_network_import(self):
        out=io.StringIO()
        with patch.object(p.Path,'read_text',side_effect=FileNotFoundError('private')),contextlib.redirect_stdout(out):
            self.assertEqual(p.main(),69)
        value=json.loads(out.getvalue());self.assertFalse(value['accepted']);self.assertEqual(value['failed_phase'],'isolation')
        self.assertNotIn('private',out.getvalue())


if __name__=='__main__':unittest.main()
