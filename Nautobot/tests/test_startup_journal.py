#!/usr/bin/env python3
"""Opt-in local rootless systemd/Podman journal receipt test; never production."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('node', ROOT/'Nautobot/ansible/scripts/startup-node.py')
node = importlib.util.module_from_spec(spec)
spec.loader.exec_module(node)


def call(argv):
    return subprocess.check_output(argv, text=True, stderr=subprocess.PIPE, timeout=30)


@unittest.skipUnless(os.environ.get('NAUTOBOT_JOURNAL_TEST_IMAGE'), 'opt-in existing local image required')
class Journal(unittest.TestCase):
    def test_current_receipt_survives_container_removal_and_excludes_prior_restart(self):
        image = call(['podman','image','inspect','--format','{{.Id}}',os.environ['NAUTOBOT_JOURNAL_TEST_IMAGE']]).strip()
        name = 'nautobot-journal-test-'+uuid.uuid4().hex[:12]
        unit = name+'.service'
        receipt = {'role':'web','passed':True,'invocation':'INVOCATION_TOKEN','steps':{
            k:{'exit_status':0,'output_limited':False} for k in ('configuration','pending_migrations','static_collection')}}
        payload = json.dumps(receipt,separators=(',',':')).replace('INVOCATION_TOKEN','%s')
        command = 'printf \'NAUTOBOT_STARTUP_RESULT='+payload+'\\n\' "$INVOCATION_ID"'
        def query(argv):
            return call([('CONTAINER_NAME='+name if a=='CONTAINER_NAME=nautobot-web' else
                          '_UID='+str(os.getuid()) if a=='_UID=999' else a) for a in argv])
        try:
            call(['systemd-run','--user','--unit',unit,'--property=Type=oneshot',
                  '--property=RemainAfterExit=yes','--property=TimeoutStartSec=30',
                  'podman','run','--rm','--pull=never','--network=none','--name',name,
                  '--log-driver=journald','--env=INVOCATION_ID',image,'sh','-c',command])
            identities=[]
            for attempt in range(2):
                if attempt:call(['systemctl','--user','restart',unit])
                invocation=call(['systemctl','--user','show',unit,'--property=InvocationID','--value']).strip()
                for _ in range(30):
                    result=node.native_status('web',invocation,query)
                    if result['passed']:break
                    time.sleep(.1)
                self.assertTrue(result['passed'],result)
                identities.append(invocation)
            self.assertNotEqual(*identities)
            self.assertFalse(node.native_status('web','f'*32,query)['passed'])
            self.assertEqual(call(['podman','ps','-a','--filter','name=^'+name+'$','--format','{{.ID}}']).strip(),'')
        finally:
            subprocess.run(['systemctl','--user','stop',unit],capture_output=True,timeout=30)
            subprocess.run(['systemctl','--user','reset-failed',unit],capture_output=True,timeout=10)
            subprocess.run(['podman','rm','--force',name],capture_output=True,timeout=15)


if __name__ == '__main__': unittest.main()
