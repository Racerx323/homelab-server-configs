#!/usr/bin/python3
"""Seal a passive NTP pilot recovery-readiness capture; no failure trigger."""
import argparse
import base64
import gzip
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import signal
import tarfile
import time

ROOT = Path(__file__).resolve().parents[1]
NTP = ROOT/'../../homelab-ntp/ntpsec'
SOURCES = {'runner.py': ROOT/'scripts/inspect-recovery-readiness.py',
    'tests.py': ROOT/'tests/test_recovery_readiness.py',
    'helper.py': NTP/'scripts/run-production-inspection.py',
    'passive.py': NTP/'scripts/run-phase3-node-inspection.py',
    'ownership.py': NTP/'scripts/run-watchdog-inspection.py'}
VENDOR = '/usr/lib/systemd/system.conf.d/40-rpi-enable-watchdog.conf'
SYSCTLS = ('panic', 'panic_on_oops', 'panic_on_warn', 'sysrq', 'watchdog',
    'soft_watchdog', 'nmi_watchdog', 'softlockup_panic', 'hardlockup_panic',
    'hung_task_panic', 'panic_on_rcu_stall')
MANUALS = ('/usr/share/man/man5/systemd-system.conf.5.gz',
           '/usr/share/man/man5/systemd.service.5.gz')
JOURNAL_KEYS = ('Storage', 'SystemMaxUse', 'RuntimeMaxUse', 'MaxRetentionSec', 'SyncIntervalSec')
COMMANDS = {
    'kernel': ['/usr/bin/uname', '-r'],
    'systemd_version': ['/usr/bin/systemctl', '--version'],
    'packages': ['/usr/bin/dpkg-query', '-W', '-f=${binary:Package}\t${Version}\t${db:Status-Abbrev}\n',
                 'systemd', 'systemd-sysv', 'raspberrypi-sys-mods', 'watchdog'],
    'vendor_owner': ['/usr/bin/dpkg-query', '-S', VENDOR],
    'driver': ['/usr/sbin/modinfo', 'bcm2835_wdt'],
    'mounts': ['/usr/bin/findmnt', '--json', '--output', 'TARGET,SOURCE,FSTYPE,VFS-OPTIONS', '--target', '/'],
    'boot_mount': ['/usr/bin/findmnt', '--json', '--output', 'TARGET,SOURCE,FSTYPE,VFS-OPTIONS', '--target', '/boot/firmware'],
    'boot_list': ['/usr/bin/journalctl', '--list-boots', '--no-pager'],
    'journal_usage': ['/usr/bin/journalctl', '--disk-usage', '--no-pager'],
}
h = p = o = None
NATIVE_PURPOSE = 'watchdog-native-inputs'
DEBUGGER_PURPOSE = 'watchdog-debugger-inputs'
NATIVE_COMMANDS = {
    'kernel': ['/usr/bin/uname', '-r'],
    'kernel_build': ['/usr/bin/uname', '-v'],
    'driver': ['/usr/sbin/modinfo', 'bcm2835_wdt'],
}
NATIVE_PATHS = (
    '/sys/kernel/kexec_loaded', '/sys/kernel/kexec_crash_loaded',
    '/sys/kernel/kexec_crash_size', '/proc/sys/kernel/kexec_load_disabled',
    '/proc/sys/kernel/panic', '/proc/sys/kernel/panic_on_oops',
    '/proc/sys/kernel/panic_on_warn', '/proc/sys/kernel/panic_print',
    '/proc/sys/kernel/panic_sys_info', '/proc/sys/kernel/sysrq',
    '/proc/consoles', '/sys/class/tty/console/active', '/proc/sys/kernel/printk',
)


def native_cmdline(text):
    keys = {'console', 'earlycon', 'earlyprintk', 'keep_bootcon', 'quiet', 'splash',
        'loglevel', 'ignore_loglevel', 'panic', 'oops', 'panic_on_warn', 'panic_print',
        'panic_sys_info', 'crashkernel', 'crash_kexec_post_notifiers', 'nokaslr',
        'nmi_watchdog', 'nowatchdog', 'softlockup_panic', 'hardlockup_panic',
        'hung_task_panic', 'bcm2835_wdt.nowayout'}
    return ' '.join(word for word in text.split() if word.split('=', 1)[0] in keys
        and re.fullmatch(r'[A-Za-z0-9_.,:=/+@-]{1,256}', word))


def module_names(text):
    lines = text.splitlines()
    if len(lines) > 512: raise ValueError('module inventory bound')
    names = []
    for line in lines:
        fields = line.split()
        if len(fields) < 6 or not re.fullmatch(r'[A-Za-z0-9_]{1,128}', fields[0]):
            raise ValueError('module inventory syntax')
        names.append(fields[0])
    return '\n'.join(names)


def debugger_cmdline(text):
    keys = {'kgdboc', 'kgdboc.kgdboc', 'kgdboc_earlycon', 'ekgdboc', 'kgdbwait',
        'kgdbcon', 'nokgdbroundup', 'earlycon', 'earlyprintk', 'keep_bootcon', 'console'}
    selected = []
    for word in text.split():
        if word.split('=', 1)[0] not in keys: continue
        if not re.fullmatch(r'[A-Za-z0-9_.,:=/+@-]{1,256}', word):
            raise ValueError('debugger token outside reviewed grammar')
        selected.append(word)
    return ' '.join(selected)


