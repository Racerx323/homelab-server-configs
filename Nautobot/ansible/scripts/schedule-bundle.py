#!/usr/bin/env python3
"""Freeze a durable schedule installation using the existing one-use transport."""
import importlib.util
import argparse
import json
from pathlib import Path
import sys
import yaml
from jsonschema import Draft202012Validator

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


transport = load('transport', Path(__file__).with_name('capture-resume-bundle.py'))
transport.STAGE = 'recurring_schedule_enablement'
transport.FILES.update({
    'launcher.py': 'Nautobot/ansible/scripts/schedule-bundle.py',
    'capture-resume-bundle.py': 'Nautobot/ansible/scripts/capture-resume-bundle.py',
    'playbook.yaml': 'Nautobot/ansible/playbooks/install-recurring-schedule.yaml',
    'schema.json': 'Nautobot/schemas/recurring-schedule.schema.json',
    'schedule_install.py': 'Nautobot/ansible/scripts/schedule_install.py',
    'runtime/scripts/schedule_install.py': 'Nautobot/ansible/scripts/schedule_install.py',
})
RUNTIME = '/var/lib/nautobot/protection/runtime'
STATE = '/var/lib/nautobot/protection/state'
UNIT_DIRECTORY = '/var/lib/nautobot/.config/systemd/user'
UNITS = ['nautobot-protection'+s for s in ('.service', '.timer', '-guard.timer', '-guard.service',
    '-recovery.service', '-freshness.service', '-freshness.timer', '-notification.service', '-notification.timer')]
TIMERS = ['nautobot-protection'+s for s in ('.timer', '-freshness.timer', '-notification.timer')]
transport.GENERATED_FILES = {'runtime/binding.json', 'runtime/supervisor.json', 'runtime-hashes.json'} | {'runtime/units/'+n for n in UNITS}
PROMOTION_FILES = ('scripts/logical_database.py', 'scripts/recurring_logical.py',
                   'scripts/recurring_node.py', 'scripts/recurring_disposal.py', 'binding.json')
ROLLBACK_FILES = ('binding.json', 'scripts/recurring_disposal.py', 'scripts/recurring_node.py')


def configure_promotion(previous_runtime=None, qualified_bundle=None):
    """Reuse the one-use launcher, carrying only the five replacements and rollback."""
    common = ('launcher.py', 'capture-resume-bundle.py', 'schema.json', 'operation.yaml',
              'accepted.yaml', 'PLAN.md', 'ansible-temp.sh', 'schedule_install.py')
    transport.FILES = {n: transport.FILES[n] for n in common}
    transport.FILES['playbook.yaml'] = 'Nautobot/ansible/playbooks/promote-recurring-logical.yaml'
    transport.FILES['trial-bundle.json'] = str(Path(qualified_bundle or '/unused')/'bundle.json')
    transport.FILES['cycle-readback.py'] = 'Nautobot/ansible/scripts/inspect-recurring-cycle.py'
    for name in PROMOTION_FILES[:-1]:
        transport.FILES['runtime/'+name] = 'Nautobot/ansible/'+name
    for name in ROLLBACK_FILES:
        # Only freeze reads this external, nonsecret input. Verify/execute use frozen bytes.
        transport.FILES['rollback/'+name] = str(Path(previous_runtime or '/unused')/name)
    transport.GENERATED_FILES = {'runtime/binding.json', 'runtime-hashes.json', 'first-cycle-expected.json'}


def cycle_expectations(op, expected):
    return {'runtime_sha256': expected, 'boot_id': op['boot_id'],
            'data_service_invocations': {n: op['baseline']['service_invocations'][n]
                for n in ('nautobot-postgresql.service', 'nautobot-redis.service')}}


