#!/bin/bash
set -eu
opts=(-o BatchMode=yes -o StrictHostKeyChecking=yes -o UpdateHostKeys=no -o ConnectTimeout=5 -o ControlMaster=no -o ControlPath=none)
ssh "${opts[@]}" pi@10.1.0.54 'sudo -n sh -se' <<'SECONDARY'
test "$(hostname -s)" = j1-svpihole00
hostname
ip -4 route get 10.1.3.75
ss -H -lnt 'sport = :18075'
cat /proc/sys/net/ipv4/ip_local_reserved_ports
getent services 18075/tcp || :
systemctl --version | head -1
systemctl show -p LoadState webmin-pi-forward.service
getent passwd wmproxyfwd || :
getent group wmproxyfwd || :
ls -ld /etc/webmin-forward /etc/systemd/system/webmin-pi-forward.service 2>&1 || :
SECONDARY
ssh "${opts[@]}" ama@10.1.3.75 'sudo -n sh -se' <<'PI'
test "$(hostname -s)" = j2-svpi3bmf
hostname
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
ss -H -lnt 'sport = :10000'
systemctl show -p ActiveState -p ExecStart ssh.service
/usr/sbin/sshd -t
sha256sum /etc/ssh/sshd_config /etc/ssh/webmin-forward/wmfwdpi
ls -ld /etc/ssh/webmin-forward /etc/ssh/webmin-forward/wmfwdpi
getent passwd wmfwdpib || :
getent group wmfwdpib || :
ls -ld /etc/ssh/webmin-forward/wmfwdpib 2>&1 || :
for pair in wmfwdpi,10.1.0.53 wmfwdpib,10.1.0.54; do
    u=${pair%,*}
    a=${pair#*,}
    printf '%s\n' "$pair"
    policy=$(/usr/sbin/sshd -T -C "user=$u,addr=$a,host=$a,laddr=10.1.3.75,lport=22")
    printf '%s\n' "$policy" | awk '$1 ~ /^(maxsessions|allowtcpforwarding|permitopen|authorizedkeysfile|authorizedkeyscommand|trustedusercakeys|authenticationmethods)$/'
done
PI