def debugger_inputs(release):
    result = {'commands': {'kernel': p.command(NATIVE_COMMANDS['kernel'])}}
    if result['commands']['kernel'].get('stdout', '').strip() != release:
        result['kernel_release_mismatch'] = True
        return result
    result['kgdboc_parameter'] = p.text_record('/sys/module/kgdboc/parameters/kgdboc', True)
    result['cmdline_policy'] = read_selected('/proc/cmdline', debugger_cmdline)
    result['panic_timeout'] = p.text_record('/proc/sys/kernel/panic')
    return result


def native_kernel_options(text):
    return '\n'.join(line for line in text.splitlines() if re.match(
        r'(?:# )?CONFIG_(?:WATCHDOG.*|BCM2835_WDT|MAGIC_SYSRQ.*|PANIC.*|PSTORE.*|KEXEC.*|CRASH.*|CONSOLE.*|VT.*|FRAMEBUFFER_CONSOLE.*|SERIAL_.*CONSOLE|PRINTK.*|KGDB.*|KDB.*|ARM64.*RAS.*)(?:=| is not set)', line))


def native_inputs(release):
    # No device files, kernel memory, module loading, console writes or crash dumps.
    result = {'commands': {name: p.command(argv) for name, argv in NATIVE_COMMANDS.items()}}
    if result['commands']['kernel'].get('stdout', '').strip() != release:
        result['kernel_release_mismatch'] = True
        return result
    root = '/usr/lib/modules/' + release
    result['commands']['package_owners'] = p.command(['/usr/bin/dpkg-query', '-S',
        '/boot/vmlinuz-' + release, '/boot/config-' + release, root + '/modules.builtin'])
    result['commands']['package_sources'] = p.command(['/usr/bin/dpkg-query', '-W',
        '-f=${binary:Package}\t${Version}\t${source:Package}\t${source:Version}\t${Architecture}\t${db:Status-Abbrev}\n',
        'linux-image-' + release, 'linux-image-rpi-v8', 'raspberrypi-kernel', 'systemd'])
    result['runtime'] = {path: p.text_record(path, path.startswith('/sys/')) for path in NATIVE_PATHS}
    result['cmdline_policy'] = read_selected('/proc/cmdline', native_cmdline)
    result['loaded_module_names'] = read_selected('/proc/modules', module_names)
    result['kernel_config'] = {path: read_selected(path, native_kernel_options, path.endswith('.gz'))
        for path in ('/boot/config-' + release, '/boot/firmware/config-' + release, '/proc/config.gz')}
    # Metadata only for build/source links: never traverse arbitrary package links.
    result['module_metadata'] = {root + '/' + name: p.metadata(root + '/' + name)
        for name in ('build', 'source', 'modules.builtin', 'modules.builtin.modinfo')}
    result['crash_units'] = {unit: p.command(['/usr/bin/systemctl', 'show', unit,
        '--property=' + p.COMMON_PROPS + p.SERVICE_PROPS])
        for unit in ('kdump.service', 'kdump-tools.service', 'kexec-load.service')}
    return result


def collect_native(spec, baseline):
    report = o.collect(spec)
    if not report['capture_complete']: return report
    inspect = debugger_inputs if spec['purpose'] == DEBUGGER_PURPOSE else native_inputs
    report['native_before'] = inspect(spec['kernel_release'])
    vendor = h.file_record(VENDOR)
    report['vendor_matches'] = vendor.get('sha256') == baseline['vendor_sha256']
    report['native_after'] = inspect(spec['kernel_release'])
    report['configuration_after'] = o.configurations(); report['manager_after'] = o.manager()
    report['protected_after'] = {f: h.file_record(f) for f in p.PROTECTED}
    report['units_after'] = p.state()
    report['boot_after'] = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    before, after = report['native_before'], report['native_after']
    report['native_stable'] = before == after
    report['capture_complete'] = (o.complete(report) and report['vendor_matches']
        and report['native_stable'] and not before.get('kernel_release_mismatch')
        and all(command.get('returncode') == 0 for name, command in before['commands'].items()
            if name in ('kernel', 'kernel_build')))
    report.update(completed_epoch=time.time(), recovery_ready=False,
        console_visibility_verified=False, reset_attribution_qualified=False,
        unknowns=['missing optional files/packages remain unknown',
            'package metadata is not complete downstream source/binary equivalence',
            'module inventory does not enumerate all built-in panic/reset callbacks',
            'console configuration does not prove messages visible on the KVM',
            'no recovery behavior tested'])
    return report


def read_selected(path, selector, compressed=False):
    row = h.file_record(path, True)
    if 'base64' not in row: return row
    raw = base64.b64decode(row.pop('base64'), validate=True)
    if compressed:
        with gzip.GzipFile(fileobj=io.BytesIO(raw)) as stream: raw = stream.read(h.LIMIT+1)
        if len(raw) > h.LIMIT: raise ValueError('decompressed input bound')
    text = raw.decode('utf-8', 'replace')
    selected = selector(text)
    if len(selected.encode()) > 65536: raise ValueError('selected text bound')
    row['selected_text'] = selected
    return row


