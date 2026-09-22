"""Record approved task identities and statuses, never Ansible result text."""
import json
import os
from pathlib import Path
import stat

from ansible.plugins.callback import CallbackBase
import yaml


def task_names():
    play = yaml.safe_load((Path(__file__).resolve().parents[1] /
                           'playbooks/deploy-runtime.yaml').read_text())[0]
    names = set()

    def visit(tasks):
        for task in tasks:
            if isinstance(task.get('name'), str):
                names.add(task['name'])
            for key in ('block', 'rescue', 'always'):
                visit(task.get(key, []))

    visit(play.get('pre_tasks', []) + play.get('tasks', []))
    return names


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'aggregate'
    CALLBACK_NAME = 'runtime_progress'
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self):
        super().__init__()
        self.allowed = task_names()
        self.count = 0

    def emit(self, event, task=None, rc=None):
        # Only fixed, bundle-bound names are retained. No host, item, invocation,
        # stdout, stderr, exception or message is ever serialized.
        row = {'event': event}
        if task is not None:
            name = task.get_name()
            row['task'] = name if name in self.allowed else 'unrecognized_task'
        if type(rc) is int and -255 <= rc <= 255:
            row['exit_status'] = rc
        if self.count >= 512:
            return
        fd = os.open(os.environ['NAUTOBOT_PROGRESS_FILE'],
                     os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW)
        try:
            info = os.fstat(fd)
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                    or stat.S_IMODE(info.st_mode) != 0o600 or info.st_size >= 131072):
                raise ValueError('unsafe_progress_file')
            os.write(fd, (json.dumps(row) + '\n').encode())
            self.count += 1
        finally:
            os.close(fd)

    def v2_playbook_on_task_start(self, task, is_conditional):
        self.emit('task_start', task)

    def v2_runner_on_failed(self, result, ignore_errors=False):
        # Respect no_log even for an otherwise harmless integer result.
        rc = None if result._task.no_log or result._result.get('_ansible_no_log') else result._result.get('rc')
        self.emit('task_failed', result._task, rc)

    def v2_runner_on_unreachable(self, result):
        self.emit('unreachable', result._task)

    def v2_playbook_on_stats(self, stats):
        self.emit('playbook_complete')
