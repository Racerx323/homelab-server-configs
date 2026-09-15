"""Read-only topology collector and byte-preserving kernel command-line planner."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def digest(data):
    return hashlib.sha256(data).hexdigest()


def render(data, bridge):
    text = data.decode("ascii")
    if not text.strip() or "\x00" in text or "\r" in text or "\n" in text.rstrip("\n") or text.endswith("\n\n"):
        raise ValueError("Boot file must contain one nonempty ASCII command line")
    pattern = r"(?<!\S)usb-storage\.quirks=([^\s]*)(?!\S)"
    matches = list(re.finditer(pattern, text))
    if len(matches) > 1:
        raise ValueError("Multiple quirk parameters require review")
    entry = bridge + ":u"
    if matches:
        match = matches[0]
        entries = match.group(1).split(",")
        seen = set()
        for value in entries:
            if not re.fullmatch(r"[0-9a-fA-F]{4}:[0-9a-fA-F]{4}:[a-zA-Z]+", value):
                raise ValueError("Malformed quirk entry")
            identity, flags = value.rsplit(":", 1)
            identity = identity.lower()
            if identity in seen:
                raise ValueError("Duplicate bridge entries require review")
            seen.add(identity)
            if identity == bridge:
                if flags != "u":
                    raise ValueError("Target bridge flags differ from reviewed profile")
        if bridge in seen:
            return data
        return (text[:match.end()] + "," + entry + text[match.end():]).encode("ascii")
    end = len(text.rstrip())
    return (text[:end] + " usb-storage.quirks=" + entry + text[end:]).encode("ascii")


def command(*args):
    return subprocess.check_output(args, text=True, timeout=15).strip()


def usb_transport(disk, expected_bridge):
    bridges = []
    drivers = []
    for ancestor in (disk, *disk.parents):
        if (ancestor / "idVendor").exists():
            bridges.append(((ancestor / "idVendor").read_text().strip() + ":" + (ancestor / "idProduct").read_text().strip()))
        driver = ancestor / "driver"
        if driver.is_symlink() and driver.resolve().name in ("uas", "usb-storage"):
            drivers.append(driver.resolve().name)
    if not bridges or bridges[0] != expected_bridge or len(drivers) != 1:
        raise ValueError("Root USB ancestry or driver does not match profile")
    return bridges[0], drivers[0]


def collect(profile):
    if command("uname", "-m") != profile["architecture"]:
        raise ValueError("Unsupported architecture")
    model = Path("/proc/device-tree/model").read_text().rstrip("\x00")
    if not model.startswith(profile["model_prefix"]):
        raise ValueError("Unsupported platform")
    root = json.loads(command("findmnt", "--json", "--output", "SOURCE,FSTYPE,UUID", "/"))["filesystems"]
    if len(root) != 1 or root[0]["fstype"] != profile["filesystem"] or not root[0]["uuid"]:
        raise ValueError("Unsupported root filesystem")
    device = Path(root[0]["source"]).resolve(strict=True)
    node = (Path("/sys/class/block") / device.name).resolve(strict=True)
    if not (node / "partition").exists():
        raise ValueError("Profile requires a directly attached partitioned root disk")
    disk = node.parent
    if (disk / "slaves").exists() and list((disk / "slaves").iterdir()):
        raise ValueError("Layered root disk unsupported")
    bridge, driver = usb_transport(disk, profile["bridge"])
    boot = Path(profile["boot_file"])
    if boot.is_symlink() or not boot.is_file():
        raise ValueError("Boot file must be a regular non-symlink file")
    original = boot.read_bytes()
    proposed = render(original, profile["bridge"])
    running = Path("/proc/cmdline").read_bytes()
    running_correct = render(running, profile["bridge"]) == running
    return dict(hostname=command("hostname", "-s"), model=model, root_uuid=root[0]["uuid"],
                root_device=str(device), disk=str(disk), bridge=bridge, driver=driver,
                boot_id=Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
                boot_sha256=digest(original), proposed_sha256=digest(proposed),
                original_b64=base64.b64encode(original).decode(),
                proposed_b64=base64.b64encode(proposed).decode(),
                changed=original != proposed, running_quirk=running_correct,
                reboot_required=(original != proposed or not running_correct or driver != profile["expected_driver"]))


if __name__ == "__main__":
    print(json.dumps(collect(json.loads(base64.b64decode(sys.argv[1])))))
