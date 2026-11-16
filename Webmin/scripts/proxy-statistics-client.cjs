/* Existing-account System Information only. Never use xterm or export sessions. */
'use strict';
const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const assert = require('node:assert/strict');

function validate(spec) {
  assert.match(spec.token, /^[0-9a-f]{64}$/);
  assert.match(spec.hostname, /^[a-z0-9.-]+$/);
  assert.equal(spec.paths.length, 6);
  assert.deepEqual(spec.paths.map(p => p.id).sort(),
    ['a-ipv4', 'a-ipv6', 'b-ipv4', 'b-ipv6', 'vip-ipv4', 'vip-ipv6']);
  for (const p of spec.paths) assert.equal(net.isIP(p.address), p.id.endsWith('ipv4') ? 4 : 6);
  assert.ok(Number.isInteger(spec.hold_seconds) && spec.hold_seconds >= 95 && spec.hold_seconds <= 300);
  assert.ok(spec.chromium.startsWith('/'));
}

function privateJSON(name) {
  const info = fs.lstatSync(name);
  assert.ok(info.isFile() && info.uid === process.getuid() && (info.mode & 0o777) === 0o600 && info.size <= 65536);
  assert.equal(fs.realpathSync(name), path.resolve(name));
  return JSON.parse(fs.readFileSync(name, 'utf8'));
}

