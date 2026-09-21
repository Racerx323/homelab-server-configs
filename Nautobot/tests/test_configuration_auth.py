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
    def settings_fixture(self):
        env={'NAUTOBOT_SECRET_KEY':'a'*128,'NAUTOBOT_DB_PASSWORD':'b'*64,'NAUTOBOT_REDIS_PASSWORD':'c'*64}
        settings=SimpleNamespace(SETTINGS_PATH='/opt/nautobot/nautobot_config.py',DEBUG=False,INSTALLATION_METRICS_ENABLED=False,
            ALLOWED_HOSTS=['nautobot.local.theama.co','j2-svpi4mf.local.theama.co'],CSRF_TRUSTED_ORIGINS=['https://nautobot.local.theama.co'],
            SECURE_PROXY_SSL_HEADER=('HTTP_X_FORWARDED_PROTO','https'),SECRET_KEY=env['NAUTOBOT_SECRET_KEY'],PLUGINS=['nautobot_dns_models'],
            DATABASES={'default':{'ENGINE':'django.db.backends.postgresql','HOST':'postgresql','PORT':5432,'NAME':'nautobot','USER':'nautobot','PASSWORD':env['NAUTOBOT_DB_PASSWORD']}},
            CACHES={'default':{'LOCATION':'redis://:'+env['NAUTOBOT_REDIS_PASSWORD']+'@redis:6379/1'}},CELERY_BROKER_URL='redis://:'+env['NAUTOBOT_REDIS_PASSWORD']+'@redis:6379/0')
        versions={'nautobot':'3.2.3','nautobot-dns-models':'2.3.0'}
        return settings,env,versions

    def test_settings_and_sensitive_inputs_are_not_mutated(self):
        settings,env,versions=self.settings_fixture()
        p.settings_check(settings,env,['nautobot_dns_models'],versions)
        for field,value in [('DEBUG',True),('PLUGINS',[]),('ALLOWED_HOSTS',['*']),('SETTINGS_PATH','/wrong')]:
            bad=copy.deepcopy(settings);setattr(bad,field,value)
            with self.assertRaises(p.CheckFailed):p.settings_check(bad,env,['nautobot_dns_models'],versions)
        with self.assertRaises(p.CheckFailed):p.settings_check(settings,{**env,'NAUTOBOT_INITIAL_ADMIN_PASSWORD':'sensitive'},['nautobot_dns_models'],versions)

    def test_default_database_port_matches_pinned_defaults(self):
        settings,env,versions=self.settings_fixture()
        for port in ('',5432,'5432'):
            settings.DATABASES['default']['PORT']=port
            p.settings_check(settings,env,['nautobot_dns_models'],versions)
        for port in ('6432',None):
            settings.DATABASES['default']['PORT']=port
            with self.assertRaisesRegex(p.CheckFailed,'^database_port$'):
                p.settings_check(settings,env,['nautobot_dns_models'],versions)
        settings.DATABASES['default']['PORT']=''
        with self.assertRaisesRegex(p.CheckFailed,'^database_port$'):
            p.settings_check(settings,{**env,'PGPORT':'6432'},['nautobot_dns_models'],versions)

    def test_main_preserves_each_settings_assertion_without_values(self):
        settings,env,versions=self.settings_fixture()
        mutations=[('SETTINGS_PATH','private','settings_path'),('DEBUG',True,'production_flags'),
            ('ALLOWED_HOSTS',['private'],'allowed_hosts'),('CSRF_TRUSTED_ORIGINS',[],'csrf_origin'),
            ('SECURE_PROXY_SSL_HEADER',('private','private'),'proxy_header'),('SECRET_KEY','PRIVATE_SECRET','django_secret'),
            ('PLUGINS',[],'plugin_registration')]
        scenarios=[]
        for field,value,code in mutations:
            bad=copy.deepcopy(settings);setattr(bad,field,value);scenarios.append((bad,env,versions,code))
        for field,code in [('ENGINE','database_engine'),('HOST','database_host'),('NAME','database_name'),('USER','database_user'),('PASSWORD','database_password'),('PORT','database_port')]:
            bad=copy.deepcopy(settings);bad.DATABASES['default'][field]='PRIVATE_SECRET';scenarios.append((bad,env,versions,code))
        scenarios.append((settings,{**env,'NAUTOBOT_INITIAL_ADMIN_PASSWORD':'PRIVATE_SECRET'},versions,'bootstrap_credential_present'))
        scenarios.append((settings,env,{'nautobot':'private','nautobot-dns-models':'private'},'package_versions'))
        for bad,environ,version_map,code in scenarios:
            modules={'django.apps':SimpleNamespace(apps=SimpleNamespace(ready=True,get_app_configs=lambda:[SimpleNamespace(name='nautobot_dns_models')])),
                     'django.conf':SimpleNamespace(settings=bad),'django.db':SimpleNamespace(connections={}),
                     'django_redis':SimpleNamespace(get_redis_connection=lambda *a:None),'redis':SimpleNamespace()}
            out=io.StringIO()
            with patch.dict(sys.modules,modules),patch.dict(p.os.environ,environ,clear=True),patch('importlib.metadata.version',side_effect=lambda name:version_map[name]),patch.object(p.Path,'read_text',return_value='disposable-configuration-authentication'),contextlib.redirect_stdout(out):
                self.assertEqual(p.main(),69)
            result=json.loads(out.getvalue());self.assertEqual(result['failure_code'],code)
            self.assertEqual(result['exception_category'],'CheckFailed');self.assertNotIn('PRIVATE_SECRET',out.getvalue())

    def postgres(self,mode):
        calls=[];closed=[]
        class Cursor:
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def execute(self,query):calls.append(query)
            def fetchone(self):return ('nautobot','nautobot',6432 if mode=='wrong_port' else 5432)
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
        if mode=='ok':p.postgres_check(Connection,config,include_negative=True)
        else:
            with self.assertRaises(Exception):p.postgres_check(Connection,config,include_negative=True)
        self.assertEqual(config,{'PASSWORD':'original','OPTIONS':{}})
        self.assertTrue(closed)
        return calls,closed

    def test_postgres_real_identity_and_password_rejection_semantics(self):
        calls,closed=self.postgres('ok');self.assertEqual(closed,[False,True])
        self.assertEqual(calls[0]['OPTIONS']['connect_timeout'],5)
        self.assertIn('SELECT current_user, current_database(), inet_server_port()',calls)
        for mode in ['accept_wrong','network','positive_failure','close_failure','wrong_port']:self.postgres(mode)

    def test_postgres_failure_branches_and_cleanup(self):
        for attempt, step, state, code in [
            ('positive','cursor',None,'postgres_positive_failure'),
            ('positive','query','42501','postgres_positive_failure'),
            ('positive','fetch',None,'postgres_positive_failure'),
            ('positive','construct',None,'postgres_positive_failure'),
            ('negative','cursor',None,'postgres_negative_missing_sqlstate'),
            ('negative','cursor','08001','postgres_negative_unexpected_sqlstate'),
            ('negative','cursor','PRIVATE_SECRET','postgres_negative_unexpected_sqlstate'),
            ('positive','close',None,'postgres_positive_cleanup_failure'),
            ('negative','close',None,'postgres_negative_cleanup_failure'),
        ]:
            closed=[]
            class OperationalError(Exception): pass
            def fail():
                error=OperationalError('PRIVATE_SECRET');error.sqlstate=state;raise error
            class Connection:
                def __init__(self,config,alias):
                    self.attempt=alias.removeprefix('qualification_')
                    if self.attempt==attempt and step=='construct':fail()
                def cursor(self):
                    if self.attempt==attempt and step=='cursor':fail()
                    if self.attempt=='negative':
                        error=OperationalError('PRIVATE_SECRET');error.sqlstate='28P01';raise error
                    return self
                def __enter__(self):return self
                def __exit__(self,*args):pass
                def execute(self,query):
                    if self.attempt==attempt and step=='query':fail()
                def fetchone(self):
                    if self.attempt==attempt and step=='fetch':fail()
                    return ('nautobot','nautobot',5432)
                def close(self):
                    closed.append(self.attempt)
                    if self.attempt==attempt and step=='close':fail()
            with self.assertRaises(p.CheckFailed) as caught:p.postgres_check(Connection,{'PASSWORD':'PRIVATE_SECRET','OPTIONS':{}},include_negative=True)
            self.assertEqual(str(caught.exception),code)
            detail=caught.exception.postgres_diagnostic
            self.assertEqual(detail['attempt'],attempt);self.assertEqual(detail['step'],step)
            self.assertEqual(detail['exception_category'],'OperationalError')
            self.assertNotIn('PRIVATE_SECRET',json.dumps(detail))
            if step!='construct':self.assertIn(attempt,closed)

    def test_postgres_diagnostics_survive_main_without_messages(self):
        settings,env,versions=self.settings_fixture()
        error=Exception('PRIVATE_SECRET');error.sqlstate='PRIVATE_SECRET'
        failure=p.postgres_failure('postgres_negative_unexpected_sqlstate','negative','cursor',error)
        modules={'django.apps':SimpleNamespace(apps=SimpleNamespace(ready=True,get_app_configs=lambda:[SimpleNamespace(name='nautobot_dns_models')])),
                 'django.conf':SimpleNamespace(settings=settings),
                 'django.db':SimpleNamespace(connections={'default':SimpleNamespace(settings_dict={})}),
                 'django_redis':SimpleNamespace(),'redis':SimpleNamespace()}
        modules['django_redis'].get_redis_connection=lambda *a:None
        out=io.StringIO()
        with patch.dict(sys.modules,modules),patch.dict(p.os.environ,env,clear=True),patch('importlib.metadata.version',side_effect=lambda name:versions[name]),patch.object(p.Path,'read_text',return_value='disposable-configuration-authentication'),patch.object(p,'native_configuration_check'),patch.object(p,'postgres_check',side_effect=failure),contextlib.redirect_stdout(out):
            self.assertEqual(p.main(),69)
        result=json.loads(out.getvalue());self.assertEqual(result['postgres_diagnostic']['sqlstate'],'other')
        self.assertEqual(result['postgres_diagnostic']['attempt'],'negative')
        self.assertEqual(result['checks'],['settings_and_plugin_registration','native_configuration_check'])
        self.assertNotIn('PRIVATE_SECRET',out.getvalue())

    def test_readiness_only_attempts_positive_connections(self):
        attempts=[]
        class Connection:
            def __init__(self,config,alias):attempts.append(alias)
            def cursor(self):return self
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def execute(self,query):pass
            def fetchone(self):return ('nautobot','nautobot',5432)
            def close(self):pass
        p.postgres_check(Connection,{'PASSWORD':'original'})
        self.assertEqual(attempts,['qualification_positive'])
        passwords=[]
        class Client:
            def __init__(self,**kwargs):passwords.append(kwargs['password']);self.connection_pool=self
            def ping(self):return True
            def close(self):pass
            def disconnect(self):pass
        p.redis_check(Client,{'password':'original'},ValueError)
        self.assertEqual(passwords,['original'])

    def test_native_command_is_invoked_and_failure_is_sanitized(self):
        from unittest.mock import Mock
        for failure in (None,RuntimeError('PRIVATE_SECRET')):
            call=Mock(side_effect=failure)
            with patch.dict(sys.modules,{'django.core.management':SimpleNamespace(call_command=call)}):
                if failure:
                    with self.assertRaisesRegex(p.CheckFailed,'^native_configuration_check$'):p.native_configuration_check()
                else:p.native_configuration_check()
            self.assertEqual(call.call_args.args,('check',));self.assertEqual(call.call_args.kwargs['verbosity'],0)

    def test_readiness_main_completes_five_checks_without_negative_opt_in(self):
        from unittest.mock import Mock
        settings,env,versions=self.settings_fixture()
        cache=Mock();cache.connection_pool.connection_kwargs={'password':'original'}
        broker=Mock();broker.connection_pool.connection_kwargs={'password':'original'}
        command=Mock()
        modules={'django.apps':SimpleNamespace(apps=SimpleNamespace(ready=True,get_app_configs=lambda:[SimpleNamespace(name='nautobot_dns_models')])),
                 'django.conf':SimpleNamespace(settings=settings),
                 'django.db':SimpleNamespace(connections={'default':SimpleNamespace(settings_dict={})}),
                 'django.core.management':SimpleNamespace(call_command=command),
                 'django_redis':SimpleNamespace(get_redis_connection=lambda *a:cache),
                 'redis':SimpleNamespace(Redis=SimpleNamespace(from_url=lambda *a:broker),exceptions=SimpleNamespace(AuthenticationError=ValueError))}
        out=io.StringIO()
        with patch.dict(sys.modules,modules),patch.dict(p.os.environ,env,clear=True),patch('importlib.metadata.version',side_effect=lambda name:versions[name]),patch.object(p.Path,'read_text',return_value='disposable-configuration-authentication'),patch.object(p,'postgres_check') as pg,patch.object(p,'redis_check') as redis,contextlib.redirect_stdout(out):
            self.assertEqual(p.main(),0)
        result=json.loads(out.getvalue())
        self.assertEqual(result['checks'],['settings_and_plugin_registration','native_configuration_check','postgresql_positive_identity_port','redis_cache_positive','redis_broker_positive'])
        self.assertTrue(result['accepted']);self.assertFalse(result['production_runtime_accepted'])
        self.assertEqual(command.call_args.args,('check',));self.assertEqual(pg.call_count,1);self.assertEqual(redis.call_count,2)
        self.assertNotIn('include_negative',pg.call_args.kwargs)
        for call in redis.call_args_list:self.assertNotIn('include_negative',call.kwargs)
        cache.close.assert_called_once();cache.connection_pool.disconnect.assert_called_once()
        broker.close.assert_called_once();broker.connection_pool.disconnect.assert_called_once()

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
        if mode=='ok':p.redis_check(Client,config,AuthenticationError,include_negative=True)
        else:
            with self.assertRaises(Exception):p.redis_check(Client,config,AuthenticationError,include_negative=True)
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