def manual_excerpt(text):
    lines = text.splitlines(); indices = set()
    for i, line in enumerate(lines):
        if re.search(r'RuntimeWatchdog|RebootWatchdog|KExecWatchdog|WatchdogDevice|nowayout|magic.close', line, re.I):
            indices.update(range(max(0,i-2),min(len(lines),i+12)))
    return '\n'.join(lines[i] for i in sorted(indices))


def kernel_options(text):
    return '\n'.join(line for line in text.splitlines() if re.match(
        r'(?:# )?CONFIG_(?:WATCHDOG.*|BCM2835_WDT|MAGIC_SYSRQ.*|PANIC.*|PSTORE.*|KEXEC.*|CRASH.*|SOFTLOCKUP.*|HARDLOCKUP.*|DETECT_HUNG_TASK)(?:=| is not set)', line))


def directory_metadata(path):
    root = Path(path)
    if root.resolve() != root: return {'indirect_not_enumerated': True}
    row = p.metadata(path)
    if row.get('missing'): return row
    row['entries'] = [{ 'name': f.name, **p.metadata(f)} for f in p.names(str(root), 64)]
    return row


def journal_configuration():
    result = {}
    for root in o.CONFIG_ROOTS:
        paths = [Path(root)/'journald.conf']; directory = Path(root)/'journald.conf.d'
        if directory.resolve() != directory:
            result[str(directory)] = {'indirect_not_enumerated': True}
        else: paths += [f for f in p.names(str(directory),64) if f.suffix == '.conf']
        for path in paths:
            if path.is_symlink():
                result[str(path)] = {'link': os.readlink(path), 'content_not_followed': True}; continue
            result[str(path)] = read_selected(path, journal_fields)
    return result


def journal_fields(text):
    section = ''; selected = []
    for line in text.splitlines():
        line = line.strip()
        if line.startswith('['): section = line; continue
        if section == '[Journal]' and '=' in line and line.split('=',1)[0].strip() in JOURNAL_KEYS:
            selected.append(line)
    return '\n'.join(selected)


def collect(spec, baseline):
    if spec['purpose'] in (NATIVE_PURPOSE, DEBUGGER_PURPOSE): return collect_native(spec, baseline)
    # Existing qualified collector supplies hostname, ownership and continuity checks.
    report = o.collect(spec)
    if not report['capture_complete']: return report
    report['readiness_commands'] = {name:p.command(argv) for name,argv in COMMANDS.items()}
    boots = report['readiness_commands']['boot_list']
    boots['stdout'] = '\n'.join(boots.get('stdout','').splitlines()[-8:])
    boots['export_limit'] = 'last eight boot-list lines; no journal message bodies'
    release = report['readiness_commands']['kernel'].get('stdout','').strip()
    if not re.fullmatch(r'[A-Za-z0-9_.+-]{1,128}', release): raise ValueError('unsafe kernel release')
    report['kernel_configuration'] = {path:read_selected(path,kernel_options,path.endswith('.gz'))
        for path in ('/boot/config-'+release, '/boot/firmware/config-'+release, '/proc/config.gz')}
    report['manuals'] = {path:read_selected(path,manual_excerpt,True) for path in MANUALS}
    report['panic_policy'] = {name:p.text_record('/proc/sys/kernel/'+name) for name in SYSCTLS}
    report['driver_parameters'] = {path:p.text_record(path,True) for path in
        ('/sys/module/bcm2835_wdt/parameters/nowayout','/sys/module/watchdog/parameters/stop_on_reboot')}
    vendor = h.file_record(VENDOR,True)
    if vendor.get('sha256') != baseline['vendor_sha256']:
        vendor.pop('base64',None); vendor['baseline_mismatch'] = True
    report['vendor_file'] = vendor
    report['journal_configuration_before'] = journal_configuration()
    report['persistence_metadata'] = {path:directory_metadata(path) for path in
        ('/var/log/journal','/run/log/journal','/sys/fs/pstore','/var/lib/systemd/pstore')}
    report['boot_files'] = {path:h.file_record(path) for path in
        ('/boot/firmware/config.txt','/boot/firmware/cmdline.txt')}
    # Export only policy keys, not root identifiers or arbitrary kernel arguments.
    report['kernel_cmdline_policy'] = read_selected('/proc/cmdline', lambda text:' '.join(
        word for word in text.split() if re.fullmatch(r'(?:panic|oops|panic_on_warn|softlockup_panic|nmi_watchdog|nowatchdog|watchdog_thresh|bcm2835_wdt\.nowayout|systemd\.(?:watchdog_device|runtime_watchdog_sec|reboot_watchdog_sec))=[A-Za-z0-9_./:+-]{1,128}',word)))
    report['pstore_service'] = p.command(['/usr/bin/systemctl','show','systemd-pstore.service',
        '--property='+p.COMMON_PROPS+p.SERVICE_PROPS])
    report['journal_configuration_after'] = journal_configuration()
    report['configuration_after'] = o.configurations(); report['manager_after'] = o.manager()
    report['protected_after'] = {f:h.file_record(f) for f in p.PROTECTED}
    report['units_after'] = p.state(); report['boot_after'] = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    report['capture_complete'] = (o.complete(report) and not vendor.get('baseline_mismatch')
        and report['journal_configuration_before'] == report['journal_configuration_after']
        and all(report['readiness_commands'][name].get('returncode') == 0 for name in ('kernel','systemd_version','mounts','boot_mount')))
    report.update(completed_epoch=time.time(), recovery_ready=False, operator_prerequisites_verified=False,
        unknowns=['independent console/media usability','peer/shared-power continuity','actual feeding/expiry/close behavior',
                  'definitive reset attribution','chosen trigger and deadlines','read-only metadata does not test journal survival'])
    return report


