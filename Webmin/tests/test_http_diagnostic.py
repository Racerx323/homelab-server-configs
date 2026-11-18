"""Neutral tests use real local HTTP; they do not stand in for Pi acceptance."""
import http.server
import io
import os
import socket
import struct
import importlib.util
import json
import http.client
import shutil
import subprocess
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch, MagicMock

spec = importlib.util.spec_from_file_location(
    "diagnostic", Path(__file__).parents[1] / "scripts/diagnose-http.py")
diagnostic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostic)


path_spec = importlib.util.spec_from_file_location(
    "path_probe", Path(__file__).parents[1] / "scripts/probe-proxy-path.py")
path_probe = importlib.util.module_from_spec(path_spec)
path_spec.loader.exec_module(path_probe)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Set-Cookie", "sid=private-test-value")
        self.end_headers()
        try:
            self.wfile.write(b"private response body")
        except BrokenPipeError:
            pass

    def log_message(self, *_args):
        pass


class SlowHandler(Handler):
    def do_GET(self):
        time.sleep(0.3)
        super().do_GET()


class DiagnosticTests(unittest.TestCase):
    def test_loopback_curl_deadline_and_private_output(self):
        class Delayed(Handler):
            def do_GET(self):
                time.sleep(6)
                super().do_GET()
        for handler, expected in ((Handler, 0), (Delayed, 28)):
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                argv = diagnostic.loopback_curl()
                argv[-1] = f"http://127.0.0.1:{server.server_port}/session_login.cgi"
                began = time.monotonic()
                row = subprocess.run(argv, capture_output=True, text=True, timeout=7)
                self.assertEqual(row.returncode, expected)
                self.assertLess(time.monotonic()-began, 6)
                self.assertEqual(len(row.stdout.split()), 4)
                self.assertNotIn("private", row.stdout + row.stderr)
            finally:
                server.shutdown(); server.server_close(); thread.join()

    def test_loopback_stream_preserves_two_process_baseline_and_failure(self):
        # This tests orchestration/privacy only. The HTTP endpoint is not Webmin;
        # proc/cgroup reads are substituted, never evidence of target capacity.
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        argv = diagnostic.loopback_curl(); argv[-1] = f"http://127.0.0.1:{server.server_port}/session_login.cgi"
        real_read = Path.read_text
        def read_text(path, *a, **kw):
            if str(path) == "/proc/meminfo": return "MemAvailable: 200000 kB\n"
            if str(path) in ("/proc/net/tcp", "/proc/net/tcp6"): return "header\n"
            return real_read(path, *a, **kw)
        def read_small(path, *args):
            if path.name == "boot_id": return "same-boot"
            if path.name == "cpu.max": return f"{cpus*100000} 100000"
            if path.name == "memory.events": return "high 0\nmax 0\noom 0\noom_kill 0\n"
            return {"memory.high":"268435456", "memory.max":"335544320", "memory.swap.max":"0"}.get(path.name, "")
        try:
            for fail, cpus in ((False, 1), (True, 1), (False, 2)):
                count = 0
                def sample(*args, **kwargs):
                    nonlocal count
                    count += 1
                    processes = [{"pid":10,"start_ticks":1}]
                    processes += ([{"pid":11,"start_ticks":2}] if count < 4 else [{"pid":12,"vanished":True}])
                    return {"processes":processes,
                            "process_inventory_complete":True,"memory.high":"134217728",
                            "memory.max":"201326592","memory.swap.max":"0",
                            "cpu.stat":"usage_usec 1\nthrottled_usec 0\n",
                            "memory.events":f"high {int(fail and count >= 4)}\nmax 0\noom 0\noom_kill 0\n"}
                output = io.StringIO()
                with patch.object(diagnostic, "sample", sample), patch.object(diagnostic, "read_small", read_small), \
                     patch.object(Path, "read_text", read_text), patch.object(diagnostic.socket, "gethostname", return_value="j2-svpi3bmf"), \
                     patch.object(diagnostic.subprocess, "run", return_value=MagicMock(stdout="10\n")), \
                     patch.object(diagnostic, "loopback_curl", return_value=argv), patch("sys.stdout", output):
                    status = diagnostic.compare_loopback(expected_cpus=cpus)
                rows = [json.loads(x) for x in output.getvalue().splitlines()]
                self.assertEqual(status, int(fail))
                self.assertEqual([x['count'] for x in rows if x['kind']=='batch_start'], [1] if fail else [1,3])
                self.assertTrue(rows[-1]['owned_clients_reaped'])
                self.assertNotIn("private", output.getvalue())
                if fail:
                    stop = next(x for x in rows if x['kind']=='stop')
                    self.assertEqual((stop['check'],stop['expected'],stop['observed']), ('memory.events.high','0','1'))
                    self.assertTrue(any(x['kind']=='sample' for x in rows[:rows.index(stop)]))
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_backend_path_and_safe_phase_evidence(self):
        for status, failure in ((200, None), (401, None), (200, TimeoutError('PRIVATE response'))):
            connection = MagicMock()
            connection.sock.getsockname.return_value = ('10.1.0.53', 1234)
            connection.sock.getpeername.return_value = ('10.1.3.75', 10000)
            response = connection.getresponse.return_value
            response.status = status
            response.read.return_value = b'<input name="pass"> PRIVATE'
            if failure: connection.getresponse.side_effect = failure
            with patch.object(path_probe.subprocess, 'run', return_value=MagicMock(stdout='[{"prefsrc":"10.1.0.53"}]')), patch.object(path_probe.http.client, 'HTTPConnection', return_value=connection):
                result = path_probe.probe('10.1.3.75', 'webmin.example', '10.1.0.53')
            self.assertEqual(connection.request.call_args.args[:2], ('GET', '/session_login.cgi'))
            self.assertEqual(connection.request.call_args.kwargs['headers']['X-Forwarded-Host'], 'webmin.example')
            self.assertEqual(connection.request.call_args.kwargs['headers']['X-Forwarded-For'], '10.1.0.53')
            agent = connection.request.call_args.kwargs['headers']['User-Agent']
            self.assertEqual(agent, 'homelab-proxy-diagnostic')
            self.assertNotIn('webmin', agent.lower())
            owner = Path(__file__).parents[2] / 'Caddy/scripts/apply-serving-health-deployment.sh'
            self.assertIn('--user-agent ' + agent, owner.read_text())
            self.assertEqual(result['accepted'], status == 200 and failure is None)
            self.assertIn('connect_seconds', result['timing'])
            self.assertNotIn('PRIVATE', json.dumps(result))
            if failure: self.assertEqual(result['phase'], 'headers')
            connection.close.assert_called_once()

    def test_resource_intervals_reject_resets_and_replaced_groups(self):
        import copy
        row = {'boot_id': 'boot', 'cgroups': {unit: {'identity': [1, 2],
               'memory.events': 'low 0\nhigh 2\nmax 0\noom 0\noom_kill 0\n'}
               for unit in ('webmin.service', 'uptime-kuma.service')}}
        after = copy.deepcopy(row)
        after['cgroups']['webmin.service']['memory.events'] = 'low 0\nhigh 3\nmax 1\noom 1\noom_kill 1\n'
        self.assertEqual(path_probe.event_delta(row, after)['webmin.service']['events']['oom_kill'], 1)
        for field, value in [('identity', [1, 3]), ('memory.events', 'unavailable'),
                             ('memory.events', 'low 0\nhigh 1\nmax 0\noom 0\noom_kill 0\n')]:
            bad = copy.deepcopy(after); bad['cgroups']['webmin.service'][field] = value
            self.assertEqual(path_probe.event_delta(row, bad)['webmin.service']['status'], 'unavailable-or-reset')
        after['boot_id'] = 'new'
        self.assertEqual(path_probe.event_delta(row, after)['webmin.service']['status'], 'unavailable-or-reset')

    def test_resource_sampler_is_bounded_private_and_not_replayed(self):
        row = {'boot_id': 'boot', 'epoch': 1, 'monotonic': 1, 'cgroups': {unit:
               {'identity': [1, 2], 'memory.events': 'low 0\nhigh 0\nmax 0\noom 0\noom_kill 0\n'}
               for unit in ('webmin.service', 'uptime-kuma.service')}}
        for stop in (False, True):
            with tempfile.TemporaryDirectory() as name, patch.object(path_probe, 'snapshot', return_value=row):
                root = Path(name)
                if stop: (root/'resource-stop').touch()
                path_probe.observe(root, seconds=.01)
                rows = [json.loads(line) for line in (root/'resource-samples.jsonl').read_text().splitlines()]
                self.assertEqual(rows[-1]['reason'], 'stop' if stop else 'deadline')
                self.assertEqual((root/'resource-samples.jsonl').stat().st_mode & 0o777, 0o600)
                self.assertTrue((root/'resource-ready').exists())
                with self.assertRaises(FileExistsError): path_probe.observe(root, seconds=.01)
                root.chmod(0o755)
                with self.assertRaises(ValueError): path_probe.observe(root, seconds=.01)

    def test_static_health_is_never_a_foreground_marker(self):
        out = io.StringIO()
        observer = path_probe.BackendWire(out, '10.1.0.53', '10.1.3.75', 'webmin.example')
        observer.packet_epoch = 1
        health = b'GET /robots.txt HTTP/1.1\r\nX-Homelab-Health: webmin-browser-health'
        marker = b'X-Homelab-Diagnostic: '+b'a'*32
        observer.headers({'id': 1}, 'request', health)
        observer.headers({'id': 2}, 'request', b'GET /session_login.cgi HTTP/1.1\r\n'+marker)
        self.assertFalse(observer.issues)
        observer.headers({'id': 3}, 'request', health+b'\r\n'+marker)
        self.assertIn('ambiguous_request_contract', observer.issues)
        self.assertEqual([(r['kind'], r['request_id']) for r in map(json.loads, out.getvalue().splitlines())],
                         [('health', None), ('marked', 'a'*32)])

    def test_backend_wire_segmented_headers_and_privacy(self):
        out = io.StringIO()
        observer = path_probe.BackendWire(out, '10.1.0.53', '10.1.3.75', 'webmin.example')
        def packet(inbound, seq, flags, data=b''):
            src, dst = ('10.1.0.53', '10.1.3.75') if inbound else ('10.1.3.75', '10.1.0.53')
            ports = (32100, 10000) if inbound else (10000, 32100)
            ip = struct.pack('!BBHHHBBH4s4s', 0x45, 0, 40+len(data), 0, 0, 64, 6, 0,
                             socket.inet_aton(src), socket.inet_aton(dst))
            tcp = struct.pack('!HHIIBBHHH', *ports, seq, 0, 0x50, flags, 65535, 0, 0)
            return ip+tcp+data
        observer.packet(packet(True, 100, 2), 1.0)
        observer.packet(packet(False, 200, 18), 1.01)
        request = (b'GET /session_login.cgi HTTP/1.1\r\nHost: webmin.example\r\n'
                   b'X-Homelab-Diagnostic: '+b'a'*32+b'\r\nCookie: SECRET_COOKIE\r\n'
                   b'Authorization: SECRET_AUTH\r\nUser-Agent: SECRET_AGENT\r\n\r\n')
        observer.packet(packet(True, 101, 24, request[:35]), 1.02)
        observer.packet(packet(True, 136, 24, request[35:]), 1.03)
        # Duplicate TCP delivery must not produce a second request receipt.
        observer.packet(packet(True, 136, 24, request[35:]), 1.04)
        response = b'HTTP/1.1 200 OK\r\nSet-Cookie: SECRET_RESPONSE\r\n\r\nSECRET_BODY'
        observer.packet(packet(False, 201, 24, response), 1.05)
        observer.packet(packet(False, 201+len(response), 17), 1.06)
        observer.finish(0)
        rows = [json.loads(line) for line in out.getvalue().splitlines()]
        self.assertNotIn('SECRET', out.getvalue())
        heads = [r for r in rows if r.get('event') == 'request-headers']
        self.assertEqual(len(heads), 1)
        self.assertEqual(heads[0]['request_id'], 'a'*32)
        self.assertEqual(heads[0]['headers']['host'], 'webmin.example')
        self.assertEqual(heads[0]['headers']['user-agent'], 'unexpected')
        self.assertEqual([r['status'] for r in rows if r.get('event') == 'response-headers'], [200])
        self.assertEqual(rows[-2]['kind'], 'fin')
        self.assertFalse(rows[-1]['issues'])
        # Loss and out-of-order data are never interpreted as absence of requests.
        bad = path_probe.BackendWire(io.StringIO(), '10.1.0.53', '10.1.3.75', 'webmin.example')
        bad.packet(packet(True, 100, 2), 1)
        bad.packet(packet(True, 102, 24, request), 2)
        self.assertIn('tcp_gap_or_reordering', bad.issues)
        bad.finish(1)
        self.assertIn('kernel_packet_drops', bad.issues)

    @unittest.skipUnless(os.environ.get('WEBMIN_WIRE_NATIVE_TEST') == '1', 'isolated CAP_NET_RAW test only')
    def test_native_packet_socket_receives_request_and_response(self):
        # Run only in --network none: actual Linux packet socket, disposable HTTP server.
        class WireHandler(Handler):
            protocol_version = 'HTTP/1.1'
            def do_GET(self):
                self.send_response(200)
                self.send_header('Content-Length', '6')
                self.send_header('Connection', 'close')
                self.send_header('Set-Cookie', 'SECRET_NATIVE_COOKIE')
                self.end_headers(); self.wfile.write(b'SECRET')
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 10000), WireHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        row = {'boot_id': 'test', 'epoch': 1, 'monotonic': 1, 'cgroups': {unit:
               {'identity': [1, 2], 'memory.events': 'low 0\nhigh 0\nmax 0\noom 0\noom_kill 0\n'}
               for unit in ('webmin.service', 'uptime-kuma.service')}}
        errors = []
        try:
            with tempfile.TemporaryDirectory() as name, patch.object(path_probe, 'snapshot', return_value=row):
                root = Path(name)
                def collect():
                    try: path_probe.observe(root, seconds=.5, wire=('127.0.0.2', '127.0.0.1', 'webmin.example'), interface='lo')
                    except Exception as error: errors.append(error)
                worker = threading.Thread(target=collect); worker.start()
                deadline = time.monotonic()+1
                while not (root/'resource-ready').exists() and time.monotonic() < deadline and not errors:
                    time.sleep(.005)
                self.assertTrue((root/'resource-ready').exists(), errors)
                connection = http.client.HTTPConnection('127.0.0.1', 10000, timeout=1, source_address=('127.0.0.2', 0))
                connection.request('GET', '/session_login.cgi', headers={'Host': 'webmin.example', 'X-Homelab-Diagnostic': 'd'*32})
                response = connection.getresponse(); response.read(); connection.close()
                worker.join(2); self.assertFalse(worker.is_alive()); self.assertFalse(errors)
                captured = (root/'backend-wire.jsonl').read_text()
                self.assertEqual((root/'backend-wire.jsonl').stat().st_mode & 0o777, 0o600)
            rows = [json.loads(line) for line in captured.splitlines()]
            self.assertFalse(rows[-1]['issues'])
            self.assertEqual([r['request_id'] for r in rows if r.get('event') == 'request-headers'], ['d'*32])
            self.assertEqual([r['status'] for r in rows if r.get('event') == 'response-headers'], [200])
            self.assertTrue(any(r.get('event') == 'response-close' for r in rows))
            self.assertNotIn('SECRET', captured)
        finally:
            server.shutdown(); server.server_close(); thread.join()

    @unittest.skipUnless(shutil.which('caddy'), 'native Caddy required for log contract')
    def test_native_caddy_correlates_safe_upstream_timing(self):
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), SlowHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        import socket
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0)); port = reservation.getsockname()[1]
        try:
            with tempfile.TemporaryDirectory() as name:
                root = Path(name)
                source = (Path(__file__).parents[1]/'proposals/30-webmin-j2-svpi3bmf.caddy').read_text()
                source = source.replace('https://webmin-j2-svpi3bmf.local.theama.co {', 'http://127.0.0.1:'+str(port)+' {')
                source = source.replace('    bind 10.1.0.56 fd36:5aa8:6971:1::56 {$NODE_IPV4} {$NODE_IPV6}\n', '')
                source = source.replace('    import local_tls\n', '')
                source = source.replace('remote_ip 10.1.0.0/22 fd36:5aa8:6971:1::/64', 'remote_ip 127.0.0.1')
                source = source.replace('10.1.3.75:10000', '127.0.0.1:'+str(server.server_port))
                (root/'Caddyfile').write_text('{\n admin off\n}\n'+source)
                adapted = subprocess.run(['caddy', 'adapt', '--config', str(root/'Caddyfile'), '--adapter', 'caddyfile'], capture_output=True, text=True, timeout=10)
                self.assertEqual(adapted.returncode, 0, adapted.stderr)
                with (root/'log').open('w') as log:
                    child = subprocess.Popen(['caddy', 'run', '--config', str(root/'Caddyfile'), '--adapter', 'caddyfile'], stdout=log, stderr=log)
                    try:
                        for _ in range(50):
                            try:
                                with socket.create_connection(('127.0.0.1', port), timeout=.1): break
                            except OSError: time.sleep(.1)
                        else: self.fail('native Caddy readiness exit='+str(child.poll())+' log='+repr((root/'log').read_text()))
                        for request_id, timeout in [(None, 2), ('a'*32, 2), ('b'*32, .05)]:
                            client = http.client.HTTPConnection('127.0.0.1', port, timeout=timeout)
                            headers = {'Cookie': 'PRIVATE-CANARY', 'Authorization': 'PRIVATE-CANARY'}
                            if request_id: headers['X-Homelab-Diagnostic'] = request_id
                            try:
                                client.request('GET', '/session_login.cgi', headers=headers)
                                response = client.getresponse(); response.read()
                                self.assertEqual(response.status, 200)
                            except TimeoutError:
                                self.assertEqual(request_id, 'b'*32)
                            finally: client.close()
                        for _ in range(40):
                            records = []
                            for line in (root/'log').read_text().splitlines():
                                try: entry = json.loads(line)
                                except ValueError: continue
                                if 'diagnostic_id' in entry: records.append(entry)
                            if len(records) >= 2: break
                            time.sleep(.1)
                        self.assertEqual({r['diagnostic_id'] for r in records}, {'a'*32, 'b'*32})
                        self.assertEqual(len(records), 2)
                        self.assertNotIn('PRIVATE', json.dumps(records))
                        for entry in records:
                            self.assertNotIn('request', entry); self.assertNotIn('resp_headers', entry)
                        success = next(r for r in records if r['diagnostic_id'] == 'a'*32)
                        self.assertEqual(success['status'], 200)
                        self.assertGreater(float(success['upstream_latency_ms']), 0)
                        self.assertGreater(float(success['upstream_duration_ms']), 0)
                        self.assertEqual(success['upstream_host'], '127.0.0.1:'+str(server.server_port))
                    finally:
                        child.terminate()
                        try: child.wait(timeout=5)
                        except subprocess.TimeoutExpired: child.kill(); child.wait()
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def request(self, handler, timeout=2):
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            return diagnostic.probe("127.0.0.1", server.server_port, "/session_login.cgi", timeout)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_actual_http_retains_status_without_private_response(self):
        result = self.request(Handler)
        self.assertEqual(result["status"], 200)
        self.assertNotIn("private", json.dumps(result))
        self.assertEqual(set(result), {"host", "path", "timeout_seconds", "status", "elapsed_seconds"})

    def test_slow_headers_are_bounded_and_recorded(self):
        result = self.request(SlowHandler, 0.05)
        self.assertEqual(result["error_type"], "TimeoutError")
        self.assertLess(result["elapsed_seconds"], 1)

    def test_remote_or_unreviewed_endpoints_are_rejected(self):
        for host, path in [("192.0.2.1", "/"), ("127.0.0.1", "/useradmin/")]:
            with self.assertRaises(ValueError):
                diagnostic.probe(host, 10000, path, 1)

    def test_profile_verification_rejects_duplicate_or_changed_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            config, policy = Path(directory) / "config", Path(directory) / "policy"
            policy.write_text('{"ssl":"0"}')
            config.write_text("unmanaged_secret=private\nssl=0\n")
            self.assertEqual(diagnostic.verify_profile(config, policy), {"managed_profile_matches": True})
            self.assertIn("private", config.read_text())
            for content in ["ssl=1\n", "ssl=0\nssl=0\n"]:
                config.write_text(content)
                with self.assertRaises(ValueError):
                    diagnostic.verify_profile(config, policy)


    def test_memory_attribution_retains_numeric_rollup_not_private_process_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            group, proc = root / "group", root / "proc"
            group.mkdir()
            (proc / "42").mkdir(parents=True)
            (group / "cgroup.procs").write_text("42\n")
            (group / "memory.stat").write_text("anon 8192\nfile 4096\n")
            (group / "memory.max").write_text("201326592\n")
            (proc / "42/status").write_text("Name:\tperl\nPPid:\t1\nVmRSS:\t16 kB\nSecret: private-canary\n")
            (proc / "42/smaps_rollup").write_text(
                "0000-ffff private-canary\nPss: 12 kB\nPss_Anon: 8 kB\n"
                "Pss_File: 4 kB\nPrivate_Dirty: 8 kB\nSwap: invalid\n")
            (proc / "42/cmdline").write_text("private-canary")
            (proc / "42/environ").write_text("private-canary")
            result = diagnostic.sample(group, time.monotonic(), proc)
            process = result["processes"][0]
            self.assertEqual(process["Pss_kib"], 12)
            self.assertEqual(process["Pss_Anon_kib"], 8)
            self.assertNotIn("Swap_kib", process)
            self.assertEqual(result["memory.stat"], "anon 8192\nfile 4096")
            self.assertTrue(result["process_inventory_complete"])
            self.assertEqual(result["memory.max"], "201326592")
            self.assertNotIn("private-canary", json.dumps(result))

    def test_disappeared_process_and_truncated_inventory_are_explicit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "cgroup.procs").write_text("\n".join(str(n) for n in range(1, 19)))
            result = diagnostic.sample(root, time.monotonic(), root / "absent")
            self.assertEqual(len(result["processes"]), 16)
            self.assertEqual(result["processes_omitted"], 2)
            self.assertFalse(result["process_inventory_complete"])
            self.assertFalse(result["processes"][0]["rollup_available"])
            (root / "cgroup.procs").write_text("1" * 9000)
            result = diagnostic.sample(root, time.monotonic(), root / "absent")
            self.assertFalse(result["process_inventory_complete"])
            self.assertIsNone(result["processes_omitted"])
            self.assertEqual(result["processes"], [])


if __name__ == "__main__":
    unittest.main()
