#!/usr/bin/env python3
"""Real container HTTP readiness probes; no production services or credentials."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from unittest.mock import patch

SCRIPTS=Path(__file__).resolve().parents[1]/'ansible/scripts'
sys.path.insert(0,str(SCRIPTS))
import recurring_node as node


def call(args):
    return subprocess.run(args,check=True,capture_output=True,text=True,timeout=30)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--image',required=True,help='Existing disposable image with Python 3')
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--startup-delay-seconds',type=float,default=2)
    args=parser.parse_args();args.output.mkdir(mode=0o700)
    assert 0 < args.startup_delay_seconds < node.READINESS_SECONDS
    server='''from http.server import HTTPServer,BaseHTTPRequestHandler
from pathlib import Path
import time
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  if Path('/tmp/hang').exists():time.sleep(10)
  self.send_response(200 if Path('/tmp/ready').exists() else 503);self.end_headers()
 def log_message(self,*args):pass
HTTPServer(('127.0.0.1',8080),Handler).serve_forever()
'''
    cid=call(['podman','run','-d','--pull=never','--network=none','--entrypoint','/usr/bin/python3',args.image,'-u','-c',server]).stdout.strip()
    real_pod=node.pod
    def pod(argv,**kwargs):
        assert argv[:2]==['exec','nautobot-web']
        return real_pod(['exec',cid,*argv[2:]],**kwargs)
    rows={'nautobot-'+role+'.service':{'ActiveState':'active','SubState':'running'} for role in node.ROLES}
    results=[]
    try:
        # Only service-manager status is controlled; the production HTTP probe runs unchanged.
        with patch.object(node,'states',return_value=rows),patch.object(node,'pod',side_effect=pod):
            try:node.health(timeout=2)
            except ValueError:pass
            else:raise AssertionError('unready endpoint accepted')
            call(['podman','exec','-d',cid,'python3','-c',f"import time;from pathlib import Path;time.sleep({args.startup_delay_seconds});Path('/tmp/ready').touch()"])
            start=time.monotonic();assert node.wait_healthy()==rows
            elapsed=time.monotonic()-start;assert args.startup_delay_seconds-0.5<=elapsed<node.READINESS_SECONDS
            results.append({'scenario':'delayed_http_readiness','passed':True,'elapsed_seconds':elapsed,
                            'startup_delay_seconds':args.startup_delay_seconds,'readiness_seconds':node.READINESS_SECONDS})
            call(['podman','exec',cid,'python3','-c',"from pathlib import Path;Path('/tmp/ready').unlink()"])
            start=time.monotonic()
            try:node.wait_healthy(timeout=2)
            except ValueError as error:assert str(error)=='readiness_deadline'
            else:raise AssertionError('persistent HTTP 503 accepted')
            elapsed=time.monotonic()-start;assert 1.9<=elapsed<4
            results.append({'scenario':'persistent_http_failure','passed':True,'elapsed_seconds':elapsed})
            call(['podman','exec',cid,'python3','-c',"from pathlib import Path;Path('/tmp/hang').touch()"])
            start=time.monotonic()
            try:node.wait_healthy(timeout=1)
            except ValueError as error:assert str(error)=='readiness_deadline'
            else:raise AssertionError('hung HTTP probe accepted')
            elapsed=time.monotonic()-start;assert 0.9<=elapsed<4
            results.append({'scenario':'hung_http_probe','passed':True,'elapsed_seconds':elapsed})
        (args.output/'results.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results))
    finally:
        call(['podman','rm','-f','--volumes',cid])
        (args.output/'cleanup.json').write_text(json.dumps({'container_id':cid,'removed':True})+'\n')


if __name__=='__main__':
    os.umask(0o077)
    main()