def validate(spec):
    purpose = spec.get('purpose')
    if purpose not in ('watchdog-recovery-readiness', NATIVE_PURPOSE, DEBUGGER_PURPOSE) or not re.fullmatch(re.escape(purpose)+r'-[a-z0-9-]{1,32}',spec.get('operation_id','')):
        raise ValueError('closed recovery-readiness scope')
    if purpose in (NATIVE_PURPOSE, DEBUGGER_PURPOSE) and not re.fullmatch(r'[A-Za-z0-9_.+-]{1,128}', spec.get('kernel_release', '')):
        raise ValueError('bound kernel release required')
    if Path(spec['directory']).name != spec['operation_id']: raise ValueError('directory identity')
    checked=dict(spec);checked.update(purpose='phase3-node-readiness',operation_id='phase3-node-readiness-check',
        directory=str(Path(spec['directory']).parent/'phase3-node-readiness-check'))
    if purpose in (NATIVE_PURPOSE, DEBUGGER_PURPOSE): del checked['kernel_release']
    p.validate(checked)


def payload(spec,files):
    raw=b''
    for name,label in [('helper.py','helper'),('passive.py','passive'),('ownership.py','ownership'),('runner.py','readiness')]:
        raw+=(f"{label}={{'__name__':'{label}','__file__':'/sealed/{name}'}}\n".encode()+b'exec(compile('+repr(files[name]).encode()+f",'/sealed/{name}','exec'),{label})\n".encode())
    raw+=b"import types,signal,json\nh=types.SimpleNamespace(**helper)\npassive['h']=h\np=types.SimpleNamespace(**passive)\nownership.update(h=h,p=p)\no=types.SimpleNamespace(**ownership)\nreadiness.update(h=h,p=p,o=o)\nsignal.signal(signal.SIGALRM,h.expired)\nsignal.alarm(240)\n"
    return raw+b"print(json.dumps(readiness['collect']("+repr(spec).encode()+b','+repr(json.loads(files['baseline.json'])).encode()+b")))\n"


