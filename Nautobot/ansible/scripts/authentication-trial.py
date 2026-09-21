#!/usr/bin/env python3
"""Freeze and launch one disposable authentication trial; no contact during preparation."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = next((p for p in Path(__file__).resolve().parents if (p/'Nautobot/manifests').is_dir()), None)
FILES = {
    'predecessor-result.json':'Nautobot/manifests/authentication-trial-result.json',
    'PLAN.md':'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md',
    'launcher.py':'Nautobot/ansible/scripts/authentication-trial.py',
    'node.py':'Nautobot/ansible/scripts/auth-trial-node.py',
    'load-node.py':'Nautobot/ansible/scripts/image-load-node.py',
    'probe.py':'Nautobot/ansible/scripts/configuration-auth-probe.py',
    'probe-tests.py':'Nautobot/tests/test_configuration_auth.py',
    'image-store.json':'Nautobot/manifests/runtime-image-store.json',
    'image-store-result.json':'Nautobot/manifests/image-load-result.json',
    'bounded.py':'Nautobot/ansible/scripts/image-build-node.py',
    'playbook.yaml':'Nautobot/ansible/playbooks/authentication-trial.yaml',
    'trial-container.yaml':'Nautobot/ansible/playbooks/trial-container.yaml',
    'operation.yaml':'Nautobot/manifests/operation.yaml',
    'schema.json':'Nautobot/schemas/authentication-trial.schema.json',
    'desired.yaml':'Nautobot/manifests/desired-state.yaml',
    'desired-schema.json':'Nautobot/schemas/desired-state.schema.json',
    'accepted.yaml':'Nautobot/manifests/accepted-live-state.yaml',
    'qualified.json':'Nautobot/manifests/qualified-image.json',
    'credentials.json':'Nautobot/manifests/provisioned-credentials.json',
    'credential-result.json':'Nautobot/manifests/credential-result.json',
    'settings.py':'Nautobot/ansible/templates/runtime/nautobot_config.py',
    'inputs.json':'Nautobot/manifests/runtime-inputs.json',
    'tests.py':'Nautobot/tests/test_authentication_trial.py',
    'PROCEDURE.md':'Nautobot/docs/CONFIGURATION_AUTHENTICATION.md',
    'ansible-temp.sh':'tests/repository/run-with-ansible-local-temp.sh',
}
GENERATED = {'spec.json','provenance.json','inventory.json','ansible.cfg'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(ok, code):
    if not ok: raise ValueError(code)


def spec_from(root):
    import yaml
    from jsonschema import Draft202012Validator
    op=yaml.safe_load((root/'operation.yaml').read_text())
    Draft202012Validator(json.loads((root/'schema.json').read_text())).validate(op)
    require(op['plan_sha256']==sha(root/'PLAN.md'),'plan_identity')
    require(op['operation']['id']=='nautobot-configuration-auth-v2','retry_definition_required')
    require(op['predecessor']['result_sha256']==sha(root/'predecessor-result.json'),'predecessor_result')
    desired=yaml.safe_load((root/'desired.yaml').read_text())
    Draft202012Validator(json.loads((root/'desired-schema.json').read_text())).validate(desired)
    qualified=json.loads((root/'qualified.json').read_text())
    credentials=json.loads((root/'credentials.json').read_text())
    result=json.loads((root/'credential-result.json').read_text())
    accepted=yaml.safe_load((root/'accepted.yaml').read_text())
    inputs=json.loads((root/'inputs.json').read_text())
    require(qualified['reference']=='localhost/nautobot-homelab@'+qualified['manifest_digest'], 'qualified_reference')
    require(inputs['custom_image']==qualified['reference'] and inputs['recovery_host']==accepted['dual_stack_identity']['fqdn'], 'runtime_inputs')
    require(credentials['terminal_result_sha256']==sha(root/'credential-result.json') and result['accepted'] and result['host_state']=='injection_verified' and result['controller_payload_cleanup_verified'], 'credential_result')
    require(credentials['target']==accepted['host_baseline']['host']=='j2-svpi4mf' and accepted['host_baseline']['state']=='accepted', 'accepted_host')
    require(not credentials['runtime_accepted'] and not result['runtime_started'] and not qualified['runtime_store_loaded'], 'unexpected_runtime_state')
    store=json.loads((root/'image-store.json').read_text())
    loaded=json.loads((root/'image-store-result.json').read_text())
    require(store['runtime_store_loaded'] and not store['runtime_accepted'] and loaded['accepted'] and loaded['outcome']=='image_store_readiness_passed' and store['terminal_result_sha256']==sha(root/'image-store-result.json'),'image_store_proof')
    images={'custom':{'reference':qualified['reference'],'digest':qualified['manifest_digest'],'image_id':qualified['image_id']}}
    for name in ('postgresql','redis'):
        item=desired['images'][name]
        require(item['reference'].endswith('@'+item['manifest_digest']) and item['platform']=='linux/arm64/v8','dependency_identity')
        images[name]={'reference':item['reference'],'digest':item['manifest_digest'],'image_id':loaded['images'][name]['Id']}
    for name,item in images.items():
        require(item['digest']==loaded['images'][name]['Digest'] and item['reference'] in loaded['images'][name]['RepoDigests'] and loaded['images'][name]['Architecture']=='arm64','loaded_image_identity')
    return {'boot_id':accepted['host_baseline']['boot_id'],'images':images,
            'settings_sha256':sha(root/'settings.py'), 'min_available_bytes':1610612736,'min_free_bytes':21474836480}


def git(*args):
    return subprocess.check_output(['git','-C',str(ROOT),*args],timeout=15)


def provenance(root):
    import yaml
    q=json.loads((root/'qualified.json').read_text()); c=json.loads((root/'credentials.json').read_text())
    a=yaml.safe_load((root/'accepted.yaml').read_text())
    store=json.loads((root/'image-store.json').read_text())
    proofs={}
    for name,item,commit_field,result_path,hash_field in [
        ('store',store,'terminal_commit','Nautobot/manifests/image-load-result.json','terminal_result_sha256'),
        ('image',q,'terminal_commit','Nautobot/manifests/image-qualification-result.json','terminal_evidence_sha256'),
        ('credentials',c,'terminal_commit','Nautobot/manifests/credential-result.json','terminal_result_sha256'),
        ('baseline',a['provenance'],'definition_commit',None,None),
        ('dns',a['dual_stack_identity'],'definition_commit',None,None)]:
        tag=item['terminal_tag'];commit=item[commit_field]
        require(git('cat-file','-t',tag).strip()==b'tag' and git('rev-parse',tag+'^{}').decode().strip()==commit,'terminal_tag')
        proof={'tag':tag,'commit':commit,'tag_object':git('rev-parse',tag).decode().strip()}
        if result_path:
            raw=git('show',tag+':'+result_path)
            require(hashlib.sha256(raw).hexdigest()==item[hash_field],'terminal_result_hash')
            proof['result']=json.loads(raw)
            if name=='image':
                require(proof['result']['image_id']==q['image_id'] and proof['result']['archive_sha256']==q['archive_sha256'] and proof['result']['oci_manifest_digest']==q['manifest_digest'] and proof['result']['outcome']=='bounded_static_image_qualification_passed','image_provenance')
            elif name=='credentials':require(raw==(root/'credential-result.json').read_bytes(),'credential_provenance')
            else:require(raw==(root/'image-store-result.json').read_bytes(),'store_provenance')
        proofs[name]=proof
    return proofs


def prepare(bundle):
    require(ROOT is not None,'repository_required')
    require(not bundle.exists(),'new_bundle_required')
    bundle.mkdir(mode=0o700)
    for name,source in FILES.items():
        p=ROOT/source;require(p.is_file() and not p.is_symlink(),'source_file');shutil.copyfile(p,bundle/name)
    spec=spec_from(bundle)
    (bundle/'spec.json').write_text(json.dumps(spec,indent=2)+'\n')
    (bundle/'provenance.json').write_text(json.dumps(provenance(bundle),indent=2)+'\n')
    (bundle/'inventory.json').write_text(json.dumps({'all':{'hosts':{'authentication_target':{
        'ansible_host':'j2-svpi4mf.local.theama.co','ansible_user':'ama','ansible_python_interpreter':'/usr/bin/python3',
        'ansible_ssh_common_args':'-o StrictHostKeyChecking=yes -o HostKeyAlias=10.1.2.170 -o BatchMode=yes -o ConnectTimeout=6'}}}})+'\n')
    (bundle/'ansible.cfg').write_text('[defaults]\nhost_key_checking=True\nretry_files_enabled=False\nstdout_callback=default\nno_target_syslog=True\n')
    for p in bundle.iterdir():p.chmod(0o600)
    (bundle/'SHA256SUMS.json').write_text(json.dumps({p.name:sha(p) for p in sorted(bundle.iterdir())},indent=2)+'\n')
    digest=sha(bundle/'SHA256SUMS.json');verify(bundle,digest);print(digest)


def verify(bundle,digest):
    require(bundle.is_dir() and not bundle.is_symlink(),'bundle_directory')
    index=bundle/'SHA256SUMS.json'
    require(index.is_file() and not index.is_symlink() and sha(index)==digest,'bundle_hash')
    rows=json.loads(index.read_text())
    require(set(rows)==set(FILES)|GENERATED and {p.name for p in bundle.iterdir()}==set(rows)|{'SHA256SUMS.json'},'bundle_members')
    for name,value in rows.items():
        p=bundle/name;require(p.is_file() and not p.is_symlink() and sha(p)==value,'bundle_member_hash')
    require(spec_from(bundle)==json.loads((bundle/'spec.json').read_text()),'derived_spec')


def evaluate(root,rc,spec):
    require(rc==0,'ansible_failed')
    result=json.loads((root/'result.json').read_text())
    require(result['accepted'] and result['cleanup_passed'] and result['continuity_passed'] and result['post_cleanup_seconds']>=75,'trial_not_accepted')
    times=[x['monotonic'] for x in result['samples']]
    require(len(times)>=16 and all(0<b-a<=15 for a,b in zip(times,times[1:])),'coverage')
    cleanup=json.loads((root/'cleanup.json').read_text())
    require(set(cleanup)=={'probe','redis','postgresql','network'} and all(cleanup.values()),'cleanup_incomplete')
    probe=json.loads((root/'probe-result.json').read_text())
    require(probe=={'accepted':True,'checks':['settings_and_plugin_registration','postgresql_positive_and_wrong_password','redis_cache_positive_missing_wrong_password','redis_broker_positive_missing_wrong_password'],'production_runtime_accepted':False,'administrator_created':False},'probe_contract')
    for role,memory in [('postgresql',768),('redis',512),('probe',1536)]:
        record=json.loads((root/(role+'.json')).read_text());limits=record['limits']
        require(record['started'] and 0<limits['memory_max']<=memory*1024**2 and limits['swap_max']==0 and 0<limits['cpus']<=2,'limits_evidence')


def archival_gate(bundle):
    """No mutation: require the prior terminal result in an annotated published tag."""
    import yaml
    op=yaml.safe_load((bundle/'operation.yaml').read_text());tag=op['predecessor']['terminal_tag']
    repo=ROOT or Path.cwd()
    def read_git(*args):return subprocess.check_output(['git','-C',str(repo),*args],timeout=20)
    require(read_git('cat-file','-t',tag).strip()==b'tag','predecessor_not_archived')
    archived=read_git('show',tag+':Nautobot/manifests/authentication-trial-result.json')
    require(archived==(bundle/'predecessor-result.json').read_bytes(),'predecessor_archive_mismatch')
    tag_object=read_git('rev-parse',tag).decode().strip()
    remote=read_git('ls-remote','--tags','origin','refs/tags/'+tag).decode().split()
    require(remote==[tag_object,'refs/tags/'+tag],'predecessor_tag_not_published')


def execute(bundle,digest):
    verify(bundle,digest)
    require(sha(Path(__file__))==sha(bundle/'launcher.py'),'execute_frozen_launcher')
    archival_gate(bundle)
    evidence=Path(tempfile.mkdtemp(prefix='nautobot-auth-trial-evidence.'));print('evidence='+str(evidence),flush=True)
    result={'accepted':False,'bundle_sha256':digest,'production_runtime_started':False,'mutation_status':'unknown_until_node_records_reviewed','rollback':'remove_only_owned_disposable_objects'}
    try:
        with tempfile.TemporaryDirectory(prefix='nautobot-auth-trial-frozen.') as tmp:
            frozen=Path(tmp)/'bundle';shutil.copytree(bundle,frozen);verify(frozen,digest)
            env={k:os.environ[k] for k in ('HOME','PATH','SSH_AUTH_SOCK') if k in os.environ}
            env.update(ANSIBLE_CONFIG=str(frozen/'ansible.cfg'),ANSIBLE_NOCOLOR='1',PYTHONDONTWRITEBYTECODE='1')
            args=['/bin/bash',str(frozen/'ansible-temp.sh'),'ansible-playbook','-i',str(frozen/'inventory.json'),str(frozen/'playbook.yaml'),'-e',json.dumps({'authentication_bundle_verified':True,'bundle_root':str(frozen),'evidence_root':str(evidence)})]
            # Output is non-secret; keep it private and bounded using the qualified capture helper.
            module=importlib.util.spec_from_file_location('bounded',frozen/'bounded.py'); b=importlib.util.module_from_spec(module);module.loader.exec_module(b)
            b.AUDIT=evidence/'execution-trace.jsonl'
            output=b.capture(args,timeout=2100,limit=4*1024*1024,env=env)
            (evidence/'ansible.log').write_text(output)
            evaluate(evidence,0,spec_from(frozen))
            result.update(accepted=True,mutation_status='disposable_trial_passed_and_removed')
    except Exception:
        result.update(accepted=False,error='execution_or_evidence_failed_review_required')
    finally:
        (evidence/'controller-result.json').write_text(json.dumps(result,indent=2)+'\n')
        (evidence/'SHA256SUMS.json').write_text(json.dumps({p.name:sha(p) for p in evidence.iterdir() if p.is_file()},indent=2)+'\n')
    return 0 if result['accepted'] else 69


def main():
    os.umask(0o077)
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['prepare','verify','execute']);p.add_argument('bundle',type=Path);p.add_argument('digest',nargs='?');p.add_argument('--operation',type=Path);a=p.parse_args()
    if a.operation is not None:
        require(a.mode=='prepare','operation_override_prepare_only')
        FILES['operation.yaml']=str(a.operation.resolve())
    if a.mode=='prepare':prepare(a.bundle.resolve());return 0
    require(a.digest is not None,'exact_bundle_approval_required')
    if a.mode=='verify':verify(a.bundle.resolve(),a.digest);return 0
    return execute(a.bundle.resolve(),a.digest)


if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception:
        print('authentication-trial operation blocked; no raw exceptions published')
        raise SystemExit(69)
