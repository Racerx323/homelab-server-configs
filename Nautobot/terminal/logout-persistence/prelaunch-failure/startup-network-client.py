#!/usr/bin/env python3
"""One unbound HTTP connection with a retained source address, including timeout."""
import json
import socket
import sys


def probe(destination):
    result = {'status': None, 'source': None, 'outcome': 'error'}
    with socket.socket(socket.AF_INET6 if ':' in destination else socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(3)
        try:
            sock.connect((destination, 8080))
            sock.sendall(b'GET /health/ HTTP/1.1\r\nHost: j2-svpi4mf.local.theama.co\r\nConnection: close\r\n\r\n')
            data = b''
            while b'\r\n' not in data and len(data) < 4096:
                chunk = sock.recv(512)
                if not chunk:
                    break
                data += chunk
            line = data.split(b'\r\n')[0].split()
            if len(line) >= 2 and line[0] in (b'HTTP/1.0', b'HTTP/1.1'):
                result.update(status=int(line[1]), outcome='response')
        except TimeoutError:
            result['outcome'] = 'timeout'
        except OSError:
            pass
        result['source'] = sock.getsockname()[0]
    return result


if __name__ == '__main__':
    print(json.dumps(probe(sys.argv[1])))