def generated(root, op):
    sys.path.insert(0, str(root/'runtime/scripts'))
    renderer = load('schedule_renderer', root/'runtime/scripts/render-recurring-protection.py')
    supervisor = {**op['supervisor'], 'execution_authorized': True}
    binding = {**op['binding'], 'execution_authorized': True}
    units = renderer.render_configuration(supervisor, Path(RUNTIME)/'supervisor.json',
                                         Path(RUNTIME)/'scripts/recurring_protection.py')
    return {'binding.json': json.dumps(binding, sort_keys=True)+'\n',
            'supervisor.json': json.dumps(supervisor, sort_keys=True)+'\n',
            **{'units/'+n: text for n, text in units.items()}}


def prepare_runtime(root, op):
    if op.get('promotion'):
        require = transport.require
        before = op['promotion']['previous_runtime_sha256']
        for name in ROLLBACK_FILES:
            require(transport.sha(root/'rollback'/name) == before[name], 'rollback_input_drift')
        old_binding = json.loads((root/'rollback/binding.json').read_text())
        binding = {**op['binding'], 'execution_authorized': True}
        require(not old_binding.get('logical_reference', False)
                and binding == {**old_binding, 'logical_reference': True}, 'binding_scope')
        (root/'runtime/binding.json').write_text(json.dumps(binding, sort_keys=True)+'\n')
        expected = {**before, **{n: transport.sha(root/'runtime'/n) for n in PROMOTION_FILES}}
        (root/'runtime-hashes.json').write_text(json.dumps(expected, sort_keys=True)+'\n')
        (root/'first-cycle-expected.json').write_text(json.dumps(cycle_expectations(op, expected), sort_keys=True)+'\n')
        return
    for name, text in generated(root, op).items():
        path = root/'runtime'/name; path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        path.write_text(text); path.chmod(0o600)
    rows = {str(p.relative_to(root/'runtime')): transport.sha(p)
            for p in sorted((root/'runtime').rglob('*')) if p.is_file()}
    (root/'runtime-hashes.json').write_text(json.dumps(rows, sort_keys=True)+'\n')


