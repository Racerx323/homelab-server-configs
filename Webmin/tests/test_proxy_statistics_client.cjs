'use strict';
// Deterministic browser adapter: verifies client contracts, not native UI/host capacity.
const assert = require('node:assert/strict');
const {validate, exercise} = require('../scripts/proxy-statistics-client.cjs');
const spec = {token: 'a'.repeat(64), hostname: 'webmin.example.test', chromium: '/usr/bin/chromium', hold_seconds: 95,
  paths: ['a-ipv4', 'a-ipv6', 'b-ipv4', 'b-ipv6', 'vip-ipv4', 'vip-ipv6'].map((id, i) => ({id, address: id.endsWith('ipv4') ? `192.0.2.${i+1}` : `fd00::${i+1}`}))};
validate(spec);
assert.throws(() => validate({...spec, paths: spec.paths.slice(1)}));
assert.throws(() => validate({...spec, hold_seconds: 301}));
assert.throws(() => validate({...spec, token: 'bad'}));
(async () => {
  for (const failure of ['', 'insecure-cookie', 'stale-frames', 'closed-socket', 'old-session-valid', 'frame-loss', 'missing-system-info', 'launch']) {
    let now = 1000, closed = 0, created = 0, live = 0, peak = 0;
    const listeners = new Set(), events = [], visited = [];
    const originalTime = process.hrtime.bigint, originalTimeout = global.setTimeout;
    const sigterm = process.listenerCount('SIGTERM'), sigint = process.listenerCount('SIGINT');
    process.hrtime.bigint = () => BigInt(Math.floor(now * 1e9));
    global.setTimeout = callback => { now += .5; for (const frame of listeners) frame(); queueMicrotask(callback); return 0; };
    const chromium = {launch: async options => {
      if (failure === 'launch') throw Error('synthetic launch failure');
      created++; peak = Math.max(peak, ++live);
      const match = options.args[0].match(/MAP [^ ]+ (.+)/), address = match[1].replace(/^\[|\]$/g, '');
      assert.ok(options.args.includes('--no-proxy-server'));
      let loggedIn = false, revoked = false, replayed = false;
      return {close: async () => {closed++; live--;}, newContext: async settings => {
        assert.equal(settings.ignoreHTTPSErrors, false);
        const page = () => {
          let onSocket, onFrame, socketClosed = false, navigated = false, loginPage = true;
          const frame = () => {
            if (!socketClosed && failure !== 'stale-frames' && !(failure === 'frame-loss' && now > 1008)) onFrame?.();
          };
          listeners.add(frame);
          return {setDefaultTimeout() {}, on: (event, callback) => {assert.equal(event, 'websocket'); onSocket = callback;},
            goto: async url => {
              visited.push(url);
              const pathname = new URL(url).pathname;
              assert.ok(['/', '/sysinfo.cgi', '/session_login.cgi'].includes(pathname));
              if (url.includes('logout=1')) { revoked = true; loggedIn = false; }
              loginPage = !loggedIn || (replayed && revoked && failure !== 'old-session-valid');
              return {status: () => 200, serverAddr: async () => ({ipAddress: address, port: 443})};
            }, locator: selector => ({fill: async () => {}, first() {return this;},
              click: async () => {
                if (selector.includes('submit')) {
                  loggedIn = true; loginPage = false;
                  onSocket({url: () => 'wss://webmin.example.test/authentic-theme/ws-12345',
                    isClosed: () => socketClosed,
                    on: (event, callback) => {assert.equal(event, 'framereceived'); onFrame = callback; callback();}});
                } else {
                  assert.equal(selector, 'a.sidebar_sysinfo_link[href="/sysinfo.cgi"]');
                  navigated = true;
                  if (failure === 'closed-socket') socketClosed = true;
                }
              },
              waitFor: async () => {
                if (selector.includes('sysinfo_host')) assert.ok(navigated && failure !== 'missing-system-info');
                else assert.ok(loginPage, 'old session must be denied');
              }, count: async () => selector.includes('sysinfo_host') ? (loginPage ? 0 : 1) : (loginPage ? 1 : 0)}),
            waitForFunction: async () => {}, close: async () => {socketClosed = true; listeners.delete(frame);}};
        };
        return {route: async (_pattern, guard) => {
          for (const [url, expected] of [['https://webmin.example.test/sysinfo.cgi', 'continue'], ['https://elsewhere.invalid/', 'abort']]) {
            let decision; await guard({request: () => ({url: () => url}), continue: () => {decision = 'continue';}, abort: () => {decision = 'abort';}});
            assert.equal(decision, expected);
          }
        }, newPage: async () => page(),
        cookies: async () => [{name: 'sid', value: 'private-session', httpOnly: true, secure: failure !== 'insecure-cookie'}],
        clearCookies: async () => {loggedIn = false;},
        addCookies: async cookies => {assert.equal(cookies.length, 1); assert.equal(cookies[0].value, 'private-session'); replayed = true; loggedIn = true;},
        close: async () => {}};
      }};
    }};
    try {
      const run = () => exercise(spec, {username: 'private-user', password: 'private-password'}, chromium,
        row => events.push({...row, monotonic_seconds: now}));
      if (failure) await assert.rejects(run()); else await run();
    } finally { process.hrtime.bigint = originalTime; global.setTimeout = originalTimeout; }
    assert.equal(created, closed); assert.ok(peak <= 2);
    assert.equal(process.listenerCount('SIGTERM'), sigterm); assert.equal(process.listenerCount('SIGINT'), sigint);
    assert.equal(events.some(r => r.kind === 'accepted'), !failure);
    assert.ok(events.some(r => r.kind === 'cleanup'));
    assert.ok(!JSON.stringify(events).includes('private-'));
    assert.ok(!visited.some(url => url.includes('xterm')));
    if (!failure && process.argv[2] === '--receipt')
      require('node:fs').writeFileSync(process.argv[3], JSON.stringify(events.map(row => ({...row, token: spec.token}))), {mode: 0o600, flag: 'wx'});
    if (!failure) for (const p of spec.paths) {
      const active = events.filter(r => r.kind === 'active' && r.id === p.id);
      const end = events.find(r => r.kind === 'workload-end' && r.id === p.id);
      assert.ok(end.monotonic_seconds - active[0].monotonic_seconds >= 95);
      assert.ok(events.some(r => r.kind === 'path-complete' && r.id === p.id && r.old_session_denied));
    }
  }
  console.log('statistics client: eight contract/cleanup cases passed; synthetic browser adapter only');
})().catch(error => {console.error(error); process.exitCode = 1;});