def review(spec):
    if spec['purpose'] == DEBUGGER_PURPOSE: return debugger_review(spec)
    if spec['purpose'] == NATIVE_PURPOSE: return native_review(spec)
    return f'''# Read-only pilot watchdog recovery-readiness inspection

Sealed, unexecuted. Exact-hash execution approval required. This permits only a
passive capture, never a recovery trigger. Target j2-svntp1 at ama@10.1.0.51,
strict existing Ed25519 alias 10.1.0.137. Operation {spec['operation_id']}.
Expires epoch {spec['expires_epoch']}; leave 270 seconds before expiry.

## Prerequisites and retained baseline

Use the accepted watchdog ownership outcome and capture hash
`{spec['baseline_capture_sha256']}`. Preserve PID 1/systemd ownership and observed
60/120-second policy. Require the accepted boot/protected hashes and stable core
services/files/manager configuration; drift is evidence, not permission to repair.
Execution approval, strict known-host identity and noninteractive sudo are needed.
Console/media usability, attendance, peer service, shared-antenna power and test
window remain operator prerequisites for later disruption, not claims from this
capture. No peer, controller, switch, master or notification endpoint is contacted.

## Exact scope

One SSH connection, stdin code to `cd / && sudo -n /usr/bin/python3 -I -B -`.
Reuse the frozen repository-owned ownership collector's read-only scope: fixed
10-unit properties, four protected hashes, boot ID, manager watchdog properties,
selected system.conf/drop-ins, lstat device identities, bounded visible-process
fd stat matching and watchdog0 sysfs. No fd target is opened/read/duplicated.
Limits: 4096 process leaders, 4096 descriptors per process, 65536 total,
64 owner matches and 1024 recorded gaps. Recheck matched PID/fd identity.

Additional fixed commands: `{json.dumps(COMMANDS,sort_keys=True)}`.
The boot-list command is output-bounded; export only its last eight lines, never
journal message bodies. Missing packages, built-in driver modinfo gaps and missing
optional tools/docs remain explicit limitations. No apt refresh or package action.

Read regular `/boot/config-RELEASE`, `/boot/firmware/config-RELEASE`, and
`/proc/config.gz`, where RELEASE is the validated uname string. Export only
CONFIG_WATCHDOG*, BCM2835_WDT, MAGIC_SYSRQ*, PANIC*, PSTORE*, KEXEC*, CRASH*,
SOFTLOCKUP*, HARDLOCKUP* and DETECT_HUNG_TASK entries. Missing config remains unknown.
Read `{MANUALS}` as bounded gzip; export watchdog-relevant excerpts only. Documentation
is evidence about the installed platform, not proof of reset behavior.

Read only `/proc/sys/kernel/` values `{SYSCTLS}`. Never read or open sysrq-trigger.
Read nowayout/stop_on_reboot at the two fixed sysfs module paths in runner.py;
no module load. Read the exact vendor drop-in only if its hash matches the accepted
capture; otherwise suppress content and fail completeness. Hash-only boot config.txt
and cmdline.txt; export only selected panic/watchdog policy tokens from /proc/cmdline.
No credentials, full kernel command line or arbitrary boot configuration is exported.

Read journald.conf and up to 64 entries per journald.conf.d under the same four
systemd configuration roots; regular files only, export only [Journal] Storage,
SystemMaxUse, RuntimeMaxUse, MaxRetentionSec and SyncIntervalSec. Record links
without following; do not enumerate indirect directories. Metadata only for
/var/log/journal, /run/log/journal, /sys/fs/pstore and /var/lib/systemd/pstore,
maximum 64 direct entries each. No journal or crash payload contents. Read only
properties of systemd-pstore.service, never activate it.

## Bounds, interruption and acceptance

Per command 10 seconds/1 MiB per stream. Each input and decompressed input at most
1 MiB; selected text at most 64 KiB. Remote alarm 240 seconds; controller 270 seconds
and 24 MiB per stream. Private local evidence only; no staged target files/locks.
An exclusive fsynced receipt precedes SSH. One attempt, no retry or alternate host;
interrupted/partial execution consumes the receipt. Retain raw streams and status.
Routine SSH/sudo/D-Bus logging and access times may occur. No target cleanup needed.

No device open/feed/ioctl, sysctl write, SysRq, panic, signal, package installation,
service/manager action, journal flush/rotation/vacuum, mount, reset, reboot, job,
notification, recovery or final observation. No generic diagnostic command may
expand the explicit scope. Existing active services are not stopped or replaced.

Capture completion requires protected continuity, matching baseline/vendor hash
and successful kernel/version/root/boot mount commands. Ownership scan gaps,
missing optional facts, documentation/metadata limitations and reset attribution
remain separately reviewed. Metadata or Storage=persistent does not prove journal
survival. Capture completion never marks recovery_ready or verifies operator facts.
Review results to select or reject a later trigger; do not infer a safe panic test.
OBS-02/D1–D5 and bounded OBS-04 remain unchanged; OBS-09 remains unstarted.

After separate approval, from homelab-server-configs:
`python3 -I -B watchdog/scripts/inspect-recovery-readiness.py execute --directory {spec['directory']} --sha256 APPROVED_SHA256`
'''


def debugger_review(spec):
    return f'''# Read-only debugger-transport confirmation

Sealed, unexecuted; separate exact-hash execution approval required.
Operation `{spec['operation_id']}`; target only j2-svntp1 at ama@10.1.0.51,
strict existing Ed25519 alias 10.1.0.137. Expires epoch {spec['expires_epoch']};
start at least 270 seconds before expiry. No trigger is selected or authorized.

## Baseline and purpose

Accepted native capture SHA-256 `{spec['baseline_capture_sha256']}`; pinned kernel
`{spec['kernel_release']}`. Reuse its boot/protected/vendor baseline. Exact package
source analysis and matching full config already explain the absent kexec path.
This scope resolves only normal/early KGDB console transport settings, with
continuity checks; it does not repeat package, module or source discovery.

Aaron confirmed ordinary KVM visibility on October 26: the displayed host is
j2-svntp1. His local attendance, separately powered laptop/KVM and working old
microSD remain operator confirmations. This capture does not interact with the
KVM or prove panic-time visibility. j1 service and antenna power stay untouched.

## Exact scope

One SSH connection streams frozen repository-owned Python on stdin to
`cd / && sudo -n /usr/bin/python3 -I -B -`. No target files or locks are created.
Reuse the existing ownership continuity scope: fixed ten-unit properties, four
protected hashes, boot ID, manager watchdog properties, selected system.conf and
drop-ins, device lstat, watchdog0 sysfs and bounded visible-process fd stat matching.
No descriptor target is opened/read/duplicated. Limits: 4096 process leaders,
4096 descriptors/process, 65536 total, 64 owner matches and 1024 recorded gaps;
recheck matched PID/fd identity. Scan gaps remain explicit limitations.

Two snapshots contain only:

- `/usr/bin/uname -r`; mismatch to the pinned release stops extra input reads.
- `/sys/module/kgdboc/parameters/kgdboc`, regular bounded text after resolution
  strictly within /sys. Preserve empty, missing and read-error as distinct results.
- `/proc/cmdline`, filtered to keys kgdboc, kgdboc.kgdboc, kgdboc_earlycon, ekgdboc,
  kgdbwait, kgdbcon, nokgdbroundup, earlycon, earlyprintk, keep_bootcon and console.
  Each selected token is at most 256 allowlisted characters; malformed selected
  tokens fail rather than disappearing. No full command line or root identifiers.
- `/proc/sys/kernel/panic`, read only, to preserve the relevant panic-timeout fact.

Recheck boot, protected files, core services, manager/configuration and vendor hash.
No package commands, crash/module inventories, debugger commands, kernel memory,
debug symbols, journal bodies, console screen capture or unrelated parameter reads.

## Controls and acceptance

Per command: 10 seconds/1 MiB per stream. Regular input: 1 MiB; exported text:
64 KiB. Remote alarm: 240 seconds; controller: 270 seconds/24 MiB per stream.
Owner-private local raw streams/status. Exclusive fsynced execution receipt before
SSH; one attempt, no retry or alternate target, including after interruption.
Ordinary SSH/sudo/D-Bus logs and access times may occur. No target cleanup needed.

No /dev open/feed/ioctl, sysctl or SysRq write, signal, panic, reset, reboot, power
action, module/debugger load/unload, debugger registration/disablement, package or
service action, console change, recording, notification or final-observation start.
Never write an empty debugger parameter as a diagnostic or attempt a test crash.

Completion requires protected/baseline/vendor continuity, matching release,
successful uname and equal snapshots. Missing parameter or selected-data errors
remain assessment gaps, not proof of absent debugging. Empty normal configuration
alone does not exclude early-console registration. Assess against the exact
package's kgdboc registration paths before choosing a trigger; no success flag
claims runtime registration was directly measured. Nonempty or ambiguous settings
require review, never automatic correction or a broader unapproved inspection.

Keep the five-minute normal-operation usable-NTP requirement. Longer deployment
testing cannot pass resilience acceptance. OBS-02/D1–D5 and OBS-04 unchanged;
OBS-09 unstarted. An eventual trigger/recovery review needs separate approval.

After separate approval, from homelab-server-configs:
`python3 -I -B watchdog/scripts/inspect-recovery-readiness.py execute --directory {spec['directory']} --sha256 APPROVED_SHA256`
'''


