settings {
    statusFile = "/run/caddy-lsyncd/status",
    statusInterval = 10,
    insist = true,
    maxProcesses = 1
}

sync {
    default.rsync,
    source = "/var/lib/caddy-sync/outbound/",
    target = "caddy-sync@pihole0.local.theama.co:/",
    delay = 5,
    delete = false,
    rsync = {
        archive = true,
        compress = true,
        protect_args = false,
        rsh = "/usr/bin/ssh -6 -p 22 -i /var/lib/caddy-sync/.ssh/id_ed25519 -o AddressFamily=inet6 -o BatchMode=yes -o BindAddress=fd36:5aa8:6971:1::54 -o ClearAllForwardings=yes -o ConnectTimeout=5 -o GlobalKnownHostsFile=/dev/null -o HostKeyAlias=pihole0.local.theama.co -o IdentitiesOnly=yes -o KbdInteractiveAuthentication=no -o PasswordAuthentication=no -o PreferredAuthentications=publickey -o StrictHostKeyChecking=yes -o UpdateHostKeys=no -o UserKnownHostsFile=/var/lib/caddy-sync/.ssh/known_hosts",
        _extra = {
            "--delay-updates",
            "--exclude=.complete",
            "--exclude=.complete.pending",
            "--exclude=*.tmp",
            "--exclude=*.swp",
            "--exclude=.git/",
            "--exclude=state/",
            "--exclude=quarantine/",
            "--no-group",
            "--no-owner",
            "--no-perms",
            "--partial"
        }
    }
}