def validate(root):
    op = yaml.safe_load((root/'operation.yaml').read_text())
    Draft202012Validator(json.loads((root/'schema.json').read_text())).validate(op)
    require = transport.require
    require(op == json.loads((root/'runtime/operation.json').read_text()), 'operation_identity')
    accepted = yaml.safe_load((root/'accepted.yaml').read_text())
    require(op['accepted_sha256'] == transport.sha(root/'accepted.yaml'), 'accepted_drift')
    require(op['plan_sha256'] == transport.sha(root/'PLAN.md'), 'plan_drift')
    require(op['baseline']['artifact_sha256'] == accepted['application_startup']['artifact_sha256'], 'accepted_artifacts')
    require(op['packages'] == accepted['recurring_prerequisites']['packages'], 'accepted_packages')
    require(op['credential_identity'] == accepted['recurring_credentials']['metadata'], 'credential_metadata')
    for key, digest in op['accepted_stage_bundles'].items():
        require(accepted[key]['bundle_sha256'] == digest, 'stage_identity')
    c = op['supervisor']; b = op['binding']
    require(c['latest_start_minute'] == 202 and c['run_seconds'] == 1800
            and c['capture_seconds'] == 450 and c['recovery_seconds'] == 240, 'schedule_deadlines')
    require(c['start_hour'] == 3 and c['end_hour'] == 4 and 'window_date' not in c, 'standing_window')
    require(c['dispose_successful_payload'] and b['upload_enabled'], 'complete_cycle_required')
    require(c['state_directory'] == STATE and b['state_directory'] == STATE, 'state_scope')
    require(b['supervisor_configuration'] == RUNTIME+'/supervisor.json'
            and b['producer'] == RUNTIME+'/scripts/application-backup.py', 'runtime_scope')
    require(b['notification'] == {'method': 'direct_apprise', 'endpoint': 'http://10.1.3.83:8000/notify/apprise',
        'hostname': 'j2-svpi4mf', 'fqdn': 'j2-svpi4mf.local.theama.co',
        'maximum_attempts': 2, 'retry_interval_seconds': 900}, 'notification_policy')
    require({k: b['credentials'].get(k) for k in op['credential_identity']} == op['credential_identity'], 'credential_binding')
    require(b['credentials']['metadata_file'] == '/var/lib/nautobot/protection/credentials/metadata.json', 'credential_path')
    require(b['artifact_sha256'] == op['baseline']['binding_artifact_sha256'], 'binding_artifacts')
    require(all(accepted['application_startup']['artifact_sha256'][k] == v
                for k, v in b['artifact_sha256'].items()
                if k in accepted['application_startup']['artifact_sha256']), 'accepted_binding_artifacts')
    require(b['backup_template']['repository_id'] == accepted['recurring_upload_integrity']['repository_id'], 'repository_identity')
    if op.get('promotion'):
        promotion = op['promotion']; before = promotion['previous_runtime_sha256']
        require(before == accepted['recurring_schedule']['runtime_sha256'], 'previous_runtime')
        trial = accepted['recurring_logical_capture']
        require(trial['independent_acceptance'] and trial['terminal_publication'] == 'published_verified'
                and trial['prepare_through_resume_seconds'] <= 450, 'logical_trial_not_accepted')
        require(transport.sha(root/'trial-bundle.json') == trial['bundle_sha256'], 'trial_bundle_drift')
        trial_files = json.loads((root/'trial-bundle.json').read_text())
        require(all(transport.sha(root/'runtime'/n) == trial_files['runtime/'+n]
                    for n in PROMOTION_FILES[:-1]), 'unqualified_logical_source')
        require(promotion['files'] == list(PROMOTION_FILES), 'promotion_scope')
        require(promotion['state']['configuration_sha256'] == before['supervisor.json'], 'state_configuration')
        require(promotion['new_files'] == list(PROMOTION_FILES[:2])
                and all(n not in before for n in promotion['new_files']), 'new_file_scope')
        for name in ROLLBACK_FILES:
            require(transport.sha(root/'rollback'/name) == before[name], 'rollback_input_drift')
        old_binding = json.loads((root/'rollback/binding.json').read_text())
        require(not old_binding.get('logical_reference', False)
                and json.loads((root/'runtime/binding.json').read_text())
                == {**old_binding, 'logical_reference': True}
                == {**b, 'execution_authorized': True}, 'binding_scope')
        expected = {**before, **{n: transport.sha(root/'runtime'/n) for n in PROMOTION_FILES}}
        require(json.loads((root/'runtime-hashes.json').read_text()) == expected, 'promotion_hashes')
        require(json.loads((root/'first-cycle-expected.json').read_text())
                == cycle_expectations(op, expected), 'cycle_expectations')
        return op
    for name, item in b['metadata_files'].items():
        require(item['path'] == RUNTIME+'/metadata/'+name
                and item['sha256'] == transport.sha(root/'runtime/metadata'/name), 'metadata_drift')
    for name, text in generated(root, op).items():
        require((root/'runtime'/name).read_text() == text, 'generated_input_drift')
    expected = json.loads((root/'runtime-hashes.json').read_text())
    actual = {str(p.relative_to(root/'runtime')): transport.sha(p)
              for p in (root/'runtime').rglob('*') if p.is_file()}
    require(actual == expected, 'runtime_hashes')
    return op


transport.prepare_runtime = prepare_runtime
transport.validate = validate
if __name__ == '__main__':
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--previous-runtime', type=Path)
    parser.add_argument('--qualified-bundle', type=Path)
    extra, remaining = parser.parse_known_args()
    sys.argv = [sys.argv[0], *remaining]
    if len(remaining) >= 2:
        definition = (Path(remaining[remaining.index('--operation')+1]) if '--operation' in remaining
                      else transport.ROOT/transport.FILES['operation.yaml'] if remaining[0] == 'freeze'
                      else Path(remaining[1])/'operation.yaml')
        if yaml.safe_load(definition.read_text()).get('promotion'):
            if remaining[0] == 'freeze' and (extra.previous_runtime is None or extra.qualified_bundle is None):
                parser.error('promotion freeze requires --previous-runtime and --qualified-bundle')
            configure_promotion(extra.previous_runtime, extra.qualified_bundle)
    sys.exit(transport.main())
