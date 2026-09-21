#!/usr/bin/env python3
"""Freeze and launch one image-only Ansible operation; preparation never contacts hosts."""
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
    'PLAN.md':'Nautobot/docs/NAUTOBOT_DEPLOYMENT_PLAN.md',
    'launcher.py':'Nautobot/ansible/scripts/load-images.py',
    'node.py':'Nautobot/ansible/scripts/image-load-node.py',
    'bounded.py':'Nautobot/ansible/scripts/image-build-node.py',
    'playbook.yaml':'Nautobot/ansible/playbooks/load-images.yaml',
    'pull-image.yaml':'Nautobot/ansible/playbooks/pull-image.yaml',
    'operation.yaml':'Nautobot/manifests/operation.yaml',
    'schema.json':'Nautobot/schemas/image-load.schema.json',
    'desired.yaml':'Nautobot/manifests/desired-state.yaml',
    'desired-schema.json':'Nautobot/schemas/desired-state.schema.json',
    'accepted.yaml':'Nautobot/manifests/accepted-live-state.yaml',
    'qualified.json':'Nautobot/manifests/qualified-image.json',
    'credentials.json':'Nautobot/manifests/provisioned-credentials.json',
    'credential-result.json':'Nautobot/manifests/credential-result.json',
    'settings.py':'Nautobot/ansible/templates/runtime/nautobot_config.py',
    'inputs.json':'Nautobot/manifests/runtime-inputs.json',
    'tests.py':'Nautobot/tests/test_image_load.py',
    'PROCEDURE.md':'Nautobot/docs/IMAGE_LOADING_AND_CONFIGURATION.md',
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
    images={'custom':{'reference':qualified['reference'],'digest':qualified['manifest_digest'],'image_id':qualified['image_id']}}
    for name in ('postgresql','redis'):
        item=desired['images'][name]
        require(item['reference'].endswith('@'+item['manifest_digest']) and item['platform']=='linux/arm64/v8','dependency_identity')
        images[name]={'reference':item['reference'],'digest':item['manifest_digest']}
    return {'boot_id':accepted['host_baseline']['boot_id'],'images':images,
            'archive':op['archive'],'archive_sha256':qualified['archive_sha256'],'archive_bytes':qualified['archive_bytes'],
            'settings_sha256':sha(root/'settings.py'), 'min_available_bytes':1610612736,'min_free_bytes':21474836480}


def git(*args):
    return subprocess.check_output(['git','-C',str(ROOT),*args],timeout=15)


def provenance(root):
    import yaml
    q=json.loads((root/'qualified.json').read_text()); c=json.loads((root/'credentials.json').read_text())
    a=yaml.safe_load((root/'accepted.yaml').read_text())
    proofs={}
    for name,item,commit_field,result_path,hash_field in [
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
            else:require(raw==(root/'credential-result.json').read_bytes(),'credential_provenance')
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
    (bundle/'inventory.json').write_text(json.dumps({'all':{'hosts':{'image_target':{
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
    after=json.loads((root/'after.json').read_text());require(after['accepted'] and not after['runtime_started'],'postflight')
    for name in ('custom','alias','postgresql','redis'):
        result=json.loads((root/(name+'-result.json')).read_text())
        require(result['accepted'] and result['worker_stopped'] and result['post_exit_seconds']>=75,'step_failed')
        times=[s['monotonic'] for s in result['samples']]
        require(len(times)>=16 and all(0<b-a<=15 for a,b in zip(times,times[1:])),'coverage')
    for name in ('custom','postgresql','redis'):
        value=json.loads((root/(name+'-image.json')).read_text());expected=spec['images'][name]
        require(value['Digest']==expected['digest'] and expected['reference'] in value['RepoDigests'] and value['Architecture']=='arm64' and value['Os']=='linux','image_evidence')
        if name=='custom':
            require(value['Id'].removeprefix('sha256:')==expected['image_id'].removeprefix('sha256:'),'image_id_evidence')


def execute(bundle,digest):
    verify(bundle,digest)
    require(sha(Path(__file__))==sha(bundle/'launcher.py'),'execute_frozen_launcher')
    evidence=Path(tempfile.mkdtemp(prefix='nautobot-image-load-evidence.'));print('evidence='+str(evidence),flush=True)
    result={'accepted':False,'bundle_sha256':digest,'runtime_started':False,'mutation_status':'unknown_until_node_records_reviewed','rollback':'no_automatic_image_removal'}
    try:
        with tempfile.TemporaryDirectory(prefix='nautobot-image-load-frozen.') as tmp:
            frozen=Path(tmp)/'bundle';shutil.copytree(bundle,frozen);verify(frozen,digest)
            env={k:os.environ[k] for k in ('HOME','PATH','SSH_AUTH_SOCK') if k in os.environ}
            env.update(ANSIBLE_CONFIG=str(frozen/'ansible.cfg'),ANSIBLE_NOCOLOR='1',PYTHONDONTWRITEBYTECODE='1')
            args=['/bin/bash',str(frozen/'ansible-temp.sh'),'ansible-playbook','-i',str(frozen/'inventory.json'),str(frozen/'playbook.yaml'),'-e',json.dumps({'image_load_bundle_verified':True,'bundle_root':str(frozen),'evidence_root':str(evidence)})]
            # Output is non-secret; keep it private and bounded using the qualified capture helper.
            module=importlib.util.spec_from_file_location('bounded',frozen/'bounded.py'); b=importlib.util.module_from_spec(module);module.loader.exec_module(b)
            b.AUDIT=evidence/'execution-trace.jsonl'
            output=b.capture(args,timeout=4500,limit=4*1024*1024,env=env)
            (evidence/'ansible.log').write_text(output)
            evaluate(evidence,0,spec_from(frozen))
            result.update(accepted=True,mutation_status='three_images_loaded_and_verified')
    except Exception:
        result.update(accepted=False,error='execution_or_evidence_failed_review_required')
    finally:
        (evidence/'result.json').write_text(json.dumps(result,indent=2)+'\n')
        (evidence/'SHA256SUMS.json').write_text(json.dumps({p.name:sha(p) for p in evidence.iterdir() if p.is_file()},indent=2)+'\n')
    return 0 if result['accepted'] else 69


def main():
    os.umask(0o077)
    p=argparse.ArgumentParser();p.add_argument('mode',choices=['prepare','verify','execute']);p.add_argument('bundle',type=Path);p.add_argument('digest',nargs='?');a=p.parse_args()
    if a.mode=='prepare':prepare(a.bundle.resolve());return 0
    require(a.digest is not None,'exact_bundle_approval_required')
    if a.mode=='verify':verify(a.bundle.resolve(),a.digest);return 0
    return execute(a.bundle.resolve(),a.digest)


if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception:
        print('image-load operation blocked; no raw exceptions published')
        raise SystemExit(69)
