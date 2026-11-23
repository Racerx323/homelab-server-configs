# Primary Webmin forward: installation review

Scope: primary j1-svpihole0 (10.1.0.53) and Pi j2-svpi3bmf (10.1.3.75)
only. The change is persistent on acceptance. No reboot, Caddy deploy, DNS,
Webmin configuration change, browser password, or secondary proxy. Use existing
pinned SSH access as pi / ama. Keep an authenticated administrative shell on
the Pi open throughout. Stop on the first mismatch; do not retry the install.

1. **Admit both hosts.** Check native names, pinned host keys and fresh
   /proc/sys/kernel/random/boot_id; compare these boot IDs at each subsequent
   phase. Repeat W-271's route, account/group, files/unit, listener and
   reserved-port checks. Require the Pi's loopback-only listener, the primary's
   .53 source, free TCP 18075, and absent owned paths. Verify the installed
   ssh.service actually uses the config being changed. Record the complete
   effective ama policy for the active connection using sshd -T -C; retain
   private output, not key material. Abort on intervening edits.
   Before modifying the Pi, provision the **primary-local** service identity.
   Require both `getent passwd wmproxyfwd` and `getent group wmproxyfwd` to
   report no match; never adopt an existing identity. On the primary use
   `useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin wmproxyfwd`.
   Record UID/GID; require a nonzero UID, only the dedicated group, locked
   password and correct passwd entry when looked up by numeric UID.
   As that user, run `sudo -n -u wmproxyfwd -- /usr/bin/ssh -G -F /dev/null wmfwdpi@10.1.3.75`.
   This checks the actual primary SSH client's UID lookup without connecting.
   On failure remove only the newly created primary identity and stop.
   Use a new private recovery directory; never reuse /root/webmin-forward-w273.
2. **Prepare Pi policy without a usable key.** Create a system account with
   its own group, no home creation, no password, /usr/sbin/nologin, and no
   privileged groups. Check both names are free first. Use
   `useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin wmfwdpi`.
   Do not unlock password authentication to make a failing test pass. Save a
   root-private metadata-preserving copy of /etc/ssh/sshd_config and its hash.
   Stage a copy alongside the original and append pi-sshd.match at EOF. Run
   `sshd -t -f STAGED` and `sshd -T -f STAGED -C user=wmfwdpi,addr=10.1.0.53,host=10.1.0.53,laddr=10.1.3.75,lport=22`.
   Require the supplied Match settings, public-key authentication enabled,
   DisableForwarding=no, and no trusted-user CA or authorized-keys command.
   Compare the full staged ama effective policy with the admission copy.
   Preserve original owner/mode, verify original hash, atomically install,
   recheck installed syntax/policy and reload ssh.service. Verify a **new**
   pinned ama login and sudo before installing any authorized key.
3. **Enroll the primary only.** Create /etc/webmin-forward root:root 0755 on
   the primary; the static service user must be able to read pi.known_hosts
   (root:root 0644). Generate a new key there as root, with umask 077:
   `ssh-keygen -q -t ed25519 -N '' -C webmin-forward-primary -f /etc/webmin-forward/primary-ed25519`.
   Never copy the private key. Transfer only its .pub line through the pinned
   admin connections. Record and compare its ssh-keygen fingerprint at both
   ends. On the Pi create /etc/ssh/webmin-forward root:root 0755; atomically
   install just this key in wmfwdpi (root:root 0644), prefixed by
   `from="10.1.0.53",restrict,port-forwarding,permitopen="127.0.0.1:10000"`.
   Verify there are no other lines or writable parent directories.
4. **Verify restriction and service.** Before starting the service, use the
   primary's dedicated identity, host pin, source and client options from the
   unit. A fresh control connection requesting an exec session must be refused;
   a direct forward (-W) to 127.0.0.1:22 must be administratively prohibited.
   Authentication/transport errors are not proof of either restriction. Install
   the reviewed unit as /etc/systemd/system/webmin-pi-forward.service (0644);
   verify it, daemon-reload and start it. Confirm the listener belongs to this
   service and appears only at 127.0.0.1:18075. From the primary run one
   bounded GET /session_login.cgi through this endpoint with the browser
   hostname as Host and User-Agent homelab-proxy-diagnostic. Require HTTP 200
   and the native login form; do not follow redirects or submit credentials.
   Recheck Pi loopback listeners, administrative access and boot continuity.
   Enable the passing unit for boot and verify active/enabled; do not reboot.
5. **Failure or withdrawal.** Stop/disable the owned unit if present, verify
   its socket closed, and revoke only the matching enrolled key. Restore the
   saved Pi SSH configuration only if the installed hash still matches this
   operation; validate syntax, reload and verify a fresh ama login. On drift or
   loss of admin access stop and use the retained shell or physical console;
   never overwrite unrelated policy. Remove only files, empty directories and
   the unprivileged account/group created by this change, checking identity
   first. Daemon-reload after unit removal. Verify original Webmin loopback,
   absent forward and baseline admin access. Record outcomes in WORK.md.

On withdrawal verify that the primary service is stopped and no processes
remain under its recorded UID. Remove only the matching primary-local
wmproxyfwd account and its owned group. Keep it for the lifetime of an
accepted service; it is distinct from wmfwdpi on the Pi.

On success retain both endpoints' configuration. A local process on the
primary can reach the loopback port; Webmin authentication remains required.
Only the public key fingerprint, status and bounded errors belong in receipts.
