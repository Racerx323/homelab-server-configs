# Discovery regression fixtures

`baseline/` contains unchanged retained Webmin 2.670 library source, including
the already qualified basic SMART polling and configured RAID modifications.
These are source-code fixtures, not host configuration or drive output. Exact
hashes are pinned in the [source manifest](../../../patches/disk-only-discovery.json);
the test resolves that manifest from the component root. Original
Webmin licensing applies to the retained library source.

The Python suite verifies baseline hashes, applies the candidate patch without
fuzz to a temporary copy, and verifies all output hashes before executing it.
`driver.pl` loads actual library functions while redirecting literal proc/sysfs
and device paths into a temporary fixture tree. Its partition commands are fake
executables that log calls and return canned text. No block devices are used.
Mount/Webmin utility dependencies are stubbed. `smart-driver.pl` executes actual
patched discovery and scheduled collection functions with synthetic controller
and health providers; it emits 22 TAP assertions.

The tests cover code contracts and partition-output parsing, not actual GPT/MBR
media, hardware RAID, kernel hotplug, installed Webmin module initialization or
live scheduling. Production qualification remains separate.
