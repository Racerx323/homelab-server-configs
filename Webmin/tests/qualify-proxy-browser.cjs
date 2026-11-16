/* Synthetic credentials only; run inside the network-none qualification container. */
const { chromium } = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');

(async () => {
  assert.ok(fs.existsSync('/run/.containerenv'));
  const family = process.argv[2] || 'ipv4';
  assert.ok(['ipv4', 'ipv6'].includes(family));
  const node = process.argv[3] || 'a';
  const mode = process.argv[4] || 'short';
  assert.ok(['a', 'b'].includes(node));
  assert.ok(['short', 'sustained'].includes(mode));
  const label = process.argv[3] ? `${node}-${family}-${mode}` : family;
  const ip = node === 'a' ? (family === 'ipv6' ? '::1' : '127.0.0.1') :
    (family === 'ipv6' ? 'fd00::2' : '127.0.0.2');
  const address = family === 'ipv6' ? `[${ip}]` : ip;
  const credentials = JSON.parse(fs.readFileSync('/evidence/login.json', 'utf8'));
  let browser;
  let stage;
  const trace = fs.openSync(`/evidence/browser-phases-${label}.jsonl`, 'wx', 0o600);
  function enter(value) {
    stage = value;
    fs.writeSync(trace, JSON.stringify({ stage, monotonic_ns: process.hrtime.bigint().toString() }) + '\n');
  }
  enter('launch');
  const result = { family, node, mode, passed: false, tls_bypass: false, websocket: false };
  const base = 'https://webmin-host.example.test';
  try {
    browser = await chromium.launch({ executablePath: '/usr/bin/chromium', headless: true,
      args: ['--no-sandbox', '--disable-dev-shm-usage', `--host-resolver-rules=MAP webmin-host.example.test ${address}`] });
    const context = await browser.newContext({ ignoreHTTPSErrors: false });
    const page = await context.newPage();
    page.setDefaultTimeout(60000);
    enter('trusted-login-page');
    const response = await page.goto('https://webmin-host.example.test/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    assert.equal(response.status(), 200);
    result.server = await response.serverAddr();
    assert.equal(result.server.ipAddress.replace(/^\[|\]$/g, ''), ip);
    assert.equal(result.server.port, 443);
    await page.locator('input[name=user]').waitFor();
    result.login_page = true;
    enter('rejected-login');
    await page.locator('input[name=user]').fill(credentials.username);
    await page.locator('input[name=pass]').fill('deliberately-invalid-fixture-password');
    await page.locator('button[type=submit], input[type=submit]').first().click();
    await page.locator('input[name=pass]').waitFor();
    assert.equal((await context.cookies()).some(c => c.name === 'sid' && c.value !== 'x'), false);
    result.bad_password_rejected = true;
    enter('login');
    await page.locator('input[name=user]').fill(credentials.username);
    await page.locator('input[name=pass]').fill(credentials.password);
    await page.locator('button[type=submit], input[type=submit]').first().click();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForFunction(() => !document.querySelector('input[name=pass]'), { timeout: 30000 });
    result.login = true;
    result.final_url = page.url().split('?')[0];
    const cookies = await context.cookies();
    result.session_cookie = cookies.some(c => c.name === 'sid' && c.value && c.httpOnly);
    assert.equal(result.session_cookie, true);
    result.secure_session_cookie = cookies.filter(c => c.name === 'sid').every(c => c.secure);
    assert.equal(result.secure_session_cookie, true);
    result.title = await page.title();
    enter('assets');
    const assetPaths = await page.locator('script[src], link[rel=stylesheet]').evaluateAll(nodes => nodes.map(n => n.src || n.href));
    assert.ok(assetPaths.length > 0);
    for (const url of assetPaths) {
      assert.equal(new URL(url).origin, base);
      const status = await page.evaluate(async url => (await fetch(url)).status, url);
      assert.equal(status, 200);
    }
    result.assets = assetPaths.length;
    const protectedURL = base + '/webmin/edit_referers.cgi';
    enter('trusted-referrer');
    await page.goto(protectedURL, { referer: base + '/', waitUntil: 'domcontentloaded' });
    assert.ok(!(await page.locator('body').innerText()).includes('Security Warning'));
    assert.ok(await page.locator('form').count());
    enter('foreign-referrer');
    await page.goto(protectedURL, { referer: 'https://foreign.example.test/', waitUntil: 'domcontentloaded' });
    assert.ok((await page.locator('body').innerText()).includes('Security Warning'));
    enter('missing-referrer');
    await page.goto(protectedURL, { waitUntil: 'domcontentloaded' });
    assert.ok((await page.locator('body').innerText()).includes('Security Warning'));
    result.referrer_checks = true;
    enter('native-websocket');
    const terminal = await context.newPage();
    const socketPromise = terminal.waitForEvent('websocket', { timeout: 60000 }).then(async socket => {
      await socket.waitForEvent('framereceived', { timeout: 30000 });
      return socket;
    });
    // Attach rejection handling while navigation is pending.
    socketPromise.catch(() => {});
    await terminal.goto(base + '/xterm/', { referer: base + '/', waitUntil: 'domcontentloaded', timeout: 60000 });
    const socket = await socketPromise;
    assert.ok(socket.url().startsWith('wss://webmin-host.example.test/'));
    // The fixture ACL permits only its unprivileged Unix user; send no terminal input.
    assert.equal(socket.isClosed(), false);
    if (mode === 'sustained') {
      enter('sustained');
      const start = process.hrtime.bigint();
      result.sustained_checks = [];
      // Keep the authenticated native WebSocket open; issue no terminal input.
      // Each round exercises a protected HTTP page while both proxy health loops run.
      for (const target of [0, 15, 30, 45, 60, 75, 95]) {
        const elapsed = Number(process.hrtime.bigint() - start) / 1e9;
        await new Promise(resolve => setTimeout(resolve, Math.max(0, target - elapsed) * 1000));
        assert.equal(socket.isClosed(), false);
        const check = await page.goto(protectedURL, { referer: base + '/', waitUntil: 'domcontentloaded' });
        assert.equal(check.status(), 200);
        assert.ok(await page.locator('form').count());
        assert.equal(await page.locator('input[name=pass]').count(), 0);
        assert.ok(!(await page.locator('body').innerText()).includes('Security Warning'));
        result.sustained_checks.push({ elapsed_seconds: Number(process.hrtime.bigint() - start) / 1e9,
          http_status: check.status(), websocket_open: !socket.isClosed() });
      }
      assert.equal(socket.isClosed(), false);
      result.sustained_seconds = Number(process.hrtime.bigint() - start) / 1e9;
      assert.ok(result.sustained_seconds >= 95);
    }
    await terminal.close();
    result.websocket = true;
    enter('logout');
    await page.goto(base + '/session_login.cgi?logout=1', { referer: base + '/', waitUntil: 'domcontentloaded' });
    await page.locator('input[name=pass]').waitFor();
    // Replaying the old cookie is confined to this synthetic fixture and never logged.
    await context.addCookies(cookies);
    await page.goto(base + '/sysinfo.cgi', { waitUntil: 'domcontentloaded' });
    await page.locator('input[name=pass]').waitFor();
    result.logout_invalidates_session = true;
    fs.writeFileSync(`/evidence/browser-expanded-${label}-dom.txt`, await page.locator('body').innerText(), { mode: 0o600 });
    result.passed = true;
  } catch (error) {
    result.failure_stage = stage;
    result.error_class = error.constructor.name;
    // No credential, URL query, cookie, response body or raw exception serialization.
    process.exitCode = 1;
  } finally {
    enter('cleanup');
    if (browser) await browser.close();
    fs.closeSync(trace);
    fs.writeFileSync(`/evidence/browser-expanded-${label}.json`, JSON.stringify(result, null, 2) + '\n', { mode: 0o600 });
    console.log(JSON.stringify(result));
  }
})();
