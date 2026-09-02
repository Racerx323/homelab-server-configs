<!-- markdownlint-disable MD041 -->

ReconYa ignores `SIGTERM` in `main()` and registers `waitForShutdown()` only
for `os.Interrupt`. Service managers such as systemd send `SIGTERM` by default,
so ReconYa stays alive until the service manager reaches its timeout and sends
`SIGKILL`.

Observed with the v0.26.0 ARM64 release under systemd:

- `systemctl restart reconya.service` logged
  `State 'stop-sigterm' timed out. Killing.` after 10 seconds;
- systemd then sent `SIGKILL`; and
- the existing `server.Shutdown()` path did not run.

A temporary unit workaround uses `KillSignal=SIGINT`. With that setting,
ReconYa logged `Received shutdown signal: interrupt` and
`[SUCCESS] Services stopped`, then restarted without a forced kill.

Please route `SIGTERM` through the existing graceful path. A minimal Unix
change would stop ignoring `SIGTERM` and register both signals:

```go
signal.Ignore(syscall.SIGQUIT)
// ...
signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
defer signal.Stop(stop)
```

`signal.NotifyContext` would also work if you prefer to propagate cancellation
to background services.

Suggested regression test:

1. Start the server with a temporary SQLite database and unused port.
2. Wait for its health endpoint.
3. Send `SIGTERM` to the process.
4. Require exit within the shutdown deadline and exit status 0.
5. Require the graceful-shutdown log and reject a forced kill.

This change would let systemd and container supervisors use their standard
termination signal. Existing interactive Ctrl+C behavior would remain intact.