def native_review(spec):
    return f'''# Read-only watchdog native-input inspection

Sealed, unexecuted; exact-hash execution approval required. Operation
`{spec['operation_id']}` targets only j2-svntp1 at `ama@10.1.0.51`, using the
existing strict Ed25519 host-key alias `10.1.0.137`. No failure injection.
Expires epoch {spec['expires_epoch']}; start at least 270 seconds before expiry.

## Purpose and prerequisites

Resolve remaining kernel package/source, crash/reset and console configuration
inputs before choosing a trigger. Accepted recovery-readiness capture SHA-256:
`{spec['baseline_capture_sha256']}`. Kernel release is pinned to
`{spec['kernel_release']}`. Require accepted boot/protected hashes, stable active
core services, manager/configuration continuity and unchanged vendor hash.
Drift blocks completion; it never authorizes repair or a retry.

Aaron confirms local attendance, working previous Debian 11 recovery microSD,
KVM on a separately powered laptop, j1 serving time/powering the antenna and
separate node PoE ports. Those are operator confirmations, not new inspection
results. No peer, switch, controller, KVM or notification endpoint is contacted.
The normal-operation outage target remains at most 300 seconds to usable NTP.
Longer deployment-test outages do not establish that resilience target.

## Exact read-only scope

One SSH connection streams frozen Python on stdin to
`cd / && sudo -n /usr/bin/python3 -I -B -`. No staged target files or locks.
Reuse the repository-owned ownership collector: fixed ten-unit properties,
four protected hashes, boot ID, manager watchdog properties, selected system.conf
and drop-ins, device lstat identities, visible-process fd stat matching and
watchdog0 sysfs. No descriptor target is opened, read or duplicated. Scan limits:
4096 process leaders, 4096 descriptors/process, 65536 total, 64 owner matches and
1024 recorded gaps; recheck matched PID/fd identity. Gaps remain reviewable.

Two native snapshots bracket these fixed inputs:

- Commands: `{json.dumps(NATIVE_COMMANDS, sort_keys=True)}`.
- `dpkg-query -S` only for `/boot/vmlinuz-RELEASE`, `/boot/config-RELEASE` and
  `/usr/lib/modules/RELEASE/modules.builtin`. RELEASE is the pinned value above.
- `dpkg-query -W` only for `linux-image-RELEASE`, `linux-image-rpi-v8`,
  `raspberrypi-kernel` and `systemd`, exporting binary package/version, source
  package/version, architecture and installation status. Missing packages or
  ownership records remain gaps; no apt/download/install/verify action.
- Read fixed runtime paths `{NATIVE_PATHS}`. Explicit sysfs paths may resolve
  only within /sys; regular bounded reads, never /dev or sysrq-trigger.
- `/proc/cmdline`: export only allowlisted console, early-console, verbosity,
  crashkernel, panic/watchdog and crash-notifier policy tokens. No full command
  line, root identifiers or arbitrary values. Exact grammar is frozen in runner.py.
- `/proc/modules`: export only validated module names, at most 512; no addresses,
  dependencies, parameters or raw module contents. Hash/metadata retained.
- `/boot/config-RELEASE`, `/boot/firmware/config-RELEASE`, `/proc/config.gz`:
  export only watchdog, BCM2835_WDT, SysRq, panic, pstore, kexec/crash,
  console/VT/framebuffer/serial-console, printk, debugger and ARM64 RAS options.
  Bounded gzip when appropriate; no arbitrary CONFIG_CMDLINE values.
- Metadata only for `/usr/lib/modules/RELEASE/` build/source links and
  modules.builtin/modules.builtin.modinfo. Do not follow links or inspect source
  trees, kernel binaries, debug symbols, /proc/kallsyms or kernel memory.
- Properties only for kdump.service, kdump-tools.service and kexec-load.service:
  Id, LoadState, ActiveState, SubState, UnitFileState, FragmentPath, DropInPaths,
  MainPID, NRestarts, InvocationID, Result, ExecMainStatus and start/exit times.
  No command/environment dumps or service action.

Recheck boot, protected files, core services, manager/configuration and vendor
hash after collection. Keep both native snapshots; do not conceal drift.
Kernel release mismatch returns an incomplete capture without the extra reads.

## Bounds and prohibited actions

Per command: 10 seconds and 1 MiB per output stream. Each regular input and
decompressed input: 1 MiB; selected text: 64 KiB. Remote alarm: 240 seconds;
controller: 270 seconds and 24 MiB per stream. Owner-private local evidence;
retain raw streams/status. An exclusive fsynced receipt precedes SSH: one
attempt, no retries, alternate hosts or replay after interruption. No target
cleanup is needed. Ordinary SSH/sudo/D-Bus logs and read access times may occur.

No watchdog/console device open, feed/ioctl, signal, sysctl/SysRq write, panic,
reboot, power action, module load/unload, crash-kernel load, package action,
service/manager change, job, recording, message, persistent logging change or
final-observation start. Do not run a demonstration to make console output appear.
No unlisted diagnostic command may expand this scope.

## Acceptance and follow-up

Capture completion requires identity/boot/protected/vendor continuity, matching
release, successful uname commands and equal native snapshots. Optional missing
facts and nonzero dpkg/modinfo results are retained as limitations, not a clean
qualification verdict. Package metadata does not prove complete binary/source
equivalence; module names do not enumerate all built-in panic/reset callbacks.
Console configuration cannot prove panic/boot text is visible through the KVM.
No kernel/journal/crash message bodies or console screen contents are collected.

Assess package source/patch provenance and competing mechanisms offline from the
capture. Resolve remaining KVM visibility with Aaron's existing-console observation;
new device interaction or configuration requires its own scope. This capture never
sets recovery_ready, console_visibility_verified or reset_attribution_qualified.
It does not select or authorize a trigger. OBS-02/D1–D5 and OBS-04 remain unchanged;
OBS-09 remains unstarted. Preserve the five-minute usable-NTP requirement in the
later single-attempt execution/recovery review.

After separate approval, from homelab-server-configs:
`python3 -I -B watchdog/scripts/inspect-recovery-readiness.py execute --directory {spec['directory']} --sha256 APPROVED_SHA256`
'''


