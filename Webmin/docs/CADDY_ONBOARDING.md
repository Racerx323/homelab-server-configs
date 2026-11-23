# Fleet Webmin onboarding through Caddy

Use one change record per selected host. The Webmin owner prepares the backend, the [Caddy owner](../../Caddy/docs/APPLICATION_ONBOARDING.md) publishes the route primary first, and the [DNS owner](../../../homelab-dns/Unbound/docs/host-record-deployment.md) manages the browser alias.

## Required readiness evidence for every host

Record the native hostname, SSH host key, browser FQDN, current listeners, installed service unit and drop-ins, effective authentication and theme settings, and recoverable configuration. On each proxy capture the route-selected source address for the chosen backend destination. Check frontend certificate coverage, client networks and existing routes. Keep private keys, password files, session cookies and credentials outside the record.

## Render the backend profile

Choose one backend address for each Webmin instance. Dual-stack browser access at the cluster VIP works independently of the upstream address family. Select either verified upstream HTTPS with a trusted certificate and renewal owner or a supervised SSH forward from each proxy to Webmin’s loopback listener. See [backend transport](WEBMIN_ARCHITECTURE.md#proxy-managed-ssh-transport).

For managed SSH, reserve an unused loopback port on each proxy. Use a dedicated local service identity and a separate key for each forward. Pin the target host key. Restrict each target identity by source and permit only local forwarding to the selected loopback destination. Deny shells, remote forwarding, agent and X11 forwarding. Check effective sshd restrictions and independent administrator access before enrolling a key. Enable and verify each forward separately. The same replicated route then uses the same loopback port on each proxy.

For direct HTTPS, configure the backend certificate identity and trust pool on both proxies. Bind the backend listener and ingress rules to the reviewed sources. Preserve unrelated settings when applying the host profile. Use the existing managed-key editor and [operations guide](OPERATIONS.md).

### Browser origin through an SSH forward

For a loopback HTTP backend, review miniserv’s external redirect scheme, host
and port independently of the SSH listener. In Webmin 2.670 these also affect
the successful login response. Require its Location to stay on the approved
HTTPS origin, the session cookie to have Secure and HttpOnly attributes, and a
subsequent protected navigation to succeed. Record only the origin, status and
attribute names. Never retain cookie values, credentials or a raw browser trace.

The login form's security badge and testing cookie use the CGI HTTPS environment.
Check these separately from the authenticated session cookie. Suppressing the
badge does not correct a redirect. Preserve the loopback bind, SSH authorization,
referrer protection and a usable recovery path when selecting proxy-specific
settings. A fixed public redirect can also redirect a tunneled recovery login.

## Execute through existing owners

1. Verify the backend login page from each proxy. Set the approved external HTTPS origin, trusted referrer and cookie settings. Choose a cheap, unauthenticated health URI that the installed version serves on that host.
2. Validate and activate the fragment on the primary. Confirm the new route and existing routes. Check that the existing replication sender is active with a running main process, then release the validated configuration through it. Verify the secondary’s release identity and route through its own upstream.
3. Add the approved browser A and AAAA records for the cluster VIPs through the DNS procedure. Verify through both resolvers. Preserve the host’s management name and reverse records.
4. From a normal workstation browser, open the HTTPS name, sign in, load System Information and watch the statistics update. Open a second protected view, sign out, then confirm a protected page requires login. Record the observed result.

### Safe WebSocket method for each host

Identify an enabled feature using WebSockets and confirm that the existing operator account can exercise it safely. Real-time System Information graphs are one option. Record expected connection, update, session close and cleanup. Avoid privileged terminals, new accounts and ACL expansion solely for testing. For statistics, confirm authenticated WSS and continuing updates. Close the test connection and log out. Leave any shared collector serving other sessions under its existing policy. Record only status, counts and timing. Document an inapplicable feature or unresolved permission with the owner.

## Guard lifecycle and recovery qualification

Take owner-scoped backups and identify a working independent SSH administration path. Verify persistent service and ingress controls on the selected host. Restore and verify a safe loopback listener before withdrawing a direct-access firewall guard. Validate sshd configuration before reloading it. Use the prior Caddy release and the DNS owner’s record delta to withdraw the affected route and name. Preserve unrelated routes, users and firewall rules.

Keep independently accepted persistent steps when their security and recovery conditions still hold. A later browser failure needs the request time, path and response status. Consult the relevant owner logs before changing settings. Use actual host measurements for capacity decisions. Retain reusable findings here and host-specific results in the host change record. A workstation tunnel is an optional recovery method.