async function exercise(spec, credentials, chromium, emit) {
  validate(spec);
  const owned = new Set();
  let stopping = false;
  const base = `https://${spec.hostname}`;
  async function cleanup() {
    stopping = true;
    const results = await Promise.allSettled([...owned].map(async item => {
      // Closing our page ends only its native statistics connection.
      await item.page.close();
      const logout = await item.context.newPage();
      await logout.goto(base + '/session_login.cgi?logout=1', { referer: base + '/', timeout: 10000 });
      await logout.locator('input[name=pass]').waitFor({ timeout: 10000 });
      await item.context.close();
    }));
    const closed = await Promise.allSettled([...owned].map(item => item.browser.close()));
    emit({ kind: 'cleanup', passed: [...results, ...closed].every(r => r.status === 'fulfilled') });
    if ([...results, ...closed].some(r => r.status === 'rejected')) throw Error('cleanup');
  }
  // Parent owns this process group; TERM requests logout before bounded hard stop.
  const onStop = () => { stopping = true; };
  process.on('SIGTERM', onStop); process.on('SIGINT', onStop);
  async function path(p, hold, barrier) {
    if (stopping) throw Error('cancelled');
    const ip = net.isIP(p.address) === 6 ? `[${p.address}]` : p.address;
    const browser = await chromium.launch({ executablePath: spec.chromium, headless: true,
      handleSIGTERM: false, handleSIGINT: false,
      args: [`--host-resolver-rules=MAP ${spec.hostname} ${ip}`, '--disable-dev-shm-usage', '--no-proxy-server'] });
    const item = { browser }; owned.add(item);
    const context = item.context = await browser.newContext({ ignoreHTTPSErrors: false });
    await context.route('**/*', route => new URL(route.request().url()).origin === base ? route.continue() : route.abort());
    const page = item.page = await context.newPage(); page.setDefaultTimeout(30000);
    const sockets = new Map();
    const fresh = () => [...sockets].filter(([socket]) => !socket.isClosed()).map(([, state]) => state);
    const frameCount = () => fresh().reduce((sum, state) => sum + state.frames, 0);
    const lastFrame = () => Math.max(0, ...fresh().map(state => state.last));
    page.on('websocket', socket => {
      const url = new URL(socket.url());
      if (url.origin !== `wss://${spec.hostname}` || !/^\/authentic-theme\/ws-\d+$/.test(url.pathname)) return;
      const state = { frames: 0, last: 0 }; sockets.set(socket, state);
      // Count receipt only; never retain frames, cookies, bodies or URL queries.
      socket.on('framereceived', () => {
        if (!socket.isClosed()) { state.frames++; state.last = Number(process.hrtime.bigint()) / 1e9; }
      });
    });
    let response = await page.goto(base + '/', { waitUntil: 'domcontentloaded' });
    assert.equal(response.status(), 200);
    const server = await response.serverAddr();
    assert.equal(server.ipAddress.replace(/^\[|\]$/g, ''), p.address); assert.equal(server.port, 443);
    await page.locator('input[name=user]').fill(credentials.username);
    await page.locator('input[name=pass]').fill(credentials.password);
    await page.locator('button[type=submit], input[type=submit]').first().click();
    await page.waitForFunction(() => !document.querySelector('input[name=pass]'), null, { timeout: 30000 });
    // The active theme resolves /sysinfo.cgi through MiniServ's preroot. Use
    // its native navigation so the theme's statistics controller remains loaded.
    const sid = (await context.cookies()).find(c => c.name === 'sid' && c.value !== 'x');
    assert.ok(sid && sid.httpOnly && sid.secure);
    await page.locator('a.sidebar_sysinfo_link[href="/sysinfo.cgi"]').click();
    await page.locator('[data-id="sysinfo_host"]').waitFor({ timeout: 30000 });
    assert.equal(await page.locator('input[name=pass]').count(), 0);
    // AJAX navigation can retain a socket; require fresh frames after page
    // readiness, never frames from login or from a socket that has since closed.
    for (const state of sockets.values()) { state.frames = 0; state.last = 0; }
    const deadline = Number(process.hrtime.bigint()) / 1e9 + 30;
    while (!frameCount() && Number(process.hrtime.bigint()) / 1e9 < deadline && !stopping)
      await new Promise(r => setTimeout(r, 100));
    assert.ok(frameCount() > 0);
    barrier.ready++;
    while (barrier.ready < 2 && !stopping) await new Promise(r => setTimeout(r, 100));
    if (stopping) throw Error('cancelled');
    const start = Number(process.hrtime.bigint()) / 1e9;
    emit({ kind: 'path', id: p.id, address: server.ipAddress, port: server.port, trusted_tls: true, login: true, statistics_frames: frameCount() });
    while (Number(process.hrtime.bigint()) / 1e9 - start < hold) {
      if (stopping) throw Error('cancelled');
      assert.ok(fresh().length > 0);
      assert.ok(Number(process.hrtime.bigint()) / 1e9 - lastFrame() <= 15);
      emit({ kind: 'active', id: p.id, statistics_frames: frameCount() });
      await new Promise(r => setTimeout(r, 500));
    }
    emit({kind: 'workload-end', id: p.id});
    await page.close();
    const logout = await context.newPage();
    await logout.goto(base + '/session_login.cgi?logout=1', { referer: base + '/', timeout: 10000 });
    await logout.locator('input[name=pass]').waitFor({ timeout: 10000 });
    // Replay only this owned session in memory. A login page after clearing the
    // cookie alone would not establish server-side invalidation.
    await context.clearCookies(); await context.addCookies([sid]);
    await logout.goto(base + '/sysinfo.cgi', { referer: base + '/', timeout: 10000 });
    await logout.locator('input[name=pass]').waitFor({ timeout: 10000 });
    assert.equal(await logout.locator('[data-id="sysinfo_host"]').count(), 0);
    await context.clearCookies();
    await context.close(); await browser.close(); owned.delete(item);
    emit({ kind: 'path-complete', id: p.id, logout: true, old_session_denied: true });
  }
  try {
    // Bound concurrency to two clients. Every path gets at least 95 seconds;
    // the final pair supplies the parent's scan-readiness gate and overlap.
    for (const ids of [['a-ipv6', 'b-ipv4'], ['vip-ipv4', 'vip-ipv6'], ['a-ipv4', 'b-ipv6']]) {
      const barrier = { ready: 0 };
      const hold = ids[0] === 'a-ipv4' ? spec.hold_seconds : 95;
      const results = await Promise.allSettled(ids.map(id =>
        path(spec.paths.find(p => p.id === id), hold, barrier)
          .catch(error => { stopping = true; throw error; })));
      assert.ok(results.every(r => r.status === 'fulfilled'));
    }
    emit({ kind: 'accepted' });
  } finally {
    try { await cleanup(); }
    finally { process.off('SIGTERM', onStop); process.off('SIGINT', onStop); }
  }
}

module.exports = { validate, exercise };
if (require.main === module) {
  process.umask(0o077);
  if (process.argv[2] === '--check') {
    const spec = privateJSON(process.argv[3]); validate(spec);
    fs.accessSync(spec.chromium, fs.constants.X_OK);
    assert.ok(require('playwright').chromium);
    console.log(JSON.stringify({source_and_module_ready: true, browser_launched: false, playwright: require('playwright/package.json').version}));
    process.exit(0);
  }
  const spec = privateJSON(process.argv[2]);
  const output = fs.openSync(process.argv[3], 'wx', 0o600);
  const emit = row => fs.writeSync(output, JSON.stringify({ ...row, token: spec.token, monotonic_seconds: Number(process.hrtime.bigint()) / 1e9 }) + '\n');
  let input = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', data => { input += data; if (input.length > 4096) process.exit(64); });
  process.stdin.on('end', async () => {
    try {
      const credentials = JSON.parse(input); input = '';
      await exercise(spec, credentials, require('playwright').chromium, emit);
    } catch (_) { emit({ kind: 'failed' }); process.exitCode = 1; }
    finally { fs.closeSync(output); }
  });
}
