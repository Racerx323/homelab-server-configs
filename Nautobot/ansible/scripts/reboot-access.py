#!/usr/bin/env python3
"""Fixed read-only access checks from the accepted proxy and monitoring sources."""
import argparse
import json
from pathlib import Path
import resource
import subprocess
import tempfile

PROXY = '''import http.client,json
result={}
for address in ('10.1.2.170','fd36:5aa8:6971:1::170'):
 c=http.client.HTTPConnection(address,8080,timeout=5)
 c.request('GET','/health/',headers={'Host':'j2-svpi4mf.local.theama.co'})
 result[address]=c.getresponse().status
 c.close()
print(json.dumps(result))
'''
MONITOR = '''import socket,json
result={}
for port in (22,10000,4949):
 with socket.create_connection(('10.1.2.170',port),timeout=5) as c:
  c.settimeout(5)
  if port==4949:
   result[str(port)]=c.recv(512).startswith(b'# munin node at ')
   c.sendall(b'quit\\n')
  else: result[str(port)]=True
print(json.dumps(result))
'''


def check(host, source):
    def limits():
        resource.setrlimit(resource.RLIMIT_FSIZE, (65536, 65536))
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        result = subprocess.run(['/usr/bin/ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
            '-o', 'ConnectTimeout=10', host, 'cd / && python3 -'], input=source.encode(),
            stdout=out, stderr=err, timeout=45, preexec_fn=limits)
        if result.returncode or out.tell() >= 65536 or err.tell() >= 65536:
            raise ValueError('access_transport_failed')
        out.seek(0)
        return json.load(out)


def collect():
    proxy = check('pi@10.1.0.53', PROXY)
    monitor = check('pi@10.1.3.83', MONITOR)
    if proxy != {'10.1.2.170': 200, 'fd36:5aa8:6971:1::170': 200} or monitor != {'22': True, '10000': True, '4949': True}:
        raise ValueError('access_failed')
    return {'proxy': proxy, 'monitor': monitor, 'certificate_trust_verified': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = collect()
    with args.output.open('x') as stream:
        json.dump(result, stream, sort_keys=True)
