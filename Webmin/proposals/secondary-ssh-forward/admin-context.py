"""Print the sshd connection criteria for ama's IPv4 administrative session."""
import ipaddress
import os
import sys

fields = os.environ.get("SSH_CONNECTION", "").split()
if len(fields) != 4:
    sys.exit("admin context: expected four SSH_CONNECTION fields before sudo")
peer, peer_port, local, local_port = fields
try:
    peer = ipaddress.IPv4Address(peer)
except ipaddress.AddressValueError:
    sys.exit("admin context: invalid IPv4 peer address")
if not (peer_port.isascii() and peer_port.isdecimal()
        and len(peer_port) <= 5 and 1 <= int(peer_port) <= 65535):
    sys.exit("admin context: invalid peer port")
if (local, local_port) != ("10.1.3.75", "22"):
    sys.exit("admin context: expected Pi endpoint 10.1.3.75:22")
print(f"user=ama,addr={peer},host={peer},laddr={local},lport={local_port}")