def prepare(directory, digest):
    raw = h.private(directory/'inspection.tar', 8*h.LIMIT)
    if h.sha(raw) != digest:
        raise ValueError('approved archive digest mismatch')
    expected = set(SOURCES) | {'known_hosts', 'baseline.json', 'spec.json', 'review.md'}
    with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
        members = archive.getmembers()
        if (len(members) != len(expected) or {m.name for m in members} != expected
                or any(not m.isfile() or m.size > h.LIMIT for m in members)):
            raise ValueError('closed bounded archive required')
        files = {m.name: archive.extractfile(m).read() for m in members}
    spec = json.loads(files['spec.json']); validate(spec)
    bound = set(SOURCES) | {'known_hosts', 'baseline.json'}
    if (spec['members'] != {n: h.sha(files[n]) for n in bound}
            or files['review.md'] != review(spec).encode()
            or spec['directory'] != str(directory.absolute())):
        raise ValueError('review/member/directory binding mismatch')
    for n, path in SOURCES.items():
        if files[n] != path.read_bytes():
            raise ValueError('repository source drift')
    for n in ('spec.json', 'review.md', 'known_hosts', 'baseline.json'):
        if h.private(directory/n) != files[n]:
            raise ValueError('local approval input drift')
    if not spec['prepared_epoch']-300 <= time.time() < spec['expires_epoch']-270:
        raise ValueError('inspection validity window')
    return spec, files


def execute(args):
    os.umask(0o077)
    directory = args.directory.absolute(); spec, files = prepare(directory, args.sha256)
    data = payload(spec, files)
    argv = h.ssh_argv({'endpoints': ['10.1.0.51'], 'host_key_alias': '10.1.0.137'}, directory)
    with (directory/'execution.json').open('xb') as stream:
        stream.write(h.encoded({'sha256': args.sha256, 'payload_sha256': h.sha(data),
                               'epoch': time.time(), 'argv': argv}))
        stream.flush(); os.fsync(stream.fileno())
    try:
        result = h.bounded(argv, timeout=270, limit=24*h.LIMIT, payload=data, env=os.environ.copy())
    except OSError as error:
        result = {'error': type(error).__name__, 'returncode': None, 'stdout': '', 'stderr': ''}
    for name in ('stdout', 'stderr'):
        (directory/(name+'.txt')).write_text(result.pop(name))
    result.update(bundle_sha256=args.sha256, capture_complete=False, production_accepted=False)
    if result.get('returncode') == 0 and not result.get('error'):
        try:
            capture = json.loads((directory/'stdout.txt').read_text())
            if (capture['operation_id'] != spec['operation_id'] or capture['hostname'] != 'j2-svntp1'
                    or capture['spec_sha256'] != h.sha(h.encoded(spec))):
                raise ValueError('capture binding mismatch')
            result['capture_complete'] = capture.get('capture_complete') is True
        except (ValueError, KeyError, TypeError):
            result['error'] = 'invalid capture binding'
    (directory/'result.json').write_bytes(h.encoded(result))
    return result


