#!/usr/bin/env python3
"""Target-side temporary capture qualification; no upload, Jobs or service changes."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import time
import workload_sampler as sampler


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args(); root = args.root
    spec = importlib.util.spec_from_file_location('producer', root/'application-backup.py')
    producer = importlib.util.module_from_spec(spec); spec.loader.exec_module(producer)
    producer.protected(root, True)
    contract = json.loads((root/'contract.json').read_text())
    cursor = json.loads(sampler.run(['/usr/bin/journalctl', '-n', '1', '-o', 'json',
                        '--output-fields=__CURSOR', '--no-pager', '--quiet']))['__CURSOR']
    reader = sampler.Reader(cursor); first = reader.sample()
    sampler.validate(first, first, None, contract)
    expected=json.loads((root/'backup-sources.json').read_text())
    producer.require(first['boot_id']==expected['boot_id'],'baseline_boot_changed')
    producer.require(all(first['services'][role]['unit']['InvocationID']==identity
        for role,identity in expected['invocations'].items()),'baseline_service_changed')
    space=os.statvfs(root)
    producer.require(space.f_bavail*space.f_frsize > 384*1024*1024, 'staging_capacity')
    producer.require(first['mem_available_bytes'] > contract['stop_criteria']['mem_available_below_bytes']+384*1024*1024, 'staging_memory_headroom')
    result = {'passed': False, 'capture_sha256': {}, 'samples': [first],
              'continuous_coverage': False, 'workload_accepted': False}
    env = {'PATH':'/usr/bin:/bin', 'HOME':str(root), 'TMPDIR':str(root), 'LC_ALL':'C'}
    deadline = time.monotonic()+900
    prefix = ['/usr/bin/python3',str(root/'workload_capture.py'),'--root',str(root)]
    try:
        for section in producer.SECTIONS:
            result['phase']=section
            target=root/('capture-'+section)
            maximum=268435456 if section=='postgresql_custom_dump' else 16777216
            rc,_=producer.invoke(prefix+[section],env,deadline,destination=target,maximum=maximum)
            producer.require(rc==0 and target.stat().st_size>0,'capture_failed_'+section)
            result['capture_sha256'][section]=producer.digest(target)
            if section=='postgresql_custom_dump':
                with target.open('rb') as dump:
                    producer.require(dump.read(5)==b'PGDMP','dump_format')
                rc,_=producer.invoke(prefix+['validate_dump'],env,deadline,input_path=target)
                producer.require(rc==0,'dump_listing')
            row=reader.sample();sampler.validate(row,first,None,contract);result['samples'].append(row)
        result['passed']=True
    except Exception as error:
        result['failure_class']=type(error).__name__
        diagnostic=root/'capture-error.json'
        if diagnostic.is_file() and not diagnostic.is_symlink() and diagnostic.stat().st_size<4096:
            result['capture_failure']=json.loads(diagnostic.read_text())
    finally:
        # Raw capture data never leaves the host; independently remove each file.
        result['cleanup']={}
        for section in producer.SECTIONS:
            path=root/('capture-'+section)
            try:
                if path.exists():producer.protected(path);path.unlink()
                result['cleanup'][section]=not path.exists()
            except Exception:result['cleanup'][section]=False
        result['passed']=result['passed'] and all(result['cleanup'].values())
        producer.record(root/'capture-qualification.json',result)
    return 0 if result['passed'] else 1

if __name__=='__main__':raise SystemExit(main())
