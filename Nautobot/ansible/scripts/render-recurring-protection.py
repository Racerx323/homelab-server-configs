#!/usr/bin/env python3
"""Render review-only user units; never install, reload or enable them."""
import argparse
from pathlib import Path
import re
from recurring_protection import Supervisor, require


def render(configuration, script):
    supervisor = Supervisor(configuration)
    c = supervisor.config
    for path in (configuration, script):
        require(path.is_absolute() and re.fullmatch(r'/[A-Za-z0-9_./-]+', str(path)), 'unit_path')
    prefix = c['unit_prefix']
    command = f'/usr/bin/python3 {script} --config {configuration}'
    common = '[Service]\nType=oneshot\nUMask=0077\nWorkingDirectory=/\nKillMode=control-group\nTimeoutStopSec=5\n'
    units = {
        prefix+'.service': '[Unit]\nDescription=Nautobot recurring application protection\n'
            f'OnFailure={prefix}-recovery.service\n'+common+
            f'TimeoutStartSec={c["run_seconds"] + 150}\nExecStart={command} run\n',
        prefix+'.timer': '[Unit]\nDescription=Nautobot nightly protection window\n[Timer]\n'
            f'OnCalendar=*-*-* 03:20:00 America/Chicago\nPersistent=false\nAccuracySec=1s\nUnit={prefix}.service\n'
            '[Install]\nWantedBy=timers.target\n',
        prefix+'-guard.timer': '[Unit]\nDescription=Nautobot independent writer recovery deadline\n[Timer]\n'
            f'OnActiveSec={c["capture_seconds"]}s\nAccuracySec=1s\nUnit={prefix}-guard.service\n',
        prefix+'-guard.service': '[Unit]\nDescription=Nautobot writer deadline recovery\n'+common+
            f'TimeoutStartSec={c["recovery_seconds"] + 60}\nExecStart={command} guard\n',
        prefix+'-recovery.service': '[Unit]\nDescription=Nautobot independent writer recovery\n'+common+
            f'TimeoutStartSec={c["recovery_seconds"] + 60}\nExecStart={command} recover\n',
        prefix+'-freshness.service': '[Unit]\nDescription=Nautobot backup freshness observation\n'+common+
            f'TimeoutStartSec=30\nExecStart={command} missed\n',
        prefix+'-freshness.timer': '[Unit]\nDescription=Nautobot missed backup observation\n[Timer]\n'
            f'OnCalendar=*-*-* 04:05:00 America/Chicago\nOnBootSec=5min\nPersistent=false\nUnit={prefix}-freshness.service\n'
            '[Install]\nWantedBy=timers.target\n',
    }


    if 'notification_argv' in c:
        argv=c['notification_argv']
        require(all(re.fullmatch(r'[A-Za-z0-9_./:-]+',a) for a in argv),'notification_command')
        notification=prefix+'-notification.service'
        units[notification]='[Unit]\nDescription=Nautobot standardized backup notification\n'+common+\
            'TimeoutStartSec=20\nExecStart='+' '.join(argv)+'\n'
        units[prefix+'-notification.timer']='[Unit]\nDescription=Nautobot notification retry\n[Timer]\n'+\
            f'OnBootSec=5min\nOnUnitActiveSec=15min\nUnit={notification}\n[Install]\nWantedBy=timers.target\n'
        for name in (prefix+'.service',prefix+'-recovery.service',prefix+'-guard.service',prefix+'-freshness.service'):
            units[name]=units[name].replace('[Unit]\n','[Unit]\nOnSuccess='+notification+'\n',1)
        # Recovery must run independently before reporting a primary failure.
        for name in (prefix+'-recovery.service',prefix+'-guard.service',prefix+'-freshness.service'):
            units[name]=units[name].replace('[Unit]\n','[Unit]\nOnFailure='+notification+'\n',1)
    return units


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    units = render(args.config.resolve(), Path(__file__).resolve().with_name('recurring_protection.py'))
    args.output.mkdir(mode=0o700, parents=False, exist_ok=False)
    for name, content in units.items(): (args.output/name).write_text(content)
