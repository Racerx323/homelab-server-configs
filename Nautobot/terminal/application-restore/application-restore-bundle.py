#!/usr/bin/env python3
"""Freeze the isolated restore contract and launch only an approved published bundle."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ('restore_node.py', 'restore_payload.py', 'restore_probe.py', 'logical_database.py',
           'restore_preflight.py', 'restore_host_monitor.py', 'workload_sampler.py',
           'persistence-preflight.py', 'startup-preflight.py')
MONITOR = ('restore_preflight.py', 'restore_host_monitor.py', 'workload_sampler.py',
           'persistence-preflight.py', 'startup-preflight.py', 'operation.json')
FILES = {name: 'Nautobot/ansible/scripts/'+name for name in (*SCRIPTS,
    'application-restore-bundle.py', 'workload_controller.py', 'run-restic-repository-preflight.py')}
FILES.update({
    'application-restore.py': 'restic/scripts/application-restore.py',
    'application-backup.py': 'restic/scripts/application-backup.py',
    'playbook.yaml': 'Nautobot/ansible/playbooks/restore-application.yaml',
    'restore-stage.yaml': 'Nautobot/ansible/playbooks/restore-stage.yaml',
    'schema.json': 'Nautobot/schemas/application-restore.schema.json',
    'preparation.yaml': 'Nautobot/manifests/application-restore-preparation.yaml',
    'accepted-state.yaml': 'Nautobot/manifests/accepted-live-state.yaml',
    'desired-state.yaml': 'Nautobot/manifests/desired-state.yaml',
    'PLAN.md': 'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md',
    'OPERATIONS.md': 'Nautobot/docs/OPERATIONS.md',
    'ansible.cfg': 'Nautobot/ansible/ansible.cfg',
    'ansible-temp.sh': 'tests/repository/run-with-ansible-local-temp.sh',
})
GENERATED = {'operation.json', 'baseline.json', 'members.json', 'logical-reference.json',
             'runtime.json', 'restore.json', 'repository', 'inventory.ini'}
RECEIPTS = ['credential-delivery.json', 'production-before.json', 'guard.json', 'guard-failure.json',
            'stopped.json', 'cleanup-result.json', 'logical-result.json', 'check-result.json',
            'checks-complete.json', 'retrieval/retrieval-result.json'] + [phase+'-failure.json' for phase in
            ('arm', 'inject', 'retrieve', 'start', 'import', 'logical', 'check', 'finish', 'host-health')]


def require(ok, reason):
    if not ok: raise ValueError(reason)


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    obj = importlib.util.module_from_spec(spec); spec.loader.exec_module(obj); return obj


def generated(op, prep):
    root = op['root']; source = prep['source']
    runtime = {'token': op['token'], 'uid': 999, 'context': 'target',
               'images': prep['runtime']['image_ids'],
               'production_containers': ['nautobot-'+role for role in ('postgresql','redis','web','worker','scheduler')],
               'restic_helper': root+'/scripts/application-restore.py'}
    contract = {k: source[k] for k in ('snapshot_id','repository_id','repository_url','hostname','tags','payload_path','content_sha256')}
    contract.update(restic='/usr/bin/restic', restic_version=op['restic_version'],
                    maximum_bytes={name: 268435456 for name in source['content_sha256']})
    return runtime, contract


def validate(op, schema):
    from jsonschema import Draft202012Validator, FormatChecker
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(op)
    require(op['root'] == '/var/lib/nautobot/restore-tests/'+op['token'], 'root_token')
    require(op['monitor_root'] == '/tmp/nautobot-restore-monitor-'+op['token'].removeprefix('nautobot-restore-'), 'monitor_token')


def freeze(operation, destination, baseline, members, logical):
    import yaml
    op = json.loads(operation.read_text())
    validate(op, json.loads((ROOT/FILES['schema.json']).read_text()))
    destination.mkdir(mode=0o700, exist_ok=False)
    for name, source in FILES.items(): shutil.copyfile(ROOT/source, destination/name)
    for name, source in (('operation.json',operation),('baseline.json',baseline),('members.json',members),('logical-reference.json',logical)):
        shutil.copyfile(source, destination/name)
    prep = yaml.safe_load((destination/'preparation.yaml').read_text())
    runtime, contract = generated(op, prep)
    for name, value in (('runtime.json',runtime),('restore.json',contract)):
        (destination/name).write_text(json.dumps(value, sort_keys=True)+'\n')
    (destination/'repository').write_text(prep['source']['repository_url']+'\n')
    (destination/'inventory.ini').write_text('[restore_target]\nj2-svpi4mf ansible_host=10.1.2.170 ansible_user=ama\n')
    manifest = {'schema_version': 1, 'source_commit': op['operation']['source_commit'],
                'files': {p.name: sha(p) for p in sorted(destination.iterdir())}}
    (destination/'bundle.json').write_text(json.dumps(manifest, sort_keys=True)+'\n')
    for path in destination.iterdir(): path.chmod(0o600)
    approval = sha(destination/'bundle.json')
    verify(destination, approval, executing=False)
    return approval


def verify(bundle, approval, executing=True):
    import yaml
    require(not any(p.is_symlink() for p in (bundle, *bundle.parents)), 'bundle_path')
    require(sha(bundle/'bundle.json') == approval, 'bundle_identity')
    manifest = json.loads((bundle/'bundle.json').read_text())
    require(set(manifest['files']) == set(FILES)|GENERATED, 'manifest_file_set')
    require({p.name for p in bundle.iterdir()} == set(FILES)|GENERATED|{'bundle.json'}, 'bundle_file_set')
    for name, digest in manifest['files'].items():
        path = bundle/name
        require(not path.is_symlink() and path.is_file() and sha(path) == digest, 'bundle_drift')
    op = json.loads((bundle/'operation.json').read_text())
    validate(op, json.loads((bundle/'schema.json').read_text()))
    for name, field in (('PLAN.md','plan_sha256'),('accepted-state.yaml','accepted_state_sha256'),
                        ('preparation.yaml','preparation_sha256'),('members.json','members_sha256'),('logical-reference.json','logical_sha256')):
        require(sha(bundle/name) == op[field], 'input_identity')
    prep = yaml.safe_load((bundle/'preparation.yaml').read_text())
    require(op['logical_sha256'] == prep['source']['logical_reference_sha256'], 'logical_reference')
    require(op['members_sha256'] == prep['configuration']['archive_member_map_sha256'], 'member_reference')
    accepted = yaml.safe_load((bundle/'accepted-state.yaml').read_text())['recovery_preservation']
    require(accepted['state'] == 'accepted', 'source_not_accepted')
    for field in ('snapshot_id','terminal_tag','archive_commit'):
        require(accepted[field] == prep['source'][field], 'archive_source')
    require(accepted['logical_before_sha256'] == op['logical_sha256'], 'accepted_logical_reference')
    expected = json.loads((bundle/'baseline.json').read_text())
    require(sha(bundle/'baseline.json') == op['baseline']['sha256'] == prep['baseline']['sha256'], 'baseline_hash')
    require(op['baseline']['collected_at'] == expected['collected_at'] == prep['baseline']['collected_at'], 'baseline_date')
    require(expected['persistence_services'] == op['baseline']['services'], 'baseline_services')
    # Pure comparisons only; importing this collector does not contact the target.
    module(bundle/'restore_preflight.py', 'restore_verify_preflight').assess(expected, op['baseline'])
    runtime, contract = generated(op, prep)
    require(json.loads((bundle/'runtime.json').read_text()) == runtime, 'runtime_contract')
    require(json.loads((bundle/'restore.json').read_text()) == contract, 'retrieval_contract')
    require((bundle/'repository').read_text() == prep['source']['repository_url']+'\n', 'repository_contract')
    require((bundle/'inventory.ini').read_text() == '[restore_target]\nj2-svpi4mf ansible_host=10.1.2.170 ansible_user=ama\n', 'inventory_contract')
    require(manifest['source_commit'] == op['operation']['source_commit'], 'source_identity')
    if executing:
        require(sha(Path(__file__)) == manifest['files']['application-restore-bundle.py'], 'launcher_drift')
        require(yaml.safe_load((ROOT/'Nautobot/manifests/operation.yaml').read_text()) == op
                and op['operation']['authorization_ready'], 'operation_not_ready')
        age = (datetime.now(timezone.utc)-datetime.fromisoformat(op['baseline']['collected_at'])).total_seconds()
        require(0 <= age <= 86400, 'baseline_expired')
        commit = op['operation']['source_commit']
        require(op['ci_success_commit'] == commit, 'ci_not_reviewed')
        for name, source in FILES.items():
            data = subprocess.run(['git','show',commit+':'+source],cwd=ROOT,capture_output=True,check=True,timeout=10).stdout
            require(hashlib.sha256(data).hexdigest() == manifest['files'][name], 'uncommitted_source')
    return manifest, op


@contextmanager
def credentials(runtime, reader, evidence):
    """Only the supervised tmpfs contains controller secrets; partial failures clean up."""
    directory = Path(tempfile.mkdtemp(prefix='restore-credentials-', dir=runtime))
    values = {}; buffers = []
    refs = {'django': ('prd_nautobot','NAUTOBOT_DJANGO_SECRET_KEY'),
            'password': ('prd_restic','NAUTOBOT_RESTIC_REPOSITORY_PASSWORD'),
            'id': ('prd_b2','NAUTOBOT_RESTIC_B2_APPLICATION_KEY_ID'),
            'key': ('prd_b2','NAUTOBOT_RESTIC_B2_APPLICATION_KEY')}
    path = directory/'delivery.json'
    try:
        for name, (config, key) in refs.items():
            raw = reader('homelab-dev',config,key); buffers.append(raw)
            require(isinstance(raw,bytearray) and 1 <= len(raw) <= 8192 and not any(c in raw for c in (0,10,13)), 'credential_format')
            values[name] = raw.decode()
        fd = os.open(path,os.O_CREAT|os.O_EXCL|os.O_WRONLY|os.O_NOFOLLOW,0o600)
        with os.fdopen(fd,'w') as stream: json.dump(values,stream)
        yield path
    finally:
        for raw in buffers:
            if isinstance(raw,bytearray): raw[:] = b'\0'*len(raw)
        values.clear()
        path.unlink(missing_ok=True); directory.rmdir()
        evidence.write_text(json.dumps({'controller_credentials_absent': not directory.exists()}))
        evidence.chmod(0o600)


def staging(bundle, manifest, op):
    root = op['root']; monitor = op['monitor_root']; files = []
    def add(name, destination, uid):
        files.append({'source':str(bundle/name),'destination':destination,'uid':uid,'sha256':manifest['files'][name]})
    for name in SCRIPTS+('application-restore.py','application-backup.py'): add(name,root+'/scripts/'+name,999)
    for name in ('runtime.json','members.json','logical-reference.json'): add(name,root+'/'+name,999)
    for name in ('restore.json','repository'): add(name,root+'/retrieval/'+name,999)
    for name in MONITOR: add(name,monitor+'/'+name,0)
    return files


def render(bundle, approval, evidence, socket):
    verify(bundle,approval)
    controller = module(bundle/'workload_controller.py','restore_controller_render')
    controller.ROOT = ROOT  # Bundled helper location is not the repository root.
    text = controller.render(bundle,approval,evidence,socket)
    old = ROOT/'Nautobot/ansible/scripts/run-workload.py'
    new = ROOT/FILES['application-restore-bundle.py']
    return text.replace('Bounded Nautobot workload controller','Bounded Nautobot isolated restore controller').replace('RuntimeMaxSec=12000','RuntimeMaxSec=4500').replace(str(old)+' --bundle',str(new)+' execute --bundle').replace(' --resolve-doppler','')


def execute(bundle, approval, evidence):
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    manifest, op = verify(bundle,approval)
    controller = module(bundle/'workload_controller.py','restore_controller')
    runtime = controller.runtime(approval)
    controller.persistent_path(evidence); controller.private_directory(evidence.parent)
    evidence.mkdir(mode=0o700,exist_ok=False)
    controller.receipt(evidence/'controller-started.json',{'approval':approval,'invocation_id':os.environ['INVOCATION_ID']})
    search = os.pathsep.join((str(Path.home()/'.local/bin'),os.defpath))
    ansible = shutil.which('ansible-playbook',path=search); doppler = shutil.which('doppler',path=search)
    require(ansible and doppler, 'controller_tools')
    resolver = module(bundle/'run-restic-repository-preflight.py','restore_secret_reader')
    resolver.DOPPLER_BASE = (doppler,*resolver.DOPPLER_BASE[1:])
    status = None
    try:
        with credentials(runtime,resolver.read_secret,evidence/'credential-cleanup.json') as secret_file:
            extra = {'restore_verified':True,'restore_execution_authorized':True,'restore_stage':True,
                     'restore_context':'target','restore_token':op['token'],'restore_root':op['root'],
                     'restore_scripts':op['root']+'/scripts','restore_stage_uid':999,
                     'restore_monitor_scripts':op['monitor_root'],'restore_files':staging(bundle,manifest,op),
                     'restore_monitor_sha256':{n:manifest['files'][n] for n in MONITOR},
                     'restore_credentials_file':str(secret_file),'restore_receipts':RECEIPTS,'restore_evidence':str(evidence)}
            inputs = evidence/'ansible-inputs.json'; inputs.write_text(json.dumps(extra)); inputs.chmod(0o600)
            env = {k:v for k,v in os.environ.items() if k in ('HOME','USER','LOGNAME','SSH_AUTH_SOCK','LANG','LC_ALL')}
            env.update(PATH=search,ANSIBLE_CONFIG=str(bundle/'ansible.cfg'),PYTHONDONTWRITEBYTECODE='1')
            def limit(): resource.setrlimit(resource.RLIMIT_FSIZE,(8388608,8388608))
            with (evidence/'ansible.log').open('xb') as output:
                status = subprocess.run(['/bin/bash',str(bundle/'ansible-temp.sh'),ansible,'-i',str(bundle/'inventory.ini'),
                    str(bundle/'playbook.yaml'),'--extra-vars','@'+str(inputs)],cwd=bundle,env=env,
                    stdout=output,stderr=output,timeout=4200,preexec_fn=limit).returncode
    finally:
        controller.receipt(evidence/'controller-result.json',{'ansible_status':status,'accepted':False,'review_required':True})
    return status


def main():
    os.umask(0o077)
    p=argparse.ArgumentParser(); sub=p.add_subparsers(dest='action',required=True)
    f=sub.add_parser('freeze')
    for name in ('operation','destination','baseline','members','logical'): f.add_argument('--'+name,type=Path,required=True)
    for action in ('verify','render-controller','execute'):
        command=sub.add_parser(action); command.add_argument('--bundle',type=Path,required=True);command.add_argument('--approve',required=True)
        if action!='verify': command.add_argument('--evidence',type=Path,required=True)
        if action=='render-controller':command.add_argument('--ssh-socket',type=Path,required=True)
    a=p.parse_args()
    if a.action=='freeze': print(freeze(a.operation,a.destination,a.baseline,a.members,a.logical))
    elif a.action=='verify': verify(a.bundle,a.approve); print('verified')
    elif a.action=='render-controller': print(render(a.bundle,a.approve,a.evidence,a.ssh_socket),end='')
    else: return execute(a.bundle,a.approve,a.evidence)
    return 0


if __name__=='__main__': raise SystemExit(main())