def seal(args):
    base = args.baseline
    outcome_raw = h.private(base/'outcome.json'); outcome = json.loads(outcome_raw)
    native = args.scope == 'native'
    debugger = args.scope == 'debugger'
    expected_baseline = ('watchdog-native-inputs-20261026-v1' if debugger else
        'watchdog-recovery-readiness-20261026-v1' if native else 'watchdog-ownership-20261026-v1')
    if outcome.get('capture_accepted') is not True or outcome.get('operation_id') != expected_baseline:
        raise ValueError('accepted ownership baseline required')
    for name, digest in outcome['evidence_sha256'].items():
        if Path(name).name != name or h.sha(h.private(base/name, 24*h.LIMIT)) != digest:
            raise ValueError('baseline evidence changed')
    capture_raw = h.private(base/'stdout.txt', 24*h.LIMIT); capture = json.loads(capture_raw)
    if not capture['capture_complete'] or capture['hostname'] != 'j2-svntp1': raise ValueError('baseline capture')
    with tarfile.open(fileobj=io.BytesIO(h.private(base/'inspection.tar', 8*h.LIMIT))) as archive:
        selected = [m for m in archive.getmembers() if m.name == 'known_hosts']
        if len(selected) != 1 or not selected[0].isfile() or selected[0].size > h.LIMIT:
            raise ValueError('known hosts member')
        known = archive.extractfile(selected[0]).read()
    if not re.fullmatch(rb'10\.1\.0\.137 ssh-ed25519 [A-Za-z0-9+/=]+\n?', known): raise ValueError('host pin')
    now = int(time.time())
    spec = {'schema': 1, 'purpose': DEBUGGER_PURPOSE if debugger else NATIVE_PURPOSE if native else 'watchdog-recovery-readiness', 'operation_id': args.output.name,
        'directory': str(args.output.absolute()), 'prepared_epoch': now, 'expires_epoch': now+86400,
        'baseline_boot_id': capture['boot_after'],
        'baseline_file_hashes': {f: capture['protected_after'][f]['sha256'] for f in p.PROTECTED},
        'baseline_capture_sha256': h.sha(capture_raw), 'members': {}}
    if native: spec['kernel_release'] = capture['readiness_commands']['kernel']['stdout'].strip()
    if debugger: spec['kernel_release'] = capture['native_after']['commands']['kernel']['stdout'].strip()
    validate(spec)
    files = {n: f.read_bytes() for n, f in SOURCES.items()}
    files['known_hosts'] = known
    files['baseline.json'] = h.encoded({'outcome_sha256': h.sha(outcome_raw), 'evidence_sha256': outcome['evidence_sha256'], 'vendor_sha256': capture['configuration_after'][VENDOR]['sha256']})
    spec['members'] = {n: h.sha(v) for n, v in files.items()}
    files.update({'spec.json': h.encoded(spec), 'review.md': review(spec).encode()})
    os.umask(0o077); args.output.mkdir(mode=0o700)
    for n, raw in files.items(): (args.output/n).write_bytes(raw)
    with tarfile.open(args.output/'inspection.tar', 'w') as archive:
        for n, raw in sorted(files.items()):
            member = tarfile.TarInfo(n); member.size = len(raw); member.mode = 0o600
            archive.addfile(member, io.BytesIO(raw))
    digest = h.sha((args.output/'inspection.tar').read_bytes()); prepare(args.output, digest)
    result = {'sha256': digest, 'expires_epoch': spec['expires_epoch'],
        'execution_ready': True, 'execution_approved': False, 'target_contact': False}
    (args.output/'sealing.json').write_bytes(h.encoded(result))
    return result


def load(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def main():
    global h, p, o
    h = load(SOURCES['helper.py']); p = load(SOURCES['passive.py']); p.h = h
    o = load(SOURCES['ownership.py']); o.h = h; o.p = p
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    s = sub.add_parser('seal'); s.add_argument('--baseline', type=Path, required=True); s.add_argument('--output', type=Path, required=True)
    s.add_argument('--scope', choices=('readiness', 'native', 'debugger'), default='readiness')
    for name in ('check', 'execute'):
        s = sub.add_parser(name); s.add_argument('--directory', type=Path, required=True); s.add_argument('--sha256', required=True)
    args = parser.parse_args()
    if args.action == 'seal': result = seal(args)
    elif args.action == 'check':
        prepare(args.directory.absolute(), args.sha256); result = {'integrity': True, 'target_contact': False}
    else: result = execute(args)
    print(json.dumps(result))
    if args.action == 'execute' and not result['capture_complete']: raise SystemExit(1)


if __name__ == '__main__':
    main()
