#!/usr/bin/env python3
"""Freeze one recovery-only trial through the shared Ansible transport."""
import importlib.util
import json
from pathlib import Path
import sys
import yaml
from jsonschema import Draft202012Validator
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('transport', Path(__file__).with_name('capture-resume-bundle.py'))
transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)
transport.STAGE = 'recurring_failure_recovery_timer_qualification'
transport.FILES.update({
    'launcher.py': 'Nautobot/ansible/scripts/recovery-timer-bundle.py',
    'capture-resume-bundle.py': 'Nautobot/ansible/scripts/capture-resume-bundle.py',
    'playbook.yaml': 'Nautobot/ansible/playbooks/qualify-recovery-timers.yaml',
    'recovery-case.yaml': 'Nautobot/ansible/tasks/qualify-recovery-case.yaml',
    'schema.json': 'Nautobot/schemas/recovery-timer-qualification.schema.json',
    'runtime/scripts/recovery_qualification.py': 'Nautobot/ansible/scripts/recovery_qualification.py',
})


def validate(root):
    op = yaml.safe_load((root/'operation.yaml').read_text())
    Draft202012Validator(json.loads((root/'schema.json').read_text())).validate(op)
    transport.require(op == json.loads((root/'runtime/operation.json').read_text()), 'operation_identity')
    transport.require(op['accepted_sha256'] == transport.sha(root/'accepted.yaml'), 'accepted_source_drift')
    accepted = yaml.safe_load((root/'accepted.yaml').read_text())
    base = '/var/lib/nautobot/protection/recovery-qualification'
    if 'retained_state' in op:
        retained = op['retained_state']
        transport.require(retained['boot_id'] == op['boot_id'], 'retained_boot')
        transport.require(set(retained['directories']) == {'.', 'killed', 'metadata', 'playbooks', 'scripts', 'tasks'}, 'retained_directories')
        for name, row in retained['files'].items():
            transport.require(not Path(name).is_absolute() and '..' not in Path(name).parts
                              and not name.startswith('killed/'), 'retained_file_scope')
            transport.require(set(row) == {'uid', 'gid', 'mode', 'sha256'} and len(row['sha256']) == 64, 'retained_file_metadata')
        for directory, rows in ((True, retained['directories']), (False, retained['files'])):
            transport.require(all(row['uid'] == 999 and row['gid'] == 985 and
                              row['mode'] == (0o700 if directory else 0o600) for row in rows.values()), 'retained_permissions')
    for case, trial in op['trials'].items():
        c = trial['supervisor']; binding = trial['binding']; directory = base+'/'+case
        transport.require(trial['plan_sha256'] == transport.sha(root/'PLAN.md'), 'plan_drift')
        transport.require(trial['baseline']['artifact_sha256'] == accepted['application_startup']['artifact_sha256'], 'accepted_artifacts')
        transport.require(trial['packages'] == accepted['recurring_prerequisites']['packages'], 'accepted_packages')
        transport.require(trial['credential_identity'] == accepted['recurring_credentials']['metadata'], 'accepted_credentials')
        transport.require(c['capture_seconds'] == 450 and c['recovery_seconds'] == 240 and c['run_seconds'] == 900, 'deadlines')
        transport.require((c['end_hour']-c['start_hour'])*60+c['end_minute']-c['start_minute'] == 60, 'window')
        transport.require(not binding['upload_enabled'] and not c['dispose_successful_payload'] and 'notification_argv' not in c, 'stage_scope')
        transport.require(c['unit_prefix'] == 'nautobot-protection-'+case and c['state_directory'] == directory+'/state', 'unit_scope')
        names = [c['unit_prefix']+suffix for suffix in ('.service','-guard.timer','-guard.service','-recovery.service')]
        transport.require(trial['unit_names'] == names and trial['unit_paths'] == [directory+'/units/'+n for n in names], 'unit_paths')
        transport.require(c['prepare_argv'] == ['/usr/bin/python3','-B',base+'/scripts/recovery_qualification.py','prepare',directory], 'prepare_command')
        transport.require(binding['state_directory'] == directory+'/state' and binding['supervisor_configuration'] == directory+'/supervisor.json', 'binding_paths')
        for name, item in binding['metadata_files'].items():
            transport.require(item['sha256'] == transport.sha(root/'runtime/metadata'/name), 'metadata_drift')
        transport.require(trial['operation']['execution_enabled'] and 'retained_state' not in trial, 'trial_scope')
    return op


transport.validate = validate
if __name__ == '__main__':
    sys.exit(transport.main())
